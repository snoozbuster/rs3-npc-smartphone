local text = require("lib/text")

describe("text.stripColours", function()
  it("returns empty string for nil", function()
    assert.are.equal("", text.stripColours(nil))
  end)

  it("leaves plain text unchanged", function()
    assert.are.equal("Banker", text.stripColours("Banker"))
  end)

  it("strips RS colour tags", function()
    assert.are.equal("Banker", text.stripColours("<col=ff0000>Banker</col>"))
  end)

  it("strips multiple tags", function()
    assert.are.equal(
      "Hello world",
      text.stripColours("<col=ffff00>Hello</col> <col=00ff00>world</col>")
    )
  end)
end)

describe("text.lowerClean", function()
  it("lowercases and strips colour tags", function()
    assert.are.equal("banker", text.lowerClean("<col=ff0000>Banker</col>"))
  end)
end)
