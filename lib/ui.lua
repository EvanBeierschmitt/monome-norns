-- lib/ui.lua
-- Screen drawing for 128x64 grayscale. Avoid allocations in hot path.

local M = {}

--- Create a UI instance bound to shared state.
--- @param state table read-only state for display
--- @return table ui instance
function M.new(state)
  return {
    state = state,
    dirty = true,
  }
end

--- Mark whether the screen needs redraw.
function M:set_dirty(value)
  self.dirty = value
end

--- Return true if a redraw is pending.
function M:is_dirty()
  return self.dirty
end

--- Draw one frame. Uses screen.* only; no allocations in loop.
function M:draw()
  screen.clear()
  screen.level(15)
  screen.move(4, 8)
  screen.text("page " .. (self.state.page or 1) .. " / " .. (self.state.page_count or 1))
  screen.move(4, 20)
  screen.text("counter " .. (self.state.counter or 0))
  screen.move(4, 32)
  screen.text(self.state.is_running and "running" or "stopped")
  screen.update()
end

return M
