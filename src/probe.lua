--[[
  Diagnostic probe: MiniMenu spell/contact logging, spell id persistence, F9 dump.
  Contact UI scrape/apply stays in the picker; inject via probe.new({ picker = … }).
]]

local text = require("lib/text")

local stripColours = text.stripColours
local lowerClean = text.lowerClean

local probe = {}

---@param value string|nil
---@return boolean
local function isNpcContactSubject(value)
  return string.find(lowerClean(value), "npc contact", 1, true) ~= nil
end

local DEFAULT_SPELL_IFACE = 1886
local DEFAULT_SPELL_STATIC = 1
local DEFAULT_SPELL_CAT = 0
local DEFAULT_SPELL_DYN = 108

--- Persistence surface probe uses (PersistentDB or a test fake).
--- Each `fun` is parenthesized so LuaLS does not treat `, SetInt` as a second return.
---@alias ProbeDb { GetInt: (fun(self: any, key: string): number?), SetInt: (fun(self: any, key: string, value: number)) }

---@alias ProbePicker { isOpen: (fun(): boolean), refreshContacts: (fun()), logContactList: (fun()), applyContactUiExperiment: (fun()), getContactLabel: (fun(dyn: number): string?), getContactLabelComponent: (fun(dyn: number): ui.Component?) }

---@alias ProbeOptions { log: Logger, db: ProbeDb, picker: ProbePicker, contactInterfaceId: number, contactButtonStatic: number, contactLabelStatic: number, enabled: boolean?, dumpKey: any? }

---@alias ProbeSpellIds { interfaceId: number, staticId: number, categoryId: number, dynamicId: number }

---@class Probe
---@field enabled boolean
---@field onMiniMenuReady fun(event: any)
---@field onMiniMenuSelected fun(event: any)
---@field onKeyDown fun(event: any)
---@field spellIds fun(): ProbeSpellIds

---@param component ui.Component|nil
---@param key string
---@return any
local function safeProp(component, key)
  if component == nil then
    return nil
  end
  local ok, value = pcall(function()
    return component[key]
  end)
  if ok then
    return value
  end
  return nil
end

---@param component ui.Component|nil
---@return string
local function describeComponent(component)
  if component == nil then
    return "nil"
  end
  return string.format(
    "iface=%s static=%s cat=%s dyn=%s type=%s",
    tostring(component.interfaceID),
    tostring(component.staticID),
    tostring(component.categoryID),
    tostring(component.dynamicID),
    tostring(component.type)
  )
end

