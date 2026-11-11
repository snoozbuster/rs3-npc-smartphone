--[[
  MiniMenu subject matching for the NPC Contact spell.
  Domain helper (not lib/); call sites are the probe MiniMenu handlers in main.
]]

local text = require("lib/text")

local npc_contact_subject = {}

---@param value string|nil
---@return boolean
function npc_contact_subject.isNpcContactSubject(value)
  return string.find(text.lowerClean(value), "npc contact", 1, true) ~= nil
end

return npc_contact_subject
