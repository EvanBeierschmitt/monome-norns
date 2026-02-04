-- lib/sequencer.lua
-- Per-line sequence of up to 8 presets; play/stop/restart; Ping handling.

local M = {}

local MAX_SLOTS = 8

--- Create sequencer state for all lines (1..4).
--- @param line_count number 1..4
--- @return table sequences per line
function M.new(line_count)
  local seq = {}
  for line = 1, (line_count or 4) do
    seq[line] = {
      preset_ids = {},
      cursor = 1,
      running = false,
      playing_slot = 0,
    }
  end
  return seq
end

--- Max slots per line.
function M.max_slots()
  return MAX_SLOTS
end

--- Cursor 1 = before first preset, 2 = on preset 1, 3 = between 1-2, 4 = on preset 2, ...
--- So cursor 1..(2*N+1) for N presets. on_preset = (cursor % 2 == 0), preset_index = cursor // 2.
--- @param row table sequencer row
--- @return boolean on_preset
--- @return number preset_index 1-based or 0 for gap
function M.cursor_info(row)
  if not row then return false, 0 end
  local n = #(row.preset_ids or {})
  local c = math.max(1, math.min(row.cursor or 1, 2 * n + 1))
  local on_preset = (c % 2 == 0)
  local preset_index = on_preset and (c // 2) or 0
  return on_preset, preset_index
end

--- Get preset id at slot (1-based).
--- @param row table sequencer row
--- @param slot number 1..N
--- @return string|nil
function M.get_preset_id(row, slot)
  if not row or not row.preset_ids then return nil end
  return row.preset_ids[slot]
end

--- Insert preset at slot (1-based). Shifts existing; max MAX_SLOTS.
--- @param row table mutated
--- @param slot number 1..N+1
--- @param preset_id string
--- @return boolean ok
function M.insert_preset(row, slot, preset_id)
  if not row then return false end
  local ids = row.preset_ids or {}
  if #ids >= MAX_SLOTS then return false end
  table.insert(ids, slot, preset_id)
  row.preset_ids = ids
  return true
end

--- Delete preset at slot (1-based).
--- @param row table mutated
--- @param slot number
function M.delete_preset(row, slot)
  if not row or not row.preset_ids then return end
  table.remove(row.preset_ids, slot)
end

--- Overwrite preset at slot.
--- @param row table mutated
--- @param slot number
--- @param preset_id string
function M.set_preset(row, slot, preset_id)
  if not row or not row.preset_ids then return end
  row.preset_ids[slot] = preset_id
end

--- Ping actions.
M.PING_INCREMENT = "increment"
M.PING_DECREMENT = "decrement"
M.PING_RESET = "reset"

return M
