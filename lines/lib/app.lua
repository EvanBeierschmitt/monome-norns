-- lib/app.lua
-- Application orchestrator: wires state, UI, params, Crow; minimal logic in main.

local State = include("lib/state")
local Ui = include("lib/ui")
local CrowIo = include("lib/crow_io")
local Sequencer = include("lib/sequencer")
local textentry = require("textentry")

local M = {}

--- Create a new app instance.
--- @return table app instance with :init(), :enc(), :key(), :redraw(), :cleanup()
function M.new()
  local app = {
    state = State.new(),
    ui = nil,
    redraw_metro = nil,
    text_scroll_metro = nil,
  }
  setmetatable(app, { __index = M })
  return app
end

--- Set to true to log sequencer-add selection to maiden/terminal for debugging wrong-preset bug.
local DEBUG_SEQUENCER_ADD = false
--- Set to true to log preset jump (E3) in preset editor for debugging "off" not reachable.
local DEBUG_JUMP_PRESET = true

--- Initialize: params, UI, redraw metro. Call once from init().
function M:init()
  if DEBUG_SEQUENCER_ADD then _G.LINES_DEBUG_SEQUENCER_ADD = true end
  if DEBUG_JUMP_PRESET then _G.LINES_DEBUG_JUMP_PRESET = true end
  self:setup_params()
  if params then
    self.state.line_count = params:get("line_count") or 4
    local vr = params:get("voltage_range") or 1
    if vr == 1 then self.state.voltage_lo, self.state.voltage_hi = -5, 5
    else self.state.voltage_lo, self.state.voltage_hi = -5, 10 end
  end
  self.ui = Ui.new(self.state)
  self:start_redraw_metro()
  self:start_text_scroll_metro()
  self:project_try_fast_load()
end

--- Setup params (norns paramset). Lines settings.
function M:setup_params()
  if not params then return end
  params:add_separator("lines")
  -- Workaround when enc/key don't reach script: navigate main menu via params
  params:add {
    type = "option",
    id = "lines_menu_sel",
    name = "Menu",
    options = { "Presets", "Preset Sequencer", "Settings", "Project" },
    default = 1,
  }
  params:add {
    type = "option",
    id = "lines_menu_enter",
    name = "Enter menu",
    options = { "no", "yes" },
    default = 1,
  }
  params:set_action("lines_menu_sel", function(v)
    if self.state then self.state.main_menu_index = v end
  end)
  params:set_action("lines_menu_enter", function(v)
    if v == 2 and self.state and self.state.screen == State.SCREEN_MAIN_MENU then
      State.on_key(self.state, 3, 1)
      params:set("lines_menu_enter", 1)
    end
  end)
  params:add {
    type = "option",
    id = "lines_back",
    name = "Back",
    options = { "no", "yes" },
    default = 1,
  }
  params:set_action("lines_back", function(v)
    if v == 2 and self.state and self.state.screen ~= State.SCREEN_MAIN_MENU then
      State.on_key(self.state, 2, 1)
      params:set("lines_back", 1)
      if self.state.screen == State.SCREEN_MAIN_MENU and params.set then
        params:set("lines_menu_sel", self.state.main_menu_index)
      end
    end
  end)
  params:add {
    type = "option",
    id = "lines_delete_preset",
    name = "Delete preset",
    options = { "no", "yes" },
    default = 1,
  }
  params:set_action("lines_delete_preset", function(v)
    if v == 2 and self.state and self.state.screen == State.SCREEN_PRESETS_LIST and #self.state.presets > 0 and self.state.preset_list_index >= 1 then
      local idx = self.state.preset_list_index
      table.remove(self.state.presets, idx)
      if self.state.editing_preset_index == idx then
        self.state.editing_preset_index = nil
      elseif self.state.editing_preset_index and self.state.editing_preset_index > idx then
        self.state.editing_preset_index = self.state.editing_preset_index - 1
      end
      if #self.state.presets == 0 then
        self.state.preset_list_index = 0
      elseif self.state.preset_list_index > #self.state.presets then
        self.state.preset_list_index = #self.state.presets
      end
      if params then params:set("lines_delete_preset", 1) end
      if self.ui then self.ui:set_dirty(true) end
    end
  end)
  params:add_separator("lines_opts")
  params:add {
    type = "number",
    id = "line_count",
    name = "Lines",
    min = 1,
    max = 4,
    default = 4,
  }
  params:add {
    type = "option",
    id = "voltage_range",
    name = "Voltage range",
    options = { "-5 .. 5V", "-5 .. 10V" },
    default = 1,
  }
  params:add_separator("clock")
  params:add {
    type = "number",
    id = "bpm",
    name = "BPM",
    min = 60,
    max = 240,
    default = 120,
  }
  params:add {
    type = "option",
    id = "ext_clock_cv",
    name = "Ext clock",
    options = { "CV1", "CV2", "Off" },
    default = 1,
  }
  params:add {
    type = "option",
    id = "run_cv",
    name = "Run",
    options = { "CV1", "CV2", "Off" },
    default = 1,
  }
  params:add {
    type = "binary",
    id = "quantize",
    name = "Quantize",
    behavior = "toggle",
    default = false,
  }
  params:set_action("line_count", function(v)
    if self.state then self.state.line_count = v end
  end)
  params:set_action("voltage_range", function(v)
    if self.state then
      if v == 1 then self.state.voltage_lo, self.state.voltage_hi = -5, 5
      else self.state.voltage_lo, self.state.voltage_hi = -5, 10 end
    end
  end)
