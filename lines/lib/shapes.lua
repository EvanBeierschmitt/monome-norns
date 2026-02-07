-- lib/shapes.lua
-- Control Forge transition shapes: normalized curve f(t) -> y, t and y in [0,1]. No norns/Crow deps.

local M = {}

-- Exponential 1-7: concave-up (slow start, fast end). y = t^p, p > 1.
local EXP_POWERS = { 1.2, 1.5, 1.9, 2.4, 3.0, 3.8, 5.0 }

-- Circle 1.4, 1.6, 1.8, 1.16: convex (steep start, flat end). y = 1 - (1-t)^p.
local CIRCLE_POWERS = { 1.4, 1.6, 1.8, 1.16 }

local function lerp(a, b, x)
  return a + (b - a) * x
end

-- Piecewise linear: table of {t, y} breakpoints (t in [0,1], y in [0,1]); lerp between points.
local function piecewise(t, points)
  if t <= 0 then return 0 end
  if t >= 1 then return 1 end
  for i = 1, #points - 1 do
    local t0, y0 = points[i][1], points[i][2]
    local t1, y1 = points[i + 1][1], points[i + 1][2]
    if t >= t0 and t <= t1 then
      local u = (t - t0) / (t1 - t0)
      return lerp(y0, y1, u)
    end
  end
  return 1
end

-- Squeeze: moderate slope -> steep -> flat (3 segments).
local SQUEEZE = { {0, 0}, {0.25, 0.2}, {0.6, 0.85}, {1, 1} }
-- Fast Line 1-3: steep -> flat -> steep.
local FAST_LINE_1 = { {0, 0}, {0.15, 0.5}, {0.85, 0.55}, {1, 1} }
local FAST_LINE_2 = { {0, 0}, {0.2, 0.55}, {0.8, 0.6}, {1, 1} }
local FAST_LINE_3 = { {0, 0}, {0.18, 0.48}, {0.82, 0.52}, {1, 1} }
-- Medium Line 1-2: gentler multi-linear.
local MEDIUM_LINE_1 = { {0, 0}, {0.25, 0.35}, {0.75, 0.65}, {1, 1} }
local MEDIUM_LINE_2 = { {0, 0}, {0.3, 0.4}, {0.7, 0.6}, {1, 1} }
-- Slow Ramp 1-2: flat -> steep -> flat.
local SLOW_RAMP_1 = { {0, 0}, {0.2, 0.08}, {0.8, 0.92}, {1, 1} }
local SLOW_RAMP_2 = { {0, 0}, {0.25, 0.1}, {0.75, 0.9}, {1, 1} }
-- Bloom: flat start, moderate rise, steeper end.
local BLOOM = { {0, 0}, {0.25, 0.05}, {0.6, 0.4}, {1, 1} }
local BLOOM_2 = { {0, 0}, {0.33, 0.03}, {0.65, 0.35}, {1, 1} }
-- Slow Curve 1-2: flat, sharp rise, flat/dip, steep end.
local SLOW_CURVE_1 = { {0, 0}, {0.15, 0.02}, {0.35, 0.5}, {0.6, 0.55}, {1, 1} }
local SLOW_CURVE_2 = { {0, 0}, {0.2, 0.05}, {0.5, 0.4}, {0.8, 0.45}, {1, 1} }
-- Delay DC / DC Delay: hold 0 then step to 1.
local DELAY_DC = { {0, 0}, {0.92, 0}, {0.96, 1}, {1, 1} }
local DC_DELAY = { {0, 0}, {0.97, 0}, {0.99, 1}, {1, 1} }
-- Curve 2X: rise, dip, rise, dip, rise.
local CURVE_2X = { {0, 0}, {0.2, 0.4}, {0.4, 0.3}, {0.6, 0.65}, {0.8, 0.55}, {1, 1} }
local CURVE_2X_B = { {0, 0}, {0.25, 0.45}, {0.45, 0.25}, {0.7, 0.7}, {0.85, 0.5}, {1, 1} }
-- Curve 2X C: triangular peak then valley then end.
local CURVE_2X_C = { {0, 0}, {0.5, 0.9}, {0.75, 0.35}, {1, 1} }

