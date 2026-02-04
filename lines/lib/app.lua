-- lib/app.lua
-- Application orchestrator: wires state, UI, params, Crow; minimal logic in main.

local State = include("lib/state")
local Ui = include("lib/ui")
local CrowIo = include("lib/crow_io")
local Sequencer = include("lib/sequencer")

local M = {}

--- Create a new app instance.
--- @return table app instance with :init(), :enc(), :key(), :redraw(), :cleanup()
function M.new()
  local app = {
    state = State.new(),
    ui = nil,
    redraw_metro = nil,
  }
  setmetatable(app, { __index = M })
  return app
end

--- Initialize: params, UI, redraw metro. Call once from init().
function M:init()
  self:setup_params()
  if params then
    self.state.line_count = params:get("line_count") or 4
    local vr = params:get("voltage_range") or 1
    if vr == 1 then self.state.voltage_lo, self.state.voltage_hi = -5, 5
    else self.state.voltage_lo, self.state.voltage_hi = -5, 10 end
  end
  self.ui = Ui.new(self.state)
  self:start_redraw_metro()
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
    options = { "Preset Sequencer", "Presets", "Settings" },
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

--- Handle encoder n with delta d. Delegates to state then marks UI dirty.
function M:enc(n, d)
  State.on_enc(self.state, n, d)
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

  local action = State.on_key(self.state, n, z)
  if action == "navigate_back" then
    -- already set in state
  elseif action == "close_preset_editor" or action == "close_settings" or action == "close_preset_sequencer" then
    -- state already updated
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

  if action == "sequencer_action" and self.state.screen == State.SCREEN_PRESET_SEQUENCER and n == 3 and z == 1 then
    self:handle_sequencer_k3()
  end

  if action == "sequencer_add_preset" and self.state.sequencer_pick_preset_for_line and #self.state.presets > 0 then
    local line = self.state.sequencer_pick_preset_for_line
    local insert_at = self.state.sequencer_pick_insert_at or 1
    local row = self.state.sequences and self.state.sequences[line]
    local idx = self.state.preset_list_index
    local p = self.state.presets[idx]
    if row and p then
      Sequencer.insert_preset(row, insert_at, p.id)
      self.state.preset_sequencer_cursor = 2 * insert_at
    end
    self.state.sequencer_pick_preset_for_line = nil
    self.state.sequencer_pick_insert_at = nil
    self.state.screen = State.SCREEN_PRESET_SEQUENCER
  end

  if self.ui then
    self.ui:set_dirty(true)
  end
end

--- Handle K3 in Preset Sequencer: execute action or play/stop.
function M:handle_sequencer_k3()
  local s = self.state
  local line = s.preset_sequencer_selected_line
  local row = s.sequences and s.sequences[line]
  if not row then return end
  local ids = row.preset_ids or {}
  local cursor = s.preset_sequencer_cursor
  local action_idx = s.preset_sequencer_action_index
  local on_preset = (cursor % 2 == 0)
  local preset_slot = on_preset and (cursor // 2) or 0
  local gap_after = (cursor + 1) // 2

  if action_idx == State.SEQ_ACTION_EDIT and on_preset and preset_slot >= 1 and preset_slot <= #ids then
    local pid = ids[preset_slot]
    for i, p in ipairs(s.presets) do
      if p.id == pid then
        s.editing_preset_index = i
        s.screen = State.SCREEN_PRESET_EDITOR
        s.editor_segment_index = 1
        s.editor_param_index = 1
        return
      end
    end
  end
  if action_idx == State.SEQ_ACTION_COPY and on_preset and preset_slot >= 1 and preset_slot <= #ids then
    local pid = ids[preset_slot]
    for _, p in ipairs(s.presets) do
      if p.id == pid then s.clipboard_preset = p break end
    end
    return
  end
  if action_idx == State.SEQ_ACTION_PASTE then
    if not s.clipboard_preset then return end
    if on_preset and preset_slot >= 1 and preset_slot <= #ids then
      Sequencer.set_preset(row, preset_slot, s.clipboard_preset.id)
    else
      Sequencer.insert_preset(row, gap_after, s.clipboard_preset.id)
    end
    return
  end
  if action_idx == State.SEQ_ACTION_DELETE and on_preset and preset_slot >= 1 and preset_slot <= #ids then
    Sequencer.delete_preset(row, preset_slot)
    local new_len = #(row.preset_ids or {})
    if s.preset_sequencer_cursor > 2 * new_len + 1 then
      s.preset_sequencer_cursor = math.max(1, 2 * new_len + 1)
    end
    return
  end
  if action_idx == State.SEQ_ACTION_ADD and not on_preset then
    s.sequencer_pick_preset_for_line = line
    s.sequencer_pick_insert_at = gap_after
    s.screen = State.SCREEN_PRESETS_LIST
    s.preset_list_index = #s.presets > 0 and 1 or 0
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
          end, function() return self:get_cv_inputs() end, bpm)
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
      end, function() return self:get_cv_inputs() end, bpm)
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
    end, function() return self:get_cv_inputs() end, bpm)
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
  self.ui = nil
end

return M