--- Create the diagnostic probe.
---@param opts ProbeOptions
---@return Probe
function probe.new(opts)
  local logf = opts.log.f
  local db = opts.db
  local picker = opts.picker
  local contactInterfaceId = opts.contactInterfaceId
  local contactButtonStatic = opts.contactButtonStatic
  local contactLabelStatic = opts.contactLabelStatic
  local enabled = opts.enabled
  if enabled == nil then
    enabled = true
  end
  local dumpKey = opts.dumpKey
  if dumpKey == nil then
    dumpKey = GameKey.F9
  end
  local actionCast = MiniMenuActionType.IF_BUTTONX1
  local actionRedial = MiniMenuActionType.IF_BUTTONX2

  local spellInterfaceId = db:GetInt("spellInterfaceId") or DEFAULT_SPELL_IFACE
  local spellStaticId = db:GetInt("spellStaticId") or DEFAULT_SPELL_STATIC
  local spellCategoryId = db:GetInt("spellCategoryId") or DEFAULT_SPELL_CAT
  local spellDynamicId = db:GetInt("spellDynamicId") or DEFAULT_SPELL_DYN

  local lastMiniMenuLogKey = nil

  ---@param component ui.Component|nil
  local function rememberSpellComponent(component)
    if component == nil then
      return
    end
    spellInterfaceId = component.interfaceID
    spellStaticId = component.staticID
    spellCategoryId = component.categoryID
    spellDynamicId = component.dynamicID
    db:SetInt("spellInterfaceId", spellInterfaceId)
    db:SetInt("spellStaticId", spellStaticId)
    db:SetInt("spellCategoryId", spellCategoryId)
    db:SetInt("spellDynamicId", spellDynamicId)
  end

  ---@param component ui.Component|nil
  ---@param tag string
  ---@return string
  local function describeGeom(component, tag)
    if component == nil then
      return tostring(tag) .. "=nil"
    end
    return string.format(
      "%s static=%s type=%s size=%sx%s pos=%s,%s scrollable=%s scroll=%sx%s",
      tostring(tag),
      tostring(safeProp(component, "staticID")),
      tostring(safeProp(component, "type")),
      tostring(safeProp(component, "width")),
      tostring(safeProp(component, "height")),
      tostring(safeProp(component, "x")),
      tostring(safeProp(component, "y")),
      tostring(safeProp(component, "scrollable")),
      tostring(safeProp(component, "scrollWidth")),
      tostring(safeProp(component, "scrollHeight"))
    )
  end

  ---@param component ui.Component|nil
  ---@return boolean
  local function isContactPickerComponent(component)
    if component == nil then
      return false
    end
    return safeProp(component, "interfaceID") == contactInterfaceId
  end

  ---@param parent ui.ComponentCollection
  ---@param staticId number
  local function dumpDynamicChildren(parent, staticId)
    local ok, err = pcall(function()
      parent:IterateDynamicComponents(function(child, visible)
        logf(
          "  child static=%s dyn=%s type=%s size=%sx%s pos=%s,%s visible=%s",
          tostring(staticId),
          tostring(safeProp(child, "dynamicID")),
          tostring(safeProp(child, "type")),
          tostring(safeProp(child, "width")),
          tostring(safeProp(child, "height")),
          tostring(safeProp(child, "x")),
          tostring(safeProp(child, "y")),
          tostring(visible)
        )
        return false
      end)
    end)
    if not ok then
      logf("  child iterate static=%s failed: %s", tostring(staticId), tostring(err))
    end
  end

  local function dumpContactScaffold()
    logf("scaffold dump iface=%s:", tostring(contactInterfaceId))
    for staticId = 0, 9 do
      local ok, component = pcall(function()
        return ui.Interfaces:GetComponent(contactInterfaceId, staticId)
      end)
      if ok and component ~= nil then
        ---@cast component ui.ComponentCollection
        logf("  %s", describeGeom(component, "s" .. tostring(staticId)))
        local sb = safeProp(component, "scrollbar")
        logf("  s%s.scrollbar=%s", tostring(staticId), tostring(sb ~= nil))
        if staticId ~= contactButtonStatic and staticId ~= contactLabelStatic then
          dumpDynamicChildren(component, staticId)
        end
      end
    end

    local sample = picker.getContactLabelComponent(0)
    local node = sample
    local depth = 0
    while node ~= nil and depth < 8 do
      if not isContactPickerComponent(node) then
        logf("  labelParent[%d] left iface=%s", depth, tostring(safeProp(node, "interfaceID")))
        break
      end
      logf("  %s", describeGeom(node, "labelParent[" .. tostring(depth) .. "]"))
      node = safeProp(node, "parent")
      depth = depth + 1
    end
  end

  local instance = {
    enabled = enabled,
  }

  ---@return ProbeSpellIds
  function instance.spellIds()
    return {
      interfaceId = spellInterfaceId,
      staticId = spellStaticId,
      categoryId = spellCategoryId,
      dynamicId = spellDynamicId,
    }
  end

  ---@param event any
  function instance.onMiniMenuReady(event)
    local menu = event.miniMenu
    if menu == nil or menu.entries == nil then
      return
    end

    for _, entry in ipairs(menu.entries) do
      local component = entry.componentData and entry.componentData.component or nil
      local subject = entry.subjectText or ""
      local verb = entry.verbText or ""

      if isNpcContactSubject(subject) or isNpcContactSubject(entry.fullText) then
        local logKey = "spell|" .. verb .. "|" .. tostring(entry.actionType)
        if logKey ~= lastMiniMenuLogKey then
          lastMiniMenuLogKey = logKey
          logf(
            "minimenu spell: verb=%q subject=%q type=%s {%s}",
            verb,
            stripColours(subject),
            tostring(entry.actionType),
            describeComponent(component)
          )
        end
        if component ~= nil and (entry.actionType == actionCast or entry.actionType == actionRedial) then
          rememberSpellComponent(component)
        end
      elseif component ~= nil
          and component.interfaceID == contactInterfaceId
          and component.staticID == contactButtonStatic then
        local dyn = component.dynamicID
        local name = picker.getContactLabel(dyn) or "?"
        local logKey = "contact|" .. tostring(dyn)
        if logKey ~= lastMiniMenuLogKey then
          lastMiniMenuLogKey = logKey
          logf("minimenu contact: dyn=%s name=%s verb=%q", tostring(dyn), name, verb)
        end
      end
    end
  end

  ---@param event any
  function instance.onMiniMenuSelected(event)
    local entry = event.entry
    if entry == nil then
      return
    end

    local component = entry.componentData and entry.componentData.component or nil

    if component ~= nil
        and component.interfaceID == contactInterfaceId
        and component.staticID == contactButtonStatic then
      local dyn = component.dynamicID
      local name = picker.getContactLabel(dyn) or "?"
      logf("selected contact: dyn=%s name=%s", tostring(dyn), name)
      return
    end

    if not isNpcContactSubject(entry.subjectText) and not isNpcContactSubject(entry.fullText) then
      return
    end

    logf(
      "selected spell: verb=%q type=%s {%s}",
      entry.verbText or "",
      tostring(entry.actionType),
      describeComponent(component)
    )
    if component ~= nil then
      rememberSpellComponent(component)
    end
  end

  ---@param event any
  function instance.onKeyDown(event)
    if not enabled then
      return
    end
    if event.gameKey ~= dumpKey then
      return
    end

    local open = picker.isOpen()
    logf(
      "F9: spell=%s/%s/%s/%s contact=%s open=%s",
      tostring(spellInterfaceId),
      tostring(spellStaticId),
      tostring(spellCategoryId),
      tostring(spellDynamicId),
      tostring(contactInterfaceId),
      tostring(open)
    )

    if not open then
      logf("F9: picker not open — cast NPC Contact first")
      return
    end

    picker.refreshContacts()
    picker.logContactList()
    dumpContactScaffold()
    picker.applyContactUiExperiment()
  end

  return instance
end

return probe
