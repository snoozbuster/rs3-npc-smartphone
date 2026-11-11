--[[
  Colour-tag / string helpers (no domain knowledge).
]]

local text = {}

---@param value string|nil
---@return string
function text.stripColours(value)
  if value == nil then
    return ""
  end
  return (string.gsub(value, "<[^>]+>", ""))
end

---@param value string|nil
---@return string
function text.lowerClean(value)
  return string.lower(text.stripColours(value))
end

return text
