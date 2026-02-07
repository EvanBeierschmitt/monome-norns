-- lib/segment.lua
-- Segment data shape, defaults, and validation. No norns/Crow APIs.

local M = {}

-- Control Forge transition shapes (44). IDs are key-friendly; use shape_display_name() for UI.
local SHAPES = {
  "linear",
  "exponential_1", "exponential_2", "exponential_3", "exponential_4", "exponential_5", "exponential_6", "exponential_7",
  "circle_1_4", "circle_1_6", "circle_1_8", "circle_1_16",
  "squeeze",
  "fast_line_1", "fast_line_2", "fast_line_3",
  "medium_line_1", "medium_line_2",
  "slow_ramp_1", "slow_ramp_2",
  "bloom", "bloom_2",
  "circle_1_16_reverse", "circle_1_8_reverse", "circle_1_6_reverse", "circle_1_4_reverse",
  "slow_curve_1", "slow_curve_2",
  "delay_dc", "dc_delay",
  "curve_2x", "curve_2x_b", "curve_2x_c",
  "zig_zag_1", "zig_zag_2", "zig_zag_3",
  "chaos_03", "chaos_06", "chaos_12", "chaos_16", "chaos_25", "chaos_33", "chaos_37", "chaos_50",
}
local LEVEL_MODES = { "abs", "absQ", "rel", "relQ" }

-- Display labels for shape param (Control Forge manual names).
local SHAPE_DISPLAY = {
  linear = "Linear",
  exponential_1 = "Exponential 1", exponential_2 = "Exponential 2", exponential_3 = "Exponential 3",
  exponential_4 = "Exponential 4", exponential_5 = "Exponential 5", exponential_6 = "Exponential 6", exponential_7 = "Exponential 7",
  circle_1_4 = "Circle 1.4", circle_1_6 = "Circle 1.6", circle_1_8 = "Circle 1.8", circle_1_16 = "Circle 1.16",
  squeeze = "Squeeze",
  fast_line_1 = "Fast Line 1", fast_line_2 = "Fast Line 2", fast_line_3 = "Fast Line 3",
  medium_line_1 = "Medium Line 1", medium_line_2 = "Medium Line 2",
  slow_ramp_1 = "Slow Ramp 1", slow_ramp_2 = "Slow Ramp 2",
  bloom = "Bloom", bloom_2 = "Bloom 2",
  circle_1_16_reverse = "Circle 1.16 Reverse", circle_1_8_reverse = "Circle 1.8 Reverse",
  circle_1_6_reverse = "Circle 1.6 Reverse", circle_1_4_reverse = "Circle 1.4 Reverse",
  slow_curve_1 = "Slow Curve 1", slow_curve_2 = "Slow Curve 2",
  delay_dc = "Delay DC", dc_delay = "DC Delay",
  curve_2x = "Curve 2X", curve_2x_b = "Curve 2X B", curve_2x_c = "Curve 2X C",
  zig_zag_1 = "Zig Zag 1", zig_zag_2 = "Zig Zag 2", zig_zag_3 = "Zig Zag 3",
  chaos_03 = "Chaos 03", chaos_06 = "Chaos 06", chaos_12 = "Chaos 12", chaos_16 = "Chaos 16",
  chaos_25 = "Chaos 25", chaos_33 = "Chaos 33", chaos_37 = "Chaos 37", chaos_50 = "Chaos 50",
}

--- Ping actions (for segment.ping_action).
M.PING_INCREMENT = "increment"
M.PING_DECREMENT = "decrement"
M.PING_RESET = "reset"

--- Default condition slot. Per-segment: input, comparison, value_mode, value(s), jump/ping targets.
--- @return table { input, comparison, value_mode, value, value_lo, value_hi, jump_to_segment, jump_to_preset_id, ping_line, ping_action }
function M.default_condition(cond_id)
  local input = (cond_id == 1) and "cv1" or "cv2"
  return {
    input = input,
    comparison = ">",
    value_mode = "abs",
    value = 0,
    value_lo = nil,
    value_hi = nil,
    jump_to_segment = 0,
    jump_to_preset_id = nil,
    ping_line = nil,
    ping_action = nil,
  }
end

--- Default segment (single segment). Each segment gets fresh cond1/cond2 tables.
--- @return table segment table
function M.default()
  local function dc(id)
    return {
      input = (id == 1) and "cv1" or "cv2",
      comparison = ">", value_mode = "abs", value = 0, value_lo = nil, value_hi = nil,
      jump_to_segment = 0, jump_to_preset_id = nil, ping_line = nil, ping_action = nil,
    }
  end
  return {
    shape = "linear",
    level_mode = "abs",
    level_value = 0,
    level_range = 0,
    level_random = nil,
    time = 1,
    time_unit = "sec",
    jump_to_segment = nil,
    jump_to_preset_id = nil,
    ping_line = nil,
    ping_action = nil,
    cond1 = dc(1),
    cond2 = dc(2),
  }
end

--- All valid shape names.
--- @return table list of shape strings
function M.shapes()
  return SHAPES
end

