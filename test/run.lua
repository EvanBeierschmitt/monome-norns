-- test/run.lua
-- Pure Lua test runner for lib/ logic. Mocks norns globals when needed.
-- Run from repo root: lua test/run.lua

local repo_root = (function()
  local path = arg[0] or ""
  if path:match("^@") then path = path:sub(2) end
  path = path:gsub("[^/\\]+$", "")
  path = path:gsub("test$", "")
  if path == "" then path = "." end
  return path
end)()

-- Lib lives under lines/lib/ when run from repo root
local lines_lib = repo_root .. "/lines/lib"
package.path = package.path .. ";" .. repo_root .. "/?.lua"

-- Mock norns include() so lines/lib/*.lua can load (paths like "lib/state")
function include(name)
  local modpath = name:gsub("%.", "/") .. ".lua"
  local f, err = loadfile(lines_lib .. "/../" .. modpath)
  if not f then
    f, err = loadfile(repo_root .. "/" .. modpath)
  end
  if not f then error("include " .. name .. ": " .. tostring(err)) end
  return f()
end

local State = include("lib/state")
local Segment = include("lib/segment")
local Preset = include("lib/preset")

local passed = 0
local failed = 0

local function ok(cond, msg)
  if cond then
    passed = passed + 1
    print("[pass] " .. (msg or "ok"))
  else
    failed = failed + 1
    print("[fail] " .. (msg or "assertion failed"))
  end
end

-- Segment
local seg = Segment.default()
ok(seg ~= nil, "Segment.default() returns table")
ok(seg.shape == "linear", "segment.shape default")
ok(seg.level_mode == "abs", "segment.level_mode default")
local ok_seg, err_seg = Segment.validate(seg, -5, 5)
ok(ok_seg == true and err_seg == nil, "Segment.validate(valid) passes")
local ok_bad = Segment.validate({ shape = "invalid" }, -5, 5)
ok(ok_bad == false, "Segment.validate(invalid shape) fails")

-- Preset
local p = Preset.new("p1", "Preset 1")
ok(p ~= nil and p.id == "p1" and p.name == "Preset 1", "Preset.new() returns preset")
ok(#p.segments == 8, "preset has 8 segments")
local ok_p, err_p = Preset.validate(p, -5, 5)
ok(ok_p == true and err_p == nil, "Preset.validate(valid) passes")

-- State.new()
local s = State.new()
ok(s ~= nil, "State.new() returns table")
ok(s.screen == State.SCREEN_MAIN_MENU, "state.screen default main_menu")
ok(type(s.main_menu_index) == "number", "state.main_menu_index is number")
ok(type(s.presets) == "table", "state.presets is table")
ok(type(s.line_count) == "number", "state.line_count is number")
ok(type(s.selected_line) == "number", "state.selected_line is number")

-- State.validate()
local ok_v, err_v = State.validate(s)
ok(ok_v == true and err_v == nil, "State.validate(valid state) passes")
local ok_b, err_b = State.validate({})
ok(ok_b == false and err_b ~= nil, "State.validate(invalid) fails with message")

-- State.on_enc() main menu
s.screen = State.SCREEN_MAIN_MENU
s.main_menu_index = 1
State.on_enc(s, 1, 1)
ok(s.main_menu_index == 2, "enc 1 on main menu moves selection")
State.on_enc(s, 1, 1)
State.on_enc(s, 1, 1)
ok(s.main_menu_index == 4, "enc 1 at max stays 4")
State.on_enc(s, 1, -1)
State.on_enc(s, 1, -1)
ok(s.main_menu_index == 2, "enc 1 -1 moves selection")

-- State.on_enc() preset editor
s.screen = State.SCREEN_PRESET_EDITOR
s.editor_segment_index = 1
s.editor_param_index = 1
s.presets = { Preset.new("p1", "P1") }
s.editing_preset_index = 1
State.on_enc(s, 1, 1)
ok(s.editor_segment_index == 2, "enc 1 in editor moves segment")
State.on_enc(s, 2, 1)
ok(s.editor_param_index == 2, "enc 2 in editor moves param")
local seg1 = s.presets[1].segments[1]
local t0 = seg1.time
State.on_enc(s, 3, 1)
ok(seg1.time == t0 + 1, "enc 3 in editor changes time")

-- State.on_key() main menu enter (K3 = enter per 070)
s.screen = State.SCREEN_MAIN_MENU
s.main_menu_index = State.MENU_PRESETS_LIST
s.presets = {}
local action = State.on_key(s, 3, 1)
ok(action == "open_presets_list", "K3 on Presets opens presets list")
ok(s.screen == State.SCREEN_PRESETS_LIST, "screen is presets list")

print("")
print(string.format("Result: %d passed, %d failed", passed, failed))
if failed > 0 then
  os.exit(1)
end
