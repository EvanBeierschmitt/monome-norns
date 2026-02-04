-- scriptname: Lines
-- v0.1.0 @evanbeierschmitt
-- Sequencable function generator for Crow CV. Inspired by Control Forge.

-- Build draw commands entirely in script so no module code runs during redraw (norns errors otherwise).
local Segment = include("lib/segment")
local SCREEN_MAIN_MENU = "main_menu"
local SCREEN_PRESETS_LIST = "presets_list"
local SCREEN_PRESET_EDITOR = "preset_editor"
local SCREEN_PRESET_SEQUENCER = "preset_sequencer"
local SCREEN_SETTINGS = "settings"
local LEVEL_HINT = 4
local LEVEL_UNSELECTED = 8
local LEVEL_TITLE = 12
local LEVEL_SELECTED = 15
local Y_STATUS = 6
local Y_CONTENT_START = 12
local Y_FOOTER = 64
local VALUE_X_RIGHT = 118
local CONTENT_H = 52
local ROW_H = 10
local SCROLLBAR_X = 122
local SCROLLBAR_W = 4
local PARAM_COUNT = 6

-- Set to false for release; when true, show last enc/key or "input ok" on main menu to confirm input reaches script
local DEBUG_INPUT = true
local last_enc = nil
local last_key = nil
local last_enc_time = 0
local last_key_time = 0

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
    local items = { "Preset Sequencer", "Presets", "Settings" }
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
      add("move", 4, 24)
      add("level", LEVEL_UNSELECTED)
      local p = (s.presets or {})[s.delete_confirm]
      if p then add("text", p.name or p.id or "?") end
    else
      add("move", 4, Y_STATUS)
      add("level", LEVEL_TITLE)
      add("text", "Presets")
      local presets = s.presets or {}
      local cur = s.preset_list_index or 0
      local total = #presets >= 1 and (#presets + 2) or (#presets + 1)
      local visible = math.floor(CONTENT_H / ROW_H)
      local scroll_offset = total > visible and math.max(0, math.min(cur, total - visible)) or 0
      for i = 0, visible - 1 do
        local r = scroll_offset + i
        if r < total then
          local y = Y_CONTENT_START + i * ROW_H
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
      if total > visible then
        add("level", LEVEL_HINT)
        add("rect", SCROLLBAR_X, Y_CONTENT_START, SCROLLBAR_W, CONTENT_H, false)
        local thumb_h = math.max(2, math.floor(CONTENT_H * visible / total))
        local thumb_y = Y_CONTENT_START + math.floor((CONTENT_H - thumb_h) * scroll_offset / math.max(1, total - visible))
        add("rect", SCROLLBAR_X, thumb_y, SCROLLBAR_W, thumb_h, true)
      end
    end
  elseif s.screen == SCREEN_PRESET_EDITOR then
    local p = s.editing_preset_index and (s.presets or {})[s.editing_preset_index]
    if not p then
      add("move", 4, Y_STATUS); add("level", LEVEL_TITLE); add("text", "No preset")
      add("move", 4, 24); add("level", LEVEL_UNSELECTED); add("text", "No preset")
    else
      add("move", 4, Y_STATUS); add("level", LEVEL_TITLE); add("text", p.name or p.id or "Preset")
      local seg_idx = s.editor_segment_index or 1
      local param_idx = s.editor_param_index or 1
      local param_names = { "Name:", "Time:", "Time unit:", "Mode:", "Level:", "Shape:", "Jump:", "Ping:" }
      local seg = p.segments and p.segments[seg_idx]
      if not seg then
        add("move", 4, Y_CONTENT_START); add("level", LEVEL_UNSELECTED); add("text", "seg " .. seg_idx)
      else
        add("move", 4, Y_CONTENT_START); add("level", LEVEL_UNSELECTED); add("text", "seg " .. seg_idx .. " / 8")
        local param_row_h = 8
        local total_rows = 8
        local visible_params = math.floor((CONTENT_H - 10) / param_row_h)
        local param_scroll = total_rows > visible_params and math.max(0, math.min(param_idx, total_rows - visible_params)) or 0
        for i = 1, visible_params do
          local pi = param_scroll + i - 1
          if pi < total_rows then
            local y = Y_CONTENT_START + 10 + (i - 1) * param_row_h
            add("move", 4, y)
            if pi == param_idx then add("level", LEVEL_SELECTED) else add("level", LEVEL_UNSELECTED) end
            add("text", param_names[pi + 1] or "?")
            local val
            if pi == 0 then
              val = p.name or p.id or "Preset"
            else
              if pi == 1 then
                local tu = seg.time_unit or "sec"
                val = tostring(seg.time) .. (tu == "beats" and " bt" or " s")
              elseif pi == 2 then val = seg.time_unit or "sec"
              elseif pi == 3 then val = seg.level_mode or "abs"
              elseif pi == 4 then
                if seg.level_mode == "absQ" or seg.level_mode == "relQ" then
                  val = Segment and Segment.voltage_to_note and Segment.voltage_to_note(seg.level_value or 0) or string.format("%.2f", seg.level_value or 0)
                else
                  val = string.format("%.2f", seg.level_value or 0)
                end
              elseif pi == 5 then val = seg.shape or "linear"
              elseif pi == 6 then val = seg.jump_to_segment and ("seg " .. seg.jump_to_segment) or "stop"
              elseif pi == 7 then val = (seg.ping_line and seg.ping_action) and ("L" .. seg.ping_line .. " " .. (seg.ping_action or "")) or "off"
              else val = "" end
            end
            add("move", VALUE_X_RIGHT, y)
            if pi == param_idx then add("level", LEVEL_SELECTED) else add("level", LEVEL_UNSELECTED) end
            add("text_right", val)
          end
        end
        if total_rows > visible_params then
          add("level", LEVEL_HINT)
          add("rect", SCROLLBAR_X, Y_CONTENT_START, SCROLLBAR_W, CONTENT_H, false)
          local thumb_h = math.max(2, math.floor(CONTENT_H * visible_params / total_rows))
          local thumb_y = Y_CONTENT_START + math.floor((CONTENT_H - thumb_h) * param_scroll / math.max(1, total_rows - visible_params))
          add("rect", SCROLLBAR_X, thumb_y, SCROLLBAR_W, thumb_h, true)
        end
      end
    end
  elseif s.screen == SCREEN_PRESET_SEQUENCER then
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
    add("move", 4, Y_STATUS); add("level", LEVEL_TITLE); add("text", "Preset Sequencer  L" .. line)
    if total_slots == 0 then
      add("move", 4, Y_CONTENT_START); add("level", LEVEL_UNSELECTED); add("text", "(empty) E3 Add")
      add("move", 4, Y_CONTENT_START + 4); add("level", LEVEL_SELECTED); add("text", ">")
    else
      for i = 1, visible_rows do
        local slot_index = scroll_offset + i
        if slot_index <= total_slots then
          local y = Y_CONTENT_START + (i - 1) * ROW_H
          local pid = ids[slot_index]
          local name = pid or "?"
          for _, pr in ipairs(s.presets or {}) do if pr.id == pid then name = pr.name or pr.id break end end
          add("move", 4, y)
          add("level", LEVEL_UNSELECTED)
          add("text", " " .. slot_index .. "  " .. name)
        end
      end
      local sel_row_local = R - scroll_offset
      local sel_sub = (cursor - 1) % 2
      local sel_y = Y_CONTENT_START + sel_row_local * ROW_H + sel_sub * (ROW_H / 2)
      if sel_row_local >= 0 and sel_row_local < visible_rows then
        add("move", 4, sel_y); add("level", LEVEL_SELECTED); add("text", ">")
      elseif sel_row_local < 0 then
        add("move", 4, Y_CONTENT_START); add("level", LEVEL_SELECTED); add("text", ">")
      else
        add("move", 4, Y_CONTENT_START + (visible_rows - 1) * ROW_H); add("level", LEVEL_SELECTED); add("text", ">")
      end
      if logical_rows > visible_rows then
        add("level", LEVEL_HINT)
        add("rect", SCROLLBAR_X, Y_CONTENT_START, SCROLLBAR_W, CONTENT_H, false)
        local thumb_h = math.max(2, math.floor(CONTENT_H * visible_rows / logical_rows))
        local thumb_y = Y_CONTENT_START + math.floor((CONTENT_H - thumb_h) * scroll_offset / math.max(1, scroll_max))
        add("rect", SCROLLBAR_X, thumb_y, SCROLLBAR_W, thumb_h, true)
      end
    end
    add("move", 4, Y_CONTENT_START + 40); add("level", LEVEL_UNSELECTED); add("text", action_names[action_idx] or "?")
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
      add("move", VALUE_X_RIGHT, y)
      if i == sel then add("level", LEVEL_SELECTED) else add("level", LEVEL_UNSELECTED) end
      add("text_right", f.value)
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

function init()
  init_error = nil
  local ok, err = pcall(function()
    App = include("lib/app")
    app = App.new()
    app:init()
  end)
  if not ok then
    init_error = tostring(err)
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
    local init_redraw = metro.init()
    init_redraw.time = 0.1
    init_redraw.count = 1
    init_redraw.event = function()
      if redraw then redraw() end
    end
    init_redraw:start()
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
      screen.move(4, 32)
      screen.text((init_error .. ""):gsub("%s+", " "):sub(1, 28))
      screen.move(4, 48)
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
  if app ~= nil then app:cleanup() end
end
