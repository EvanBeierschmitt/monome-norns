-- lib/conditionals.lua
-- Conditional jump evaluation. Pure: inputs table, no norns/Crow calls.

local M = {}

local COMPARISONS = { ">", ">=", "<", "<=", "=", "<>", "><" }
local INPUT_SOURCES = { "cv1", "cv2", "line1", "line2", "line3", "line4" }

--- All comparison operators.
--- @return table
function M.comparisons()
  return COMPARISONS
end

--- All input source names.
--- @return table
function M.input_sources()
  return INPUT_SOURCES
end

--- Evaluate one condition against inputs.
--- @param condition table { input = "cv1"|"cv2"|"line1".."line4", comparison = ">"|">="|"<"|"<="|"="|"<>"|"><", value = number }
--- @param inputs table { cv1 = number, cv2 = number, line1 = number, line2 = number, line3 = number, line4 = number }
--- @return boolean result
function M.evaluate(condition, inputs)
  if not condition or not inputs then return false end
  local v = inputs[condition.input]
  if v == nil then return false end
  local val = condition.value or 0
  local cmp = condition.comparison or "="
  if cmp == ">" then return v > val end
  if cmp == ">=" then return v >= val end
  if cmp == "<" then return v < val end
  if cmp == "<=" then return v <= val end
  if cmp == "=" then return math.abs(v - val) < 0.001 end
  if cmp == "<>" then
    local lo, hi = condition.value_lo or val, condition.value_hi or val
    if lo > hi then lo, hi = hi, lo end
    return v >= lo and v <= hi
  end
  if cmp == "><" then
    local lo, hi = condition.value_lo or val, condition.value_hi or val
    if lo > hi then lo, hi = hi, lo end
    return v < lo or v > hi
  end
  return false
end

return M
