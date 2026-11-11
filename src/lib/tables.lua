--[[
  Small table helpers (no domain knowledge).
]]

local tables = {}

--- Shallow copy of `source`. Non-tables yield `{}`.
---@generic T: table
---@param source T|nil
---@return T
function tables.clone(source)
  local copy = {}
  if type(source) ~= "table" then
    return copy
  end
  for key, value in pairs(source) do
    copy[key] = value
  end
  return copy
end

--- Remove the first array entry equal to `value` (`==`).
---@param list table
---@param value any
---@return boolean true if an entry was removed
function tables.removeValue(list, value)
  for i = 1, #list do
    if list[i] == value then
      table.remove(list, i)
      return true
    end
  end
  return false
end

return tables
