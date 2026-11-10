--[[
  Colour-tag / subject-text helpers for NPC Smartphone.
]]

local text = {}

function text.stripColours(value)
  if value == nil then
    return ""
  end
  return (string.gsub(value, "<[^>]+>", ""))
end

function text.lowerClean(value)
  return string.lower(text.stripColours(value))
end

function text.isNpcContactSubject(value)
  return string.find(text.lowerClean(value), "npc contact", 1, true) ~= nil
end

return text
