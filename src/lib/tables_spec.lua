local tables = require("lib/tables")

describe("tables.clone", function()
  it("returns an empty table for nil", function()
    local copy = tables.clone(nil)
    assert.are.same({}, copy)
  end)

  it("shallow-copies key/value pairs", function()
    local source = { a = 1, b = false }
    local copy = tables.clone(source)
    assert.are.same({ a = 1, b = false }, copy)
    assert.are_not.equal(source, copy)
  end)

  it("does not alias nested tables", function()
    -- shallow: nested table reference is shared by design
    local nested = { n = 1 }
    local source = { nested = nested }
    local copy = tables.clone(source)
    assert.are.equal(nested, copy.nested)
    source.nested = { n = 2 }
    assert.are.equal(1, copy.nested.n)
  end)

  it("mutating the source after clone does not change the copy's top-level keys", function()
    local source = { flag = true }
    local copy = tables.clone(source)
    source.flag = false
    source.extra = 1
    assert.is_true(copy.flag)
    assert.is_nil(copy.extra)
  end)
end)

describe("tables.removeValue", function()
  it("removes the first matching array entry", function()
    local list = { "a", "b", "a" }
    assert.is_true(tables.removeValue(list, "a"))
    assert.are.same({ "b", "a" }, list)
  end)

  it("returns false when the value is absent", function()
    local list = { "a", "b" }
    assert.is_false(tables.removeValue(list, "c"))
    assert.are.same({ "a", "b" }, list)
  end)

  it("matches by reference for function values", function()
    local fn = function() end
    local list = { fn }
    assert.is_true(tables.removeValue(list, fn))
    assert.are.same({}, list)
  end)
end)

