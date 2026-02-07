-- lib/crow_io.lua
-- Crow CV output and input. All crow.* calls live here for testability.

local Conditionals = include("lib/conditionals")
local Shapes = include("lib/shapes")

local M = {}

local PERSISTENCE_VERSION = 1

-- Last volts from inputs 1 and 2 (stream callback)
M._cv1 = 0
M._cv2 = 0
-- True only after set_cv_streaming() runs successfully (so run gate from CV works).
M._streaming_set_up = false
-- One metro per output line (1..4), reused for shape-driven ramp steps and segment-end.
M._line_metros = {}
-- Per-line ramp state for repeating metro: start_time, time_sec, start_v, effective, on_done, shape_id.
M._line_ramp_state = {}
local RAMP_STEP_SEC = 0.02

local RUN_THRESHOLD_V = 0.5

-- Set to true to log CV output calls to Maiden (debug triangle LFO / stop).
local DEBUG_CV = false
-- Set to true to log segment-end jump decision (seg.jump_to_segment, use_jump, jump_idx, same_preset, decision).
local DEBUG_JUMP = true

-- Cleared once before first output to reduce Crow REPL "attempt to call nil value (global 'connected')" when Crow runs script that references connected().
M._crow_cleared_for_output = false

--- Get persistence version for save/load.
--- @return number
function M.persistence_version()
  return PERSISTENCE_VERSION
end

--- Whether Crow is connected (norns global). Safe to call; returns false if crow/API missing or errors.
--- @return boolean
function M.connected()
  local ok, result = pcall(function()
    if crow and crow.connected then
      return crow.connected()
    end
    return false
  end)
  return (ok and result) or false
end

--- Start streaming CV from inputs 1 and 2 for run gate and conditionals.
--- Skips setup if crow API would upload a script that errors on Crow (e.g. global 'connected' nil on Crow REPL).
function M.set_cv_streaming()
  -- Kill switch: never call inp.mode() so we never upload the script that errors on Crow (global 'connected' nil). Run gate from CV stays off until norns crow lib is fixed.
  return nil
  --[[ dead code: re-enable when norns crow lib no longer uploads script that calls global connected()
  if not crow or not crow.input then return end
  local ok, err = pcall(function()
    for i = 1, 2 do
      local inp = crow.input[i]
      if inp and inp.mode then
        if i == 1 then
          inp.stream = function(v) M._cv1 = v end
        else
          inp.stream = function(v) M._cv2 = v end
        end
        inp.mode("stream", 0.05)
      end
    end
    M._streaming_set_up = true
  end)
  if not ok and err and print then
    print("[lines] crow set_cv_streaming: " .. tostring(err))
  end
  --]]
end

--- Run gate: true when run_cv is Off (3), when Crow is not connected, or when the selected input voltage is above threshold.
--- Check _streaming_set_up first so we never call crow.connected() when CV streaming is off (avoids Crow REPL "attempt to call nil value (global 'connected')" spam).
--- @param run_cv number 1 = CV1, 2 = CV2, 3 = Off
--- @return boolean
function M.get_run_high(run_cv)
  if run_cv == 3 or not run_cv then return true end
  if not M._streaming_set_up then return true end
  if not M.connected() then return true end
  local v = (run_cv == 1) and M._cv1 or M._cv2
  return (v or 0) > RUN_THRESHOLD_V
end

--- Return current CV input volts for conditionals. Uses streamed _cv1, _cv2.
--- @return table { cv1, cv2, line1, line2, line3, line4 }
function M.get_cv_inputs()
  return {
    cv1 = M._cv1 or 0,
    cv2 = M._cv2 or 0,
    line1 = 0, line2 = 0, line3 = 0, line4 = 0,
  }
end

