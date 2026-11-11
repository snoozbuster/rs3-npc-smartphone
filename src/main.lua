--[[
  NPC Smartphone — RS3 plugin

  Improves the NPC Contact spell selection UI.

  Discovered layout (beta capture):
    Spellbook Cast button:  iface=1886 static=1 cat=0 dyn=108
    Contact picker:         iface=88
      static 0..8           type=20 layout layers
      static 9              Close (ops Speak-to N/A; ops={1:Close})
      static=1 cat=0 dyn=N  Speak-to button for contact slot N (type=4)
      static=2 cat=0 dyn=N  name label for contact slot N (type=2 text)
      static=8 cat=0 dyn=14 title "Choose a character"
]]

local log = require("lib/log")
local bind = require("lib/bind")
local prettyui_host = require("lib/prettyui_host")
local state = require("state")
local settings = require("settings")
local settingsView = require("settings/view")
local contactPicker = require("contact/picker")
local probe = require("probe")

local logger = log.new("npc-smartphone")
local logf = logger.f

local REFS = {
  logic = "npcSmartphone.logic",
  miniMenuReady = "npcSmartphone.miniMenuReady",
  miniMenuSelected = "npcSmartphone.miniMenuSelected",
  keyDown = "npcSmartphone.keyDown",
  settingsLayer = "npcSmartphone.settingsLayer",
  contentLayer = "npcSmartphone.contentLayer",
}

local store = state.new(PersistentDB)
local settingsUi = bind.new({
  host = prettyui_host,
  render = function(parent)
    return settingsView.render(parent, store)
  end,
  subscribe = function(fn)
    return store:subscribe(fn)
  end,
})

local picker = contactPicker.new({
  store = store,
  log = logger,
  db = PersistentDB,
})

local contactProbe = probe.new({
  log = logger,
  db = PersistentDB,
  picker = picker,
  contactInterfaceId = contactPicker.CONTACT_IFACE,
  contactButtonStatic = contactPicker.CONTACT_BUTTON_STATIC,
  contactLabelStatic = contactPicker.CONTACT_LABEL_STATIC,
})

---@type BoundViewInstance|nil
local settingsHubView = nil
---@type BoundViewInstance|nil
local settingsRibbonView = nil

local function onSettingsLayerReady(event)
  local parent = event.component
  if parent == nil then
    logf("settings layer: missing component")
    return
  end

  if settingsHubView ~= nil then
    settingsHubView.update(parent)
  else
    settingsHubView = settingsUi.mount(parent)
  end
  logf("settings layer mounted (plugin hub)")
end

local function onContentLayerReady(event)
  local parent = event.component
  if parent == nil then
    logf("content layer: missing component")
    return
  end

  if settingsRibbonView ~= nil then
    settingsRibbonView.update(parent)
  else
    settingsRibbonView = settingsUi.mount(parent)
  end
  logf("content layer mounted (in-game plugins)")
end

Event.Logic.Subscribe(REFS.logic, picker.onLogic)
Event.SettingsLayerReady.Subscribe(REFS.settingsLayer, onSettingsLayerReady)
Event.ContentLayerReady.Subscribe(REFS.contentLayer, onContentLayerReady)
if contactProbe.enabled then
  Event.MiniMenuReady.Subscribe(REFS.miniMenuReady, contactProbe.onMiniMenuReady)
  Event.MiniMenuEntrySelected.Subscribe(REFS.miniMenuSelected, contactProbe.onMiniMenuSelected)
  Event.KeyDown.Subscribe(REFS.keyDown, contactProbe.onKeyDown)
end

function PluginShutdown()
  Event.Logic.Unsubscribe(REFS.logic)
  Event.SettingsLayerReady.Unsubscribe(REFS.settingsLayer)
  Event.ContentLayerReady.Unsubscribe(REFS.contentLayer)
  if contactProbe.enabled then
    Event.MiniMenuReady.Unsubscribe(REFS.miniMenuReady)
    Event.MiniMenuEntrySelected.Unsubscribe(REFS.miniMenuSelected)
    Event.KeyDown.Unsubscribe(REFS.keyDown)
  end
  picker.destroy()
  if settingsHubView ~= nil then
    settingsHubView.unmount()
    settingsHubView = nil
  end
  if settingsRibbonView ~= nil then
    settingsRibbonView.unmount()
    settingsRibbonView = nil
  end
  logf("shutdown")
end

local spellIds = contactProbe.spellIds()
logf(
  "loaded v0.0.22 layout=88/{speak:static1,name:static2} hideChatheads=%s spell=%s/%s/%s/%s",
  tostring(store:get(settings.HIDE_CHATHEADS)),
  tostring(spellIds.interfaceId),
  tostring(spellIds.staticId),
  tostring(spellIds.categoryId),
  tostring(spellIds.dynamicId)
)
