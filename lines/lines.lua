-- scriptname: Lines
-- v0.1.0 @evanbeierschmitt
-- Sequencable function generator for Crow CV. Inspired by Control Forge.

-- Workaround: on hot reload, norns clock can try to resume stale coroutines (bad argument #1 to 'resume' (thread expected)).
-- If clock is global and has resume, wrap it to ignore invalid threads so the script loads cleanly.
do
  local c = _G.clock
  if c and type(c.resume) == "function" then
    local orig = c.resume
    c.resume = function(thread, ...)
      if type(thread) == "thread" then return orig(thread, ...) end
      return nil
    end
  end
end

-- Build draw commands entirely in script so no module code runs during redraw (norns errors otherwise).
local Segment = include("lib/segment")
local State = include("lib/state")
local SCREEN_MAIN_MENU = "main_menu"
local SCREEN_PRESETS_LIST = "presets_list"
local SCREEN_PRESET_EDITOR = "preset_editor"
local SCREEN_PRESET_SEQUENCER = "preset_sequencer"
local SCREEN_SETTINGS = "settings"
local SCREEN_PROJECT = "project"
local LEVEL_HINT = 4
local LEVEL_UNSELECTED = 8
local LEVEL_TITLE = 12
local LEVEL_SELECTED = 15
local Y_STATUS = 6
local Y_CONTENT_START = 18
local Y_FOOTER = 64
local VALUE_X_RIGHT = 118
local CONTENT_H = 46
local ROW_H = 10
local SCROLLBAR_X = 124
local SCROLLBAR_W = 2
local PARAM_COUNT = 6
local PROJECT_MENU_VISIBLE = 4
local PROJECT_LIST_START = 32

-- Set to false for release; when true, show last enc/key or "input ok" on main menu to confirm input reaches script
local DEBUG_INPUT = false
local last_enc = nil
local last_key = nil
local last_enc_time = 0
local last_key_time = 0

-- Approximate character width for norns font (pixels)
local CHAR_WIDTH = 6
-- Available width for right-aligned text values (VALUE_X_RIGHT - label_end, conservative estimate)
-- Only scroll if text exceeds this by a margin to avoid unnecessary scrolling
local VALUE_AVAILABLE_WIDTH = 60

-- Calculate approximate text width in pixels
local function text_width(str)
  if not str then return 0 end
  return #tostring(str) * CHAR_WIDTH
end

-- Get or create scroll state for a text field
local function get_scroll_state(state, key, text)
  if not state.text_scroll_offsets then state.text_scroll_offsets = {} end
  local width = text_width(text)
  local max_offset = math.max(0, width - VALUE_AVAILABLE_WIDTH)
  if max_offset <= 0 then
    if state.text_scroll_offsets[key] then
      state.text_scroll_offsets[key] = nil
    end
    return { offset = 0, max_offset = 0 }
  end
  if not state.text_scroll_offsets[key] then
    state.text_scroll_offsets[key] = {
      offset = 0,
      max_offset = max_offset,
      pause_count = 0,
    }
  else
    state.text_scroll_offsets[key].max_offset = max_offset
  end
  return state.text_scroll_offsets[key]
end

-- Apply scroll offset to text and return modified x position
local function apply_text_scroll(state, key, text, x_pos)
  local scroll = get_scroll_state(state, key, text)
  if scroll.max_offset > 0 then
    local scroll_x = x_pos - scroll.offset
    return scroll_x, scroll.offset
  end
  return x_pos, 0
end

local function build_draw_commands(state)
  local cmds = {}
  local function add(...) table.insert(cmds, {...}) end
  local s = state or {}
  add("clear")
  add("level", LEVEL_SELECTED)
  if s.screen == SCREEN_MAIN_MENU then
    add("move", 4, Y_STATUS)
    add("level", LEVEL_TITLE)
    add("text", "Lines")
    local idx = s.main_menu_index or 1
    local items = { "Presets", "Preset Sequencer", "Settings", "Project" }
    for i, name in ipairs(items) do
      local y = Y_CONTENT_START + (i - 1) * 10
      add("move", 4, y)
      if i == idx then add("level", LEVEL_SELECTED); add("text", "> " .. name)
      else add("level", LEVEL_UNSELECTED); add("text", "  " .. name) end
    end
    if DEBUG_INPUT then
      add("move", 4, Y_FOOTER)
      add("level", LEVEL_HINT)
      local now = (os and os.clock and os.clock()) or 0
      add("move", 4, 63)
      add("level", LEVEL_HINT)
      if (now - last_enc_time) < 1 or (now - last_key_time) < 1 then
        add("text", "input ok")
      elseif (now - last_enc_time) >= 5 and (now - last_key_time) >= 5 then
        add("text", "No input: open norns.local")
      else
        add("text", "E" .. tostring(last_enc or "-") .. " K" .. tostring(last_key or "-"))
      end
    end
  elseif s.screen == SCREEN_PRESETS_LIST then
    if s.delete_confirm then
      add("move", 4, Y_STATUS)
      add("level", LEVEL_TITLE)
      add("text", "Delete preset?")
      add("move", 4, 20)
      add("level", LEVEL_UNSELECTED)
      local p = (s.presets or {})[s.delete_confirm]
      if p then add("text", p.name or p.id or "?") end
      add("move", 4, 30)
      add("level", LEVEL_UNSELECTED)
      add("text", "Are you sure?")
      add("move", 4, 44)
      add("level", LEVEL_HINT)
      add("text", "K3 yes  K2 no")
    else
      local pick_for_sequencer = (s.sequencer_pick_preset_for_line ~= nil)
      local presets = s.presets or {}
      local cur = s.preset_list_index or 0
      local total, scroll_offset, visible
      if pick_for_sequencer then
        add("move", 4, Y_STATUS)
        add("level", LEVEL_TITLE)
        add("text", "Select Available Preset")
        total = #presets
        visible = math.floor(CONTENT_H / ROW_H)
        if total == 0 then
          add("move", 4, Y_CONTENT_START + 8)
          add("level", LEVEL_UNSELECTED)
          add("text", "(no presets - create from Presets)")
          add("move", 4, Y_CONTENT_START + 22)
          add("level", LEVEL_HINT)
          add("text", "K2 back")
        else
          scroll_offset = total > visible and math.max(0, math.min(cur - 1, total - visible)) or 0
          for i = 0, visible - 1 do
            local r = scroll_offset + i + 1
            if r <= total then
              local y = Y_CONTENT_START + i * ROW_H
              local p = presets[r]
              if p then
                add("move", 4, y)
                add("level", r == cur and LEVEL_SELECTED or LEVEL_UNSELECTED)
                add("text", (r == cur and "> " or "  ") .. (p.name or p.id or "?"))
              end
            end
          end
          if total > visible then
            add("level", LEVEL_HINT)
            add("rect", SCROLLBAR_X, Y_CONTENT_START, SCROLLBAR_W, CONTENT_H, false)
            local thumb_h = math.max(1, math.floor(CONTENT_H * visible / total))
            local thumb_y = Y_CONTENT_START + math.floor((CONTENT_H - thumb_h) * scroll_offset / math.max(1, total - visible))
            add("rect", SCROLLBAR_X, thumb_y, SCROLLBAR_W, thumb_h, true)
          end
        end
      else
        add("move", 4, Y_STATUS)
        add("level", LEVEL_TITLE)
        add("text", "Presets")
        total = #presets + 1
        visible = math.floor(CONTENT_H / ROW_H)
        scroll_offset = total > visible and math.max(0, math.min(cur, total - visible)) or 0
        for i = 0, visible - 1 do
          local r = scroll_offset + i
          if r < total then
            local y = Y_CONTENT_START + i * ROW_H
            add("move", 4, y)
            if r == 0 then
              add("level", cur == 0 and LEVEL_SELECTED or LEVEL_UNSELECTED)
              add("text", (cur == 0 and "> " or "  ") .. "+ Create New Preset")
            else
              local p = presets[r]
              if p then
                add("level", r == cur and LEVEL_SELECTED or LEVEL_UNSELECTED)
                add("text", (r == cur and "> " or "  ") .. (p.name or p.id or "?"))
              end
            end
          end
        end
        if cur >= 1 and cur <= #presets then
          add("move", 4, Y_FOOTER - 6)
          add("level", LEVEL_HINT)
          local act = s.preset_list_action or "edit"
          add("text", (act == "edit" and "> " or "  ") .. "Edit  " .. (act == "delete" and "> " or "  ") .. "Del  " .. (act == "duplicate" and "> " or "  ") .. "Dup")
        end
        if total > visible then
          add("level", LEVEL_HINT)
          add("rect", SCROLLBAR_X, Y_CONTENT_START, SCROLLBAR_W, CONTENT_H, false)
          local thumb_h = math.max(1, math.floor(CONTENT_H * visible / total))
          local thumb_y = Y_CONTENT_START + math.floor((CONTENT_H - thumb_h) * scroll_offset / math.max(1, total - visible))
          add("rect", SCROLLBAR_X, thumb_y, SCROLLBAR_W, thumb_h, true)
        end
      end
    end
  elseif s.screen == SCREEN_PRESET_EDITOR then
    if s.pending_name_save_confirm then
      add("move", 4, Y_STATUS); add("level", LEVEL_TITLE); add("text", "Save preset name changes?")
      add("move", 4, Y_CONTENT_START + 10); add("level", LEVEL_UNSELECTED); add("text", "K2 Discard   K3 Save")
    elseif s.preset_name_edit_mode then
      add("move", 4, Y_STATUS); add("level", LEVEL_TITLE); add("text", "Edit name")
      local buf = s.preset_name_edit_buffer or ""
      local last_char = 0
      for i = #buf, 1, -1 do
        if buf:sub(i, i) ~= " " then last_char = i break end
      end
      local max_pos = last_char + 1
      local pos = math.max(1, math.min(max_pos, s.editing_name_position or 1))
      local y = Y_CONTENT_START + 8
      for i = 1, #buf do
        local char = buf:sub(i, i)
        local is_cur = (i == pos)
        add("move", 4 + (i - 1) * 6, y)
        add("level", is_cur and LEVEL_SELECTED or LEVEL_UNSELECTED)
        add("text", (is_cur and (char == " " or char == "")) and "_" or char)
      end
      if pos == #buf + 1 then
        add("move", 4 + #buf * 6, y); add("level", LEVEL_SELECTED); add("text", "_")
      end
      add("move", 4, Y_CONTENT_START + 28); add("level", LEVEL_HINT); add("text", "E1 del  E2 char  E3 pos")
      add("move", 4, Y_FOOTER - 8); add("level", LEVEL_HINT); add("text", "K2 back  K3 save")
    elseif s.pending_edited_preset_save_confirm then
      add("move", 4, Y_STATUS); add("level", LEVEL_TITLE); add("text", "Keep your changes?")
      add("move", 4, Y_CONTENT_START + 10); add("level", LEVEL_UNSELECTED); add("text", "K2 Discard   K3 Save")
    elseif s.pending_new_preset_save_confirm then
      add("move", 4, Y_STATUS); add("level", LEVEL_TITLE); add("text", "Save preset?")
      add("move", 4, Y_CONTENT_START + 10); add("level", LEVEL_UNSELECTED); add("text", "K2 Discard   K3 Save")
    else
    local p = s.editing_preset_index and (s.presets or {})[s.editing_preset_index]
    if not p then
      add("move", 4, Y_STATUS); add("level", LEVEL_TITLE); add("text", "No preset")
      add("move", 4, 24); add("level", LEVEL_UNSELECTED); add("text", "No preset")
    else
      add("move", 4, Y_STATUS); add("level", LEVEL_TITLE); add("text", p.name or p.id or "Preset")
      local seg_idx = s.editor_segment_index or 1
      local param_idx = s.editor_param_index or 1
      local param_names = {
        "Name:", "Time unit:", "Time:", "Mode:", "Level:", "Level range:", "Level random:",
        "Shape:", "Segment jump:", "Preset jump:", "Ping:",
        "Cond1 in:", "Cond1 cmp:", "Cond1 mode:", "Cond1 val:", "Cond1 val hi:", "Cond1 jump:", "Cond1 jpre:", "Cond1 ping:",
        "Cond2 in:", "Cond2 cmp:", "Cond2 mode:", "Cond2 val:", "Cond2 val hi:", "Cond2 jump:", "Cond2 jpre:", "Cond2 ping:",
      }
      local seg = p.segments and p.segments[seg_idx]
      if not seg then
        add("move", 4, Y_CONTENT_START); add("level", LEVEL_UNSELECTED); add("text", "seg " .. seg_idx)
      else
        add("move", 4, Y_CONTENT_START); add("level", LEVEL_UNSELECTED); add("text", "seg " .. seg_idx .. " / 8")
        local visible = State.visible_editor_params(seg) or {}
        local total_rows = #visible
        local param_row_h = 8
        local visible_params = math.floor((CONTENT_H - 10) / param_row_h)
        local param_scroll = total_rows > visible_params and math.max(0, math.min(param_idx, total_rows - visible_params)) or 0
        for i = 1, visible_params do
          local row_idx = param_scroll + i - 1
          if row_idx < total_rows then
            local param_id = visible[row_idx + 1]
            local y = Y_CONTENT_START + 10 + (i - 1) * param_row_h
            add("move", 4, y)
            if row_idx == param_idx then add("level", LEVEL_SELECTED) else add("level", LEVEL_UNSELECTED) end
            add("text", param_names[param_id + 1] or "?")
            local val
            if param_id == 0 then
              val = p.name or p.id or "Preset"
            else
              if param_id == 1 then val = seg.time_unit or "sec"
              elseif param_id == 2 then
                local tu = seg.time_unit or "sec"
                val = tostring(seg.time) .. (tu == "beats" and " bt" or " s")
              elseif param_id == 3 then val = seg.level_mode or "abs"
              elseif param_id == 4 then
                if seg.level_mode == "absQ" then
                  val = Segment and Segment.voltage_to_note and Segment.voltage_to_note(seg.level_value or 0) or string.format("%.2f", seg.level_value or 0)
                elseif seg.level_mode == "relQ" then
                  val = tostring(math.floor((seg.level_value or 0) * 12 + 0.5)) .. " st"
                else
                  val = string.format("%.2f", seg.level_value or 0)
                end
              elseif param_id == 5 then val = string.format("%.2f", seg.level_range or 0)
              elseif param_id == 6 then val = (seg.level_random == "gaussian" and "Gaussian") or (seg.level_random == "linear" and "linear") or "off"
              elseif param_id == 7 then val = Segment.shape_display_name(seg.shape) or "Linear"
              elseif param_id == 8 then val = seg.jump_to_segment and ("seg " .. seg.jump_to_segment) or "stop"
              elseif param_id == 9 then
                if seg.jump_to_preset_id then
                  local name = "off"
                  for _, pr in ipairs(s.presets or {}) do
                    if pr.id == seg.jump_to_preset_id then name = pr.name or pr.id break end
                  end
                  val = name
                else
                  val = "off"
                end
              elseif param_id == 10 then val = (seg.ping_line and seg.ping_action) and ("L" .. seg.ping_line .. " " .. (seg.ping_action or "")) or "off"
              elseif param_id >= 11 and param_id <= 18 then
                local c = seg.cond1
                if not c then val = "" else
                  if param_id == 11 then val = c.input or "cv1"
                  elseif param_id == 12 then val = c.comparison or ">"
                  elseif param_id == 13 then val = c.value_mode or "abs"
                  elseif param_id == 14 then
                    local vm = c.value_mode or "abs"
                    if vm == "absQ" then val = Segment and Segment.voltage_to_note and Segment.voltage_to_note(c.value or 0) or string.format("%.2f", c.value or 0)
                    elseif vm == "relQ" then val = tostring(math.floor((c.value or 0) * 12 + 0.5)) .. " st"
                    else val = string.format("%.2f", c.value or 0) end
                  elseif param_id == 15 then
                    local cmp = c.comparison or ">"
                    if cmp == "<>" or cmp == "><" then
                      local vm = c.value_mode or "abs"
                      if vm == "absQ" then val = Segment and Segment.voltage_to_note and Segment.voltage_to_note(c.value_hi or c.value or 0) or string.format("%.2f", c.value_hi or c.value or 0)
                      elseif vm == "relQ" then val = tostring(math.floor((c.value_hi or c.value or 0) * 12 + 0.5)) .. " st"
                      else val = string.format("%.2f", c.value_hi or c.value or 0) end
                    else val = "-" end
                  elseif param_id == 16 then val = c.jump_to_segment == nil and "off" or (c.jump_to_segment == 0 and "stop" or ("seg " .. c.jump_to_segment))
                  elseif param_id == 17 then
                    if c.jump_to_preset_id then
                      local name = "off"
                      for _, pr in ipairs(s.presets or {}) do if pr.id == c.jump_to_preset_id then name = pr.name or pr.id break end end
                      val = name
                    else val = "off" end
                  else val = (c.ping_line and c.ping_action) and ("L" .. c.ping_line .. " " .. (c.ping_action or "")) or "off" end
                end
              elseif param_id >= 19 and param_id <= 26 then
                local c = seg.cond2
                if not c then val = "" else
                  if param_id == 19 then val = c.input or "cv2"
                  elseif param_id == 20 then val = c.comparison or ">"
                  elseif param_id == 21 then val = c.value_mode or "abs"
                  elseif param_id == 22 then
                    local vm = c.value_mode or "abs"
                    if vm == "absQ" then val = Segment and Segment.voltage_to_note and Segment.voltage_to_note(c.value or 0) or string.format("%.2f", c.value or 0)
                    elseif vm == "relQ" then val = tostring(math.floor((c.value or 0) * 12 + 0.5)) .. " st"
                    else val = string.format("%.2f", c.value or 0) end
                  elseif param_id == 23 then
                    local cmp = c.comparison or ">"
                    if cmp == "<>" or cmp == "><" then
                      local vm = c.value_mode or "abs"
                      if vm == "absQ" then val = Segment and Segment.voltage_to_note and Segment.voltage_to_note(c.value_hi or c.value or 0) or string.format("%.2f", c.value_hi or c.value or 0)
                      elseif vm == "relQ" then val = tostring(math.floor((c.value_hi or c.value or 0) * 12 + 0.5)) .. " st"
                      else val = string.format("%.2f", c.value_hi or c.value or 0) end
                    else val = "-" end
                  elseif param_id == 24 then val = c.jump_to_segment == nil and "off" or (c.jump_to_segment == 0 and "stop" or ("seg " .. c.jump_to_segment))
                  elseif param_id == 25 then
                    if c.jump_to_preset_id then
                      local name = "off"
                      for _, pr in ipairs(s.presets or {}) do if pr.id == c.jump_to_preset_id then name = pr.name or pr.id break end end
                      val = name
                    else val = "off" end
                  else val = (c.ping_line and c.ping_action) and ("L" .. c.ping_line .. " " .. (c.ping_action or "")) or "off" end
                end
              else val = "" end
            end
            local scroll_key = "preset_editor_" .. seg_idx .. "_" .. param_id
            local scroll = get_scroll_state(s, scroll_key, val)
            local display_val = val
            if scroll.max_offset > 0 then
              local str = tostring(val)
              local char_offset = math.floor(scroll.offset / CHAR_WIDTH)
              if char_offset >= 0 and char_offset < #str then
                display_val = string.sub(str, char_offset + 1)
              else
                display_val = str
              end
            end
            add("move", VALUE_X_RIGHT, y)
            if row_idx == param_idx then add("level", LEVEL_SELECTED) else add("level", LEVEL_UNSELECTED) end
            add("text_right", display_val)
          end
        end
        if total_rows > visible_params then
          add("level", LEVEL_HINT)
          add("rect", SCROLLBAR_X, Y_CONTENT_START, SCROLLBAR_W, CONTENT_H, false)
          local thumb_h = math.max(1, math.floor(CONTENT_H * visible_params / total_rows))
          local thumb_y = Y_CONTENT_START + math.floor((CONTENT_H - thumb_h) * param_scroll / math.max(1, total_rows - visible_params))
          add("rect", SCROLLBAR_X, thumb_y, SCROLLBAR_W, thumb_h, true)
        end
      end
    end
    end
  elseif s.screen == SCREEN_PRESET_SEQUENCER then
    if s.sequencer_delete_confirm then
      add("move", 4, Y_STATUS); add("level", LEVEL_TITLE); add("text", "Delete from sequence?")
      add("move", 4, 24); add("level", LEVEL_UNSELECTED); add("text", "Are you sure?")
      add("move", 4, 44); add("level", LEVEL_HINT); add("text", "K3 yes  K2 no")
    else
    local line = s.preset_sequencer_selected_line or 1
    local seq = s.sequences and s.sequences[line] or {}
    local ids = seq.preset_ids or {}
    local cursor = s.preset_sequencer_cursor or 1
    local action_idx = s.preset_sequencer_action_index or 1
    local available_actions = State.sequencer_available_actions(s)
    if #available_actions == 0 or action_idx < 1 or action_idx > #available_actions then
      action_idx = 1
    end
    local action_id_to_name = { [State.SEQ_ACTION_EDIT] = "Edit", [State.SEQ_ACTION_COPY] = "Copy", [State.SEQ_ACTION_PASTE] = "Paste", [State.SEQ_ACTION_DELETE] = "Delete", [State.SEQ_ACTION_ADD] = "Add", [State.SEQ_ACTION_REPLACE] = "Replace", [State.SEQ_ACTION_PLAY_STOP] = (s.sequencer_running and "Stop" or "Play") }
    local action_name = action_id_to_name[available_actions[action_idx]] or "Add"
    if action_name == "Paste" and s.clipboard_preset then
      action_name = "Paste: " .. (s.clipboard_preset.name or s.clipboard_preset.id or "?")
    end
    local total_slots = #ids
    local visible_rows = math.floor(CONTENT_H / ROW_H)
    local logical_rows = total_slots + 1
    local R = math.floor((cursor - 1) / 2)
    local scroll_max = math.max(0, logical_rows - visible_rows)
    local scroll_offset = math.max(0, math.min(R - visible_rows + 1, scroll_max))
    add("move", 4, Y_STATUS); add("level", LEVEL_TITLE); add("text", "Preset Sequencer  L" .. line)
    add("move", VALUE_X_RIGHT, Y_STATUS); add("level", LEVEL_SELECTED); add("text_right", s.sequencer_running and "■" or "▶")
    if total_slots == 0 then
      add("move", 4, Y_CONTENT_START); add("level", LEVEL_UNSELECTED); add("text", "(empty)")
    else
      local logical_rows = (total_slots >= 8) and total_slots or (total_slots + 1)
      local scroll_max = math.max(0, logical_rows - visible_rows)
      local scroll_offset = math.max(0, math.min(cursor - 1, scroll_max))
      local arrow_row_local = cursor - scroll_offset
      for i = 1, visible_rows do
        local row_index = scroll_offset + i
        local y = Y_CONTENT_START + (i - 1) * ROW_H
        local is_selected = (arrow_row_local == i) or (arrow_row_local < 1 and i == 1) or (arrow_row_local > visible_rows and i == visible_rows)
        add("move", 4, y)
        add("level", is_selected and LEVEL_SELECTED or LEVEL_UNSELECTED)
        add("text", is_selected and ">" or " ")
        add("move", 4 + CHAR_WIDTH, y)
        if row_index <= total_slots then
          local pid = ids[row_index]
          local name = pid or "?"
          for _, pr in ipairs(s.presets or {}) do if pr.id == pid then name = pr.name or pr.id break end end
          add("text", string.format("%2d  %s", row_index, name))
        elseif total_slots < 8 then
          add("text", string.format("%2s  %s", "+", "(add)"))
        end
      end
      if logical_rows > visible_rows then
        add("level", LEVEL_HINT)
        add("rect", SCROLLBAR_X, Y_CONTENT_START, SCROLLBAR_W, CONTENT_H, false)
        local thumb_h = math.max(1, math.floor(CONTENT_H * visible_rows / logical_rows))
        local thumb_y = Y_CONTENT_START + math.floor((CONTENT_H - thumb_h) * scroll_offset / math.max(1, scroll_max))
        add("rect", SCROLLBAR_X, thumb_y, SCROLLBAR_W, thumb_h, true)
      end
    end
    local scroll_key = "sequencer_action_" .. line
    local scroll = get_scroll_state(s, scroll_key, action_name)
    local display_action = action_name
    if scroll.max_offset > 0 then
      local str = tostring(action_name)
      local char_offset = math.floor(scroll.offset / CHAR_WIDTH)
      if char_offset >= 0 and char_offset < #str then
        display_action = string.sub(str, char_offset + 1)
      else
        display_action = str
      end
    end
    add("move", 4, Y_CONTENT_START + 40); add("level", LEVEL_UNSELECTED); add("text", display_action)
    end
  elseif s.screen == SCREEN_SETTINGS then
    add("move", 4, Y_STATUS); add("level", LEVEL_TITLE); add("text", "Settings")
    local fields = {
      { label = "Lines:", value = tostring(s.line_count or 4) },
      { label = "Voltage:", value = (s.voltage_lo or -5) .. " .. " .. (s.voltage_hi or 5) },
      { label = "Ext Clock:", value = (s.ext_clock_cv == 3) and "Off" or ("CV" .. (s.ext_clock_cv or 1)) },
      { label = "Run:", value = (s.run_cv == 3) and "Off" or ("CV" .. (s.run_cv or 1)) },
      { label = "Quantize:", value = (s.quantize and "on" or "off") },
    }
    local sel = s.settings_field_index or 1
    for i, f in ipairs(fields) do
      local y = Y_CONTENT_START + (i - 1) * ROW_H
      add("move", 4, y)
      if i == sel then add("level", LEVEL_SELECTED) else add("level", LEVEL_UNSELECTED) end
      add("text", f.label)
      local scroll_key = "settings_" .. i
      local scroll = get_scroll_state(s, scroll_key, f.value)
      local display_val = f.value
      if scroll.max_offset > 0 then
        local str = tostring(f.value)
        local char_offset = math.floor(scroll.offset / CHAR_WIDTH)
        if char_offset >= 0 and char_offset < #str then
          display_val = string.sub(str, char_offset + 1)
        else
          display_val = str
        end
      end
      add("move", VALUE_X_RIGHT, y)
      if i == sel then add("level", LEVEL_SELECTED) else add("level", LEVEL_UNSELECTED) end
      add("text_right", display_val)
    end
  elseif s.screen == SCREEN_PROJECT then
    local function current_project_name()
      local p = s.current_project_path
      if not p or p == "" then return "(new)" end
      return p:gsub("^.*/", ""):gsub("%.lua$", "") or "(new)"
    end
    if s.project_sub_screen then
      if s.project_delete_confirm then
        add("move", 4, Y_STATUS); add("level", LEVEL_TITLE); add("text", "Delete project?")
        local name = s.project_delete_confirm:gsub("^.*/", ""):gsub("%.lua$", "") or "?"
        add("move", 4, Y_CONTENT_START); add("level", LEVEL_UNSELECTED); add("text", name)
        add("move", 4, Y_CONTENT_START + 14); add("level", LEVEL_HINT); add("text", "K3 yes  K2 no")
      else
        add("move", 4, Y_STATUS); add("level", LEVEL_TITLE); add("text", "Project: " .. current_project_name())
        local sub_title = (s.project_sub_screen == "load" and "Load project") or (s.project_sub_screen == "fast_load" and "Set fast load") or "Delete project"
        add("move", 4, Y_CONTENT_START); add("level", LEVEL_UNSELECTED); add("text", sub_title)
        local list = s.project_list or {}
        local cur = s.project_list_index or 1
        local visible = 4
        local total = #list
        local scroll = total > visible and math.max(0, math.min(cur - 1, total - visible)) or 0
        local fast_path = s.project_fast_load_path
        for i = 1, visible do
          local r = scroll + i
          if r <= total then
            local path = list[r]
            local name = path and path:gsub("^.*/", ""):gsub("%.lua$", "") or "?"
            local is_fast = (fast_path and path and path == fast_path)
            local star = is_fast and " *" or ""
            local y = PROJECT_LIST_START + (i - 1) * ROW_H
            add("move", 4, y)
            if r == cur then add("level", LEVEL_SELECTED); add("text", "> " .. name .. star)
            else add("level", LEVEL_UNSELECTED); add("text", "  " .. name .. star) end
          end
        end
        if total == 0 then
          add("move", 4, PROJECT_LIST_START); add("level", LEVEL_UNSELECTED); add("text", "(no saved projects)")
        end
      end
    else
      add("move", 4, Y_STATUS); add("level", LEVEL_TITLE); add("text", "Project: " .. current_project_name())
      local available = State.project_available_actions(s)
      local idx = s.project_menu_index or 1
      local total = #available
      local visible = PROJECT_MENU_VISIBLE
      local scroll_offset = math.max(0, math.min(idx - 1, total - visible))
      local action_names = {
        [State.PROJECT_SAVE] = "Save project",
        [State.PROJECT_LOAD] = "Load project",
        [State.PROJECT_SAVE_AS] = "Save As",
        [State.PROJECT_RENAME] = "Rename project",
        [State.PROJECT_SET_FAST_LOAD] = "Set fast load",
        [State.PROJECT_DELETE] = "Delete project",
      }
      for i = 1, visible do
        local r = scroll_offset + i
        if r <= total then
          local action_id = available[r]
          local name = action_names[action_id] or "?"
          local y = Y_CONTENT_START + (i - 1) * ROW_H
          add("move", 4, y)
          if r == idx then add("level", LEVEL_SELECTED); add("text", "> " .. name)
          else add("level", LEVEL_UNSELECTED); add("text", "  " .. name) end
        end
      end
      if total > visible then
        add("level", LEVEL_HINT)
        add("rect", SCROLLBAR_X, Y_CONTENT_START, SCROLLBAR_W, visible * ROW_H, false)
        local thumb_h = math.max(1, math.floor(visible * ROW_H * visible / total))
        local thumb_y = Y_CONTENT_START + math.floor((visible * ROW_H - thumb_h) * scroll_offset / math.max(1, total - visible))
        add("rect", SCROLLBAR_X, thumb_y, SCROLLBAR_W, thumb_h, true)
      end
    end
  else
    add("move", 4, Y_STATUS); add("level", LEVEL_TITLE); add("text", "Lines")
    add("move", 4, 32); add("text", "Lines")
  end
  return cmds
end

local init_error = nil
local App = nil
local app = nil
local init_redraw_metro = nil

function init()
  init_error = nil
  local ok, err = pcall(function()
    App = include("lib/app")
  end)
  if not ok then
    init_error = "include app: " .. tostring(err)
    if print then print("[lines] init error: " .. init_error) end
    app = nil
    -- skip rest
  else
    ok, err = pcall(function()
      app = App.new()
    end)
    if not ok then
      init_error = "App.new: " .. tostring(err)
      if print then print("[lines] init error: " .. init_error) end
      app = nil
    else
      ok, err = pcall(function()
        app:init()
      end)
      if not ok then
        init_error = "app:init: " .. tostring(err)
        if print then print("[lines] init error: " .. init_error) end
        app = nil
      end
    end
  end
  if init_error then
    app = nil
  end
  -- Ensure norns can find enc/key (script env may redirect; register explicitly)
  if norns and norns.script then
    norns.script.enc = enc
    norns.script.key = key
  end
  if rawset and _G then
    rawset(_G, "enc", enc)
    rawset(_G, "key", key)
  end
  if redraw then redraw() end
  -- One-shot metro for initial redraw delay (avoid clock.run coroutine; can break on script clear/warmreload)
  if metro then
    -- Clear ref only; do not call metro:stop()—if it already fired, stopping causes pthread_cancel errors.
    init_redraw_metro = nil
    init_redraw_metro = metro.init()
    init_redraw_metro.time = 0.1
    init_redraw_metro.count = 1
    init_redraw_metro.event = function()
      if redraw then redraw() end
      init_redraw_metro = nil
    end
    init_redraw_metro:start()
  end
end

function enc(n, d)
  last_enc = n
  last_enc_time = (os and os.clock and os.clock()) or 0
  if app ~= nil then
    app:enc(n, d)
    if redraw then redraw() end
  end
end

function key(n, z)
  last_key = n
  last_key_time = (os and os.clock and os.clock()) or 0
  if app ~= nil then
    app:key(n, z)
    if redraw then redraw() end
  end
end

function redraw()
  if init_error then
    if screen then
      screen.clear()
      screen.level(15)
      screen.move(4, 16)
      screen.text("Lines: init error")
      local msg = (init_error .. ""):gsub("%s+", " ")
      screen.move(4, 28)
      screen.text(msg:sub(1, 56))
      if #msg > 56 then
        screen.move(4, 38)
        screen.text(msg:sub(57, 112))
      end
      screen.move(4, 52)
      screen.text("See Maiden for full msg")
      screen.update()
    end
    return
  end

  if app ~= nil and screen then
    -- Re-assert enc/key so script keeps receiving input (norns or mods may overwrite after init)
    if norns and norns.script then
      norns.script.enc = enc
      norns.script.key = key
    end
    if rawset and _G then
      rawset(_G, "enc", enc)
      rawset(_G, "key", key)
    end
    local state = app.state
    if state then
      -- Sync from params (workaround when enc/key don't reach script)
      if params and params.get then
        local menu_sel = params:get("lines_menu_sel")
        if menu_sel and state.screen == SCREEN_MAIN_MENU then
          state.main_menu_index = menu_sel
        end
        if params:get("lines_menu_enter") == 2 and state.screen == SCREEN_MAIN_MENU then
          app:key(3, 1)
          if params.set then params:set("lines_menu_enter", 1) end
        end
        if params:get("lines_back") == 2 and state.screen ~= SCREEN_MAIN_MENU then
          app:key(2, 1)
          if params.set then params:set("lines_back", 1) end
        end
      end
      local cmds = build_draw_commands(state)
      for _, c in ipairs(cmds) do
        if c[1] == "clear" then screen.clear()
        elseif c[1] == "level" then screen.level(c[2] or 15)
        elseif c[1] == "move" then screen.move(c[2] or 0, c[3] or 0)
        elseif c[1] == "text" then screen.text(c[2] or "")
        elseif c[1] == "text_right" then screen.text_right(c[2] or "")
        elseif c[1] == "rect" then
          screen.rect(c[2] or 0, c[3] or 0, c[4] or 0, c[5] or 0)
          if c[6] then screen.fill() else screen.stroke() end
        end
      end
      if app.ui then app.ui.dirty = false end
    else
      screen.clear()
      screen.level(15)
      screen.move(4, 32)
      screen.text("Lines")
    end
    if screen.update then screen.update() end
    return
  end

  -- No app (e.g. before init finishes): show placeholder
  if screen then
    screen.clear()
    screen.level(15)
    screen.move(4, 32)
    screen.text("Lines")
    screen.update()
  end
end

function cleanup()
  -- Clear ref only; do not call metro:stop()—if it already fired, stopping causes pthread_cancel errors.
  init_redraw_metro = nil
  if app ~= nil then app:cleanup() end
end
