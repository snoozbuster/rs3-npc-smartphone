local observable = require("lib/observable")

describe("observable", function()
  it("returns the initial value from get", function()
    local store = observable.new({ flag = true })
    assert.is_true(store:get("flag"))
    assert.is_nil(store:get("missing"))
  end)

  it("notifies subscribers when a value changes", function()
    local store = observable.new({ flag = false })
    local calls = {}
    store:subscribe(function(key, value)
      calls[#calls + 1] = { key = key, value = value }
    end)

    assert.is_true(store:set("flag", true))
    assert.are.equal(1, #calls)
    assert.are.equal("flag", calls[1].key)
    assert.is_true(calls[1].value)
    assert.is_true(store:get("flag"))
  end)

  it("skips notify when the value is unchanged", function()
    local store = observable.new({ flag = true })
    local calls = 0
    store:subscribe(function()
      calls = calls + 1
    end)

    assert.is_false(store:set("flag", true))
    assert.are.equal(0, calls)
  end)

  it("unsubscribe stops further notifications", function()
    local store = observable.new({ n = 0 })
    local calls = 0
    local unsubscribe = store:subscribe(function()
      calls = calls + 1
    end)

    store:set("n", 1)
    unsubscribe()
    store:set("n", 2)
    assert.are.equal(1, calls)
  end)

  it("notifies all subscribers when a value changes", function()
    local store = observable.new({ n = 0 })
    local a = 0
    local b = 0
    store:subscribe(function()
      a = a + 1
    end)
    store:subscribe(function()
      b = b + 1
    end)

    store:set("n", 1)
    assert.are.equal(1, a)
    assert.are.equal(1, b)
  end)

  it("still notifies remaining subscribers if one unsubscribes during notify", function()
    local store = observable.new({ n = 0 })
    local first = 0
    local second = 0
    local unsubscribeFirst
    unsubscribeFirst = store:subscribe(function()
      first = first + 1
      unsubscribeFirst()
    end)
    store:subscribe(function()
      second = second + 1
    end)

    store:set("n", 1)
    assert.are.equal(1, first)
    assert.are.equal(1, second)
  end)

  it("does not alias the initial table into the store", function()
    local initial = { flag = true }
    local store = observable.new(initial)
    initial.flag = false
    initial.extra = 1

    assert.is_true(store:get("flag"))
    assert.is_nil(store:get("extra"))
  end)
end)
