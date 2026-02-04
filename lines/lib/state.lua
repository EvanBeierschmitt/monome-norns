-- lib/state.lua
-- Application state and screen navigation. Pure(ish) transitions where possible.

local Preset = include("lib/preset")
local Segment = include("lib/segment")
local Sequencer = include("lib/sequencer")

local M = {}

-- Screen identifiers
M.SCREEN_MAIN_MENU = "main_menu"
M.SCREEN_PRESET_SEQUENCER = "preset_sequencer"
M.SCREEN_PRESETS_LIST = "presets_list"
M.SCREEN_PRESET_EDITOR = "preset_editor"
M.SCREEN_SETTINGS = "settings"

-- Main menu item indices (E1). Preset Editor not in menu; enter from Presets list.
M.MENU_PRESET_SEQUENCER = 1
M.MENU_PRESETS_LIST = 2
M.MENU_SETTINGS = 3
M.MENU_COUNT = 3

-- Preset editor parameters (E2)
M.PARAM_TIME = 1
M.PARAM_TIME_UNIT = 2
M.PARAM_LEVEL_MODE = 3
M.PARAM_LEVEL_VALUE = 4
M.PARAM_SHAPE = 5
M.PARAM_JUMP = 6
M.PARAM_PING = 7
M.PARAM_COUNT = 7

