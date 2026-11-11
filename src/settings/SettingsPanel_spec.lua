local SettingsPanel = require("settings/SettingsPanel")
local settings = require("settings")

describe("SettingsPanel", function()
  local function render(hideChatheads, set)
    return SettingsPanel({
      hideChatheads = hideChatheads,
      set = set or function() end,
      width = 320,
      height = 240,
    })
  end

  it("returns a box with title and checkbox_group children", function()
    local tree = render(true)

    assert.are.equal("box", tree.type)
    assert.are.equal(320, tree.props.width)
    assert.are.equal(240, tree.props.height)
    assert.are.equal(2, #tree.children)

    local title = tree.children[1]
    assert.are.equal("title", title.type)
    assert.are.equal("NPC Smartphone", title.props.text)

    local group = tree.children[2]
    assert.are.equal("checkbox_group", group.type)
    assert.are.equal(1, #group.props.choices)

    local choice = group.props.choices[1]
    assert.are.equal("Hide chatheads", choice.text)
    assert.are.equal(settings.HIDE_CHATHEADS, choice.value)
    assert.is_true(choice.selected)
  end)

  it("marks hideChatheads choice unselected when props are false", function()
    local tree = render(false)
    assert.is_false(tree.children[2].props.choices[1].selected)
  end)

  it("invokes props.set from checkbox_group onChange", function()
    local calls = {}
    local tree = render(false, function(key, value)
      calls[#calls + 1] = { key = key, value = value }
    end)

    tree.children[2].props.onChange(settings.HIDE_CHATHEADS, true)

    assert.are.same({
      { key = settings.HIDE_CHATHEADS, value = true },
    }, calls)
  end)

  it("passes false through onChange to props.set", function()
    local calls = {}
    local tree = render(true, function(key, value)
      calls[#calls + 1] = { key = key, value = value }
    end)

    tree.children[2].props.onChange(settings.HIDE_CHATHEADS, false)

    assert.are.same({
      { key = settings.HIDE_CHATHEADS, value = false },
    }, calls)
  end)
end)
