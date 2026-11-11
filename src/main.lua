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

local text = require("lib/text")
local log = require("lib/log")
local bind = require("lib/bind")
local prettyui_host = require("lib/prettyui_host")
local state = require("state")
local settings = require("settings")
local settingsView = require("settings/view")
local probe = require("probe")

local stripColours = text.stripColours
local lowerClean = text.lowerClean
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

-- User setting: hide Speak-to MODEL chatheads and reflow labels into a compact grid.
-- Off = leave the vanilla chathead picker untouched.
-- Exposed via SettingsLayer (Plugin Hub Manage) and ContentLayer (in-game Plugins ribbon).
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

-- Compact-layout feature flags (only applied when hideChatheads is on).
-- MODELs are the Speak-to click targets: keep them unhidden, clear their visuals,
-- and move/resize them onto the packed labels so names stay clickable.
-- Scrollbar gutter is static=3 (from scaffold). Do not heuristic-hide static=8 borders.
local COLLAPSE_LABELS = true
local CLAMP_SCROLL_SIZE = true
local HIDE_SCROLLBAR = true
local FIT_WINDOW_TO_CONTENT = true
local COMPACT_COLS = 5
local COMPACT_ROW_HEIGHT = 22      -- label cells are tall (~100); use text-sized pitch instead
local INTERFACE_BOTTOM_PAD = 48    -- keep descenders / last row inside the frame
local CONTACT_SCROLLBAR_STATIC = 3 -- 16x284 gutter at x≈475
local CONTACT_VIEWPORT_STATIC = 0  -- 471x284 scroll host
-- Frame/chrome layers to shorten when fitting the window (iface 88 scaffold).
-- Snapshot heights before any SetSize — resizing a parent can auto-resize children,
-- and applying delta again would double-shrink (cut off the list).
local CONTACT_FRAME_STATICS = { 0, 3, 4, 5, 6, 7, 8 }

local CONTACT_IFACE = 88
local CONTACT_BUTTON_STATIC = 1 -- Speak-to / chathead MODELs
local CONTACT_LABEL_STATIC = 2  -- name text
local CONTACT_CAT = 0
local CONTACT_SLOT_MAX = 64

PersistentDB:SetInt("contactInterfaceId", CONTACT_IFACE)

local contactOpen = false
local contacts = {} -- array of { dyn, name, hasSpeakTo }
local refreshPending = false
local refreshWaitTicks = 0
local REFRESH_MAX_WAIT_TICKS = 60 -- ~ interface populate timeout
local uiExperimentApplied = false
local lastCompact = nil           -- { baseY, rowH, rows, contentBottom, sampleLabel }
local layoutBackup = nil          -- vanilla geometry captured before compacting
---@type BoundViewInstance|nil
local settingsHubView = nil
---@type BoundViewInstance|nil
local settingsRibbonView = nil
local unsubscribeHideChatheads = nil
---@type Probe|nil
local contactProbe = nil

local function safeProp(component, key)
  local ok, value = pcall(function()
    return component[key]
  end)
  if ok then
    return value
  end
  return nil
end

local function componentText(component)
  local content = safeProp(component, "content")
  if content ~= nil and tostring(content) ~= "" then
    return stripColours(tostring(content))
  end
  local label = safeProp(component, "label")
  if label ~= nil and tostring(label) ~= "" then
    return stripColours(tostring(label))
  end
  return nil
end

local function getContactLabelComponent(dyn)
  local ok, component = pcall(function()
    return ui.Interfaces:GetComponent(CONTACT_IFACE, CONTACT_LABEL_STATIC, CONTACT_CAT, dyn)
  end)
  if not ok then
    return nil
  end
  return component
end

local function getContactLabel(dyn)
  local component = getContactLabelComponent(dyn)
  if component == nil then
    return nil
  end
  return componentText(component)
end

