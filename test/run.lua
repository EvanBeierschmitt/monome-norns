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

package.path = package.path .. ";" .. repo_root .. "/?.lua"

-- Minimal norns mock so libs that expect include() can be stubbed
local _norns_mock = {}
function _norns_mock.include(name)
  local modpath = name:gsub("%.", "/") .. ".lua"
  local f, err = loadfile(repo_root .. "/" .. modpath)
  if not f then error("include " .. name .. ": " .. tostring(err)) end
  return f()
end

-- Load State without norns (no include() used in state.lua)
local State
do
  local path = repo_root .. "/lib/state.lua"
  local f, err = loadfile(path)
  if not f then
    print("ERROR: cannot load lib/state.lua: " .. tostring(err))
    os.exit(1)
  end
  State = f()
end

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

-- State.new()
local s = State.new()
ok(s ~= nil, "State.new() returns table")
ok(type(s.page) == "number", "state.page is number")
ok(type(s.page_count) == "number", "state.page_count is number")
ok(type(s.counter) == "number", "state.counter is number")
ok(type(s.is_running) == "boolean", "state.is_running is boolean")

-- State.validate()
local ok_v, err_v = State.validate(s)
ok(ok_v == true and err_v == nil, "State.validate(valid state) passes")
local ok_b, err_b = State.validate({})
ok(ok_b == false and err_b ~= nil, "State.validate(invalid) fails with message")
local ok_n = State.validate(123)
ok(ok_n == false, "State.validate(non-table) fails")

-- State.on_enc()
s.page = 1
s.page_count = 2
State.on_enc(s, 1, 1)
ok(s.page == 2, "enc 1 +1 moves page to 2")
State.on_enc(s, 1, 1)
ok(s.page == 2, "enc 1 +1 at max page stays 2")
State.on_enc(s, 1, -1)
ok(s.page == 1, "enc 1 -1 moves page to 1")
State.on_enc(s, 1, -1)
ok(s.page == 1, "enc 1 -1 at min page stays 1")

s.counter = 0
State.on_enc(s, 2, 3)
ok(s.counter == 3, "enc 2 adds delta to counter")

-- State.on_key()
s.is_running = false
State.on_key(s, 2, 1)
ok(s.is_running == true, "key 2 press toggles is_running on")
State.on_key(s, 2, 1)
ok(s.is_running == false, "key 2 press toggles is_running off")

s.counter = 10
State.on_key(s, 3, 1)
ok(s.counter == 0, "key 3 press resets counter")

State.on_key(s, 1, 0)
ok(s.is_running == false, "key 1 release does not change state")

print("")
print(string.format("Result: %d passed, %d failed", passed, failed))
if failed > 0 then
  os.exit(1)
end
