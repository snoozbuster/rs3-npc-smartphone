-- Spec files run in a busted sandbox; required modules read real `_G`.
_G.MiniMenuActionType = {
  IF_BUTTONX1 = 1,
  IF_BUTTONX2 = 2,
}
_G.GameKey = { F9 = 120 }

local probe = require("probe")

---@return ProbeDb, table<string, number>
local function fakeDb(seed)
  local data = seed or {}
  ---@type ProbeDb
  local db = {
    GetInt = function(_, key)
      return data[key]
    end,
    SetInt = function(_, key, value)
      data[key] = value
    end,
  }
  return db, data
end

---@return Logger, string[]
local function fakeLog()
  local lines = {}
  return {
    f = function(fmt, ...)
      lines[#lines + 1] = string.format(fmt, ...)
    end,
  }, lines
end

---@param overrides table|nil partial ProbePicker field overrides
---@return ProbePicker, { refresh: number, logList: number, apply: number }
local function fakePicker(overrides)
  local calls = {
    refresh = 0,
    logList = 0,
    apply = 0,
  }
  ---@type ProbePicker
  local picker = {
    isOpen = function()
      return false
    end,
    refreshContacts = function()
      calls.refresh = calls.refresh + 1
    end,
    logContactList = function()
      calls.logList = calls.logList + 1
    end,
    applyContactUiExperiment = function()
      calls.apply = calls.apply + 1
    end,
    getContactLabel = function()
      return nil
    end,
    getContactLabelComponent = function()
      return nil
    end,
  }
  if overrides ~= nil then
    for key, value in pairs(overrides) do
      picker[key] = value
    end
  end
  return picker, calls
end

describe("probe.new", function()
  it("loads default spell ids when db is empty", function()
    local logger = fakeLog()
    local instance = probe.new({
      log = logger,
      db = fakeDb(),
      picker = fakePicker(),
      contactInterfaceId = 88,
      contactButtonStatic = 1,
      contactLabelStatic = 2,
    })
    local ids = instance.spellIds()
    assert.are.equal(1886, ids.interfaceId)
    assert.are.equal(1, ids.staticId)
    assert.are.equal(0, ids.categoryId)
    assert.are.equal(108, ids.dynamicId)
  end)

  it("remembers spell component from MiniMenu select", function()
    local logger = fakeLog()
    local db, data = fakeDb()
    local instance = probe.new({
      log = logger,
      db = db,
      picker = fakePicker(),
      contactInterfaceId = 88,
      contactButtonStatic = 1,
      contactLabelStatic = 2,
    })

    instance.onMiniMenuSelected({
      entry = {
        subjectText = "NPC Contact",
        verbText = "Cast",
        actionType = _G.MiniMenuActionType.IF_BUTTONX1,
        componentData = {
          component = {
            interfaceID = 1886,
            staticID = 1,
            categoryID = 0,
            dynamicID = 99,
            type = 4,
          },
        },
      },
    })

    local ids = instance.spellIds()
    assert.are.equal(1886, ids.interfaceId)
    assert.are.equal(99, ids.dynamicId)
    assert.are.equal(1886, data.spellInterfaceId)
    assert.are.equal(99, data.spellDynamicId)
  end)

  it("F9 closed: logs and does not apply", function()
    local logger, lines = fakeLog()
    local picker, calls = fakePicker({
      isOpen = function()
        return false
      end,
    })
    local instance = probe.new({
      log = logger,
      db = fakeDb(),
      picker = picker,
      contactInterfaceId = 88,
      contactButtonStatic = 1,
      contactLabelStatic = 2,
    })

    instance.onKeyDown({ gameKey = _G.GameKey.F9 })

    assert.are.equal(0, calls.refresh)
    assert.are.equal(0, calls.apply)
    assert.is_truthy(string.find(lines[#lines], "picker not open", 1, true))
  end)

  it("F9 open: refreshes, lists, and applies", function()
    local logger = fakeLog()
    local picker, calls = fakePicker({
      isOpen = function()
        return true
      end,
    })
    -- Avoid touching ui.Interfaces during scaffold dump.
    _G.ui = {
      Interfaces = {
        GetComponent = function()
          return nil
        end,
      },
    }
    local instance = probe.new({
      log = logger,
      db = fakeDb(),
      picker = picker,
      contactInterfaceId = 88,
      contactButtonStatic = 1,
      contactLabelStatic = 2,
    })

    instance.onKeyDown({ gameKey = _G.GameKey.F9 })

    assert.are.equal(1, calls.refresh)
    assert.are.equal(1, calls.logList)
    assert.are.equal(1, calls.apply)
  end)

  it("logs contact MiniMenu lines via picker label lookup", function()
    local logger, lines = fakeLog()
    local picker = fakePicker({
      getContactLabel = function(dyn)
        if dyn == 3 then
          return "Banker"
        end
        return nil
      end,
    })
    local instance = probe.new({
      log = logger,
      db = fakeDb(),
      picker = picker,
      contactInterfaceId = 88,
      contactButtonStatic = 1,
      contactLabelStatic = 2,
    })

    instance.onMiniMenuReady({
      miniMenu = {
        entries = {
          {
            subjectText = "Speak-to",
            verbText = "Speak-to",
            actionType = 0,
            componentData = {
              component = {
                interfaceID = 88,
                staticID = 1,
                categoryID = 0,
                dynamicID = 3,
                type = 4,
              },
            },
          },
        },
      },
    })

    assert.is_truthy(string.find(lines[1], "minimenu contact", 1, true))
    assert.is_truthy(string.find(lines[1], "Banker", 1, true))
  end)

  it("matches coloured NPC Contact MiniMenu subjects", function()
    local logger, lines = fakeLog()
    local db, data = fakeDb()
    local instance = probe.new({
      log = logger,
      db = db,
      picker = fakePicker(),
      contactInterfaceId = 88,
      contactButtonStatic = 1,
      contactLabelStatic = 2,
    })

    instance.onMiniMenuReady({
      miniMenu = {
        entries = {
          {
            subjectText = "<col=ffffff>Npc Contact</col>",
            verbText = "Cast",
            actionType = _G.MiniMenuActionType.IF_BUTTONX1,
            componentData = {
              component = {
                interfaceID = 1886,
                staticID = 1,
                categoryID = 0,
                dynamicID = 42,
                type = 4,
              },
            },
          },
        },
      },
    })

    assert.is_truthy(string.find(lines[1], "minimenu spell", 1, true))
    assert.are.equal(42, data.spellDynamicId)
  end)

  it("ignores unrelated MiniMenu subjects", function()
    local logger, lines = fakeLog()
    local db, data = fakeDb()
    local instance = probe.new({
      log = logger,
      db = db,
      picker = fakePicker(),
      contactInterfaceId = 88,
      contactButtonStatic = 1,
      contactLabelStatic = 2,
    })

    instance.onMiniMenuSelected({
      entry = {
        subjectText = "Banker",
        verbText = "Talk-to",
        actionType = 0,
        componentData = {
          component = {
            interfaceID = 12,
            staticID = 0,
            categoryID = 0,
            dynamicID = 1,
            type = 4,
          },
        },
      },
    })

    assert.are.equal(0, #lines)
    assert.is_nil(data.spellDynamicId)
  end)
end)