--- Set output voltage with slew.
--- After the first crow.clear(), we send a stub "connected = function() return true end" to Crow so scripts that reference connected() do not error.
--- @param line number 1..4
--- @param volts number target voltage
--- @param slew_sec number slew time in seconds
function M.output_volts(line, volts, slew_sec)
  if DEBUG_CV and print then
    print(string.format("[lines] output_volts line=%d volts=%.2f slew=%.3f", line, volts or 0, slew_sec or 0))
  end
  if not crow or not crow.output then return end
  if not M._crow_cleared_for_output and crow.clear then
    pcall(function() crow.clear() end)
    M._crow_cleared_for_output = true
    -- Define connected() on Crow so any script that references it (e.g. from norns crow lib) does not error with "attempt to call nil value (global 'connected')".
    if crow.send then
      pcall(function() crow.send("connected = function() return true end") end)
    end
  end
  local out = crow.output[line]
  if out then
    -- Crow doc: set slew then volts so the move is applied with the intended time.
    -- Note: setting output[n].shape from norns is not supported by the protocol (Crow errors "attempt to index a string value (field 'shape')"); use Crow default slew curve.
    out.slew = slew_sec or 0
    out.volts = volts
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
--- Drives CV ramp from Control Forge shape (stepped output); uses one repeating metro per line.
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
  local start_v = (type(from_volts) == "number") and from_volts or 0
  local shape_id = (type(segment.shape) == "string") and segment.shape or "linear"
  if DEBUG_CV and print then
    print(string.format("[lines] start_segment line=%d from_volts=%.2f start_v=%.2f effective=%.2f time_sec=%.3f shape=%s", line, from_volts or 0, start_v, effective, time_sec, shape_id))
  end
  M.output_volts(line, start_v, 0)
  if not on_done then return end
  local m = M._line_metros[line]
  if not m and metro and metro.init then
    m = metro.init()
    if m then M._line_metros[line] = m end
  end
  if not m then
    M.output_volts(line, effective, 0)
    on_done(effective)
    return
  end
  local now_fn = (util and util.time) and function() return util.time() end or function() return os.clock() end
  M._line_ramp_state[line] = {
    start_time = now_fn(),
    time_sec = time_sec,
    start_v = start_v,
    effective = effective,
    on_done = on_done,
    shape_id = shape_id,
  }
  m.time = RAMP_STEP_SEC
  m.count = -1
  m.event = function()
    local st = M._line_ramp_state[line]
    if not st then return end
    local elapsed = now_fn() - st.start_time
    local t = (elapsed >= st.time_sec) and 1 or (elapsed / st.time_sec)
    local y = Shapes.shape_value(st.shape_id, t)
    local v = st.start_v + (st.effective - st.start_v) * y
    M.output_volts(line, v, 0)
    if t >= 1 then
      M._line_ramp_state[line] = nil
      pcall(function() m:stop() end)
      M.output_volts(line, st.effective, 0)
      if st.on_done then st.on_done(st.effective) end
    end
  end
  m:start()
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
    if DEBUG_CV and print then
      print(string.format("[lines] play_seg line=%d seg_idx=%d from_volts=%.2f level_value=%.2f time=%s time_unit=%s", line, seg_idx, from_volts or 0, seg.level_value or 0, tostring(seg.time), tostring(seg.time_unit)))
    end
    M.start_segment(line, seg, from_volts, function(end_volts)
      local ok, err = pcall(function()
        local inputs = get_inputs()
        local use_jump, use_jpreset = seg.jump_to_segment, seg.jump_to_preset_id
        local use_ping_line, use_ping_action = seg.ping_line, seg.ping_action
        local def1 = build_cond_def(seg.cond1, 1)
        local def2 = build_cond_def(seg.cond2, 2)
        local cond1_met = def1 and Conditionals.evaluate(def1, inputs)
        local cond2_met = def2 and Conditionals.evaluate(def2, inputs)
        if cond1_met and seg.cond1 then
          local c1_jump = (type(seg.cond1.jump_to_segment) == "number") and seg.cond1.jump_to_segment or tonumber(seg.cond1.jump_to_segment)
          if c1_jump and c1_jump >= 1 and c1_jump <= 8 then
            use_jump = c1_jump
            use_jpreset = seg.cond1.jump_to_preset_id
          end
          if seg.cond1.ping_line and seg.cond1.ping_action then
            use_ping_line = seg.cond1.ping_line
            use_ping_action = seg.cond1.ping_action
          end
        elseif cond2_met and seg.cond2 then
          local c2_jump = (type(seg.cond2.jump_to_segment) == "number") and seg.cond2.jump_to_segment or tonumber(seg.cond2.jump_to_segment)
          if c2_jump and c2_jump >= 1 and c2_jump <= 8 then
            use_jump = c2_jump
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
        local jump_idx = (type(use_jump) == "number") and use_jump or tonumber(use_jump)
        if DEBUG_JUMP and print then
          local decision = (jump_idx and jump_idx >= 1 and jump_idx <= 8 and same_preset) and ("play_seg(" .. tostring(jump_idx) .. ")") or "on_preset_done()"
          print(string.format("[lines] jump seg_idx=%d seg.jump_to_segment=%s use_jump=%s use_jpreset=%s jump_idx=%s same_preset=%s -> %s",
            seg_idx, tostring(seg.jump_to_segment), tostring(use_jump), tostring(use_jpreset), tostring(jump_idx), tostring(same_preset), decision))
        end
        if jump_idx and jump_idx >= 1 and jump_idx <= 8 and same_preset then
          play_seg(jump_idx, end_volts or 0)
        else
          if on_preset_done then on_preset_done() end
        end
      end)
      if not ok and err then
        if print then print("[lines] segment on_done error: " .. tostring(err)) end
        if on_preset_done then on_preset_done() end
      end
    end, bpm)
  end
  play_seg(1, 0)
end

--- Stop output on a line (set to 0 instantly to avoid slew overshoot below 0).
--- @param line number 1..4
function M.stop_line(line)
  if DEBUG_CV and print then
    print(string.format("[lines] stop_line line=%d", line))
  end
  M.output_volts(line, 0, 0)
end

--- Stop all per-line segment metros and clear ramp state (cleanup on stop / hot reload).
function M.stop_all_segment_metros()
  for line, m in pairs(M._line_metros or {}) do
    if m and type(m.stop) == "function" then
      pcall(function() m:stop() end)
    end
  end
  M._line_metros = {}
  M._line_ramp_state = {}
end

return M
