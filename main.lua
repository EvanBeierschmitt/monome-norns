-- scriptname: norns script skeleton (correct-by-default layout)
-- v0.1.0 @evanbeierschmitt

-- This entry script is intentionally thin.
-- Wire modules together here; keep logic inside lib/.

local App = include("lib/app")

local app = nil

function init()
  app = App.new()
  app:init()
end

function enc(n, d)
  if app ~= nil then
    app:enc(n, d)
  end
end

function key(n, z)
  if app ~= nil then
    app:key(n, z)
  end
end

function redraw()
  if app ~= nil then
    app:redraw()
  end
end

function cleanup()
  if app ~= nil then
    app:cleanup()
  end
end