end

--- Start the redraw metro so screen updates periodically.
function M:start_redraw_metro()
  if not metro then return end
  self.redraw_metro = metro.init()
  self.redraw_metro.time = 1.0 / 15
  self.redraw_metro.event = function()
    if self.ui then
      self.ui:set_dirty(true)
      if redraw then redraw() end
    end
  end
  self.redraw_metro:start()
end

--- Start the text scroll metro to animate scrolling text. Only scrolls the currently focused param in preset editor to avoid flicker on other rows.
function M:start_text_scroll_metro()
  if not metro then return end
  self.text_scroll_metro = metro.init()
  self.text_scroll_metro.time = 0.15
  self.text_scroll_metro.event = function()
    if self.state and self.state.text_scroll_offsets then
      local updated = false
      local focus_key = nil
      if self.state.screen == State.SCREEN_PRESET_EDITOR and self.state.editor_segment_index and self.state.editor_param_index ~= nil then
        local p = State.get_editing_preset(self.state)
        local seg = p and p.segments and p.segments[self.state.editor_segment_index]
        local visible = State.visible_editor_params(seg)
        local param_id = visible and visible[self.state.editor_param_index + 1]
        focus_key = "preset_editor_" .. self.state.editor_segment_index .. "_" .. (param_id or self.state.editor_param_index)
      end
      for key, scroll_data in pairs(self.state.text_scroll_offsets) do
        if scroll_data.max_offset > 0 and (focus_key == nil or key == focus_key) then
          scroll_data.pause_count = (scroll_data.pause_count or 0) + 1
          if scroll_data.pause_count >= 10 then
            scroll_data.offset = scroll_data.offset + 1
            if scroll_data.offset > scroll_data.max_offset then
              scroll_data.offset = 0
              scroll_data.pause_count = 0
            end
            updated = true
          end
        end
      end
      if updated and self.ui then
        self.ui:set_dirty(true)
        if redraw then redraw() end
      end
    end
  end
  self.text_scroll_metro:start()
end

