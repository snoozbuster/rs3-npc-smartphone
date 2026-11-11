--[[
  Runtime shape checks plus EmmyLua contracts exercised under LuaLS --check.
  Typed locals / field reads fail typecheck if h() overloads or props drift.
]]

local element = require("lib/element")

describe("element.h", function()
  it("returns a BoxElement for type box", function()
    ---@type BoxElement
    local box = element.h("box", { width = 100, height = 50 }, {
      element.h("title", { text = "T" }),
    })

    -- Typed field access: typecheck fails if BoxElement / BoxElementProps drift.
    local width = box.props.width
    local height = box.props.height
    local kids = box.children

    assert.are.equal("box", box.type)
    assert.are.equal(100, width)
    assert.are.equal(50, height)
    assert.is_not_nil(kids)
    assert.are.equal(1, #kids)
  end)

  it("returns a TitleElement for type title", function()
    ---@type TitleElement
    local title = element.h("title", { text = "Hello" })

    local text = title.props.text

    assert.are.equal("title", title.type)
    assert.are.equal("Hello", text)
    assert.is_nil(title.children)
  end)

  it("returns a CheckboxGroupElement for type checkbox_group", function()
    ---@param value any
    ---@param selected boolean
    local function onChange(value, selected) end

    ---@type CheckboxGroupElement
    local group = element.h("checkbox_group", {
      choices = {
        { text = "A", value = "a", selected = true },
      },
      onChange = onChange,
    })

    local choices = group.props.choices
    local handler = group.props.onChange

    assert.are.equal("checkbox_group", group.type)
    assert.are.equal(1, #choices)
    assert.are.equal("A", choices[1].text)
    assert.are.equal("a", choices[1].value)
    assert.is_true(choices[1].selected)
    assert.are.equal(onChange, handler)
    assert.is_nil(group.children)
  end)

  it("defaults nil props to an empty table", function()
    ---@type BoxElement
    local box = element.h("box")

    assert.are.equal("box", box.type)
    assert.are.same({}, box.props)
    assert.is_nil(box.children)
  end)
end)
