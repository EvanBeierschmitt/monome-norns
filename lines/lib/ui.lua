-- lib/ui.lua
-- Screen drawing for 128x64 grayscale. Rossum-style 3-tier layout (070).
-- Returns a list of draw commands so the script (lines.lua) can run screen.*; norns errors if screen is called from a module.

local State = include("lib/state")
local Segment = include("lib/segment")

local M = {}

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

-- Brightness hierarchy (070)
local LEVEL_HINT = 4
local LEVEL_UNSELECTED = 8
local LEVEL_TITLE = 12
local LEVEL_SELECTED = 15

-- Tier y positions: status 0-7, content 10-52, footer 55-63
local Y_STATUS = 6
local Y_CONTENT_START = 18
local Y_FOOTER = 58
local VALUE_X_RIGHT = 118
local CONTENT_H = 46
local ROW_H = 10
local PROJECT_MENU_VISIBLE = 4
local PROJECT_LIST_START = 32
local SCROLLBAR_X = 124
local SCROLLBAR_W = 2

--- Create a UI instance bound to shared state.
--- @param state table read-only state for display
--- @return table ui instance
function M.new(state)
  local ui = {
    state = state,
    dirty = true,
  }
  setmetatable(ui, { __index = M })
  return ui
end

--- Mark whether the screen needs redraw.
function M:set_dirty(value)
  self.dirty = value
end

--- Return true if a redraw is pending.
function M:is_dirty()
  return self.dirty
end

--- Draw tier 1: status line (context). add("move", x, y), add("level", n), add("text", s).
--- @param title string
--- @param add function(...) appends one draw command
function M:draw_status(title, add)
  add("move", 4, Y_STATUS)
  add("level", LEVEL_TITLE)
  add("text", title or "")
end

--- Draw tier 3: footer hint.
--- @param add function
--- @param hint string
--- @param right_text string|nil
function M:draw_footer(add, hint, right_text)
  add("move", 4, Y_FOOTER)
  add("level", LEVEL_HINT)
  add("text", hint or "")
  if right_text and right_text ~= "" then
    add("move", VALUE_X_RIGHT, Y_FOOTER)
    add("text_right", right_text)
  end
end

--- Draw one frame. Returns list of draw commands: {"clear"}, {"level", n}, {"move", x, y}, {"text", s}, {"text_right", s}.
function M:draw()
  local cmds = {}
  local function add(...) table.insert(cmds, {...}) end

  add("clear")
  add("level", LEVEL_SELECTED)
  local s = self.state
  if s.screen == State.SCREEN_MAIN_MENU then
    self:draw_main_menu(add)
  elseif s.screen == State.SCREEN_PRESETS_LIST then
    self:draw_presets_list(add)
  elseif s.screen == State.SCREEN_PRESET_EDITOR then
    self:draw_preset_editor(add)
  elseif s.screen == State.SCREEN_PRESET_SEQUENCER then
    self:draw_preset_sequencer(add)
  elseif s.screen == State.SCREEN_SETTINGS then
    self:draw_settings(add)
  elseif s.screen == State.SCREEN_PROJECT then
    self:draw_project(add)
  else
    self:draw_status("Lines", add)
    add("move", 4, 32)
    add("text", "Lines")
  end
  return cmds
end

--- Main menu: E1 select, K3 enter, K2 back (070). Order: Presets, Preset Sequencer, Settings, Project.
function M:draw_main_menu(add)
  self:draw_status("Lines", add)
  local idx = self.state.main_menu_index or 1
  local items = { "Presets", "Preset Sequencer", "Settings", "Project" }
  for i, name in ipairs(items) do
    local y = Y_CONTENT_START + (i - 1) * 10
    add("move", 4, y)
    if i == idx then
      add("level", LEVEL_SELECTED)
      add("text", "> " .. name)
    else
      add("level", LEVEL_UNSELECTED)
      add("text", "  " .. name)
    end
  end
end