--- Handle encoder n with delta d. Delegates to state then marks UI dirty.
function M:enc(n, d)
  State.on_enc(self.state, n, d)
  if self.state.screen == State.SCREEN_PRESETS_LIST and self.state.sequencer_pick_preset_for_line and n == 2 then
    if self.state.preset_list_index < 1 or self.state.preset_list_index > #self.state.presets then
      self.state.preset_list_index = math.max(1, math.min(self.state.preset_list_index, #self.state.presets))
    end
  end
  -- Keep params in sync so redraw() doesn't overwrite encoder-driven main menu selection
  if self.state.screen == State.SCREEN_MAIN_MENU and params and params.set then
    params:set("lines_menu_sel", self.state.main_menu_index)
  end
  -- Sync Settings state to params when user changes via encoders
  if self.state.screen == State.SCREEN_SETTINGS and params and params.set then
    params:set("line_count", self.state.line_count)
    params:set("voltage_range", (self.state.voltage_hi == 10) and 2 or 1)
    params:set("ext_clock_cv", self.state.ext_clock_cv)
    params:set("run_cv", self.state.run_cv)
    params:set("quantize", self.state.quantize and 1 or 0)
  end
  if self.ui then
    self.ui:set_dirty(true)
  end
end

--- Handle key n with state z. K1 is system-reserved; script uses K2/K3 only. All keys handled immediately (no long-press); delete via params.
function M:key(n, z)
  if self.state.pending_name_save_confirm then
    if n == 2 and z == 1 then
      self.state.pending_name_save_confirm = false
      self.state.preset_name_before_edit = nil
      self.state.preset_name_edit_buffer = ""
    elseif n == 3 and z == 1 then
      local p = State.get_editing_preset(self.state)
      if p and self.state.preset_name_edit_buffer and self.state.preset_name_edit_buffer ~= "" then
        local trimmed = self.state.preset_name_edit_buffer:gsub("^%s+", ""):gsub("%s+$", "")
        p.name = (trimmed ~= "") and trimmed or "Preset"
      end
      self.state.pending_name_save_confirm = false
      self.state.preset_name_before_edit = nil
      self.state.preset_name_edit_buffer = ""
    end
    if self.ui then self.ui:set_dirty(true) end
    return
  end

  if self.state.pending_edited_preset_save_confirm then
    if n == 3 and z == 1 then
      self.state.pending_edited_preset_save_confirm = false
      self.state.preset_before_edit = nil
      self.state.preset_edited_dirty = false
      if self.state.came_from_sequencer then
        self.state.screen = State.SCREEN_PRESET_SEQUENCER
        self.state.came_from_sequencer = false
      else
        self.state.screen = State.SCREEN_PRESETS_LIST
      end
      self.state.editing_preset_index = nil
    elseif n == 2 and z == 1 then
      local idx = self.state.editing_preset_index
      local backup = self.state.preset_before_edit
      if idx and idx >= 1 and idx <= #(self.state.presets or {}) and backup then
        local p = self.state.presets[idx]
        if p then
          p.id = backup.id
          p.name = backup.name
          p.segments = {}
          for i, seg in ipairs(backup.segments or {}) do
            p.segments[i] = {}
            for k, v in pairs(seg) do
              if type(v) == "table" and (k == "cond1" or k == "cond2") then
                p.segments[i][k] = {}
                for k2, v2 in pairs(v) do p.segments[i][k][k2] = v2 end
              else
                p.segments[i][k] = v
              end
            end
          end
        end
      end
      self.state.pending_edited_preset_save_confirm = false
      self.state.preset_before_edit = nil
      self.state.preset_edited_dirty = false
      if self.state.came_from_sequencer then
        self.state.screen = State.SCREEN_PRESET_SEQUENCER
        self.state.came_from_sequencer = false
      else
        self.state.screen = State.SCREEN_PRESETS_LIST
      end
      self.state.editing_preset_index = nil
    end
    if self.ui then self.ui:set_dirty(true) end
    return
  end

  if self.state.pending_new_preset_save_confirm then
    if n == 3 and z == 1 then
      self.state.pending_new_preset_save_confirm = false
      self.state.preset_created_this_session = false
      if self.state.came_from_sequencer then
        self.state.screen = State.SCREEN_PRESET_SEQUENCER
        self.state.came_from_sequencer = false
      else
        self.state.screen = State.SCREEN_PRESETS_LIST
      end
      self.state.editing_preset_index = nil
    elseif n == 2 and z == 1 then
      local idx = self.state.editing_preset_index
      if idx and idx >= 1 and idx <= #(self.state.presets or {}) then
        table.remove(self.state.presets, idx)
      end
      self.state.pending_new_preset_save_confirm = false
      self.state.preset_created_this_session = false
      self.state.editing_preset_index = nil
      if self.state.came_from_sequencer then
        self.state.screen = State.SCREEN_PRESET_SEQUENCER
        self.state.came_from_sequencer = false
      else
        self.state.screen = State.SCREEN_PRESETS_LIST
        if self.state.preset_list_index > #(self.state.presets or {}) then
          self.state.preset_list_index = math.max(0, #self.state.presets)
        end
      end
    end
    if self.ui then self.ui:set_dirty(true) end
    return
  end

  if self.state.sequencer_delete_confirm then
    if n == 3 and z == 1 then
      local dc = self.state.sequencer_delete_confirm
      local row = self.state.sequences and self.state.sequences[dc.line]
      if row then
        Sequencer.delete_preset(row, dc.slot)
        local new_len = #(row.preset_ids or {})
        if self.state.preset_sequencer_cursor > new_len + 1 then
          self.state.preset_sequencer_cursor = math.max(1, new_len + 1)
        end
      end
      self.state.sequencer_delete_confirm = nil
    elseif n == 2 and z == 1 then
      self.state.sequencer_delete_confirm = nil
    end
    if self.ui then self.ui:set_dirty(true) end
    return
  end

  if self.state.delete_confirm then
    if n == 3 and z == 1 then
      local idx = self.state.delete_confirm
      table.remove(self.state.presets, idx)
      if self.state.editing_preset_index == idx then
        self.state.editing_preset_index = nil
        self.state.screen = State.SCREEN_PRESETS_LIST
      elseif self.state.editing_preset_index and self.state.editing_preset_index > idx then
        self.state.editing_preset_index = self.state.editing_preset_index - 1
      end
      if #self.state.presets == 0 then
        self.state.preset_list_index = 0
      elseif self.state.preset_list_index > #self.state.presets then
        self.state.preset_list_index = #self.state.presets
      end
      self.state.delete_confirm = nil
    elseif n == 2 and z == 1 then
      self.state.delete_confirm = nil
    end
    if self.ui then self.ui:set_dirty(true) end
    return
  end

  if self.state.preset_name_edit_mode then
    if n == 2 and z == 1 then
      self.state.preset_name_edit_mode = false
      self.state.pending_name_save_confirm = true
    elseif n == 3 and z == 1 then
      local p = State.get_editing_preset(self.state)
      if p and self.state.preset_name_edit_buffer then
        local trimmed = self.state.preset_name_edit_buffer:gsub("^%s+", ""):gsub("%s+$", "")
        p.name = (trimmed ~= "") and trimmed or "Preset"
        if self.state.preset_before_edit then self.state.preset_edited_dirty = true end
      end
      self.state.preset_name_edit_mode = false
      self.state.preset_name_edit_buffer = ""
      self.state.preset_name_before_edit = nil
    end
    if self.ui then self.ui:set_dirty(true) end
    return
  end

  if self.state.screen == State.SCREEN_PRESET_EDITOR and self.state.editor_param_index == 0 and n == 3 and z == 1 then
    local p = State.get_editing_preset(self.state)
    if p then
      self.state.preset_name_before_edit = p.name or ""
      self.state.preset_name_edit_buffer = p.name or ""
      self.state.preset_name_edit_mode = true
      self.state.editing_name_position = 1
    end
    if self.ui then self.ui:set_dirty(true) end
    return
  end

  local action = State.on_key(self.state, n, z)
  if action == "navigate_back" then
    -- already set in state
  elseif action == "close_preset_editor" or action == "close_settings" or action == "close_preset_sequencer" or action == "close_project" then
    -- state already updated
  elseif action == "project_save" then
    self:project_save()
  elseif action == "project_load" then
    self:project_show_load_list()
  elseif action == "project_load_selected" then
    self:project_load_selected()
  elseif action == "project_save_as" then
    self:project_save_as()
  elseif action == "project_rename" then
    self:project_rename()
  elseif action == "project_set_fast_load" then
    self:project_show_fast_load_list()
  elseif action == "project_set_fast_load_selected" then
    self:project_set_fast_load_selected()
  elseif action == "project_delete" then
    self:project_show_delete_list()
  elseif action == "project_delete_confirmed" then
    self:project_delete_confirmed()
  elseif action == "project_delete_cancel" then
    self.state.project_delete_confirm = nil
    if self.ui then self.ui:set_dirty(true) end
  elseif action == "project_list_back" then
    if self.ui then self.ui:set_dirty(true) end
  end

  if n == 3 and z == 1 and self.state.screen == State.SCREEN_PRESET_EDITOR then
    local p = State.get_editing_preset(self.state)
    local play = self.state.playing
    if p and play then
      if play.running and play.preset_id == p.id and play.line == self.state.selected_line then
        if CrowIo.stop_line then CrowIo.stop_line(play.line) end
        play.running = false
      else
        if play.running and CrowIo.stop_line then CrowIo.stop_line(play.line) end
        play.line = self.state.selected_line
        play.preset_id = p.id
        play.running = true
        local bpm = (params and params.get and params:get("bpm")) or 120
        CrowIo.play_preset(play.line, p, function()
          if self.state.playing.preset_id == p.id and self.state.playing.line == play.line then
            self.state.playing.running = false
          end
          if self.ui then self.ui:set_dirty(true) end
          if redraw then redraw() end
        end, nil, function() return self:get_cv_inputs() end, bpm)
      end
    end
  end

  if action == "duplicate_preset" then
    local idx = self.state.preset_list_index
    local presets = self.state.presets or {}
    if idx >= 1 and idx <= #presets then
      local p = presets[idx]
      if p then
        local copy = State.copy_preset(p)
        if copy then
          local base_id = (p.id or "preset"):gsub("_copy.*$", "")
          local new_id = base_id .. "_copy"
          local n = 1
          local existing = {}
          for _, pr in ipairs(presets) do existing[pr.id] = true end
          while existing[new_id] do n = n + 1; new_id = base_id .. "_copy_" .. n end
          copy.id = new_id
          copy.name = (p.name or p.id or "Preset") .. " copy"
          table.insert(presets, idx + 1, copy)
          State.sort_presets_alphabetically(self.state)
          for i, pr in ipairs(self.state.presets or {}) do
            if pr.id == new_id then self.state.preset_list_index = i break end
          end
        end
      end
    end
    if self.ui then self.ui:set_dirty(true) end
    return
  end

  if action == "sequencer_action" and self.state.screen == State.SCREEN_PRESET_SEQUENCER and n == 3 and z == 1 then
    self:handle_sequencer_k3()
  end

  if action == "sequencer_add_preset" and self.state.sequencer_pick_preset_for_line then
    -- Use index captured in on_key at K3 press so the correct preset is added/replaced
    local idx = self.state.sequencer_add_preset_index or self.state.preset_list_index
    local preset_id_to_add = (idx >= 1 and idx <= #self.state.presets) and self.state.presets[idx] and self.state.presets[idx].id or nil
    local line = self.state.sequencer_pick_preset_for_line
    local row = self.state.sequences and self.state.sequences[line]
    if preset_id_to_add and row then
      local replace_slot = self.state.sequencer_pick_replace_slot
      if replace_slot and replace_slot >= 1 and replace_slot <= #(row.preset_ids or {}) then
        Sequencer.set_preset(row, replace_slot, preset_id_to_add)
        self.state.preset_sequencer_cursor = replace_slot
      else
        local insert_at = self.state.sequencer_pick_insert_at or 1
        Sequencer.insert_preset(row, insert_at, preset_id_to_add)
        self.state.preset_sequencer_cursor = insert_at
      end
    end
    self.state.sequencer_pick_preset_for_line = nil
    self.state.sequencer_pick_insert_at = nil
    self.state.sequencer_pick_replace_slot = nil
    self.state.sequencer_add_preset_index = nil
    self.state.screen = State.SCREEN_PRESET_SEQUENCER
  end

  if self.ui then
    self.ui:set_dirty(true)
  end
end

--- Handle K3 in Preset Sequencer: execute action (action from available list). Cursor 1..#ids = on preset, #ids+1 = end slot.
function M:handle_sequencer_k3()
  local s = self.state
  local line = s.preset_sequencer_selected_line
  local row = s.sequences and s.sequences[line]
  if not row then return end
  local ids = row.preset_ids or {}
  local cursor = s.preset_sequencer_cursor
  local available = State.sequencer_available_actions(s)
  local action_idx = s.preset_sequencer_action_index or 1
  if #available == 0 or action_idx < 1 or action_idx > #available then
    action_idx = 1
  end
  local action_id = available[action_idx]
  local on_preset = (cursor >= 1 and cursor <= #ids)
  local preset_slot = on_preset and cursor or 0
  local insert_at = (#ids + 1)

  if action_id == State.SEQ_ACTION_EDIT and on_preset and preset_slot >= 1 and preset_slot <= #ids then
    local pid = ids[preset_slot]
    for i, p in ipairs(s.presets) do
      if p.id == pid then
        s.editing_preset_index = i
        s.preset_before_edit = State.copy_preset(p)
        s.preset_edited_dirty = false
        s.screen = State.SCREEN_PRESET_EDITOR
        s.editor_segment_index = 1
        s.editor_param_index = 1
        s.came_from_sequencer = true
        return
      end
    end
  end
  if action_id == State.SEQ_ACTION_COPY and on_preset and preset_slot >= 1 and preset_slot <= #ids then
    local pid = ids[preset_slot]
    for _, p in ipairs(s.presets) do
      if p.id == pid then s.clipboard_preset = p break end
    end
    return
  end
  if action_id == State.SEQ_ACTION_PASTE then
    if not s.clipboard_preset then return end
    if on_preset and preset_slot >= 1 and preset_slot <= #ids then
      Sequencer.set_preset(row, preset_slot, s.clipboard_preset.id)
    else
      Sequencer.insert_preset(row, insert_at, s.clipboard_preset.id)
    end
    return
  end
  if action_id == State.SEQ_ACTION_DELETE and on_preset and preset_slot >= 1 and preset_slot <= #ids then
    s.sequencer_delete_confirm = { line = line, slot = preset_slot }
    return
  end
  if action_id == State.SEQ_ACTION_REPLACE and on_preset and preset_slot >= 1 and preset_slot <= #ids then
    s.sequencer_pick_preset_for_line = line
    s.sequencer_pick_replace_slot = preset_slot
    s.sequencer_pick_insert_at = nil
    s.screen = State.SCREEN_PRESETS_LIST
    if #s.presets > 0 then
      s.preset_list_index = 1
      s.sequencer_pick_selected_index = 1
    else
      s.preset_list_index = 0
      s.sequencer_pick_selected_index = nil
    end
    s.preset_list_action = "edit"
    return
  end
  if action_id == State.SEQ_ACTION_ADD and not on_preset then
    s.sequencer_pick_preset_for_line = line
    s.sequencer_pick_insert_at = insert_at
    s.sequencer_pick_replace_slot = nil
    s.screen = State.SCREEN_PRESETS_LIST
    if #s.presets > 0 then
      s.preset_list_index = 1
      s.sequencer_pick_selected_index = 1
    else
      s.preset_list_index = 0
      s.sequencer_pick_selected_index = nil
    end
    s.preset_list_action = "edit"
    if DEBUG_SEQUENCER_ADD and print then
      print("[lines] entered Select Available Preset: preset_list_index=1 insert_at=" .. tostring(insert_at))
    end
    return
  end
end

--- Start sequencer: play first preset on each line.
function M:sequencer_start()
  local s = self.state
  s.sequencer_running = true
  for line = 1, s.line_count do
    local row = s.sequences[line]
    if row then
      row.playing_slot = 1
      row.running = true
      local ids = row.preset_ids or {}
      if #ids > 0 then
        local pid = ids[1]
        local preset = self:preset_by_id(pid)
        if preset then
          local bpm = (params and params.get and params:get("bpm")) or 120
          CrowIo.play_preset(line, preset, function()
            self:sequencer_line_done(line)
          end, function(tgt_line, action)
            self:sequencer_ping(tgt_line, action)
          end, function() return self:get_cv_inputs() end, bpm, function(id)
            return id == 1 and (self.state.conditional_1_input or "cv1") or (self.state.conditional_2_input or "cv2")
          end)
        end
      end
    end
  end
end

--- When a line's preset finishes: advance slot and play next or stop.
function M:sequencer_line_done(line)
  local s = self.state
  local row = s.sequences and s.sequences[line]
  if not row or not s.sequencer_running then return end
  row.playing_slot = (row.playing_slot or 1) + 1
  local ids = row.preset_ids or {}
  if row.playing_slot <= #ids then
    local preset = self:preset_by_id(ids[row.playing_slot])
    if preset then
      local bpm = (params and params.get and params:get("bpm")) or 120
      CrowIo.play_preset(line, preset, function()
        self:sequencer_line_done(line)
      end, function(tgt_line, action)
        self:sequencer_ping(tgt_line, action)
      end, function() return self:get_cv_inputs() end, bpm, function(id)
        return id == 1 and (self.state.conditional_1_input or "cv1") or (self.state.conditional_2_input or "cv2")
      end)
    end
  else
    row.running = false
    CrowIo.stop_line(line)
  end
  if self.ui then self.ui:set_dirty(true) end
  if redraw then redraw() end
end

--- Ping: change target line's slot and restart that preset.
function M:sequencer_ping(target_line, action)
  local s = self.state
  local row = s.sequences and s.sequences[target_line]
  if not row then return end
  local ids = row.preset_ids or {}
  local n = #ids
  if n == 0 then return end
  local slot = row.playing_slot or 1
  if action == Sequencer.PING_INCREMENT then
    slot = (slot % n) + 1
  elseif action == Sequencer.PING_DECREMENT then
    slot = slot - 1
    if slot < 1 then slot = n end
  elseif action == Sequencer.PING_RESET then
    slot = 1
  end
  row.playing_slot = slot
  CrowIo.stop_line(target_line)
  local preset = self:preset_by_id(ids[slot])
  if preset then
    local bpm = (params and params.get and params:get("bpm")) or 120
    CrowIo.play_preset(target_line, preset, function()
      self:sequencer_line_done(target_line)
    end, function(tgt_line, act)
      self:sequencer_ping(tgt_line, act)
    end, function() return self:get_cv_inputs() end, bpm, function(id)
      return id == 1 and (self.state.conditional_1_input or "cv1") or (self.state.conditional_2_input or "cv2")
    end)
  end
  if self.ui then self.ui:set_dirty(true) end
  if redraw then redraw() end
end

--- Stop all lines and sequencer.
function M:sequencer_stop()
  local s = self.state
  s.sequencer_running = false
  for line = 1, 4 do
    if CrowIo.stop_line then CrowIo.stop_line(line) end
    local row = s.sequences and s.sequences[line]
    if row then row.running = false end
  end
end

--- Find preset by id in state.presets.
function M:preset_by_id(id)
  for _, p in ipairs(self.state.presets or {}) do
    if p.id == id then return p end
  end
  return nil
end

--- Return current CV inputs for conditional evaluation. Stub: zeros; later wire Crow input and line voltages.
--- @return table { cv1, cv2, line1, line2, line3, line4 }
function M:get_cv_inputs()
  return {
    cv1 = 0, cv2 = 0,
    line1 = 0, line2 = 0, line3 = 0, line4 = 0,
  }
end

--- Project file directory (norns _path.data). Returns nil if not on norns or _path not yet set.
function M:project_dir()
  local ok, path = pcall(function()
    if _path and _path.data then return _path.data end
    return nil
  end)
  return ok and path or nil
end

--- Serialize state to a plain table (presets, sequences, settings) for saving.
function M:project_export_data()
  local s = self.state
  local presets = {}
  for i, p in ipairs(s.presets or {}) do
    presets[i] = State.copy_preset(p)
  end
  local sequences = {}
  local line_count = s.line_count or 4
  for line = 1, line_count do
    local row = (s.sequences or {})[line]
    sequences[line] = {
      preset_ids = (row and row.preset_ids) and (function() local t = {} for j, id in ipairs(row.preset_ids) do t[j] = id end return t end)() or {},
      cursor = 1,
      running = false,
      playing_slot = 0,
    }
  end
  return {
    version = 1,
    presets = presets,
    sequences = sequences,
    line_count = line_count,
    voltage_lo = s.voltage_lo,
    voltage_hi = s.voltage_hi,
    ext_clock_cv = s.ext_clock_cv,
    run_cv = s.run_cv,
    quantize = s.quantize,
  }
end

--- Apply loaded project data to state.
function M:project_apply_data(data)
  if not data or type(data) ~= "table" then return end
  local s = self.state
  if data.presets and type(data.presets) == "table" then
    s.presets = data.presets
  end
  if data.sequences and type(data.sequences) == "table" then
    s.sequences = data.sequences
  end
  if type(data.line_count) == "number" and data.line_count >= 1 and data.line_count <= 4 then
    s.line_count = data.line_count
  end
  if type(data.voltage_lo) == "number" then s.voltage_lo = data.voltage_lo end
  if type(data.voltage_hi) == "number" then s.voltage_hi = data.voltage_hi end
  if type(data.ext_clock_cv) == "number" then s.ext_clock_cv = data.ext_clock_cv end
  if type(data.run_cv) == "number" then s.run_cv = data.run_cv end
  if data.quantize ~= nil then s.quantize = data.quantize end
  s.preset_list_index = #(s.presets or {}) > 0 and 1 or 0
  s.editing_preset_index = nil
  s.sequencer_delete_confirm = nil
  if params and params.set then
    params:set("line_count", s.line_count)
    params:set("voltage_range", (s.voltage_hi == 10) and 2 or 1)
    params:set("ext_clock_cv", s.ext_clock_cv)
    params:set("run_cv", s.run_cv)
    params:set("quantize", s.quantize and 1 or 0)
  end
  if self.ui then self.ui:set_dirty(true) end
end

--- Save project to path. Path is full path (e.g. _path.data .. "lines_myproject.lua").
function M:project_save_to_path(path)
  if not path or path == "" then return end
  local data = self:project_export_data()
  local function ser(v)
    if v == nil then return "nil"
    elseif type(v) == "boolean" then return v and "true" or "false"
    elseif type(v) == "number" then return tostring(v)
    elseif type(v) == "string" then return string.format("%q", v)
    elseif type(v) == "table" then
      local parts = {}
      for i = 1, #v do parts[#parts + 1] = ser(v[i]) end
      for k, v2 in pairs(v) do
        if type(k) ~= "number" or k < 1 or k > #v then
          parts[#parts + 1] = "[" .. (type(k) == "string" and string.format("%q", k) or ser(k)) .. "]=" .. ser(v2)
        end
      end
      return "{" .. table.concat(parts, ",") .. "}"
    end
    return "nil"
  end
  local content = "return " .. ser(data)
  local f = io.open(path, "w")
  if f then
    f:write(content)
    f:close()
    self.state.current_project_path = path
    if self.ui then self.ui:set_dirty(true) end
  end
end

--- Load project from path. Path is full path. Errors during load/apply are caught.
function M:project_load_from_path(path)
  if not path or path == "" then return end
  local f = io.open(path, "r")
  if not f then return end
  local content = f:read("*a")
  f:close()
  if not content or content == "" then return end
  local fn, err = load(content)
  if not fn then
    if print then print("[lines] project load parse: " .. tostring(err)) end
    return
  end
  local ok, data = pcall(fn)
  if not ok then
    if print then print("[lines] project load run: " .. tostring(data)) end
    if self.ui then self.ui:set_dirty(true) end
    return
  end
  if ok and data then
    local apply_ok, apply_err = pcall(function() self:project_apply_data(data) end)
    if apply_ok then
      self.state.current_project_path = path
    elseif print then
      print("[lines] project apply: " .. tostring(apply_err))
    end
  end
  if self.ui then self.ui:set_dirty(true) end
end

--- Fast-load marker file path (stores project path).
function M:project_fast_load_path()
  local dir = self:project_dir()
  if not dir then return nil end
  return dir .. "lines_fast_load"
end

--- Read current fast-load path from marker file (for UI star). Returns full path or nil.
function M:project_read_fast_load_path()
  local marker = self:project_fast_load_path()
  if not marker then return nil end
  local f = io.open(marker, "r")
  if not f then return nil end
  local content = f:read("*a")
  f:close()
  if not content or not content:match("%S") then return nil end
  local path = content:gsub("^%s+", ""):gsub("%s+$", ""):gsub("[\r\n]+", "")
  if path == "" then return nil end
  if path:sub(1, 1) ~= "/" then
    local dir = self:project_dir()
    if dir then path = dir .. path end
  end
  return path
end

--- List saved projects (lines_*.lua) in project dir; set state.project_list to full paths.
function M:project_refresh_list()
  local dir = self:project_dir()
  self.state.project_list = {}
  if not dir then return end
  local f = io.popen("ls " .. dir:gsub(" ", "\\ ") .. " 2>/dev/null")
  if f then
    for name in f:lines() do
      if name:match("^lines_.*%.lua$") then
        self.state.project_list[#self.state.project_list + 1] = dir .. name
      end
    end
    f:close()
  end
  self.state.project_list_index = math.max(1, math.min(self.state.project_list_index or 1, #self.state.project_list))
  if #self.state.project_list == 0 then
    self.state.project_list_index = 1
  end
end

--- Save project to current path (only shown when project already saved).
function M:project_save()
  if self.state.current_project_path and self.state.current_project_path ~= "" then
    self:project_save_to_path(self.state.current_project_path)
  end
  if self.ui then self.ui:set_dirty(true) end
end

--- Show load list: refresh list, enter sub-screen, store current fast-load path for star.
function M:project_show_load_list()
  self:project_refresh_list()
  self.state.project_fast_load_path = self:project_read_fast_load_path()
  self.state.project_sub_screen = "load"
  self.state.project_list_index = 1
  if self.ui then self.ui:set_dirty(true) end
end

--- Load the project selected in the list.
function M:project_load_selected()
  local list = self.state.project_list or {}
  local idx = self.state.project_list_index or 1
  if idx >= 1 and idx <= #list then
    self:project_load_from_path(list[idx])
  end
  self.state.project_sub_screen = nil
  if self.ui then self.ui:set_dirty(true) end
end

--- Normalize user-entered name to project filename (strip all leading "lines_" so we never double-prefix).
local function project_name_to_filename(name)
  local base = (name or ""):gsub("%s+", "_"):gsub("[^%w_-]", "")
  if base == "" then base = "project" end
  base = base:gsub("^(lines_)+", "")
  return "lines_" .. base .. ".lua"
end

--- Save As: prompt for name and save (new project or copy).
function M:project_save_as()
  local dir = self:project_dir()
  if not dir then return end
  if textentry then
    local default = (self.state.current_project_path and self.state.current_project_path:gsub("^.*/", ""):gsub("%.lua$", "") or "project")
    default = default:gsub("^(lines_)+", "")
    textentry.enter(function(name)
      if name and name:match("%S") then
        local path = dir .. project_name_to_filename(name)
        self:project_save_to_path(path)
      end
      if self.ui then self.ui:set_dirty(true) end
      if redraw then redraw() end
    end, default)
  end
end

--- Rename project: prompt for new name, save to new path, delete old file, update current and fast-load if needed.
function M:project_rename()
  local dir = self:project_dir()
  if not dir then return end
  local old_path = self.state.current_project_path
  if not old_path or old_path == "" then
    if self.ui then self.ui:set_dirty(true) end
    return
  end
  if textentry then
    local default = old_path:gsub("^.*/", ""):gsub("%.lua$", ""):gsub("^(lines_)+", "")
    textentry.enter(function(name)
      if name and name:match("%S") then
        local new_path = dir .. project_name_to_filename(name)
        if new_path == old_path then
          if self.ui then self.ui:set_dirty(true) end
          if redraw then redraw() end
          return
        end
        self:project_save_to_path(new_path)
        if os and os.remove and old_path ~= new_path then
          os.remove(old_path)
        end
        if self.state.project_fast_load_path == old_path then
          self.state.project_fast_load_path = new_path
          local marker = self:project_fast_load_path()
          if marker then
            local f = io.open(marker, "w")
            if f then f:write(new_path) f:close() end
          end
        end
      end
      if self.ui then self.ui:set_dirty(true) end
      if redraw then redraw() end
    end, default)
  end
end

--- Show set-fast-load list: refresh list, enter sub-screen, store current fast-load path for star.
function M:project_show_fast_load_list()
  self:project_refresh_list()
  self.state.project_fast_load_path = self:project_read_fast_load_path()
  self.state.project_sub_screen = "fast_load"
  self.state.project_list_index = 1
  if self.ui then self.ui:set_dirty(true) end
end

--- Show delete list: refresh list, enter sub-screen.
function M:project_show_delete_list()
  self:project_refresh_list()
  self.state.project_sub_screen = "delete"
  self.state.project_list_index = 1
  self.state.project_delete_confirm = nil
  if self.ui then self.ui:set_dirty(true) end
end

--- Delete the project file that was confirmed (state.project_delete_confirm). Clear current_project_path if it was that file.
function M:project_delete_confirmed()
  local path = self.state.project_delete_confirm
  self.state.project_delete_confirm = nil
  if path and path ~= "" then
    if self.state.current_project_path == path then
      self.state.current_project_path = nil
    end
    if os and os.remove then
      os.remove(path)
    end
  end
  self:project_refresh_list()
  if self.ui then self.ui:set_dirty(true) end
end

--- Set the selected project in the list as fast-load.
function M:project_set_fast_load_selected()
  local list = self.state.project_list or {}
  local idx = self.state.project_list_index or 1
  local marker = self:project_fast_load_path()
  if marker and idx >= 1 and idx <= #list then
    local full_path = (list[idx] or ""):gsub("[\r\n]+", "")
    local f = io.open(marker, "w")
    if f then
      f:write(full_path)
      f:close()
    end
    self.state.project_fast_load_path = full_path
  end
  self.state.project_sub_screen = nil
  if self.ui then self.ui:set_dirty(true) end
end

--- On init: load fast-load project if set (path stored in lines_fast_load file). Errors are caught so init never fails.
function M:project_try_fast_load()
  local ok, err = pcall(function()
    local marker = self:project_fast_load_path()
    if not marker then return end
    local f = io.open(marker, "r")
    if not f then return end
    local content = f:read("*a")
    f:close()
    if not content or not content:match("%S") then return end
    local load_path = content:gsub("^%s+", ""):gsub("%s+$", ""):gsub("[\r\n]+", "")
    if load_path == "" then return end
    if load_path:sub(1, 1) ~= "/" then
      local dir = self:project_dir()
      if dir then load_path = dir .. load_path end
    end
    self:project_load_from_path(load_path)
  end)
  if not ok and err and print then
    print("[lines] project_try_fast_load: " .. tostring(err))
  end
end

--- Redraw: return list of draw commands for script to run (screen.* must be called from script).
--- @return table|nil list of {"clear"}|{"level",n}|{"move",x,y}|{"text",s}|{"text_right",s}
function M:redraw()
  if self.ui and self.ui:is_dirty() then
    local cmds = self.ui:draw()
    self.ui:set_dirty(false)
    return cmds
  end
  return nil
end

--- Cleanup: stop metro, stop sequencer and Crow playback. Call from global cleanup().
function M:cleanup()
  if self.state then
    if self.state.sequencer_running then
      self:sequencer_stop()
    end
    if self.state.playing and self.state.playing.running then
      if CrowIo.stop_line then CrowIo.stop_line(self.state.playing.line) end
      self.state.playing.running = false
    end
    if CrowIo.stop_line then
      for line = 1, 4 do CrowIo.stop_line(line) end
    end
  end
  if self.redraw_metro then
    self.redraw_metro:stop()
    self.redraw_metro = nil
  end
  if self.text_scroll_metro then
    self.text_scroll_metro:stop()
    self.text_scroll_metro = nil
  end
  self.ui = nil
end

return M
