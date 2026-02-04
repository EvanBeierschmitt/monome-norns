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

--- Start playing one segment on a line. Calls on_done after segment time.
--- Phase 1: linear contour only (shape ignored for contour; data model ready).
--- @param line number 1..4
--- @param segment table segment (shape, level_value, time, time_unit "sec"|"beats")
--- @param from_volts number starting voltage
--- @param on_done function() callback when segment finishes
--- @param bpm number optional; used when segment.time_unit == "beats" (time_sec = time * 60 / bpm)
function M.start_segment(line, segment, from_volts, on_done, bpm)
  if not segment or not segment.time then
    if on_done then on_done() end
    return
  end
  local time_sec = segment.time
  if (segment.time_unit or "sec") == "beats" and bpm and bpm > 0 then
    time_sec = segment.time * 60 / bpm
  end
  if time_sec < 0.01 then time_sec = 0.01 end
  M.output_volts(line, segment.level_value or 0, time_sec)
  if metro and on_done then
    local seg_metro = metro.init()
    seg_metro.time = time_sec
    seg_metro.count = 1
    seg_metro.event = function()
      if on_done then on_done() end
    end
    seg_metro:start()
  elseif on_done then
    on_done()
  end
end

--- Play a preset on a line: run segments in order; evaluate conditionals at segment end; call on_ping when applicable.
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
  local function play_seg(seg_idx, from_volts)
    local seg = preset.segments[seg_idx]
    if not seg then
      if on_preset_done then on_preset_done() end
      return
    end
    M.start_segment(line, seg, from_volts, function()
      local inputs = get_inputs()
      local use_jump, use_jpreset = seg.jump_to_segment, seg.jump_to_preset_id
      local use_ping_line, use_ping_action = seg.ping_line, seg.ping_action
      if seg.cond1 and Conditionals.evaluate(seg.cond1, inputs) then
        if seg.cond1.assign_to == "jump" and seg.cond1.jump_to_segment then
          use_jump = seg.cond1.jump_to_segment
          use_jpreset = seg.cond1.jump_to_preset_id
        elseif seg.cond1.assign_to == "ping" and seg.cond1.ping_line then
          use_ping_line = seg.cond1.ping_line
          use_ping_action = seg.cond1.ping_action
        end
      end
      if seg.cond2 and Conditionals.evaluate(seg.cond2, inputs) then
        if seg.cond2.assign_to == "jump" and seg.cond2.jump_to_segment then
          use_jump = seg.cond2.jump_to_segment
          use_jpreset = seg.cond2.jump_to_preset_id
        elseif seg.cond2.assign_to == "ping" and seg.cond2.ping_line then
          use_ping_line = seg.cond2.ping_line
          use_ping_action = seg.cond2.ping_action
        end
      end
      if on_ping and use_ping_line and use_ping_action then
        on_ping(use_ping_line, use_ping_action)
      end
      local same_preset = (use_jpreset == nil or use_jpreset == preset.id)
      if use_jump and same_preset and use_jump >= 1 and use_jump <= 8 then
        play_seg(use_jump, seg.level_value or 0)
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