-- Deterministic pseudo-noise in [-1, 1] for chaos/zigzag (same t -> same value).
local function noise(t)
  local x = t * 937.7 + t * 701.3 + t * 433.1
  return (math.sin(x) * 0.5 + 0.5) * 2 - 1
end

--- Normalized shape value: y = f(t), t in [0,1], y in [0,1]. Unknown shape_id falls back to linear.
--- @param shape_id string e.g. "linear", "exponential_1", "circle_1_4"
--- @param t number 0..1
--- @return number 0..1
function M.shape_value(shape_id, t)
  if type(t) ~= "number" then return 0 end
  if t <= 0 then return 0 end
  if t >= 1 then return 1 end

  if shape_id == "linear" then
    return t
  end

  if shape_id == "exponential_1" or shape_id == "exponential_2" or shape_id == "exponential_3" or
     shape_id == "exponential_4" or shape_id == "exponential_5" or shape_id == "exponential_6" or shape_id == "exponential_7" then
    local i = tonumber(shape_id:match("(%d)$"))
    if i and i >= 1 and i <= 7 then
      return t ^ EXP_POWERS[i]
    end
  end

  if shape_id == "circle_1_4" or shape_id == "circle_1_6" or shape_id == "circle_1_8" or shape_id == "circle_1_16" then
    local p
    if shape_id == "circle_1_4" then p = 1.4
    elseif shape_id == "circle_1_6" then p = 1.6
    elseif shape_id == "circle_1_8" then p = 1.8
    elseif shape_id == "circle_1_16" then p = 1.16
    else return t end
    return 1 - (1 - t) ^ p
  end

  if shape_id == "squeeze" then return piecewise(t, SQUEEZE) end
  if shape_id == "fast_line_1" then return piecewise(t, FAST_LINE_1) end
  if shape_id == "fast_line_2" then return piecewise(t, FAST_LINE_2) end
  if shape_id == "fast_line_3" then return piecewise(t, FAST_LINE_3) end
  if shape_id == "medium_line_1" then return piecewise(t, MEDIUM_LINE_1) end
  if shape_id == "medium_line_2" then return piecewise(t, MEDIUM_LINE_2) end
  if shape_id == "slow_ramp_1" then return piecewise(t, SLOW_RAMP_1) end
  if shape_id == "slow_ramp_2" then return piecewise(t, SLOW_RAMP_2) end

  -- 21-22: Bloom, Bloom 2
  if shape_id == "bloom" then return piecewise(t, BLOOM) end
  if shape_id == "bloom_2" then return piecewise(t, BLOOM_2) end

  -- 23-26: Circle reverse (steep start, flat end): y = t^p, p < 1
  if shape_id == "circle_1_16_reverse" then return t ^ (1 / 1.16) end
  if shape_id == "circle_1_8_reverse" then return t ^ (1 / 1.8) end
  if shape_id == "circle_1_6_reverse" then return t ^ (1 / 1.6) end
  if shape_id == "circle_1_4_reverse" then return t ^ (1 / 1.4) end

  -- 27-28: Slow Curve 1-2
  if shape_id == "slow_curve_1" then return piecewise(t, SLOW_CURVE_1) end
  if shape_id == "slow_curve_2" then return piecewise(t, SLOW_CURVE_2) end

  -- 29-30: Delay DC, DC Delay
  if shape_id == "delay_dc" then return piecewise(t, DELAY_DC) end
  if shape_id == "dc_delay" then return piecewise(t, DC_DELAY) end

  -- 31-33: Curve 2X, 2X B, 2X C
  if shape_id == "curve_2x" then return piecewise(t, CURVE_2X) end
  if shape_id == "curve_2x_b" then return piecewise(t, CURVE_2X_B) end
  if shape_id == "curve_2x_c" then return piecewise(t, CURVE_2X_C) end

  -- 34-36: Zig Zag (linear ramp + triangle oscillation). "Width" = amplitude of the zig-zag.
  -- Zig Zag 1: high CV shifts at start, thinner over time (amplitude envelope decreases).
  if shape_id == "zig_zag_1" then
    local ramp = t
    local env = 1 - t
    local tri = 2 * math.abs(2 * ((t * 18) % 1) - 1) - 1
    return math.max(0, math.min(1, ramp + 0.1 * env * tri))
  end
  -- Zig Zag 2: constant width (constant amplitude).
  if shape_id == "zig_zag_2" then
    local ramp = t
    local tri = 2 * math.abs(2 * ((t * 18) % 1) - 1) - 1
    return math.max(0, math.min(1, ramp + 0.06 * tri))
  end
  -- Zig Zag 3: big at start, small about midway, big again at end (amplitude dips in middle).
  if shape_id == "zig_zag_3" then
    local ramp = t
    local env = 4 * (t - 0.5) * (t - 0.5)
    local tri = 2 * math.abs(2 * ((t * 18) % 1) - 1) - 1
    return math.max(0, math.min(1, ramp + 0.1 * env * tri))
  end

  -- 37-44: Chaos (linear + deterministic noise)
  local chaos_amt = nil
  if shape_id == "chaos_03" then chaos_amt = 0.03
  elseif shape_id == "chaos_06" then chaos_amt = 0.06
  elseif shape_id == "chaos_12" then chaos_amt = 0.12
  elseif shape_id == "chaos_16" then chaos_amt = 0.16
  elseif shape_id == "chaos_25" then chaos_amt = 0.25
  elseif shape_id == "chaos_33" then chaos_amt = 0.33
  elseif shape_id == "chaos_37" then chaos_amt = 0.37
  elseif shape_id == "chaos_50" then chaos_amt = 0.5
  end
  if chaos_amt then
    local y = t + chaos_amt * noise(t)
    return math.max(0, math.min(1, y))
  end

  return t
