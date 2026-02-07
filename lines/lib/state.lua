-- lib/state.lua
-- Application state and screen navigation. Pure(ish) transitions where possible.

local Preset = include("lib/preset")
local Segment = include("lib/segment")
local Sequencer = include("lib/sequencer")
local Conditionals = include("lib/conditionals")

local M = {}

-- Screen identifiers
M.SCREEN_MAIN_MENU = "main_menu"
M.SCREEN_PRESET_SEQUENCER = "preset_sequencer"
M.SCREEN_PRESETS_LIST = "presets_list"
M.SCREEN_PRESET_EDITOR = "preset_editor"
M.SCREEN_SETTINGS = "settings"
M.SCREEN_PROJECT = "project"

-- Main menu item indices (E1). Order: Presets, Preset Sequencer, Settings, Project.
M.MENU_PRESETS_LIST = 1
M.MENU_PRESET_SEQUENCER = 2
M.MENU_SETTINGS = 3
M.MENU_PROJECT = 4
M.MENU_COUNT = 4

-- Project sub-menu (E1 when screen == SCREEN_PROJECT). Order for display; availability is dynamic.
M.PROJECT_SAVE = 1
M.PROJECT_LOAD = 2
M.PROJECT_SAVE_AS = 3
M.PROJECT_RENAME = 4
M.PROJECT_SET_FAST_LOAD = 5
M.PROJECT_DELETE = 6

-- Preset editor parameters (E2). Order: Name=0, Time unit..Ping=1..10, Cond1 (input, comparison, value_mode, value, value_hi, jump seg, jump preset, ping), Cond2 (same).
M.PARAM_TIME_UNIT = 1
M.PARAM_TIME = 2
M.PARAM_LEVEL_MODE = 3
M.PARAM_LEVEL_VALUE = 4
M.PARAM_LEVEL_RANGE = 5
M.PARAM_LEVEL_RANDOM = 6
M.PARAM_SHAPE = 7
M.PARAM_JUMP_SEGMENT = 8
M.PARAM_JUMP_PRESET = 9
M.PARAM_PING = 10
M.PARAM_COND1_INPUT = 11
M.PARAM_COND1_COMPARISON = 12
M.PARAM_COND1_VALUE_MODE = 13
M.PARAM_COND1_VALUE = 14
M.PARAM_COND1_VALUE_HI = 15
M.PARAM_COND1_JUMP_SEGMENT = 16
M.PARAM_COND1_JUMP_PRESET = 17
M.PARAM_COND1_PING = 18
M.PARAM_COND2_INPUT = 19
M.PARAM_COND2_COMPARISON = 20
M.PARAM_COND2_VALUE_MODE = 21
M.PARAM_COND2_VALUE = 22
M.PARAM_COND2_VALUE_HI = 23
M.PARAM_COND2_JUMP_SEGMENT = 24
M.PARAM_COND2_JUMP_PRESET = 25
M.PARAM_COND2_PING = 26
M.PARAM_COUNT = 27

-- Preset sequencer actions (E3)
M.SEQ_ACTION_EDIT = 1
M.SEQ_ACTION_COPY = 2
M.SEQ_ACTION_PASTE = 3
M.SEQ_ACTION_DELETE = 4
M.SEQ_ACTION_ADD = 5
M.SEQ_ACTION_REPLACE = 6
M.SEQ_ACTION_PLAY_STOP = 7
M.SEQ_ACTION_COUNT = 7

--- Create new application state.
--- @return table state
function M.new()
  local state = {
    screen = M.SCREEN_MAIN_MENU,
    main_menu_index = 1,
    presets = {},
    preset_list_index = 1,
    editing_preset_index = nil,
    editor_segment_index = 1,
    editor_param_index = 1,
    selected_line = 1,
    line_count = 4,
    voltage_lo = -5,
    voltage_hi = 5,
    ext_clock_cv = 1,
    run_cv = 1,
    quantize = false,
    playing = {
      line = 1,
      preset_id = nil,
      segment_index = 0,
      running = false,
    },
    clipboard_preset = nil,
    sequences = nil,
    preset_sequencer_selected_line = 1,
    preset_sequencer_cursor = 1,
    preset_sequencer_action_index = 1,
    sequencer_running = false,
    sequencer_play_requested = false,
    settings_field_index = 1,
    preset_delete_candidate = nil,
    editing_name_position = 1,
    preset_name_before_edit = nil,
    preset_editor_blocked_playing = false,
    pending_name_save_confirm = false,
    preset_name_edit_mode = false,
    preset_name_edit_buffer = "",
    preset_created_this_session = false,
    preset_list_action = "edit",
    pending_new_preset_save_confirm = false,
    preset_edited_dirty = false,
    preset_before_edit = nil,
    pending_edited_preset_save_confirm = false,
    sequencer_delete_confirm = nil,
    sequencer_empty_slot_action_index = nil,
    text_scroll_offsets = {},
    text_scroll_time = 0,
    came_from_sequencer = false,
    project_menu_index = 1,
    current_project_path = nil,
    project_list = {},
    project_list_index = 1,
    project_sub_screen = nil,
    project_fast_load_path = nil,
    project_delete_confirm = nil,
  }
  state.sequences = Sequencer.new(4)
  return state
