--[[
  Settings render: snapshot parent geometry + store into SettingsPanel props.
  Lifecycle (host / subscribe / mount) lives in lib/bind at the wiring site.
]]

local settings = require("settings")
local settings_panel = require("settings/SettingsPanel")
local SettingsPanel = settings_panel.SettingsPanel

local view = {}

--- Build props from the current store and parent geometry.
---@param parent ui.Component
---@param store StateStore
---@return SettingsPanelProps
local function buildProps(parent, store)
  return {
    hideChatheads = store:get(settings.HIDE_CHATHEADS) == true,
    width = parent.width,
    height = parent.height,
    set = function(key, value)
      store:set(key, value)
    end,
  }
end

--- Render the settings element tree for `parent` + `store`.
---@param parent ui.Component
---@param store StateStore
---@return Element
function view.render(parent, store)
  return SettingsPanel(buildProps(parent, store))
end

return view
