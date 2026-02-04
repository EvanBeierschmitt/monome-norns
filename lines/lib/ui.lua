-- lib/ui.lua
-- Screen drawing for 128x64 grayscale. Rossum-style 3-tier layout (070).
-- Returns a list of draw commands so the script (lines.lua) can run screen.*; norns errors if screen is called from a module.

local State = include("lib/state")
local Segment = include("lib/segment")

local M = {}

-- Brightness hierarchy (070)
local LEVEL_HINT = 4
local LEVEL_UNSELECTED = 8
local LEVEL_TITLE = 12
local LEVEL_SELECTED = 15

-- Tier y positions: status 0-7, content 10-52, footer 55-63
local Y_STATUS = 6
local Y_CONTENT_START = 12
local Y_FOOTER = 58
local VALUE_X_RIGHT = 118
local CONTENT_H = 52
local ROW_H = 10
local SCROLLBAR_X = 122
local SCROLLBAR_W = 4

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
  else
    self:draw_status("Lines", add)
    add("move", 4, 32)
    add("text", "Lines")
  end
  return cmds
end

--- Main menu: E1 select, K3 enter, K2 back (070). Preset Editor not in menu; enter from Presets list.
function M:draw_main_menu(add)
  self:draw_status("Lines", add)
  local idx = self.state.main_menu_index or 1
  local items = { "Preset Sequencer", "Presets", "Settings" }
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

--- Presets list: status, + Create New Preset, scroll, footer with n/total.
function M:draw_presets_list(add)
  if self.state.delete_confirm then
    self:draw_status("Delete preset?", add)
    add("move", 4, 24)
    add("level", LEVEL_UNSELECTED)
    local idx = self.state.delete_confirm
    local p = (self.state.presets or {})[idx]
    if p then add("text", p.name or p.id or "?") end
    return
  end
  self:draw_status("Presets", add)
  local presets = self.state.presets or {}
  local cur = self.state.preset_list_index or 0
  local total = #presets >= 1 and (#presets + 2) or (#presets + 1)
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
      elseif #presets >= 1 and r == #presets + 1 then
        add("level", r == cur and LEVEL_SELECTED or LEVEL_UNSELECTED)
        add("text", (r == cur and "> " or "  ") .. "Delete selected preset")
      else
        local p = presets[r]
        if p then
          add("level", r == cur and LEVEL_SELECTED or LEVEL_UNSELECTED)
          add("text", (r == cur and "> " or "  ") .. (p.name or p.id or "?"))
        end
      end
    end
  end
end

--- Preset editor: Name row (index 0), then segment params. Two-column label left, value right-aligned (070).
--- When level_mode is absQ/relQ, Level value shown as note (e.g. C3). E3 on Name row cycles preset names.
function M:draw_preset_editor(add)
  local p = State.get_editing_preset(self.state)
  if not p then
    self:draw_status("No preset", add)
    add("move", 4, 24)
    add("level", LEVEL_UNSELECTED)
    add("text", "No preset")
    return
  end
  self:draw_status(p.name or p.id or "Preset", add)
  local seg_idx = self.state.editor_segment_index or 1
  local param_idx = self.state.editor_param_index or 0
  local param_names = { "Name:", "Time:", "Time unit:", "Mode:", "Level:", "Shape:", "Jump:", "Ping:" }
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
  for i = 0, State.PARAM_COUNT do
    local y = Y_CONTENT_START + 10 + i * 8
    add("move", 4, y)
    if i == param_idx then
      add("level", LEVEL_SELECTED)
    else
      add("level", LEVEL_UNSELECTED)
    end
    local name = param_names[i + 1] or ""
    add("text", name)
    local val
    if i == 0 then
      val = p.name or p.id or "Preset"
    elseif i == State.PARAM_TIME then
      local tu = seg.time_unit or "sec"
      val = tostring(seg.time) .. (tu == "beats" and " bt" or " s")
    elseif i == State.PARAM_TIME_UNIT then val = seg.time_unit or "sec"
    elseif i == State.PARAM_LEVEL_MODE then val = seg.level_mode or "abs"
    elseif i == State.PARAM_LEVEL_VALUE then
      if seg.level_mode == "absQ" or seg.level_mode == "relQ" then
        val = Segment.voltage_to_note and Segment.voltage_to_note(seg.level_value or 0) or string.format("%.2f", seg.level_value or 0)
      else
        val = string.format("%.2f", seg.level_value or 0)
      end
    elseif i == State.PARAM_SHAPE then val = seg.shape or "linear"
    elseif i == State.PARAM_JUMP then
      if seg.jump_to_segment then val = "seg " .. seg.jump_to_segment else val = "stop" end
    elseif i == State.PARAM_PING then
      if seg.ping_line and seg.ping_action then val = "L" .. seg.ping_line .. " " .. (seg.ping_action or "") else val = "off" end
    else val = ""
    end
    add("move", VALUE_X_RIGHT, y)
    if i == param_idx then add("level", LEVEL_SELECTED) else add("level", LEVEL_UNSELECTED) end
    add("text_right", val)
  end
