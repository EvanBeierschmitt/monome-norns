-- lib/crow_io.lua
-- Crow CV output and input. All crow.* calls live here for testability.

local Conditionals = include("lib/conditionals")

local M = {}

local PERSISTENCE_VERSION = 1

--- Get persistence version for save/load.
--- @return number
function M.persistence_version()
  return PERSISTENCE_VERSION
end

--- Whether Crow is connected (norns global).
--- @return boolean
function M.connected()
  if crow and crow.connected then
    return crow.connected()
  end
  return false
end

--- Set output voltage with slew. Linear contour for Phase 1.
--- @param line number 1..4
--- @param volts number target voltage
--- @param slew_sec number slew time in seconds
function M.output_volts(line, volts, slew_sec)
  if not crow or not crow.output then return end
  local out = crow.output[line]
  if out then
    out.volts = volts
    out.slew = slew_sec or 0
  end
end

--- Compute effective end level for a segment (level_value + optional randomization).
--- @param segment table segment (level_value, level_range, level_random)
--- @return number effective voltage
function M.effective_level(segment)
  if not segment then return 0 end
  local base = segment.level_value or 0
  local range = segment.level_range or 0
  local mode = segment.level_random
  if range <= 0 or (mode ~= "linear" and mode ~= "gaussian") then
    return base
  end
  local offset
  if mode == "linear" then
    offset = (math.random() * 2 - 1) * range
  else
    local u1, u2 = math.random(), math.random()
    if u1 <= 0 then u1 = 0.001 end
    local sigma = range / 2
    offset = sigma * math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
    if offset < -range then offset = -range elseif offset > range then offset = range end
  end
  return base + offset
end

--- Start playing one segment on a line. Calls on_done after segment time.
--- Phase 1: linear contour only (shape ignored for contour; data model ready).
--- Uses effective_level (level_value + level_range/level_random) for output and for next segment from_volts.
--- @param line number 1..4
--- @param segment table segment (shape, level_value, level_range, level_random, time, time_unit)
--- @param from_volts number starting voltage
--- @param on_done function(end_volts) callback when segment finishes; end_volts is effective level for next segment
--- @param bpm number optional; used when segment.time_unit == "beats" (time_sec = time * 60 / bpm)
function M.start_segment(line, segment, from_volts, on_done, bpm)
  if not segment or not segment.time then
    if on_done then on_done(from_volts or 0) end
    return
  end
  local time_sec = segment.time
  if (segment.time_unit or "sec") == "beats" and bpm and bpm > 0 then
    time_sec = segment.time * 60 / bpm
  end
  if time_sec < 0.01 then time_sec = 0.01 end
  local effective = M.effective_level(segment)
  M.output_volts(line, effective, time_sec)
  if metro and on_done then
    local seg_metro = metro.init()
    seg_metro.time = time_sec
    seg_metro.count = 1
    seg_metro.event = function()
      if on_done then on_done(effective) end
    end
    seg_metro:start()
  elseif on_done then
    on_done(effective)
  end
end

--- Play a preset on a line: run segments in order; evaluate conditionals at segment end; call on_ping when applicable.
--- Uses per-segment cond.input; no assign toggles: if cond is met and has jump/ping targets, use them. Cond1 overrides Cond2.
--- @param line number 1..4
--- @param preset table preset with .id and .segments
--- @param on_preset_done function() when preset finishes (no more jump)
--- @param on_ping function(target_line, action) when segment completes with ping (default or conditional)
--- @param get_inputs function() -> { cv1, cv2, line1, line2, line3, line4 } for conditional evaluation (optional)
--- @param bpm number optional; used when segment.time_unit == "beats"
function M.play_preset(line, preset, on_preset_done, on_ping, get_inputs, bpm)
  if not preset or not preset.segments then
    if on_preset_done then on_preset_done() end
    return
  end
  get_inputs = get_inputs or function() return { cv1 = 0, cv2 = 0, line1 = 0, line2 = 0, line3 = 0, line4 = 0 } end
  local function build_cond_def(cond, cond_id)
    if not cond then return nil end
    local input_src = cond.input
    if not input_src then
      input_src = (cond_id == 1) and "cv1" or "cv2"
    end
    return {
      input = input_src,
      comparison = cond.comparison or ">",
      value = cond.value or 0,
      value_lo = cond.value_lo,
      value_hi = cond.value_hi,
    }
  end
  local function play_seg(seg_idx, from_volts)
    local seg = preset.segments[seg_idx]
    if not seg then
      if on_preset_done then on_preset_done() end
      return
    end
    M.start_segment(line, seg, from_volts, function(end_volts)
      local inputs = get_inputs()
      local use_jump, use_jpreset = seg.jump_to_segment, seg.jump_to_preset_id
      local use_ping_line, use_ping_action = seg.ping_line, seg.ping_action
      local def1 = build_cond_def(seg.cond1, 1)
      local def2 = build_cond_def(seg.cond2, 2)
      local cond1_met = def1 and Conditionals.evaluate(def1, inputs)
      local cond2_met = def2 and Conditionals.evaluate(def2, inputs)
      if cond1_met and seg.cond1 then
        if seg.cond1.jump_to_segment and seg.cond1.jump_to_segment >= 1 and seg.cond1.jump_to_segment <= 8 then
          use_jump = seg.cond1.jump_to_segment
          use_jpreset = seg.cond1.jump_to_preset_id
        end
        if seg.cond1.ping_line and seg.cond1.ping_action then
          use_ping_line = seg.cond1.ping_line
          use_ping_action = seg.cond1.ping_action
        end
      elseif cond2_met and seg.cond2 then
        if seg.cond2.jump_to_segment and seg.cond2.jump_to_segment >= 1 and seg.cond2.jump_to_segment <= 8 then
          use_jump = seg.cond2.jump_to_segment
          use_jpreset = seg.cond2.jump_to_preset_id
        end
        if seg.cond2.ping_line and seg.cond2.ping_action then
          use_ping_line = seg.cond2.ping_line
          use_ping_action = seg.cond2.ping_action
        end
      end
      if on_ping and use_ping_line and use_ping_action then
        on_ping(use_ping_line, use_ping_action)
      end
      local same_preset = (use_jpreset == nil or use_jpreset == preset.id)
      if use_jump and same_preset and use_jump >= 1 and use_jump <= 8 then
        play_seg(use_jump, end_volts or 0)
      else
        if on_preset_done then on_preset_done() end
      end
    end, bpm)
  end
  play_seg(1, 0)
end

--- Stop output on a line (set to 0 with short slew).
--- @param line number 1..4
function M.stop_line(line)
  M.output_volts(line, 0, 0.01)
end

return M
