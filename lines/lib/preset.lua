-- lib/preset.lua
-- Preset = up to 8 segments; validation. No norns/Crow APIs.

local Segment = include("lib/segment")

local M = {}

local MAX_SEGMENTS = 8

--- Create a new empty preset with default segments.
--- @param id string preset id
--- @param name string display name
--- @return table preset
function M.new(id, name)
  local p = {
    id = id or "preset_1",
    name = name or "Preset 1",
    segments = {},
  }
  for i = 1, MAX_SEGMENTS do
    p.segments[i] = Segment.default()
  end
  return p
end

--- Maximum number of segments per preset.
--- @return number
function M.max_segments()
  return MAX_SEGMENTS
end

--- Validate a preset (all segments valid).
--- @param preset table preset
--- @param voltage_lo number
--- @param voltage_hi number
--- @return boolean ok
--- @return string|nil err
function M.validate(preset, voltage_lo, voltage_hi)
  if type(preset) ~= "table" then
    return false, "preset must be a table"
  end
  if type(preset.id) ~= "string" or preset.id == "" then
    return false, "preset.id must be non-empty string"
  end
  if type(preset.name) ~= "string" then
    return false, "preset.name must be a string"
  end
  if type(preset.segments) ~= "table" then
    return false, "preset.segments must be a table"
  end
  for i = 1, MAX_SEGMENTS do
    local seg = preset.segments[i]
    if seg == nil then
      return false, "preset.segments[" .. i .. "] missing"
    end
    local ok_seg, err = Segment.validate(seg, voltage_lo, voltage_hi)
    if not ok_seg then
      return false, "segment " .. i .. ": " .. tostring(err)
    end
  end
  return true, nil
end

return M