local function getContactButton(dyn)
  local ok, component = pcall(function()
    return ui.Interfaces:GetComponent(CONTACT_IFACE, CONTACT_BUTTON_STATIC, CONTACT_CAT, dyn)
  end)
  if not ok then
    return nil
  end
  return component
end

local function buttonHasSpeakTo(component)
  if component == nil then
    return false
  end
  local opConfig = safeProp(component, "opConfig")
  if opConfig == nil then
    return false
  end
  local names = safeProp(opConfig, "opNames")
  if names == nil then
    return false
  end
  for _, name in ipairs(names) do
    if lowerClean(name) == "speak-to" then
      return true
    end
  end
  return false
end

--- Read all contact slots from the known static=1 / static=2 layout.
--- Kept small: one GetComponent pair per dyn, well under the 1000ms cap.
local function refreshContacts()
  local iface = ui.Interfaces:GetInterface(CONTACT_IFACE)
  if iface == nil then
    contacts = {}
    return contacts
  end

  local nextContacts = {}
  local misses = 0
  for dyn = 0, CONTACT_SLOT_MAX do
    local name = getContactLabel(dyn)
    local button = getContactButton(dyn)
    if name ~= nil or button ~= nil then
      misses = 0
      nextContacts[#nextContacts + 1] = {
        dyn = dyn,
        name = name,
        hasSpeakTo = buttonHasSpeakTo(button),
      }
    else
      misses = misses + 1
      if #nextContacts > 0 and misses >= 3 then
        break
      end
    end
  end

  contacts = nextContacts
  PersistentDB:SetStructuredData("contactSlots", contacts)
  return contacts
end