--- Display name for shape param (Control Forge manual names).
--- @param shape_id string e.g. "exponential_1"
--- @return string e.g. "Exponential 1", or shape_id if unknown
function M.shape_display_name(shape_id)
  if not shape_id then return "linear" end
  return SHAPE_DISPLAY[shape_id] or shape_id
end

--- All valid level modes.
--- @return table list of level mode strings
function M.level_modes()
  return LEVEL_MODES
end

--- All valid condition value modes (same as level: abs, absQ, rel, relQ).
--- @return table list of mode strings
function M.cond_value_modes()
  return LEVEL_MODES
end

--- Validate a segment table.
--- @param seg table segment
--- @param voltage_lo number min voltage (e.g. -5)
--- @param voltage_hi number max voltage (e.g. 5)
--- @return boolean ok
--- @return string|nil err
function M.validate(seg, voltage_lo, voltage_hi)
  if type(seg) ~= "table" then
    return false, "segment must be a table"
  end
  voltage_lo = voltage_lo or -5
  voltage_hi = voltage_hi or 5

  local found = false
  for _, s in ipairs(SHAPES) do
    if s == seg.shape then found = true break end
  end
  if not found then
    -- Migrate old shapes (sine, square, log, exp) to linear so saved presets stay valid.
    seg.shape = "linear"
  end

  found = false
  for _, m in ipairs(LEVEL_MODES) do
    if m == seg.level_mode then found = true break end
  end
  if not found then
    return false, "invalid level_mode"
  end

  if type(seg.level_value) ~= "number" then
    return false, "level_value must be a number"
  end
  if type(seg.time) ~= "number" then
    return false, "time must be a number"
  end
  local tu = seg.time_unit or "sec"
  if tu == "sec" then
    if seg.time < 1 or seg.time > 9999 then
      return false, "time (sec) must be 1..9999"
    end
  elseif tu == "beats" then
    if seg.time < 1 or seg.time > 999 then
      return false, "time (beats) must be 1..999"
    end
  else
    return false, "time_unit must be sec or beats"
  end
  if seg.jump_to_segment ~= nil then
    if type(seg.jump_to_segment) ~= "number" or seg.jump_to_segment < 0 or seg.jump_to_segment > 8 then
      return false, "jump_to_segment must be 0 (stop), 1..8, or nil"
    end
  end
  if seg.jump_to_preset_id ~= nil and type(seg.jump_to_preset_id) ~= "string" then
    return false, "jump_to_preset_id must be string or nil"
  end
  if seg.ping_line ~= nil then
    if type(seg.ping_line) ~= "number" or seg.ping_line < 1 or seg.ping_line > 4 then
      return false, "ping_line must be 1..4 or nil"
    end
  end
  if seg.ping_action ~= nil then
    local ok_act = seg.ping_action == "increment" or seg.ping_action == "decrement" or seg.ping_action == "reset"
    if not ok_act then
      return false, "ping_action must be increment|decrement|reset or nil"
    end
  end
  if seg.cond1 then
    if type(seg.cond1.value) ~= "number" then
      return false, "cond1.value must be number"
    end
    if seg.cond1.value_mode then
      found = false
      for _, m in ipairs(LEVEL_MODES) do
        if m == seg.cond1.value_mode then found = true break end
      end
      if not found then
        return false, "cond1.value_mode must be abs, absQ, rel, or relQ"
      end
    end
  end
  if seg.cond2 then
    if type(seg.cond2.value) ~= "number" then
      return false, "cond2.value must be number"
    end
    if seg.cond2.value_mode then
      found = false
      for _, m in ipairs(LEVEL_MODES) do
        if m == seg.cond2.value_mode then found = true break end
      end
      if not found then
        return false, "cond2.value_mode must be abs, absQ, rel, or relQ"
      end
    end
  end
  if type(seg.level_range) == "number" and seg.level_range < 0 then
    return false, "level_range must be >= 0"
  end
  if seg.level_random ~= nil and seg.level_random ~= "linear" and seg.level_random ~= "gaussian" and seg.level_random ~= "off" then
    return false, "level_random must be nil, off, linear, or gaussian"
  end
  return true, nil
end

--- Clamp level_value into voltage range for display/save (abs modes).
--- @param seg table segment (mutated)
--- @param voltage_lo number
--- @param voltage_hi number
function M.clamp_level(seg, voltage_lo, voltage_hi)
  if seg.level_mode == "abs" or seg.level_mode == "absQ" then
    if seg.level_value < voltage_lo then seg.level_value = voltage_lo end
    if seg.level_value > voltage_hi then seg.level_value = voltage_hi end
  end
end

local NOTE_NAMES = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }

--- Format voltage as musical note (1V/oct, C3 = 0V). For absQ/relQ display.
--- @param volts number voltage
--- @return string e.g. "C3", "C#3", "D4"
function M.voltage_to_note(volts)
  if type(volts) ~= "number" then return "?" end
  local o = math.floor(volts) + 3
  local s = math.floor((volts % 1) * 12 + 0.5)
  if s >= 12 then s = 0; o = o + 1 end
  if s < 0 then s = 11; o = o - 1 end
  return (NOTE_NAMES[s + 1] or "?") .. o
end

return M
