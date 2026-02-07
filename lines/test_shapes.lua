-- test_shapes.lua
-- Output each Control Forge shape to Crow output 1 over 2s for scope verification.
-- From Maiden REPL (with Lines loaded): dofile(_path.code .. "lines/test_shapes.lua"); run_shape_test()
-- Each shape ramps 0V -> 5V over 2s, then 0.5s pause, then next shape.

local Shapes = include("lib/shapes")
local Segment = include("lib/segment")

function run_shape_test()
  if not Segment or not Segment.shapes then return end
  local shape_ids = Segment.shapes()
  local line = 1
  local duration = 2.0
  local step = 0.02
  clock.run(function()
    for _, shape_id in ipairs(shape_ids) do
      local start_t = util.time()
      while util.time() - start_t < duration do
        local t = (util.time() - start_t) / duration
        if t > 1 then t = 1 end
        local y = Shapes.shape_value(shape_id, t)
        if crow and crow.output and crow.output[line] then
          crow.output[line].slew = 0
          crow.output[line].volts = 5 * y
        end
        clock.sleep(step)
      end
      if crow and crow.output and crow.output[line] then
        crow.output[line].slew = 0
        crow.output[line].volts = 0
      end
      clock.sleep(0.5)
    end
  end)
end
