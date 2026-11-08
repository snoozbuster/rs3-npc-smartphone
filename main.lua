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

local REFS = {
  logic = "npcSmartphone.logic",
  miniMenuReady = "npcSmartphone.miniMenuReady",
  miniMenuSelected = "npcSmartphone.miniMenuSelected",
  keyDown = "npcSmartphone.keyDown",
}

local PROBE_ENABLED = true
local PROBE_DUMP_KEY = GameKey.F9

-- Experiment: hide Speak-to MODEL chatheads so only name LABELs remain.
-- Note: those MODELs are also the click targets; hiding them removes Speak-to.
-- After hiding, pack labels into a tighter grid (don't move MODEL click zones).
-- Scrollbar gutter is static=3 (from scaffold). Do not heuristic-hide static=8 borders.
local HIDE_CHATHEADS = true
local COLLAPSE_LABELS = true
local CLAMP_SCROLL_SIZE = true
local HIDE_SCROLLBAR = true
local FIT_WINDOW_TO_CONTENT = true
local COMPACT_COLS = 5
local COMPACT_ROW_HEIGHT = 22 -- label cells are tall (~100); use text-sized pitch instead
local INTERFACE_BOTTOM_PAD = 48 -- keep descenders / last row inside the frame
local CONTACT_SCROLLBAR_STATIC = 3 -- 16x284 gutter at x≈475
local CONTACT_VIEWPORT_STATIC = 0 -- 471x284 scroll host
-- Frame/chrome layers to shorten when fitting the window (iface 88 scaffold).
-- Snapshot heights before any SetSize — resizing a parent can auto-resize children,
-- and applying delta again would double-shrink (cut off the list).
local CONTACT_FRAME_STATICS = { 0, 3, 4, 5, 6, 7, 8 }

local ACTION_CAST = MiniMenuActionType.IF_BUTTONX1
local ACTION_REDIAL = MiniMenuActionType.IF_BUTTONX2

local SPELL_IFACE = 1886
local SPELL_STATIC = 1
local SPELL_CAT = 0
local SPELL_DYN = 108

local CONTACT_IFACE = 88
local CONTACT_BUTTON_STATIC = 1 -- Speak-to / chathead MODELs
local CONTACT_LABEL_STATIC = 2 -- name text
local CONTACT_CAT = 0
local CONTACT_SLOT_MAX = 64

local contactInterfaceId = CONTACT_IFACE
local spellInterfaceId = PersistentDB:GetInt("spellInterfaceId") or SPELL_IFACE
local spellStaticId = PersistentDB:GetInt("spellStaticId") or SPELL_STATIC
local spellCategoryId = PersistentDB:GetInt("spellCategoryId") or SPELL_CAT
local spellDynamicId = PersistentDB:GetInt("spellDynamicId") or SPELL_DYN

PersistentDB:SetInt("contactInterfaceId", CONTACT_IFACE)

local contactOpen = false
local contacts = {} -- array of { dyn, name, hasSpeakTo }
local lastMiniMenuLogKey = nil
local refreshPending = false
local refreshWaitTicks = 0
local REFRESH_MAX_WAIT_TICKS = 60 -- ~ interface populate timeout
local uiExperimentApplied = false
local chatheadsHidden = false
local lastCompact = nil -- { baseY, rowH, rows, contentBottom, sampleLabel }

local function logf(fmt, ...)
  print(string.format("[npc-smartphone] " .. fmt, ...))
end

local function stripColours(text)
  if text == nil then
    return ""
  end
  return (string.gsub(text, "<[^>]+>", ""))
end

local function lowerClean(text)
  return string.lower(stripColours(text))
end

local function isNpcContactSubject(text)
  return string.find(lowerClean(text), "npc contact", 1, true) ~= nil
end

local function safeProp(component, key)
  local ok, value = pcall(function()
    return component[key]
  end)
  if ok then
    return value
  end
  return nil
end

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

local function rememberSpellComponent(component)
  if component == nil then
    return
  end
  spellInterfaceId = component.interfaceID
  spellStaticId = component.staticID
  spellCategoryId = component.categoryID
  spellDynamicId = component.dynamicID
  PersistentDB:SetInt("spellInterfaceId", spellInterfaceId)
  PersistentDB:SetInt("spellStaticId", spellStaticId)
  PersistentDB:SetInt("spellCategoryId", spellCategoryId)
  PersistentDB:SetInt("spellDynamicId", spellDynamicId)
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

--- Hide the whole chathead layer immediately (anti-flash), then each MODEL child.
local function hideContactChatheadLayer()
  if not HIDE_CHATHEADS then
    return 0
  end

  local hiddenCount = 0
  local okGet, layer = pcall(function()
    return ui.Interfaces:GetComponent(CONTACT_IFACE, CONTACT_BUTTON_STATIC)
  end)
  if not okGet or layer == nil then
    return 0
  end

  local okHide, hideErr = pcall(function()
    layer.hidden = true
  end)
  if okHide then
    hiddenCount = hiddenCount + 1
  else
    logf("hide chathead layer failed: %s", tostring(hideErr))
  end

  pcall(function()
    layer:IterateDynamicComponents(function(child, visible)
      local ok = pcall(function()
        child.hidden = true
      end)
      if ok then
        hiddenCount = hiddenCount + 1
      end
      return false
    end)
  end)

  return hiddenCount
end

--- Hide each contact MODEL (static=1). Labels (static=2) stay visible.
local function hideContactChatheads()
  if not HIDE_CHATHEADS then
    return 0
  end

  local hiddenCount = hideContactChatheadLayer()
  local failCount = 0
  for _, slot in ipairs(contacts) do
    local button = getContactButton(slot.dyn)
    if button == nil then
      failCount = failCount + 1
    else
      local ok, err = pcall(function()
        button.hidden = true
      end)
      if ok then
        hiddenCount = hiddenCount + 1
      else
        failCount = failCount + 1
        logf("hide chathead dyn=%s failed: %s", tostring(slot.dyn), tostring(err))
      end
    end
  end

  chatheadsHidden = hiddenCount > 0
  logf(
    "hide chatheads: hidden=%d fail=%d (labels remain at static=%d)",
    hiddenCount,
    failCount,
    CONTACT_LABEL_STATIC
  )
  return hiddenCount
end

--- True when iface 88's shell has geometry (may be before contact slots exist).
local function isContactPickerShellPresent()
  local iface = ui.Interfaces:GetInterface(CONTACT_IFACE)
  if iface == nil then
    return false
  end
  local ok, layer = pcall(function()
    return ui.Interfaces:GetComponent(CONTACT_IFACE, CONTACT_VIEWPORT_STATIC)
  end)
  if not ok or layer == nil then
    return false
  end
  local width = safeProp(layer, "width")
  local height = safeProp(layer, "height")
  return type(width) == "number" and type(height) == "number" and width >= 50 and height >= 50
end

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

local function isContactPickerComponent(component)
  if component == nil then
    return false
  end
  return safeProp(component, "interfaceID") == CONTACT_IFACE
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
  logf("scaffold dump iface=%s:", tostring(CONTACT_IFACE))
  for staticId = 0, 9 do
    local ok, component = pcall(function()
      return ui.Interfaces:GetComponent(CONTACT_IFACE, staticId)
    end)
    if ok and component ~= nil then
      logf("  %s", describeGeom(component, "s" .. tostring(staticId)))
      local sb = safeProp(component, "scrollbar")
      logf("  s%s.scrollbar=%s", tostring(staticId), tostring(sb ~= nil))
      -- Chrome / scrollbar suspects: dump non-contact statics fully; sample 1/2 lightly.
      if staticId ~= CONTACT_BUTTON_STATIC and staticId ~= CONTACT_LABEL_STATIC then
        dumpDynamicChildren(component, staticId)
      end
    end
  end

  local sample = getContactLabelComponent(0)
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

--- Pack name labels into a denser grid using the original column X positions.
--- Leaves MODEL components untouched (guidelines: don't move 3D click zones).
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
    gutter:IterateDynamicComponents(function(child, visible)
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
  dumpContactScaffold()
  hideContactChatheads()
  collapseContactLabels()
  clampContactScrollSize()
  fitContactWindowToContent()
  local sbHidden = hideContactScrollbarSprites()
  logf("hide scrollbar: hidden=%d (static=%d gutter + children)", sbHidden, CONTACT_SCROLLBAR_STATIC)
  uiExperimentApplied = true
end

local function onContactOpened()
  logf("contact iface %s OPEN", tostring(CONTACT_IFACE))
  refreshPending = true
  refreshWaitTicks = 0
  uiExperimentApplied = false
  chatheadsHidden = false
  lastCompact = nil
  -- Kill the legacy chathead flash as early as possible.
  hideContactChatheadLayer()
  hideContactScrollbarSprites()
end

local function onContactClosed()
  logf("contact iface %s closed", tostring(CONTACT_IFACE))
  contacts = {}
  refreshPending = false
  refreshWaitTicks = 0
  uiExperimentApplied = false
  chatheadsHidden = false
  lastCompact = nil
end

local function onLogic()
  -- Suppress chatheads the instant the shell has geometry, before slots are ready.
  if not uiExperimentApplied and isContactPickerShellPresent() then
    hideContactChatheadLayer()
    hideContactScrollbarSprites()
  end

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
    -- Keep suppressing newly spawned chatheads while we wait for full layout.
    hideContactChatheadLayer()

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
  if contactOpen and uiExperimentApplied and HIDE_SCROLLBAR then
    hideContactScrollbarSprites()
  end
end

local function onMiniMenuReady(event)
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
      if component ~= nil and (entry.actionType == ACTION_CAST or entry.actionType == ACTION_REDIAL) then
        rememberSpellComponent(component)
      end
    elseif component ~= nil
        and component.interfaceID == CONTACT_IFACE
        and component.staticID == CONTACT_BUTTON_STATIC then
      local dyn = component.dynamicID
      local name = getContactLabel(dyn) or "?"
      local logKey = "contact|" .. tostring(dyn)
      if logKey ~= lastMiniMenuLogKey then
        lastMiniMenuLogKey = logKey
        logf("minimenu contact: dyn=%s name=%s verb=%q", tostring(dyn), name, verb)
      end
    end
  end
end

local function onMiniMenuSelected(event)
  local entry = event.entry
  if entry == nil then
    return
  end

  local component = entry.componentData and entry.componentData.component or nil

  if component ~= nil
      and component.interfaceID == CONTACT_IFACE
      and component.staticID == CONTACT_BUTTON_STATIC then
    local dyn = component.dynamicID
    local name = getContactLabel(dyn) or "?"
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

local function onKeyDown(event)
  if not PROBE_ENABLED then
    return
  end
  if event.gameKey ~= PROBE_DUMP_KEY then
    return
  end

  logf(
    "F9: spell=%s/%s/%s/%s contact=%s open=%s",
    tostring(spellInterfaceId),
    tostring(spellStaticId),
    tostring(spellCategoryId),
    tostring(spellDynamicId),
    tostring(contactInterfaceId),
    tostring(contactOpen)
  )

  if not contactOpen then
    logf("F9: picker not open — cast NPC Contact first")
    return
  end

  refreshContacts()
  logContactList()
  applyContactUiExperiment()
end

Event.Logic.Subscribe(REFS.logic, onLogic)
Event.MiniMenuReady.Subscribe(REFS.miniMenuReady, onMiniMenuReady)
Event.MiniMenuEntrySelected.Subscribe(REFS.miniMenuSelected, onMiniMenuSelected)
Event.KeyDown.Subscribe(REFS.keyDown, onKeyDown)

function PluginShutdown()
  Event.Logic.Unsubscribe(REFS.logic)
  Event.MiniMenuReady.Unsubscribe(REFS.miniMenuReady)
  Event.MiniMenuEntrySelected.Unsubscribe(REFS.miniMenuSelected)
  Event.KeyDown.Unsubscribe(REFS.keyDown)
  logf("shutdown")
end

logf(
  "loaded v0.0.18 layout=88/{speak:static1,name:static2} hide=%s collapse=%s clampScroll=%s hideSb=%s fit=%s spell=%s/%s/%s/%s",
  tostring(HIDE_CHATHEADS),
  tostring(COLLAPSE_LABELS),
  tostring(CLAMP_SCROLL_SIZE),
  tostring(HIDE_SCROLLBAR),
  tostring(FIT_WINDOW_TO_CONTENT),
  tostring(spellInterfaceId),
  tostring(spellStaticId),
  tostring(spellCategoryId),
  tostring(spellDynamicId)
)
