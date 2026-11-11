--[[
  Settings panel as a pure function component: props → element tree.
]]

local element = require("lib/element")
local settings = require("settings")

---@class SettingsPanelProps
---@field hideChatheads boolean
---@field set fun(key: StateKey, value: boolean)
---@field width number
---@field height number

---@param props SettingsPanelProps
---@return Element
local function SettingsPanel(props)
  return element.h("box", { width = props.width, height = props.height }, {
    element.h("title", { text = "NPC Smartphone" }),
    element.h("checkbox_group", {
      choices = {
        {
          text = "Hide chatheads",
          value = settings.HIDE_CHATHEADS,
          selected = props.hideChatheads == true,
        },
      },
      onChange = function(value, selected)
        props.set(value, selected and true or false)
      end,
    }),
  })
end

return SettingsPanel
