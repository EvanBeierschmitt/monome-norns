-- Minimal screen test: only draws "hello" so you can check if norns + screen work.
-- To use: temporarily copy this file over lines.lua on norns, run Lines. If you see "hello", screen works.
-- Restore lines.lua from the repo after testing.

function init()
  redraw()
end

function redraw()
  if screen then
    screen.clear()
    screen.level(15)
    screen.move(4, 32)
    screen.text("hello")
    screen.update()
  end
end

function enc() end
function key() end
function cleanup() end
