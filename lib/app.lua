-- lib/app.lua
-- Application orchestrator: wires state, UI, params; minimal logic in main.

local State = include("lib/state")
local Ui = include("lib/ui")

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
  self.ui = Ui.new(self.state)
  self:start_redraw_metro()
end

--- Setup params (norns paramset). Add parameters here.
function M:setup_params()
  params:add_separator("script")
  params:add {
    type = "number",
    id = "example",
    name = "Example",
    min = 0,
    max = 100,
    default = 50,
  }
end

--- Start the redraw metro so screen updates periodically.
function M:start_redraw_metro()
  self.redraw_metro = metro.init()
  self.redraw_metro.time = 1.0 / 15
  self.redraw_metro.event = function()
    if self.ui then
      self.ui:set_dirty(true)
      redraw()
    end
  end
  self.redraw_metro:start()
end

--- Handle encoder n with delta d. Delegates to state then marks UI dirty.
function M:enc(n, d)
  State.on_enc(self.state, n, d)
  if self.ui then
    self.ui:set_dirty(true)
  end
end

--- Handle key n with state z. Delegates to state then marks UI dirty.
function M:key(n, z)
  State.on_key(self.state, n, z)
  if self.ui then
    self.ui:set_dirty(true)
  end
end

--- Redraw screen if dirty. Call from global redraw().
function M:redraw()
  if self.ui and self.ui:is_dirty() then
    self.ui:draw()
    self.ui:set_dirty(false)
  end
end

--- Cleanup: stop metro. Call from global cleanup().
function M:cleanup()
  if self.redraw_metro then
    self.redraw_metro:stop()
    self.redraw_metro = nil
  end
  self.ui = nil
end

return M