--- Presets list: status, + Create New Preset, scroll; footer Edit/Delete when preset selected; or "Select Available Preset" when adding from sequencer (no Create New Preset).
function M:draw_presets_list(add)
  if self.state.delete_confirm then
    self:draw_status("Delete preset?", add)
    add("move", 4, 20)
    add("level", LEVEL_UNSELECTED)
    local idx = self.state.delete_confirm
    local p = (self.state.presets or {})[idx]
    if p then add("text", p.name or p.id or "?") end
    add("move", 4, 30)
    add("level", LEVEL_UNSELECTED)
    add("text", "Are you sure?")
    add("move", 4, 44)
    add("level", LEVEL_HINT)
    add("text", "K3 yes  K2 no")
    return
  end
  local pick_for_sequencer = (self.state.sequencer_pick_preset_for_line ~= nil)
  local presets = self.state.presets or {}
  local cur = self.state.preset_list_index or 0
  if pick_for_sequencer then
    self:draw_status("Select Available Preset", add)
    local total = #presets
    if total == 0 then
      add("move", 4, Y_CONTENT_START + 8)
      add("level", LEVEL_UNSELECTED)
      add("text", "(no presets - create from Presets)")
      add("move", 4, Y_CONTENT_START + 22)
      add("level", LEVEL_HINT)
      add("text", "K2 back")
    else
      local visible = 4
      local scroll_offset = total > visible and math.max(0, math.min(cur - 1, total - visible)) or 0
      for i = 0, visible - 1 do
        local r = scroll_offset + i + 1
        if r <= total then
          local y = Y_CONTENT_START + i * 10
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
    return
  end
  self:draw_status("Presets", add)
  local total = #presets + 1
  local visible = 4
  local scroll_offset = total > visible and math.max(0, math.min(cur, total - visible)) or 0
  for i = 0, visible - 1 do
    local r = scroll_offset + i
    if r < total then
      local y = Y_CONTENT_START + i * 10
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
    local act = self.state.preset_list_action or "edit"
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