-- Preset sequencer actions (E3)
M.SEQ_ACTION_EDIT = 1
M.SEQ_ACTION_COPY = 2
M.SEQ_ACTION_PASTE = 3
M.SEQ_ACTION_DELETE = 4
M.SEQ_ACTION_ADD = 5
M.SEQ_ACTION_COUNT = 5

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
    settings_field_index = 1,
    preset_delete_candidate = nil,
    editing_name_position = 1,
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
  if type(state.main_menu_index) ~= "number" or state.main_menu_index < 1 or state.main_menu_index > M.MENU_COUNT then
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
      local old_idx = state.preset_list_index
      local max_idx = count >= 1 and (count + 1) or 0
      state.preset_list_index = clamp(state.preset_list_index + (d > 0 and 1 or -1), 0, max_idx)
      if count >= 1 and state.preset_list_index == count + 1 and old_idx >= 1 and old_idx <= count then
        state.preset_delete_candidate = old_idx
      end
    end
    return
  end

  if state.screen == M.SCREEN_PRESET_EDITOR then
    if n == 1 then
      state.editor_segment_index = clamp(state.editor_segment_index + (d > 0 and 1 or -1), 1, Preset.max_segments())
    elseif n == 2 then
      local p = M.get_editing_preset(state)
      if state.editor_param_index == 0 and p then
        local MAX_NAME_LEN = 16
        local len = #(p.name or "")
        local max_pos = math.min(len + 1, MAX_NAME_LEN)
        local pos = state.editing_name_position or 1
        if pos == 1 and d < 0 then
          state.editor_param_index = M.PARAM_COUNT
        elseif pos >= max_pos and d > 0 then
          state.editor_param_index = 1
        else
          state.editing_name_position = clamp(pos + (d > 0 and 1 or -1), 1, math.max(1, max_pos))
        end
      else
        state.editor_param_index = clamp(state.editor_param_index + (d > 0 and 1 or -1), 0, M.PARAM_COUNT)
      end
    elseif n == 3 then
      local p = M.get_editing_preset(state)
      if p then
        if state.editor_param_index == 0 then
          local CHARSET = " ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"
          local pos = state.editing_name_position or 1
          local name = p.name or ""
          while #name < pos do name = name .. " " end
          if #name > 16 then name = name:sub(1, 16) end
          local ch = name:sub(pos, pos)
          if ch == "" then ch = " " end
          local idx = 0
          for i = 1, #CHARSET do if CHARSET:sub(i, i) == ch then idx = i break end end
          if idx == 0 then idx = 1 end
          idx = idx + (d > 0 and 1 or -1)
          if idx < 1 then idx = #CHARSET elseif idx > #CHARSET then idx = 1 end
          ch = CHARSET:sub(idx, idx)
          name = name:sub(1, pos - 1) .. ch .. name:sub(pos + 1)
          p.name = name:sub(1, 16)
          if p.name == "" then p.name = " " end
        else
          local coarse = false
          local seg = p.segments[state.editor_segment_index]
          if seg then
            if state.editor_param_index == M.PARAM_TIME then
            local step = coarse and 10 or 1
            local hi = (seg.time_unit or "sec") == "beats" and 999 or 9999
            seg.time = clamp(seg.time + (d > 0 and step or -step), 1, hi)
          elseif state.editor_param_index == M.PARAM_TIME_UNIT then
            local units = { "sec", "beats" }
            local idx = 1
            for i, u in ipairs(units) do if u == (seg.time_unit or "sec") then idx = i break end end
            idx = clamp(idx + (d > 0 and 1 or -1), 1, #units)
            seg.time_unit = units[idx]
            if seg.time_unit == "beats" and seg.time > 999 then seg.time = 999 end
          elseif state.editor_param_index == M.PARAM_LEVEL_VALUE then
            local step = coarse and 0.5 or 0.1
            seg.level_value = clamp(seg.level_value + (d > 0 and step or -step), state.voltage_lo, state.voltage_hi)
          elseif state.editor_param_index == M.PARAM_SHAPE then
            local shapes = Segment.shapes()
            local idx = 1
            for i, s in ipairs(shapes) do
              if s == seg.shape then idx = i break end
            end
            idx = clamp(idx + (d > 0 and 1 or -1), 1, #shapes)
            seg.shape = shapes[idx]
          elseif state.editor_param_index == M.PARAM_LEVEL_MODE then
            local modes = Segment.level_modes()
            local idx = 1
            for i, m in ipairs(modes) do
              if m == seg.level_mode then idx = i break end
            end
            idx = clamp(idx + (d > 0 and 1 or -1), 1, #modes)
            seg.level_mode = modes[idx]
          elseif state.editor_param_index == M.PARAM_JUMP then
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
          elseif state.editor_param_index == M.PARAM_PING then
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
          end
          end
        end
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
    elseif n == 2 then
      local row = state.sequences and state.sequences[state.preset_sequencer_selected_line]
      local max_cursor = row and (2 * #row.preset_ids + 1) or 1
      state.preset_sequencer_cursor = clamp(state.preset_sequencer_cursor + (d > 0 and 1 or -1), 1, math.max(1, max_cursor))
    elseif n == 3 then
      state.preset_sequencer_action_index = clamp(state.preset_sequencer_action_index + (d > 0 and 1 or -1), 1, M.SEQ_ACTION_COUNT)
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

--- Handle key: dispatch by screen. K1 is system-reserved on norns (opens system menu); script uses K2/K3 only.
--- @param state table mutated
--- @param n number key 2 or 3 (K1 not delivered to script)
--- @param z number 0 = release, 1 = press
--- @return string|nil action for app to handle (e.g. "navigate_back", "start_play", "open_editor")
function M.on_key(state, n, z)
  if z ~= 1 then return nil end

  if n == 3 and state.screen == M.SCREEN_MAIN_MENU then
    if state.main_menu_index == M.MENU_PRESET_SEQUENCER then
      state.screen = M.SCREEN_PRESET_SEQUENCER
      return "open_preset_sequencer"
    elseif state.main_menu_index == M.MENU_PRESETS_LIST then
      state.screen = M.SCREEN_PRESETS_LIST
      state.preset_list_index = #state.presets > 0 and 1 or 0
      return "open_presets_list"
    elseif state.main_menu_index == M.MENU_SETTINGS then
      state.screen = M.SCREEN_SETTINGS
      return "open_settings"
    end
    return nil
  end

  if state.screen == M.SCREEN_PRESETS_LIST then
    if n == 2 then
      state.screen = M.SCREEN_MAIN_MENU
      return "close_presets_list"
    end
    if n == 3 then
      if state.sequencer_pick_preset_for_line and #state.presets > 0 and state.preset_list_index >= 1 then
        return "sequencer_add_preset"
      end
      if state.preset_list_index == #state.presets + 1 and #state.presets >= 1 and state.preset_delete_candidate then
        state.delete_confirm = state.preset_delete_candidate
        return "confirm_delete_preset"
      end
      if state.preset_list_index == 0 then
        local preset = Preset.new("preset_1", "Preset 1")
        table.insert(state.presets, preset)
        state.editing_preset_index = #state.presets
        state.preset_list_index = #state.presets
        state.screen = M.SCREEN_PRESET_EDITOR
        state.editor_segment_index = 1
        state.editor_param_index = 0
        state.editing_name_position = 1
        return "open_preset_editor"
      end
      if state.preset_list_index >= 1 and state.preset_list_index <= #state.presets then
        state.editing_preset_index = state.preset_list_index
        state.screen = M.SCREEN_PRESET_EDITOR
        state.editor_segment_index = 1
        state.editor_param_index = 0
        state.editing_name_position = 1
        return "open_preset_editor"
      end
    end
    return nil
  end

  if state.screen == M.SCREEN_PRESET_EDITOR then
    if n == 2 then
      state.screen = M.SCREEN_PRESETS_LIST
      state.editing_preset_index = nil
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