end

--- Validate state invariants.
--- @param state table
--- @return boolean ok
--- @return string|nil err
function M.validate(state)
  if type(state) ~= "table" then
    return false, "state must be a table"
  end
  if state.screen == nil then
    return false, "state.screen required"
  end
  if type(state.main_menu_index) ~= "number" or state.main_menu_index < 1 or state.main_menu_index > 4 then
    return false, "state.main_menu_index out of range"
  end
  if type(state.presets) ~= "table" then
    return false, "state.presets must be a table"
  end
  if type(state.preset_list_index) ~= "number" or state.preset_list_index < 0 then
    return false, "state.preset_list_index invalid"
  end
  if type(state.selected_line) ~= "number" or state.selected_line < 1 or state.selected_line > 4 then
    return false, "state.selected_line must be 1..4"
  end
  if type(state.line_count) ~= "number" or state.line_count < 1 or state.line_count > 4 then
    return false, "state.line_count must be 1..4"
  end
  return true, nil
end

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

--- Handle encoder: dispatch by screen and encoder number.
--- @param state table mutated
--- @param n number encoder 1..3
--- @param d number delta
function M.on_enc(state, n, d)
  if state.screen == M.SCREEN_MAIN_MENU then
    -- Any encoder (E1/E2/E3) moves main menu selection; some norns only deliver E2/E3 to script
    if n == 1 or n == 2 or n == 3 then
      state.main_menu_index = clamp(state.main_menu_index + (d > 0 and 1 or -1), 1, M.MENU_COUNT)
    end
    return
  end

  if state.screen == M.SCREEN_PRESETS_LIST then
    if n == 2 then
      local count = #state.presets
      local lo, hi
      if state.sequencer_pick_preset_for_line then
        lo = count > 0 and 1 or 0
        hi = count
        if state.preset_list_index < lo or state.preset_list_index > hi then
          state.preset_list_index = lo
        end
      else
        lo = 0
        hi = count
      end
      state.preset_list_index = clamp(state.preset_list_index + (d > 0 and 1 or -1), lo, hi)
      if state.sequencer_pick_preset_for_line then
        state.sequencer_pick_selected_index = state.preset_list_index
        if _G.LINES_DEBUG_SEQUENCER_ADD and print then
          local p = state.presets and state.presets[state.preset_list_index]
          print("[lines] enc E2 presets_list pick: preset_list_index=" .. tostring(state.preset_list_index) .. " d=" .. tostring(d) .. " name=" .. (p and (p.name or p.id) or "?"))
        end
      end
      if not state.sequencer_pick_preset_for_line and state.preset_list_index >= 1 then
        state.preset_list_action = "edit"
      end
    elseif n == 3 and state.preset_list_index >= 1 and not state.sequencer_pick_preset_for_line then
      local actions = { "edit", "delete", "duplicate" }
      local cur = state.preset_list_action or "edit"
      local ai = 1
      for i, a in ipairs(actions) do if a == cur then ai = i break end end
      ai = ai + (d > 0 and 1 or -1)
      if ai < 1 then ai = #actions elseif ai > #actions then ai = 1 end
      state.preset_list_action = actions[ai]
    end
    return
  end

  if state.screen == M.SCREEN_PRESET_EDITOR then
    if state.preset_name_edit_mode then
      local buf = state.preset_name_edit_buffer or ""
      local pos = state.editing_name_position or 1
      local charset = " ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"
      if n == 1 then
        -- E1: delete character before cursor (backspace) only when turning left
        if d < 0 and pos > 1 and #buf >= pos - 1 then
          state.preset_name_edit_buffer = buf:sub(1, pos - 2) .. buf:sub(pos)
          state.editing_name_position = pos - 1
        end
      elseif n == 2 then
        while #buf < pos do buf = buf .. " " end
        local cur = buf:sub(pos, pos)
        local idx = charset:find(cur, 1, true) or 1
        idx = idx + (d > 0 and 1 or -1)
        if idx < 1 then idx = #charset elseif idx > #charset then idx = 1 end
        local newchar = charset:sub(idx, idx)
        state.preset_name_edit_buffer = buf:sub(1, pos - 1) .. newchar .. buf:sub(pos + 1)
      elseif n == 3 then
        local last_char = 0
        for i = #buf, 1, -1 do
          if buf:sub(i, i) ~= " " then last_char = i break end
        end
        local max_pos = last_char + 1
        pos = clamp(pos + (d > 0 and 1 or -1), 1, max_pos)
        state.editing_name_position = pos
      end
      return
    end
    local p_editing = M.get_editing_preset(state)
    if p_editing and state.playing and state.playing.running and state.playing.preset_id == p_editing.id then
      state.preset_editor_blocked_playing = true
      return
    end
    state.preset_editor_blocked_playing = false
    if n == 1 then
      state.editor_segment_index = clamp(state.editor_segment_index + (d > 0 and 1 or -1), 1, Preset.max_segments())
    elseif n == 2 then
      local p = M.get_editing_preset(state)
      local seg = p and p.segments and p.segments[state.editor_segment_index]
      local visible = M.visible_editor_params(seg)
      local nvis = #visible
      if nvis > 0 then
        state.editor_param_index = clamp(state.editor_param_index + (d > 0 and 1 or -1), 0, nvis - 1)
      end
    elseif n == 3 then
      local p = p_editing or M.get_editing_preset(state)
      local seg = p and p.segments and p.segments[state.editor_segment_index]
      local visible = M.visible_editor_params(seg)
      local current_param_id = visible and visible[state.editor_param_index + 1]
      if p and seg and current_param_id and current_param_id ~= 0 then
        local coarse = false
          if current_param_id == M.PARAM_TIME then
            local step = coarse and 10 or 1
            local hi = (seg.time_unit or "sec") == "beats" and 999 or 9999
            seg.time = clamp(seg.time + (d > 0 and step or -step), 1, hi)
          elseif current_param_id == M.PARAM_TIME_UNIT then
            local units = { "sec", "beats" }
            local idx = 1
            for i, u in ipairs(units) do if u == (seg.time_unit or "sec") then idx = i break end end
            idx = clamp(idx + (d > 0 and 1 or -1), 1, #units)
            seg.time_unit = units[idx]
            if seg.time_unit == "beats" and seg.time > 999 then seg.time = 999 end
          elseif current_param_id == M.PARAM_LEVEL_VALUE then
            if seg.level_mode == "relQ" then
              local semitones = math.floor((seg.level_value or 0) * 12 + 0.5)
              semitones = clamp(semitones + (d > 0 and 1 or -1), -48, 48)
              seg.level_value = semitones / 12
            else
              local step = coarse and 0.5 or 0.1
              seg.level_value = clamp(seg.level_value + (d > 0 and step or -step), state.voltage_lo, state.voltage_hi)
            end
          elseif current_param_id == M.PARAM_SHAPE then
            local shapes = Segment.shapes()
            local idx = 1
            for i, s in ipairs(shapes) do
              if s == seg.shape then idx = i break end
            end
            idx = clamp(idx + (d > 0 and 1 or -1), 1, #shapes)
            seg.shape = shapes[idx]
          elseif current_param_id == M.PARAM_LEVEL_MODE then
            local modes = Segment.level_modes()
            local idx = 1
            for i, m in ipairs(modes) do
              if m == seg.level_mode then idx = i break end
            end
            idx = clamp(idx + (d > 0 and 1 or -1), 1, #modes)
            seg.level_mode = modes[idx]
          elseif current_param_id == M.PARAM_LEVEL_RANGE then
            local step = 0.1
            local hi = 5
            seg.level_range = (seg.level_range or 0) + (d > 0 and step or -step)
            if seg.level_range < 0 then seg.level_range = 0 elseif seg.level_range > hi then seg.level_range = hi end
          elseif current_param_id == M.PARAM_LEVEL_RANDOM then
            local opts = { nil, "linear", "gaussian" }
            local idx = 1
            for i, o in ipairs(opts) do if o == (seg.level_random or nil) then idx = i break end end
            idx = clamp(idx + (d > 0 and 1 or -1), 1, #opts)
            seg.level_random = opts[idx]
          elseif current_param_id == M.PARAM_JUMP_SEGMENT then
            if seg.jump_to_segment == nil then
              if d > 0 then seg.jump_to_segment = 1 end
            else
              seg.jump_to_segment = seg.jump_to_segment + (d > 0 and 1 or -1)
              if seg.jump_to_segment < 1 then
                seg.jump_to_segment = nil
              else
                seg.jump_to_segment = clamp(seg.jump_to_segment, 1, Preset.max_segments())
              end
            end
          elseif current_param_id == M.PARAM_JUMP_PRESET then
            local presets = state.presets or {}
            -- list[1] = off (nil); list[2..] = preset ids. Do not use #list to append (Lua # is undefined when list[1] is nil).
            local list = { nil }
            for i, p in ipairs(presets) do
              list[i + 1] = p.id
            end
            local list_len = 1 + #presets
            local idx = 1
            if seg.jump_to_preset_id == nil then
              idx = 1
            else
              for i = 1, list_len do
                if list[i] == seg.jump_to_preset_id then idx = i break end
              end
            end
            local idx_before = idx
            -- Explicit step: d < 0 = decrease (toward off), d > 0 = increase
            if d < 0 and idx > 1 then
              idx = idx - 1
            elseif d > 0 and idx < list_len then
              idx = idx + 1
            end
            if _G.LINES_DEBUG_JUMP_PRESET and print then
              print("[lines] preset_jump E3: d=" .. tostring(d) .. " idx_before=" .. tostring(idx_before) .. " idx_after=" .. tostring(idx) .. " list_len=" .. tostring(list_len) .. " value=" .. (list[idx] and tostring(list[idx]) or "off"))
            end
            seg.jump_to_preset_id = list[idx]
          elseif current_param_id == M.PARAM_PING then
            local actions = { Segment.PING_INCREMENT, Segment.PING_DECREMENT, Segment.PING_RESET }
            local function ping_to_idx(pl, pa)
              if not pl or not pa then return 0 end
              local line = clamp(pl, 1, 4)
              local act = 0
              for i, a in ipairs(actions) do if a == pa then act = i break end end
              return (line - 1) * 3 + act
            end
            local function idx_to_ping(idx)
              if idx <= 0 then return nil, nil end
              local line = math.floor((idx - 1) / 3) + 1
              local act = (idx - 1) % 3 + 1
              return line, actions[act]
            end
            local idx = ping_to_idx(seg.ping_line, seg.ping_action)
            idx = clamp(idx + (d > 0 and 1 or -1), 0, 12)
            seg.ping_line, seg.ping_action = idx_to_ping(idx)
          elseif current_param_id and current_param_id >= M.PARAM_COND1_INPUT and current_param_id <= M.PARAM_COND2_PING then
            if not seg.cond1 then seg.cond1 = Segment.default_condition and Segment.default_condition(1) or {} end
            if not seg.cond2 then seg.cond2 = Segment.default_condition and Segment.default_condition(2) or {} end
            local c1, c2 = seg.cond1, seg.cond2
            if not c1.input then c1.input = "cv1" end
            if not c2.input then c2.input = "cv2" end
            if not c1.value_mode then c1.value_mode = "abs" end
            if not c2.value_mode then c2.value_mode = "abs" end
            if current_param_id == M.PARAM_COND1_INPUT or current_param_id == M.PARAM_COND2_INPUT then
              local inputs = Conditionals and Conditionals.input_sources and Conditionals.input_sources() or { "cv1", "cv2", "line1", "line2", "line3", "line4" }
              local cc = current_param_id == M.PARAM_COND1_INPUT and c1 or c2
              local cur = cc.input or "cv1"
              local si = 1
              for i, name in ipairs(inputs) do if name == cur then si = i break end end
              si = clamp(si + (d > 0 and 1 or -1), 1, #inputs)
              cc.input = inputs[si]
            elseif current_param_id == M.PARAM_COND1_COMPARISON or current_param_id == M.PARAM_COND2_COMPARISON then
              local comps = Conditionals and Conditionals.comparisons and Conditionals.comparisons() or { ">", ">=", "<", "<=", "=", "<>", "><" }
              local cc = current_param_id == M.PARAM_COND1_COMPARISON and c1 or c2
              local cur = cc.comparison or ">"
              local ci = 1
              for i, comp in ipairs(comps) do if comp == cur then ci = i break end end
              ci = clamp(ci + (d > 0 and 1 or -1), 1, #comps)
              cc.comparison = comps[ci]
            elseif current_param_id == M.PARAM_COND1_VALUE_MODE or current_param_id == M.PARAM_COND2_VALUE_MODE then
              local modes = Segment.cond_value_modes and Segment.cond_value_modes() or Segment.level_modes and Segment.level_modes() or { "abs", "absQ", "rel", "relQ" }
              local cc = current_param_id == M.PARAM_COND1_VALUE_MODE and c1 or c2
              local cur = cc.value_mode or "abs"
              local mi = 1
              for i, m in ipairs(modes) do if m == cur then mi = i break end end
              mi = clamp(mi + (d > 0 and 1 or -1), 1, #modes)
              cc.value_mode = modes[mi]
            elseif current_param_id == M.PARAM_COND1_VALUE or current_param_id == M.PARAM_COND2_VALUE then
              local c = current_param_id == M.PARAM_COND1_VALUE and c1 or c2
              local vm = c.value_mode or "abs"
              if vm == "absQ" or vm == "relQ" then
                local semitones = math.floor((c.value or 0) * 12 + 0.5)
                semitones = clamp(semitones + (d > 0 and 1 or -1), -48, 48)
                c.value = semitones / 12
              else
                local step = 0.1
                c.value = (c.value or 0) + (d > 0 and step or -step)
                c.value = clamp(c.value, state.voltage_lo, state.voltage_hi)
              end
            elseif current_param_id == M.PARAM_COND1_VALUE_HI or current_param_id == M.PARAM_COND2_VALUE_HI then
              local c = current_param_id == M.PARAM_COND1_VALUE_HI and c1 or c2
              local cmp = c.comparison or ">"
              if cmp ~= "<>" and cmp ~= "><" then return end
              if c.value_hi == nil then c.value_hi = c.value or 0 end
              local lo = c.value or 0
              local vm = c.value_mode or "abs"
              if vm == "absQ" or vm == "relQ" then
                local semitones = math.floor((c.value_hi or 0) * 12 + 0.5)
                local lo_st = math.floor(lo * 12 + 0.5)
                semitones = clamp(semitones + (d > 0 and 1 or -1), lo_st, 48)
                c.value_hi = semitones / 12
                if c.value_hi < lo then c.value_hi = lo end
              else
                local step = 0.1
                c.value_hi = (c.value_hi or lo) + (d > 0 and step or -step)
                c.value_hi = clamp(c.value_hi, state.voltage_lo, state.voltage_hi)
                if c.value_hi < lo then c.value_hi = lo end
              end
            elseif current_param_id == M.PARAM_COND1_JUMP_SEGMENT or current_param_id == M.PARAM_COND2_JUMP_SEGMENT then
              local c = current_param_id == M.PARAM_COND1_JUMP_SEGMENT and c1 or c2
              -- off (nil) -> stop (0) -> seg 1 -> ... -> seg 8; halt at off (left) and seg 8 (right)
              local list = { nil, 0, 1, 2, 3, 4, 5, 6, 7, 8 }
              local idx = 1
              if c.jump_to_segment == nil then idx = 1
              elseif c.jump_to_segment == 0 then idx = 2
              else idx = (c.jump_to_segment or 0) + 2 end
              idx = clamp(idx + (d > 0 and 1 or -1), 1, #list)
              c.jump_to_segment = list[idx]
            elseif current_param_id == M.PARAM_COND1_JUMP_PRESET or current_param_id == M.PARAM_COND2_JUMP_PRESET then
              local c = current_param_id == M.PARAM_COND1_JUMP_PRESET and c1 or c2
              local presets = state.presets or {}
              local list = { nil }; for i, p in ipairs(presets) do list[i + 1] = p.id end
              local list_len = 1 + #presets
              local idx = 1
              if c.jump_to_preset_id == nil then idx = 1 else for i = 1, list_len do if list[i] == c.jump_to_preset_id then idx = i break end end end
              if d < 0 and idx > 1 then idx = idx - 1 elseif d > 0 and idx < list_len then idx = idx + 1 end
              c.jump_to_preset_id = list[idx]
            elseif current_param_id == M.PARAM_COND1_PING or current_param_id == M.PARAM_COND2_PING then
              local c = current_param_id == M.PARAM_COND1_PING and c1 or c2
              local actions = { Segment.PING_INCREMENT, Segment.PING_DECREMENT, Segment.PING_RESET }
              local function ping_to_idx(pl, pa)
                if not pl or not pa then return 0 end
                local line = clamp(pl, 1, 4)
                local act = 0
                for i, a in ipairs(actions) do if a == pa then act = i break end end
                return (line - 1) * 3 + act
              end
              local function idx_to_ping(idx)
                if idx <= 0 then return nil, nil end
                local line = math.floor((idx - 1) / 3) + 1
                local act = (idx - 1) % 3 + 1
                return line, actions[act]
              end
              local idx = ping_to_idx(c.ping_line, c.ping_action)
              idx = clamp(idx + (d > 0 and 1 or -1), 0, 12)
              c.ping_line, c.ping_action = idx_to_ping(idx)
            end
          if state.preset_before_edit then state.preset_edited_dirty = true end
        end
      end
    end
    return
  end

  if state.screen == M.SCREEN_PROJECT then
    if state.project_sub_screen then
      if n == 1 or n == 2 or n == 3 then
        local list = state.project_list or {}
        state.project_list_index = clamp((state.project_list_index or 1) + (d > 0 and 1 or -1), 1, math.max(1, #list))
      end
    else
      if n == 1 or n == 2 or n == 3 then
        local available = M.project_available_actions(state)
        state.project_menu_index = clamp((state.project_menu_index or 1) + (d > 0 and 1 or -1), 1, #available)
      end
    end
    return
  end

  if state.screen == M.SCREEN_SETTINGS then
    if n == 2 then
      state.settings_field_index = clamp(state.settings_field_index + (d > 0 and 1 or -1), 1, 5)
    elseif n == 3 then
      local idx = state.settings_field_index
      if idx == 1 then
        state.line_count = clamp(state.line_count + (d > 0 and 1 or -1), 1, 4)
      elseif idx == 2 then
        local vr = (state.voltage_lo == -5 and state.voltage_hi == 5) and 1 or 2
        vr = clamp(vr + (d > 0 and 1 or -1), 1, 2)
        if vr == 1 then state.voltage_lo, state.voltage_hi = -5, 5 else state.voltage_lo, state.voltage_hi = -5, 10 end
      elseif idx == 3 then
        state.ext_clock_cv = clamp(state.ext_clock_cv + (d > 0 and 1 or -1), 1, 3)
      elseif idx == 4 then
        state.run_cv = clamp(state.run_cv + (d > 0 and 1 or -1), 1, 3)
      elseif idx == 5 then
        state.quantize = (d > 0) or not (d < 0)
      end
    end
    return
  end

  if state.screen == M.SCREEN_PRESET_SEQUENCER then
    if n == 1 then
      state.preset_sequencer_selected_line = clamp(state.preset_sequencer_selected_line + (d > 0 and 1 or -1), 1, state.line_count)
      local row = state.sequences and state.sequences[state.preset_sequencer_selected_line]
      local ids = row and row.preset_ids or {}
      local max_c = (#ids >= 8) and 8 or (#ids + 1)
      state.preset_sequencer_cursor = clamp(state.preset_sequencer_cursor, 1, math.max(1, max_c))
    elseif n == 2 then
      local row = state.sequences and state.sequences[state.preset_sequencer_selected_line]
      local ids = row and row.preset_ids or {}
      local old_cursor = state.preset_sequencer_cursor
      local was_on_empty = (old_cursor > #ids)
      local max_cursor = (#ids >= 8) and 8 or (#ids + 1)
      state.preset_sequencer_cursor = clamp(state.preset_sequencer_cursor + (d > 0 and 1 or -1), 1, math.max(1, max_cursor))
      local new_cursor = state.preset_sequencer_cursor
      local is_on_empty = (new_cursor > #ids)
      if was_on_empty and not is_on_empty then
        if state.sequencer_empty_slot_action_index then
          local available = M.sequencer_available_actions(state)
          state.preset_sequencer_action_index = clamp(state.sequencer_empty_slot_action_index, 1, #available)
        end
      elseif not was_on_empty and is_on_empty then
        state.sequencer_empty_slot_action_index = state.preset_sequencer_action_index
        local available = M.sequencer_available_actions(state)
        if #available > 0 then
          state.preset_sequencer_action_index = 1
        end
      end
    elseif n == 3 then
      local available = M.sequencer_available_actions(state)
      if #available > 0 then
        state.preset_sequencer_action_index = clamp(state.preset_sequencer_action_index, 1, #available)
        state.preset_sequencer_action_index = clamp(state.preset_sequencer_action_index + (d > 0 and 1 or -1), 1, #available)
      else
        state.preset_sequencer_action_index = 1
      end
    end
    return
  end
end

--- Get the preset currently being edited (or nil).
--- @param state table
--- @return table|nil preset
function M.get_editing_preset(state)
  if state.editing_preset_index == nil then return nil end
  return state.presets[state.editing_preset_index]
end

--- Deep copy a preset (id, name, segments and all segment fields including cond1/cond2).
--- @param p table preset
--- @return table|nil copy
function M.copy_preset(p)
  if not p or type(p) ~= "table" then return nil end
  local copy = { id = p.id, name = p.name, segments = {} }
  for i, seg in ipairs(p.segments or {}) do
    copy.segments[i] = {}
    for k, v in pairs(seg) do
      if type(v) == "table" and (k == "cond1" or k == "cond2") then
        copy.segments[i][k] = {}
        for k2, v2 in pairs(v) do copy.segments[i][k][k2] = v2 end
      else
        copy.segments[i][k] = v
      end
    end
  end
  return copy
end

--- List of visible preset editor param ids (0..26). When Cond1/Cond2 input is "off", that cond's cmp/mode/val/jump/ping params are hidden.
--- @param seg table segment (with cond1.input, cond2.input)
--- @return table array of param ids (1-based; param 0 = Name, 1 = Time unit, ...)
function M.visible_editor_params(seg)
  if not seg then return {} end
  local vis = {}
  for i = 0, 10 do vis[#vis + 1] = i end
  vis[#vis + 1] = M.PARAM_COND1_INPUT
  local c1 = seg.cond1
  if c1 and c1.input ~= "off" then
    for i = M.PARAM_COND1_COMPARISON, M.PARAM_COND1_PING do vis[#vis + 1] = i end
  end
  vis[#vis + 1] = M.PARAM_COND2_INPUT
  local c2 = seg.cond2
  if c2 and c2.input ~= "off" then
    for i = M.PARAM_COND2_COMPARISON, M.PARAM_COND2_PING do vis[#vis + 1] = i end
  end
  return vis
end

--- Sort state.presets alphabetically by name (then by id if same).
--- @param state table (mutated)
function M.sort_presets_alphabetically(state)
  local presets = state.presets
  if not presets or #presets < 2 then return end
  table.sort(presets, function(a, b)
    local na = (a and a.name) or (a and a.id) or ""
    local nb = (b and b.name) or (b and b.id) or ""
    na = na:lower()
    nb = nb:lower()
    if na ~= nb then return na < nb end
    return ((a and a.id) or "") < ((b and b.id) or "")
  end)
end

--- Preset Sequencer: list of available action ids. Cursor 1..#ids = on preset (Edit, Copy, Delete, Paste); cursor #ids+1 = end slot (Add, Paste).
--- @param state table
--- @return table list of M.SEQ_ACTION_* ids
function M.sequencer_available_actions(state)
  local row = state.sequences and state.sequences[state.preset_sequencer_selected_line]
  local ids = row and row.preset_ids or {}
  local cursor = state.preset_sequencer_cursor or 1
  local on_preset = (cursor >= 1 and cursor <= #ids)
  local list = {}
  if on_preset then
    list[#list + 1] = M.SEQ_ACTION_EDIT
    list[#list + 1] = M.SEQ_ACTION_COPY
    list[#list + 1] = M.SEQ_ACTION_REPLACE
    list[#list + 1] = M.SEQ_ACTION_DELETE
  else
    if #ids < 8 then
      list[#list + 1] = M.SEQ_ACTION_ADD
    end
  end
  if state.clipboard_preset then
    list[#list + 1] = M.SEQ_ACTION_PASTE
  end
  if #list == 0 then
    list[#list + 1] = M.SEQ_ACTION_ADD
  end
  table.insert(list, 1, M.SEQ_ACTION_PLAY_STOP)
  return list
end

--- Project menu: available actions in order. New/unsaved: Save As, Load, Set fast load, Delete. Saved: Save, Load, Save As, Rename, Set fast load, Delete.
--- @param state table
--- @return table list of M.PROJECT_* ids
function M.project_available_actions(state)
  local has_current = (state.current_project_path and state.current_project_path ~= "")
  if has_current then
    return { M.PROJECT_SAVE, M.PROJECT_LOAD, M.PROJECT_SAVE_AS, M.PROJECT_RENAME, M.PROJECT_SET_FAST_LOAD, M.PROJECT_DELETE }
  else
    return { M.PROJECT_LOAD, M.PROJECT_SAVE_AS, M.PROJECT_SET_FAST_LOAD, M.PROJECT_DELETE }
  end
end

--- Handle key: dispatch by screen. K1 is system-reserved on norns (opens system menu); script uses K2/K3 only.
--- @param state table mutated
--- @param n number key 2 or 3 (K1 not delivered to script)
--- @param z number 0 = release, 1 = press
--- @return string|nil action for app to handle (e.g. "navigate_back", "start_play", "open_editor")
function M.on_key(state, n, z)
  if z ~= 1 then return nil end

  if n == 3 and state.screen == M.SCREEN_MAIN_MENU then
    if state.main_menu_index == M.MENU_PRESETS_LIST then
      state.screen = M.SCREEN_PRESETS_LIST
      state.preset_list_index = #state.presets > 0 and 1 or 0
      state.sequencer_pick_preset_for_line = nil
      return "open_presets_list"
    elseif state.main_menu_index == M.MENU_PRESET_SEQUENCER then
      state.screen = M.SCREEN_PRESET_SEQUENCER
      local row = state.sequences and state.sequences[state.preset_sequencer_selected_line]
      local ids = row and row.preset_ids or {}
      local max_c = (#ids >= 8) and 8 or (#ids + 1)
      state.preset_sequencer_cursor = clamp(state.preset_sequencer_cursor or 1, 1, math.max(1, max_c))
      local available = M.sequencer_available_actions(state)
      if #available > 0 then
        state.preset_sequencer_action_index = clamp(state.preset_sequencer_action_index or 1, 1, #available)
      else
        state.preset_sequencer_action_index = 1
      end
      return "open_preset_sequencer"
    elseif state.main_menu_index == M.MENU_SETTINGS then
      state.screen = M.SCREEN_SETTINGS
      return "open_settings"
    elseif state.main_menu_index == M.MENU_PROJECT then
      state.screen = M.SCREEN_PROJECT
      state.project_sub_screen = nil
      local available = M.project_available_actions(state)
      state.project_menu_index = clamp(state.project_menu_index or 1, 1, #available)
      return "open_project"
    end
    return nil
  end

  if state.screen == M.SCREEN_PROJECT then
    if state.project_sub_screen then
      if state.project_delete_confirm then
        if n == 2 then
          state.project_delete_confirm = nil
          return "project_delete_cancel"
        end
        if n == 3 then return "project_delete_confirmed" end
        return nil
      end
      if n == 2 then
        state.project_sub_screen = nil
        return "project_list_back"
      end
      if n == 3 then
        if state.project_sub_screen == "load" then return "project_load_selected"
        elseif state.project_sub_screen == "fast_load" then return "project_set_fast_load_selected"
        elseif state.project_sub_screen == "delete" then
          local list = state.project_list or {}
          local idx = state.project_list_index or 1
          if idx >= 1 and idx <= #list then
            state.project_delete_confirm = list[idx]
            return "project_show_delete_confirm"
          end
        end
      end
      return nil
    end
    if n == 2 then
      state.screen = M.SCREEN_MAIN_MENU
      return "close_project"
    end
    if n == 3 then
      local available = M.project_available_actions(state)
      local idx = state.project_menu_index or 1
      local action_id = available[idx]
      if action_id == M.PROJECT_SAVE then return "project_save"
      elseif action_id == M.PROJECT_LOAD then return "project_load"
      elseif action_id == M.PROJECT_SAVE_AS then return "project_save_as"
      elseif action_id == M.PROJECT_RENAME then return "project_rename"
      elseif action_id == M.PROJECT_SET_FAST_LOAD then return "project_set_fast_load"
      elseif action_id == M.PROJECT_DELETE then return "project_delete"
      end
    end
    return nil
  end

  if state.screen == M.SCREEN_PRESETS_LIST then
    if n == 2 then
      if state.sequencer_pick_preset_for_line then
        state.sequencer_pick_preset_for_line = nil
        state.sequencer_pick_insert_at = nil
        state.sequencer_pick_replace_slot = nil
        state.sequencer_pick_selected_index = nil
        state.screen = M.SCREEN_PRESET_SEQUENCER
        return "close_presets_list"
      end
      state.screen = M.SCREEN_MAIN_MENU
      return "close_presets_list"
    end
    if n == 3 then
      if state.sequencer_pick_preset_for_line then
        if state.preset_list_index >= 1 and state.preset_list_index <= #state.presets then
          state.sequencer_add_preset_index = state.preset_list_index
          if _G.LINES_DEBUG_SEQUENCER_ADD and print then
            local p = state.presets and state.presets[state.preset_list_index]
            print("[lines] key K3 sequencer_add_preset: preset_list_index=" .. tostring(state.preset_list_index) .. " sequencer_add_preset_index=" .. tostring(state.sequencer_add_preset_index) .. " name=" .. (p and (p.name or p.id) or "?"))
          end
          return "sequencer_add_preset"
        end
      elseif state.preset_list_index >= 1 and state.preset_list_index <= #state.presets then
        if state.preset_list_action == "delete" then
          state.delete_confirm = state.preset_list_index
          return "confirm_delete_preset"
        end
        if state.preset_list_action == "duplicate" then
          return "duplicate_preset"
        end
        state.editing_preset_index = state.preset_list_index
        local p = state.presets[state.preset_list_index]
        if p then
          state.preset_before_edit = M.copy_preset(p)
          state.preset_edited_dirty = false
        end
        state.screen = M.SCREEN_PRESET_EDITOR
        state.editor_segment_index = 1
        state.editor_param_index = 0
        state.editing_name_position = 1
        return "open_preset_editor"
      end
      if state.preset_list_index == 0 and not state.sequencer_pick_preset_for_line then
        local existing_ids = {}
        for _, p in ipairs(state.presets or {}) do existing_ids[p.id] = true end
        local n = 1
        while existing_ids["preset_" .. n] do n = n + 1 end
        local new_id = "preset_" .. n
        local preset = Preset.new(new_id, "Preset_" .. n)
        table.insert(state.presets, preset)
        state.editing_preset_index = #state.presets
        state.preset_list_index = #state.presets
        state.preset_before_edit = nil
        state.preset_edited_dirty = false
        state.screen = M.SCREEN_PRESET_EDITOR
        state.editor_segment_index = 1
        state.editor_param_index = 0
        state.editing_name_position = 1
        state.preset_created_this_session = true
        return "open_preset_editor"
      end
    end
    return nil
  end

  if state.screen == M.SCREEN_PRESET_EDITOR then
    if n == 2 then
      if state.preset_created_this_session then
        state.pending_new_preset_save_confirm = true
        return "prompt_new_preset_save_discard"
      end
      if state.preset_edited_dirty and state.preset_before_edit then
        state.pending_edited_preset_save_confirm = true
        return "prompt_edited_preset_save"
      end
      if state.came_from_sequencer then
        state.screen = M.SCREEN_PRESET_SEQUENCER
        state.came_from_sequencer = false
      else
        state.screen = M.SCREEN_PRESETS_LIST
      end
      state.editing_preset_index = nil
      state.preset_before_edit = nil
      state.preset_edited_dirty = false
      return "close_preset_editor"
    end
    return nil
  end

  if state.screen == M.SCREEN_SETTINGS then
    if n == 2 then
      state.screen = M.SCREEN_MAIN_MENU
      return "close_settings"
    end
    return nil
  end

  -- K3 Play/Stop (and other sequencer actions) only on Preset Sequencer screen, not on Presets list.
  if state.screen == M.SCREEN_PRESET_SEQUENCER then
    if n == 2 then
      state.screen = M.SCREEN_MAIN_MENU
      return "close_preset_sequencer"
    end
    if n == 3 then
      return "sequencer_action"
    end
    return nil
  end

  return nil
end

return M
