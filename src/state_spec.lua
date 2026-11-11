local state = require("state")
local tables = require("lib/tables")

local function fakeDb(initial)
  local data = tables.clone(initial)

  return {
    GetBool = function(_, key)
      return data[key]
    end,
    SetBool = function(_, key, value)
      data[key] = value
    end,
    _data = data,
  }
end

describe("state", function()
  it("defaults hideChatheads to true when db returns nil", function()
    local db = fakeDb()
    local store = state.new(db)
    assert.is_true(store:get("hideChatheads"))
  end)

  it("seeds hideChatheads into db when missing", function()
    local db = fakeDb()
    state.new(db)
    assert.is_true(db._data.hideChatheads)
  end)

  it("does not rewrite hideChatheads when db already has a value", function()
    local db = fakeDb({ hideChatheads = false })
    local writes = 0
    local originalSet = db.SetBool
    db.SetBool = function(self, key, value)
      writes = writes + 1
      return originalSet(self, key, value)
    end

    local store = state.new(db)
    assert.is_false(store:get("hideChatheads"))
    assert.are.equal(0, writes)
  end)

  it("loads hideChatheads from db when present", function()
    local db = fakeDb({ hideChatheads = false })
    local store = state.new(db)
    assert.is_false(store:get("hideChatheads"))
  end)

  it("persists and notifies on successful set", function()
    local db = fakeDb({ hideChatheads = true })
    local store = state.new(db)
    local calls = {}
    store:subscribe(function(key, value)
      calls[#calls + 1] = { key = key, value = value }
    end)

    assert.is_true(store:set("hideChatheads", false))
    assert.is_false(db._data.hideChatheads)
    assert.is_false(store:get("hideChatheads"))
    assert.are.equal(1, #calls)
    assert.are.equal("hideChatheads", calls[1].key)
    assert.is_false(calls[1].value)
  end)

  it("skips persist and notify when unchanged", function()
    local db = fakeDb({ hideChatheads = true })
    local store = state.new(db)
    local writes = 0
    local originalSet = db.SetBool
    db.SetBool = function(self, key, value)
      writes = writes + 1
      return originalSet(self, key, value)
    end
    local calls = 0
    store:subscribe(function()
      calls = calls + 1
    end)

    assert.is_false(store:set("hideChatheads", true))
    assert.are.equal(0, writes)
    assert.are.equal(0, calls)
  end)

  it("rejects unknown keys without mutating or notifying", function()
    local db = fakeDb({ hideChatheads = true })
    local store = state.new(db)
    local writes = 0
    local originalSet = db.SetBool
    db.SetBool = function(self, key, value)
      writes = writes + 1
      return originalSet(self, key, value)
    end
    local calls = 0
    store:subscribe(function()
      calls = calls + 1
    end)

    -- Intentionally not a StateKey: runtime allowlist must still reject it.
    ---@diagnostic disable-next-line: param-type-mismatch
    assert.is_false(store:set("unknownOption", true))
    ---@diagnostic disable-next-line: param-type-mismatch
    assert.is_nil(store:get("unknownOption"))
    assert.are.equal(0, writes)
    assert.are.equal(0, calls)
  end)
end)