--- Preset editor: Name row (index 0), then segment params. Two-column label left, value right-aligned (070).
--- When level_mode is absQ/relQ, Level value shown as note (e.g. C3). E3 on Name row cycles preset names.
function M:draw_preset_editor(add)
  if self.state.pending_edited_preset_save_confirm then
    self:draw_status("Keep your changes?", add)
    add("move", 4, Y_CONTENT_START + 10)
    add("level", LEVEL_UNSELECTED)
    add("text", "K2 Discard   K3 Save")
    return
  end
  if self.state.pending_new_preset_save_confirm then
    self:draw_status("Save preset?", add)
    add("move", 4, Y_CONTENT_START + 10)
    add("level", LEVEL_UNSELECTED)
    add("text", "K2 Discard   K3 Save")
    return
  end
  local p = State.get_editing_preset(self.state)
  if not p then
    self:draw_status("No preset", add)
    add("move", 4, 24)
    add("level", LEVEL_UNSELECTED)
    add("text", "No preset")
    return
  end
  if self.state.pending_name_save_confirm then
    self:draw_status("Save preset name changes?", add)
    add("move", 4, Y_CONTENT_START + 10)
    add("level", LEVEL_UNSELECTED)
    add("text", "K2 Discard   K3 Save")
    return
  end
  if self.state.preset_name_edit_mode then
    self:draw_status("Edit name", add)
    local buf = self.state.preset_name_edit_buffer or ""
    local last_char = 0
    for i = #buf, 1, -1 do
      if buf:sub(i, i) ~= " " then last_char = i break end
    end
    local max_pos = last_char + 1
    local pos = math.max(1, math.min(max_pos, self.state.editing_name_position or 1))
    local y = Y_CONTENT_START + 8
    for i = 1, #buf do
      local char = buf:sub(i, i)
      local is_cur = (i == pos)
      add("move", 4 + (i - 1) * 6, y)
      add("level", is_cur and LEVEL_SELECTED or LEVEL_UNSELECTED)
      add("text", (is_cur and (char == " " or char == "")) and "_" or char)
    end
    if pos == #buf + 1 then
      add("move", 4 + #buf * 6, y)
      add("level", LEVEL_SELECTED)
      add("text", "_")
    end
    add("move", 4, Y_CONTENT_START + 28)
    add("level", LEVEL_HINT)
    add("text", "E1 del  E2 char  E3 pos")
    add("move", 4, Y_FOOTER - 8)
    add("level", LEVEL_HINT)
    add("text", "K2 back  K3 save")
    return
  end
  self:draw_status(p.name or p.id or "Preset", add)
  if self.state.preset_editor_blocked_playing then
    add("move", 4, Y_CONTENT_START)
    add("level", LEVEL_SELECTED)
    add("text", "Stop playback to edit")
    add("move", 4, Y_CONTENT_START + 12)
    add("level", LEVEL_HINT)
    add("text", "Stop in sequencer or press K3 in editor")
    return
  end
  local seg_idx = self.state.editor_segment_index or 1
  local param_idx = self.state.editor_param_index or 0
  local param_names = {
    "Name:", "Time unit:", "Time:", "Mode:", "Level:", "Level range:", "Level random:",
    "Shape:", "Segment jump:", "Preset jump:", "Ping:",
    "Cond1 in:", "Cond1 cmp:", "Cond1 mode:", "Cond1 val:", "Cond1 val hi:", "Cond1 jump:", "Cond1 jpre:", "Cond1 ping:",
    "Cond2 in:", "Cond2 cmp:", "Cond2 mode:", "Cond2 val:", "Cond2 val hi:", "Cond2 jump:", "Cond2 jpre:", "Cond2 ping:",
  }
  local seg = p.segments[seg_idx]
  if not seg then
    add("move", 4, Y_CONTENT_START)
    add("level", LEVEL_UNSELECTED)
    add("text", "seg " .. seg_idx)
    return
  end
  add("move", 4, Y_CONTENT_START)
  add("level", LEVEL_UNSELECTED)
  add("text", "seg " .. seg_idx .. " / 8")
  local visible = State.visible_editor_params(seg) or {}
  for i = 0, #visible - 1 do
    local param_id = visible[i + 1]
    local y = Y_CONTENT_START + 10 + i * 8
    add("move", 4, y)
    if i == param_idx then
      add("level", LEVEL_SELECTED)
    else
      add("level", LEVEL_UNSELECTED)
    end
    local name = param_names[param_id + 1] or ""
    add("text", name)
    local val
    if param_id == 0 then
      val = p.name or p.id or "Preset"
    elseif param_id == State.PARAM_TIME_UNIT then val = seg.time_unit or "sec"
    elseif param_id == State.PARAM_TIME then
      local tu = seg.time_unit or "sec"
      val = tostring(seg.time) .. (tu == "beats" and " bt" or " s")
    elseif param_id == State.PARAM_LEVEL_MODE then val = seg.level_mode or "abs"
    elseif param_id == State.PARAM_LEVEL_VALUE then
      if seg.level_mode == "absQ" then
        val = Segment.voltage_to_note and Segment.voltage_to_note(seg.level_value or 0) or string.format("%.2f", seg.level_value or 0)
      elseif seg.level_mode == "relQ" then
        val = tostring(math.floor((seg.level_value or 0) * 12 + 0.5)) .. " st"
      else
        val = string.format("%.2f", seg.level_value or 0)
      end
    elseif param_id == State.PARAM_LEVEL_RANGE then val = string.format("%.2f", seg.level_range or 0)
    elseif param_id == State.PARAM_LEVEL_RANDOM then
      val = (seg.level_random == "gaussian" and "Gaussian") or (seg.level_random == "linear" and "linear") or "off"
    elseif param_id == State.PARAM_SHAPE then val = Segment.shape_display_name(seg.shape) or "Linear"
    elseif param_id == State.PARAM_JUMP_SEGMENT then
      if seg.jump_to_segment then val = "seg " .. seg.jump_to_segment else val = "stop" end
    elseif param_id == State.PARAM_JUMP_PRESET then
      if seg.jump_to_preset_id then
        local name = "off"
        for _, pr in ipairs(self.state.presets or {}) do
          if pr.id == seg.jump_to_preset_id then name = pr.name or pr.id break end
        end
        val = name
      else
        val = "off"
      end
    elseif param_id == State.PARAM_PING then
      if seg.ping_line and seg.ping_action then val = "L" .. seg.ping_line .. " " .. (seg.ping_action or "") else val = "off" end
    elseif param_id >= State.PARAM_COND1_INPUT and param_id <= State.PARAM_COND1_PING then
      local c = seg.cond1
      if not c then val = "" else
        if param_id == State.PARAM_COND1_INPUT then val = c.input or "cv1"
        elseif param_id == State.PARAM_COND1_COMPARISON then val = c.comparison or ">"
        elseif param_id == State.PARAM_COND1_VALUE_MODE then val = c.value_mode or "abs"
        elseif param_id == State.PARAM_COND1_VALUE then
          local vm = c.value_mode or "abs"
          if vm == "absQ" then val = Segment.voltage_to_note and Segment.voltage_to_note(c.value or 0) or string.format("%.2f", c.value or 0)
          elseif vm == "relQ" then val = tostring(math.floor((c.value or 0) * 12 + 0.5)) .. " st"
          else val = string.format("%.2f", c.value or 0) end
        elseif param_id == State.PARAM_COND1_VALUE_HI then
          local cmp = c.comparison or ">"
          if cmp == "<>" or cmp == "><" then
            local vm = c.value_mode or "abs"
            if vm == "absQ" then val = Segment.voltage_to_note and Segment.voltage_to_note(c.value_hi or c.value or 0) or string.format("%.2f", c.value_hi or c.value or 0)
            elseif vm == "relQ" then val = tostring(math.floor((c.value_hi or c.value or 0) * 12 + 0.5)) .. " st"
            else val = string.format("%.2f", c.value_hi or c.value or 0) end
          else val = "-" end
        elseif param_id == State.PARAM_COND1_JUMP_SEGMENT then
          if c.jump_to_segment == nil then val = "off" elseif c.jump_to_segment == 0 then val = "stop" else val = "seg " .. c.jump_to_segment end
        elseif param_id == State.PARAM_COND1_JUMP_PRESET then
          if c.jump_to_preset_id then
            local name = "off"
            for _, pr in ipairs(self.state.presets or {}) do if pr.id == c.jump_to_preset_id then name = pr.name or pr.id break end end
            val = name
          else val = "off" end
        else val = (c.ping_line and c.ping_action) and ("L" .. c.ping_line .. " " .. (c.ping_action or "")) or "off" end
      end
    elseif param_id >= State.PARAM_COND2_INPUT and param_id <= State.PARAM_COND2_PING then
      local c = seg.cond2
      if not c then val = "" else
        if param_id == State.PARAM_COND2_INPUT then val = c.input or "cv2"
        elseif param_id == State.PARAM_COND2_COMPARISON then val = c.comparison or ">"
        elseif param_id == State.PARAM_COND2_VALUE_MODE then val = c.value_mode or "abs"
        elseif param_id == State.PARAM_COND2_VALUE then
          local vm = c.value_mode or "abs"
          if vm == "absQ" then val = Segment.voltage_to_note and Segment.voltage_to_note(c.value or 0) or string.format("%.2f", c.value or 0)
          elseif vm == "relQ" then val = tostring(math.floor((c.value or 0) * 12 + 0.5)) .. " st"
          else val = string.format("%.2f", c.value or 0) end
        elseif param_id == State.PARAM_COND2_VALUE_HI then
          local cmp = c.comparison or ">"
          if cmp == "<>" or cmp == "><" then
            local vm = c.value_mode or "abs"
            if vm == "absQ" then val = Segment.voltage_to_note and Segment.voltage_to_note(c.value_hi or c.value or 0) or string.format("%.2f", c.value_hi or c.value or 0)
            elseif vm == "relQ" then val = tostring(math.floor((c.value_hi or c.value or 0) * 12 + 0.5)) .. " st"
            else val = string.format("%.2f", c.value_hi or c.value or 0) end
          else val = "-" end
        elseif param_id == State.PARAM_COND2_JUMP_SEGMENT then
          if c.jump_to_segment == nil then val = "off" elseif c.jump_to_segment == 0 then val = "stop" else val = "seg " .. c.jump_to_segment end
        elseif param_id == State.PARAM_COND2_JUMP_PRESET then
          if c.jump_to_preset_id then
            local name = "off"
            for _, pr in ipairs(self.state.presets or {}) do if pr.id == c.jump_to_preset_id then name = pr.name or pr.id break end end
            val = name
          else val = "off" end
        else val = (c.ping_line and c.ping_action) and ("L" .. c.ping_line .. " " .. (c.ping_action or "")) or "off" end
      end
    else val = ""
    end
    local scroll_key = "preset_editor_" .. seg_idx .. "_" .. param_id
    local scroll = get_scroll_state(self.state, scroll_key, val)
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
    if i == param_idx then add("level", LEVEL_SELECTED) else add("level", LEVEL_UNSELECTED) end
    add("text_right", display_val)
  end
end

--- Preset Sequencer: selection bar for gaps/start/end; scrollbar when overflow. Overlay "Are you sure?" when sequencer_delete_confirm.
function M:draw_preset_sequencer(add)
  local s = self.state
  if s.sequencer_delete_confirm then
    self:draw_status("Delete from sequence?", add)
    add("move", 4, 24)
    add("level", LEVEL_UNSELECTED)
    add("text", "Are you sure?")
    add("move", 4, 44)
    add("level", LEVEL_HINT)
    add("text", "K3 yes  K2 no")
    return
  end
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
  self:draw_status("Preset Sequencer  L" .. line, add)
  add("move", VALUE_X_RIGHT, Y_STATUS)
  add("level", LEVEL_SELECTED)
  add("text_right", s.sequencer_running and "■" or "▶")
  if total_slots == 0 then
    add("move", 4, Y_CONTENT_START)
    add("level", LEVEL_UNSELECTED)
    add("text", "(empty)")
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
        for _, p in ipairs(s.presets or {}) do
          if p.id == pid then name = p.name or p.id break end
        end
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
  add("move", 4, Y_CONTENT_START + 40)
  add("level", LEVEL_UNSELECTED)
  add("text", display_action)
end

--- Settings: two-column label left, value right-aligned. E2 field, E3 value.
function M:draw_settings(add)
  self:draw_status("Settings", add)
  local s = self.state
  local sel = s.settings_field_index or 1
  local fields = {
    { label = "Lines:", value = tostring(s.line_count or 4) },
    { label = "Voltage:", value = (s.voltage_lo or -5) .. " .. " .. (s.voltage_hi or 5) },
    { label = "Ext Clock:", value = (s.ext_clock_cv == 3) and "Off" or ("CV" .. (s.ext_clock_cv or 1)) },
    { label = "Run:", value = (s.run_cv == 3) and "Off" or ("CV" .. (s.run_cv or 1)) },
    { label = "Quantize:", value = (s.quantize and "on" or "off") },
  }
  for i, f in ipairs(fields) do
    local y = Y_CONTENT_START + (i - 1) * 10
    add("move", 4, y)
    add("level", i == sel and LEVEL_SELECTED or LEVEL_UNSELECTED)
    add("text", f.label)
    local scroll_key = "settings_" .. i
    local scroll = get_scroll_state(self.state, scroll_key, f.value)
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
    add("level", i == sel and LEVEL_SELECTED or LEVEL_UNSELECTED)
    add("text_right", display_val)
  end
end

--- Project: dynamic menu. Status shows current project. List sub-screen shows star for fast-load project.
function M:draw_project(add)
  local s = self.state
  local function current_project_name()
    local p = s.current_project_path
    if not p or p == "" then return "(new)" end
    return p:gsub("^.*/", ""):gsub("%.lua$", "") or "(new)"
  end
  if s.project_sub_screen then
    if s.project_delete_confirm then
      self:draw_status("Delete project?", add)
      local name = s.project_delete_confirm:gsub("^.*/", ""):gsub("%.lua$", "") or "?"
      add("move", 4, Y_CONTENT_START)
      add("level", LEVEL_UNSELECTED)
      add("text", name)
      add("move", 4, Y_CONTENT_START + 14)
      add("level", LEVEL_HINT)
      add("text", "K3 yes  K2 no")
      return
    end
    self:draw_status("Project: " .. current_project_name(), add)
    add("move", 4, Y_CONTENT_START)
    add("level", LEVEL_UNSELECTED)
    local sub_title = (s.project_sub_screen == "load" and "Load project") or (s.project_sub_screen == "fast_load" and "Set fast load") or "Delete project"
    add("text", sub_title)
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
        local y = PROJECT_LIST_START + (i - 1) * 10
        add("move", 4, y)
        add("level", r == cur and LEVEL_SELECTED or LEVEL_UNSELECTED)
        add("text", (r == cur and "> " or "  ") .. name .. star)
      end
    end
    if total == 0 then
      add("move", 4, PROJECT_LIST_START)
      add("level", LEVEL_UNSELECTED)
      add("text", "(no saved projects)")
    end
    return
  end
  self:draw_status("Project: " .. current_project_name(), add)
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
      local y = Y_CONTENT_START + (i - 1) * 10
      add("move", 4, y)
      add("level", r == idx and LEVEL_SELECTED or LEVEL_UNSELECTED)
      add("text", (r == idx and "> " or "  ") .. name)
    end
  end
  if total > visible then
    add("level", LEVEL_HINT)
    add("rect", SCROLLBAR_X, Y_CONTENT_START, SCROLLBAR_W, visible * 10, false)
    local thumb_h = math.max(1, math.floor(visible * 10 * visible / total))
    local thumb_y = Y_CONTENT_START + math.floor((visible * 10 - thumb_h) * scroll_offset / math.max(1, total - visible))
    add("rect", SCROLLBAR_X, thumb_y, SCROLLBAR_W, thumb_h, true)
  end
end

return M