end

--- Preset Sequencer: selection bar for gaps/start/end; scrollbar when overflow.
function M:draw_preset_sequencer(add)
  local s = self.state
  local line = s.preset_sequencer_selected_line or 1
  local seq = s.sequences and s.sequences[line] or {}
  local ids = seq.preset_ids or {}
  local cursor = s.preset_sequencer_cursor or 1
  local action_idx = s.preset_sequencer_action_index or 1
  local action_names = { "Edit", "Copy", "Paste", "Delete", "Add" }
  local total_slots = #ids
  local visible_rows = math.floor(CONTENT_H / ROW_H)
  local logical_rows = total_slots + 1
  local R = math.floor((cursor - 1) / 2)
  local scroll_max = math.max(0, logical_rows - visible_rows)
  local scroll_offset = math.max(0, math.min(R - visible_rows + 1, scroll_max))
  self:draw_status("Preset Sequencer  L" .. line, add)
  if total_slots == 0 then
    add("move", 4, Y_CONTENT_START)
    add("level", LEVEL_UNSELECTED)
    add("text", "(empty) E3 Add")
    add("move", 4, Y_CONTENT_START + 4)
    add("level", LEVEL_SELECTED)
    add("text", ">")
  else
    for i = 1, visible_rows do
      local slot_index = scroll_offset + i
      if slot_index <= total_slots then
        local y = Y_CONTENT_START + (i - 1) * ROW_H
        local pid = ids[slot_index]
        local name = pid or "?"
        for _, p in ipairs(s.presets or {}) do
          if p.id == pid then name = p.name or p.id break end
        end
        add("move", 4, y)
        add("level", LEVEL_UNSELECTED)
        add("text", " " .. slot_index .. "  " .. name)
      end
    end
    local sel_row_local = R - scroll_offset
    local sel_sub = (cursor - 1) % 2
    local sel_y = Y_CONTENT_START + sel_row_local * ROW_H + sel_sub * (ROW_H / 2)
    if sel_row_local >= 0 and sel_row_local < visible_rows then
      add("move", 4, sel_y)
      add("level", LEVEL_SELECTED)
      add("text", ">")
    elseif sel_row_local < 0 then
      add("move", 4, Y_CONTENT_START)
      add("level", LEVEL_SELECTED)
      add("text", ">")
    else
      add("move", 4, Y_CONTENT_START + (visible_rows - 1) * ROW_H)
      add("level", LEVEL_SELECTED)
      add("text", ">")
    end
    if logical_rows > visible_rows then
      add("level", LEVEL_HINT)
      add("rect", SCROLLBAR_X, Y_CONTENT_START, SCROLLBAR_W, CONTENT_H, false)
      local thumb_h = math.max(2, math.floor(CONTENT_H * visible_rows / logical_rows))
      local thumb_y = Y_CONTENT_START + math.floor((CONTENT_H - thumb_h) * scroll_offset / math.max(1, scroll_max))
      add("rect", SCROLLBAR_X, thumb_y, SCROLLBAR_W, thumb_h, true)
    end
  end
  add("move", 4, Y_CONTENT_START + 40)
  add("level", LEVEL_UNSELECTED)
  add("text", action_names[action_idx] or "?")
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
    add("move", VALUE_X_RIGHT, y)
    add("level", i == sel and LEVEL_SELECTED or LEVEL_UNSELECTED)
    add("text_right", f.value)
  end
end

return M