end

-- All shape ids (mirrors Segment.SHAPES) for run_assertions without requiring Segment.
local ALL_SHAPE_IDS = {
  "linear",
  "exponential_1", "exponential_2", "exponential_3", "exponential_4", "exponential_5", "exponential_6", "exponential_7",
  "circle_1_4", "circle_1_6", "circle_1_8", "circle_1_16",
  "squeeze", "fast_line_1", "fast_line_2", "fast_line_3", "medium_line_1", "medium_line_2", "slow_ramp_1", "slow_ramp_2",
  "bloom", "bloom_2",
  "circle_1_16_reverse", "circle_1_8_reverse", "circle_1_6_reverse", "circle_1_4_reverse",
  "slow_curve_1", "slow_curve_2", "delay_dc", "dc_delay",
  "curve_2x", "curve_2x_b", "curve_2x_c",
  "zig_zag_1", "zig_zag_2", "zig_zag_3",
  "chaos_03", "chaos_06", "chaos_12", "chaos_16", "chaos_25", "chaos_33", "chaos_37", "chaos_50",
}

--- Optional self-check: assert f(0)=0, f(1)=1 for all shapes; linear and exp/circle behavior.
--- Call from REPL: Shapes = include("lib/shapes"); Shapes.run_assertions()
function M.run_assertions()
  for _, id in ipairs(ALL_SHAPE_IDS) do
    assert(M.shape_value(id, 0) == 0, "shape " .. tostring(id) .. " f(0) ~= 0")
    assert(M.shape_value(id, 1) == 1, "shape " .. tostring(id) .. " f(1) ~= 1")
  end
  assert(M.shape_value("linear", 0.5) == 0.5, "linear(0.5) ~= 0.5")
  assert(M.shape_value("exponential_1", 0.5) < 0.5, "exponential_1 concave-up")
  assert(M.shape_value("circle_1_4", 0.5) > 0.5, "circle_1_4 convex")
  return true
end

return M
