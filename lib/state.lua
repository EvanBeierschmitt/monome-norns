-- lib/state.lua
-- Pure(ish) application state + state transitions.

local State = {}

-- new()
-- Create a new state table with defaults.
function State.new()
  return {
    page = 1,
    page_count = 2,
    counter = 0,
    is_running = false,
  }
end

-- validate(state)
-- Validate invariants; returns (ok, err).
function State.validate(state)
  if type(state) ~= "table" then
    return false, "state must be a table"
  end
  if type(state.page) ~= "number" then
    return false, "state.page must be a number"
  end
  if type(state.page_count) ~= "number" then
    return false, "state.page_count must be a number"
  end
  if state.page < 1 or state.page > state.page_count then
    return false, "state.page out of range"
  end
  if type(state.counter) ~= "number" then
    return false, "state.counter must be a number"
  end
  if type(state.is_running) ~= "boolean" then
    return false, "state.is_running must be a boolean"
  end
  return true, nil
end

-- clamp(v, lo, hi)
-- Internal helper.
local function clamp(v, lo, hi)
  if v < lo then
    return lo
  end
  if v > hi then
    return hi
  end
  return v
end

-- on_enc(state, n, d)
-- Handle encoder input. Mutates and returns state.
function State.on_enc(state, n, d)
  if n == 1 then
    state.page = clamp(state.page + (d > 0 and 1 or -1), 1, state.page_count)
    return state
  end

  if n == 2 then
    state.counter = state.counter + d
    return state
  end

  if n == 3 then
    -- reserved for future mapping
    return state
  end

  return state
end

-- on_key(state, n, z)
-- Handle key input. Mutates and returns state.
function State.on_key(state, n, z)
  if z ~= 1 then
    return state
  end

  if n == 2 then
    state.is_running = not state.is_running
    return state
  end

  if n == 3 then
    state.counter = 0
    return state
  end

  return state
end

return State