local function logContactList()
  logf("contacts (%d):", #contacts)
  for _, slot in ipairs(contacts) do
    logf(
      "  dyn=%02d speak=%s name=%s",
      slot.dyn,
      tostring(slot.hasSpeakTo),
      tostring(slot.name)
    )
  end
end

local function getStaticComponent(staticId)
  local ok, component = pcall(function()
    return ui.Interfaces:GetComponent(CONTACT_IFACE, staticId)
  end)
  if not ok then
    return nil
  end
  return component
end

local function setComponentHidden(component, hidden)
  if component == nil then
    return false
  end
  local ok = pcall(function()
    component.hidden = hidden
  end)
  return ok
end

--- Clear the MODEL visual without hiding the component (keeps Speak-to clickable).
local function clearSpeakToModelVisual(button)
  if button == nil then
    return false
  end
  local ok = pcall(function()
    button:SetModel(ui.ModelType.NONE, 0)
  end)
  if not ok then
    ok = pcall(function()
      button.alpha = 0
    end)
  end
  return ok
end

local function restoreSpeakToModelVisual(button, entry)
  if button == nil or entry == nil then
    return false
  end
  local ok = pcall(function()
    if entry.modelType ~= nil and entry.modelID1 ~= nil then
      if entry.modelID2 ~= nil then
        button:SetModel(entry.modelType, entry.modelID1, entry.modelID2)
      else
        button:SetModel(entry.modelType, entry.modelID1)
      end
    end
    if entry.alpha ~= nil then
      button.alpha = entry.alpha
    end
  end)
  return ok
end

local function clearLayoutBackup()
  layoutBackup = nil
end

local function captureLayoutBackup()
  if layoutBackup ~= nil then
    return layoutBackup
  end

  local backup = {
    labels = {},
    buttons = {},
    sizes = {},
    scrolls = {},
  }

  for _, slot in ipairs(contacts) do
    local label = getContactLabelComponent(slot.dyn)
    if label ~= nil then
      local x = safeProp(label, "x")
      local y = safeProp(label, "y")
      local w = safeProp(label, "width")
      local h = safeProp(label, "height")
      if x ~= nil and y ~= nil then
        backup.labels[#backup.labels + 1] = {
          dyn = slot.dyn,
          x = x,
          y = y,
          w = w or 80,
          h = h or 16,
          clickthrough = safeProp(label, "clickthrough"),
        }
      end
    end

    local button = getContactButton(slot.dyn)
    if button ~= nil then
      local x = safeProp(button, "x")
      local y = safeProp(button, "y")
      local w = safeProp(button, "width")
      local h = safeProp(button, "height")
      if x ~= nil and y ~= nil then
        backup.buttons[#backup.buttons + 1] = {
          dyn = slot.dyn,
          x = x,
          y = y,
          w = w or 80,
          h = h or 80,
          modelType = safeProp(button, "modelType"),
          modelID1 = safeProp(button, "modelID1"),
          modelID2 = safeProp(button, "modelID2"),
          alpha = safeProp(button, "alpha"),
        }
      end
    end
  end

  for _, staticId in ipairs(CONTACT_FRAME_STATICS) do
    local component = getStaticComponent(staticId)
    if component ~= nil then
      local width = safeProp(component, "width")
      local height = safeProp(component, "height")
      if type(width) == "number" and type(height) == "number" then
        backup.sizes[staticId] = { width = width, height = height }
      end
      local scrollWidth = safeProp(component, "scrollWidth")
      local scrollHeight = safeProp(component, "scrollHeight")
      if type(scrollWidth) == "number" and type(scrollHeight) == "number" then
        backup.scrolls[staticId] = {
          width = scrollWidth,
          height = scrollHeight,
          x = safeProp(component, "scrollX") or 0,
          y = safeProp(component, "scrollY") or 0,
        }
      end
    end
  end

  for _, staticId in ipairs({ CONTACT_BUTTON_STATIC, CONTACT_LABEL_STATIC }) do
    if backup.sizes[staticId] == nil then
      local component = getStaticComponent(staticId)
      if component ~= nil then
        local width = safeProp(component, "width")
        local height = safeProp(component, "height")
        if type(width) == "number" and type(height) == "number" then
          backup.sizes[staticId] = { width = width, height = height }
        end
      end
    end
  end

  local sizeCount = 0
  for _ in pairs(backup.sizes) do
    sizeCount = sizeCount + 1
  end
  local scrollCount = 0
  for _ in pairs(backup.scrolls) do
    scrollCount = scrollCount + 1
  end
  layoutBackup = backup
  logf(
    "layout backup: labels=%d buttons=%d sizes=%d scrolls=%d",
    #backup.labels,
    #backup.buttons,
    sizeCount,
    scrollCount
  )
  return backup
end

local function restoreVanillaContactLayout()
  local backup = layoutBackup
  local restoredLabels = 0
  local restoredButtons = 0
  local restoredSizes = 0
  local restoredScrolls = 0

  if backup ~= nil then
    for _, entry in ipairs(backup.labels) do
      local label = getContactLabelComponent(entry.dyn)
      if label ~= nil then
        local ok = pcall(function()
          label:SetSize(entry.w, entry.h)
          label:SetPos(entry.x, entry.y)
          if entry.clickthrough ~= nil then
            label.clickthrough = entry.clickthrough
          end
        end)
        if ok then
          restoredLabels = restoredLabels + 1
        end
      end
    end

    for _, entry in ipairs(backup.buttons or {}) do
      local button = getContactButton(entry.dyn)
      if button ~= nil then
        local ok = pcall(function()
          button:SetSize(entry.w, entry.h)
          button:SetPos(entry.x, entry.y)
        end)
        if ok then
          restoreSpeakToModelVisual(button, entry)
          restoredButtons = restoredButtons + 1
        end
      end
    end

    for staticId, size in pairs(backup.sizes) do
      local component = getStaticComponent(staticId)
      if component ~= nil then
        local ok = pcall(function()
          component:SetSize(size.width, size.height)
        end)
        if ok then
          restoredSizes = restoredSizes + 1
        end
      end
    end

    for staticId, scroll in pairs(backup.scrolls) do
      local component = getStaticComponent(staticId)
      if component ~= nil then
        local ok = pcall(function()
          component:SetScrollSize(scroll.width, scroll.height)
          component:SetScrollPos(scroll.x, scroll.y)
        end)
        if ok then
          restoredScrolls = restoredScrolls + 1
        end
      end
    end
  end

  local gutter = getStaticComponent(CONTACT_SCROLLBAR_STATIC)
  setComponentHidden(gutter, false)
  if gutter ~= nil then
    pcall(function()
      gutter:IterateDynamicComponents(function(child, _visible)
        setComponentHidden(child, false)
        return false
      end)
    end)
  end

  -- Compact mode MoveToFront'd the Speak-to layer over labels; put names back on top.
  local labelLayer = getStaticComponent(CONTACT_LABEL_STATIC)
  if labelLayer ~= nil then
    pcall(function()
      labelLayer:MoveToFront()
    end)
  end
  if backup ~= nil then
    for _, entry in ipairs(backup.labels) do
      local label = getContactLabelComponent(entry.dyn)
      if label ~= nil then
        pcall(function()
          label:MoveToFront()
        end)
      end
    end
  end

  clearLayoutBackup()
  lastCompact = nil
  logf(
    "restored vanilla: labels=%d buttons=%d sizes=%d scrolls=%d",
    restoredLabels,
    restoredButtons,
    restoredSizes,
    restoredScrolls
  )
end

--- GetInterface(88) can be non-nil while the picker is not actually on screen.
--- Require real geometry + a contact slot before treating it as open.
local function isContactPickerVisiblyOpen()
  local iface = ui.Interfaces:GetInterface(CONTACT_IFACE)
  if iface == nil then
    return false
  end

  local ok, layer = pcall(function()
    return ui.Interfaces:GetComponent(CONTACT_IFACE, 0)
  end)
  if not ok or layer == nil then
    return false
  end

  local width = safeProp(layer, "width")
  local height = safeProp(layer, "height")
  if type(width) ~= "number" or type(height) ~= "number" or width < 50 or height < 50 then
    return false
  end

  if safeProp(layer, "visibleGlobal") == false then
    return false
  end

  -- At least one contact label/button must exist.
  if getContactLabel(0) == nil and getContactButton(0) == nil then
    return false
  end

  return true
end

--- Pack name labels into a denser grid using the original column X positions.
--- Speak-to MODELs are aligned onto these cells afterwards (see alignSpeakToHitboxesToLabels).
local function collapseContactLabels()
  lastCompact = nil
  if not COLLAPSE_LABELS or #contacts == 0 then
    return 0
  end

  local entries = {}
  for _, slot in ipairs(contacts) do
    local label = getContactLabelComponent(slot.dyn)
    if label ~= nil then
      local x = safeProp(label, "x")
      local y = safeProp(label, "y")
      local w = safeProp(label, "width")
      local h = safeProp(label, "height")
      if x ~= nil and y ~= nil then
        entries[#entries + 1] = {
          component = label,
          dyn = slot.dyn,
          x = x,
          y = y,
          w = w or 80,
          h = h or 16,
        }
      end
    end
  end

  if #entries == 0 then
    logf("collapse labels: no readable label geometry")
    return 0
  end

  -- First row supplies column X anchors and the top Y.
  -- Label components are ~chathead-tall; use a text-sized pitch instead of label.height.
  local colX = {}
  local baseY = entries[1].y
  local rowH = COMPACT_ROW_HEIGHT
  local colCount = math.min(COMPACT_COLS, #entries)
  for i = 1, colCount do
    colX[i] = entries[i].x
  end

  local rows = math.ceil(#entries / COMPACT_COLS)
  local contentBottom = baseY + (rows * rowH)

  if #entries > colCount then
    local oldPitch = entries[colCount + 1].y - entries[1].y
    logf(
      "collapse labels: oldRowPitch=%d newRowPitch=%d labelH=%d cols=%d rows=%d baseY=%d contentBottom=%d",
      oldPitch,
      rowH,
      entries[1].h,
      colCount,
      rows,
      baseY,
      contentBottom
    )
  end

  local moved = 0
  local failCount = 0
  for i, entry in ipairs(entries) do
    local col = ((i - 1) % COMPACT_COLS) + 1
    local row = math.floor((i - 1) / COMPACT_COLS)
    local x = colX[col] or entry.x
    local y = baseY + (row * rowH)
    local ok, err = pcall(function()
      -- Shrink the tall chathead-sized label cell so text packs tightly.
      entry.component:SetSize(entry.w, rowH)
      entry.component:SetPos(x, y)
      -- Let clicks reach the Speak-to MODEL that will overlay this cell.
      entry.component.clickthrough = true
    end)
    if ok then
      moved = moved + 1
    else
      failCount = failCount + 1
      if failCount <= 3 then
        logf("collapse label dyn=%s failed: %s", tostring(entry.dyn), tostring(err))
      end
    end
  end

  lastCompact = {
    baseY = baseY,
    rowH = rowH,
    rows = rows,
    contentBottom = contentBottom,
    sampleLabel = entries[1].component,
  }

  logf("collapse labels: moved=%d fail=%d", moved, failCount)
  return moved
end

--- Keep Speak-to MODELs unhidden (action stays bound), clear their chathead visuals,
--- and move/resize each onto its packed name label so clicking a name contacts the NPC.
local function alignSpeakToHitboxesToLabels()
  local buttonLayer = getStaticComponent(CONTACT_BUTTON_STATIC)
  if buttonLayer ~= nil then
    pcall(function()
      buttonLayer:MoveToFront()
    end)
  end

  local moved = 0
  local cleared = 0
  local failCount = 0

  for _, slot in ipairs(contacts) do
    local label = getContactLabelComponent(slot.dyn)
    local button = getContactButton(slot.dyn)
    if label == nil or button == nil then
      failCount = failCount + 1
    else
      local x = safeProp(label, "x")
      local y = safeProp(label, "y")
      local w = safeProp(label, "width")
      local h = safeProp(label, "height")
      if x == nil or y == nil then
        failCount = failCount + 1
      else
        setComponentHidden(button, false)
        if clearSpeakToModelVisual(button) then
          cleared = cleared + 1
        end
        local ok, err = pcall(function()
          button:SetSize(w or 80, h or COMPACT_ROW_HEIGHT)
          button:SetPos(x, y)
          button:MoveToFront()
        end)
        if ok then
          moved = moved + 1
        else
          failCount = failCount + 1
          if failCount <= 3 then
            logf("align speak-to dyn=%s failed: %s", tostring(slot.dyn), tostring(err))
          end
        end
      end
    end
  end

  logf(
    "align speak-to: moved=%d cleared=%d fail=%d",
    moved,
    cleared,
    failCount
  )
  return moved
end

--- Shrink contact content layers (static 1/2 are ~470x750) and clamp the viewport
--- scroll region (static 0) so compacted labels don't leave overflow.
local function clampContactScrollSize()
  if not CLAMP_SCROLL_SIZE or lastCompact == nil then
    return
  end

  local contentBottom = lastCompact.contentBottom + INTERFACE_BOTTOM_PAD
  local sizeTouched = 0
  local scrollTouched = 0

  -- Content hosts for models/labels: shorten them to the packed label grid.
  for _, staticId in ipairs({ CONTACT_BUTTON_STATIC, CONTACT_LABEL_STATIC }) do
    local okGet, component = pcall(function()
      return ui.Interfaces:GetComponent(CONTACT_IFACE, staticId)
    end)
    if okGet and component ~= nil then
      local width = safeProp(component, "width")
      local height = safeProp(component, "height")
      if type(width) == "number" and type(height) == "number"
          and height > contentBottom + 8 then
        local ok, err = pcall(function()
          component:SetSize(width, contentBottom)
        end)
        if ok then
          sizeTouched = sizeTouched + 1
          logf(
            "shrink content static=%d %dx%d -> %dx%d",
            staticId,
            width,
            height,
            width,
            contentBottom
          )
        else
          logf("shrink content static=%d failed: %s", staticId, tostring(err))
        end
      end
    end
  end

  -- Viewport host: only touch when scroll region actually overflows the view.
  local okView, viewport = pcall(function()
    return ui.Interfaces:GetComponent(CONTACT_IFACE, CONTACT_VIEWPORT_STATIC)
  end)
  if okView and viewport ~= nil then
    local width = safeProp(viewport, "width")
    local height = safeProp(viewport, "height")
    local scrollWidth = safeProp(viewport, "scrollWidth")
    local scrollHeight = safeProp(viewport, "scrollHeight")
    if type(height) == "number" and type(scrollHeight) == "number" and scrollHeight > height then
      local targetScrollH = contentBottom
      if contentBottom <= height then
        targetScrollH = height
      end
      local ok, err = pcall(function()
        viewport:SetScrollSize(scrollWidth or width or 0, targetScrollH)
        viewport:SetScrollPos(0, 0)
      end)
      if ok then
        scrollTouched = scrollTouched + 1
        logf(
          "clamp viewport scroll %s -> %d (viewH=%d contentBottom=%d)",
          tostring(scrollHeight),
          targetScrollH,
          height,
          contentBottom
        )
      else
        logf("clamp viewport scroll failed: %s", tostring(err))
      end
    end
  end

  logf(
    "clamp scroll: contentBottom=%d sizeSets=%d scrollSets=%d",
    contentBottom,
    sizeTouched,
    scrollTouched
  )
end

--- Shorten iface-88 frame/chrome layers by the same delta as the viewport shrink.
--- Keeps title chrome; only removes the empty chathead leftover height.
local function fitContactWindowToContent()
  if not FIT_WINDOW_TO_CONTENT or lastCompact == nil then
    return
  end

  local contentBottom = lastCompact.contentBottom + INTERFACE_BOTTOM_PAD
  local okView, viewport = pcall(function()
    return ui.Interfaces:GetComponent(CONTACT_IFACE, CONTACT_VIEWPORT_STATIC)
  end)
  if not okView or viewport == nil then
    logf("fit window: viewport missing")
    return
  end

  -- Read all heights first so a parent SetSize can't change child heights mid-loop.
  local snapshots = {}
  for _, staticId in ipairs(CONTACT_FRAME_STATICS) do
    local okGet, component = pcall(function()
      return ui.Interfaces:GetComponent(CONTACT_IFACE, staticId)
    end)
    if okGet and component ~= nil then
      local width = safeProp(component, "width")
      local height = safeProp(component, "height")
      if type(width) == "number" and type(height) == "number" then
        snapshots[staticId] = {
          component = component,
          width = width,
          height = height,
        }
      end
    end
  end

  local viewSnap = snapshots[CONTACT_VIEWPORT_STATIC]
  if viewSnap == nil then
    logf("fit window: viewport snapshot missing")
    return
  end

  local viewH = viewSnap.height
  if viewH <= contentBottom + 4 then
    logf("fit window: no shrink needed viewH=%d contentBottom=%d", viewH, contentBottom)
    return
  end

  local delta = viewH - contentBottom
  local resized = 0

  for _, staticId in ipairs(CONTACT_FRAME_STATICS) do
    local snap = snapshots[staticId]
    if snap ~= nil and snap.width <= 600 and snap.height > delta + 40 then
      local newH = snap.height - delta
      local ok, err = pcall(function()
        snap.component:SetSize(snap.width, newH)
      end)
      if ok then
        resized = resized + 1
        logf(
          "fit window static=%d %dx%d -> %dx%d",
          staticId,
          snap.width,
          snap.height,
          snap.width,
          newH
        )
      else
        logf("fit window static=%d failed: %s", staticId, tostring(err))
      end
    end
  end

  -- Keep scroll region matched and pinned to top so the list isn't clipped mid-grid.
  pcall(function()
    local scrollWidth = safeProp(viewport, "scrollWidth")
    viewport:SetScrollSize(scrollWidth or viewSnap.width, contentBottom)
    viewport:SetScrollPos(0, 0)
  end)

  logf("fit window: delta=%d contentBottom=%d resized=%d", delta, contentBottom, resized)
end

--- Hide the dedicated scrollbar gutter (static=3) and all of its sprite children.
--- Re-run while open: wheel interaction can resurrect scrollbar chrome.
local function hideContactScrollbarSprites()
  if not HIDE_SCROLLBAR then
    return 0
  end

  local hidden = 0
  local okGet, gutter = pcall(function()
    return ui.Interfaces:GetComponent(CONTACT_IFACE, CONTACT_SCROLLBAR_STATIC)
  end)
  if not okGet or gutter == nil then
    logf("hide scrollbar: static=%d missing", CONTACT_SCROLLBAR_STATIC)
    return 0
  end

  local okHideGutter, gutterErr = pcall(function()
    gutter.hidden = true
  end)
  if okHideGutter then
    hidden = hidden + 1
  else
    logf("hide scrollbar gutter failed: %s", tostring(gutterErr))
  end

  local okIter, iterErr = pcall(function()
    gutter:IterateDynamicComponents(function(child, _visible)
      local okHide, hideErr = pcall(function()
        child.hidden = true
      end)
      if okHide then
        hidden = hidden + 1
      elseif hideErr ~= nil then
        logf(
          "hide sb child dyn=%s failed: %s",
          tostring(safeProp(child, "dynamicID")),
          tostring(hideErr)
        )
      end
      return false
    end)
  end)
  if not okIter then
    logf("hide scrollbar iterate failed: %s", tostring(iterErr))
  end

  return hidden
end

local function pickerLooksReady()
  if #contacts == 0 then
    return false
  end
  -- Prefer waiting until layout has real geometry; fall back to names alone.
  local sample = getContactLabelComponent(contacts[1].dyn)
  if sample == nil then
    return false
  end
  local w = safeProp(sample, "width")
  local h = safeProp(sample, "height")
  if type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then
    return true
  end
  -- Names exist but size still 0 — treat as ready after a few waits so we don't stall forever.
  return refreshWaitTicks >= 5 and contacts[1].name ~= nil
end

local function applyContactUiExperiment()
  if not store:get(settings.HIDE_CHATHEADS) then
    logf("hide chatheads off — leaving vanilla picker")
    uiExperimentApplied = true
    return
  end

  captureLayoutBackup()
  collapseContactLabels()
  alignSpeakToHitboxesToLabels()
  clampContactScrollSize()
  fitContactWindowToContent()
  local sbHidden = hideContactScrollbarSprites()
  logf("hide scrollbar: hidden=%d (static=%d gutter + children)", sbHidden, CONTACT_SCROLLBAR_STATIC)
  uiExperimentApplied = true
end

--- Apply or restore compact contact layout when hideChatheads changes while open.
---@param hideChatheads boolean
local function onHideChatheadsChanged(hideChatheads)
  logf("setting hideChatheads=%s", tostring(hideChatheads))

  if not contactOpen then
    return
  end

  if hideChatheads then
    uiExperimentApplied = false
    lastCompact = nil
    clearLayoutBackup()
    refreshPending = true
    refreshWaitTicks = 0
    refreshContacts()
    if pickerLooksReady() then
      refreshPending = false
      applyContactUiExperiment()
    end
  else
    refreshPending = false
    restoreVanillaContactLayout()
    uiExperimentApplied = true
  end
end

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

local function onContactOpened()
  logf(
    "contact iface %s OPEN (hideChatheads=%s)",
    tostring(CONTACT_IFACE),
    tostring(store:get(settings.HIDE_CHATHEADS))
  )
  refreshPending = true
  refreshWaitTicks = 0
  uiExperimentApplied = false
  lastCompact = nil
  clearLayoutBackup()
end

local function onContactClosed()
  logf("contact iface %s closed", tostring(CONTACT_IFACE))
  contacts = {}
  refreshPending = false
  refreshWaitTicks = 0
  uiExperimentApplied = false
  lastCompact = nil
  clearLayoutBackup()
end

local function onLogic()
  local open = isContactPickerVisiblyOpen()
  if open ~= contactOpen then
    contactOpen = open
    if open then
      onContactOpened()
    else
      onContactClosed()
    end
  end

  -- Wait until the picker finishes spawning contact slots (often >1 tick).
  if refreshPending and contactOpen and not uiExperimentApplied then
    refreshWaitTicks = refreshWaitTicks + 1
    refreshContacts()

    if pickerLooksReady() then
      refreshPending = false
      logContactList()
      logf("picker ready after %d tick(s)", refreshWaitTicks)
      applyContactUiExperiment()
    elseif refreshWaitTicks >= REFRESH_MAX_WAIT_TICKS then
      refreshPending = false
      logContactList()
      logf("picker wait timed out after %d ticks; applying anyway", refreshWaitTicks)
      applyContactUiExperiment()
    elseif refreshWaitTicks == 1 or refreshWaitTicks % 10 == 0 then
      logf(
        "picker waiting tick=%d contacts=%d",
        refreshWaitTicks,
        #contacts
      )
    end
  end

  -- Wheel events can unhide scrollbar chrome; keep the gutter suppressed while open.
  if store:get(settings.HIDE_CHATHEADS) and contactOpen and uiExperimentApplied and HIDE_SCROLLBAR then
    hideContactScrollbarSprites()
  end
end

contactProbe = probe.new({
  log = logger,
  db = PersistentDB,
  picker = {
    isOpen = function()
      return contactOpen
    end,
    refreshContacts = refreshContacts,
    logContactList = logContactList,
    applyContactUiExperiment = applyContactUiExperiment,
    getContactLabel = getContactLabel,
    getContactLabelComponent = getContactLabelComponent,
  },
  contactInterfaceId = CONTACT_IFACE,
  contactButtonStatic = CONTACT_BUTTON_STATIC,
  contactLabelStatic = CONTACT_LABEL_STATIC,
})

unsubscribeHideChatheads = store:subscribe(function(key, value)
  if key ~= settings.HIDE_CHATHEADS then
    return
  end
  onHideChatheadsChanged(value and true or false)
end)

Event.Logic.Subscribe(REFS.logic, onLogic)
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
  if contactProbe ~= nil and contactProbe.enabled then
    Event.MiniMenuReady.Unsubscribe(REFS.miniMenuReady)
    Event.MiniMenuEntrySelected.Unsubscribe(REFS.miniMenuSelected)
    Event.KeyDown.Unsubscribe(REFS.keyDown)
  end
  if unsubscribeHideChatheads ~= nil then
    unsubscribeHideChatheads()
    unsubscribeHideChatheads = nil
  end
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
  "loaded v0.0.22 layout=88/{speak:static1,name:static2} hideChatheads=%s collapse=%s clampScroll=%s hideSb=%s fit=%s spell=%s/%s/%s/%s",
  tostring(store:get(settings.HIDE_CHATHEADS)),
  tostring(COLLAPSE_LABELS),
  tostring(CLAMP_SCROLL_SIZE),
  tostring(HIDE_SCROLLBAR),
  tostring(FIT_WINDOW_TO_CONTENT),
  tostring(spellIds.interfaceId),
  tostring(spellIds.staticId),
  tostring(spellIds.categoryId),
  tostring(spellIds.dynamicId)
)
