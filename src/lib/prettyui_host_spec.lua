local element = require("lib/element")
local prettyui_host = require("lib/prettyui_host")

---@class FakeCheckbox
---@field setSelectedCalls { value: any, selected: boolean }[]
---@field onChange (fun(group: any, values: any[], value: any, selected: boolean))?
---@field SetSelected fun(self: FakeCheckbox, value: any, selected: boolean)

---@class FakeSimpleView
---@field parent any
---@field options table
---@field titles string[]
---@field checkboxes FakeCheckbox[]
---@field destroyed boolean
---@field AddTitle fun(self: FakeSimpleView, text: string)
---@field AddCheckboxButton fun(self: FakeSimpleView, choices: table, options: table?): FakeCheckbox
---@field Destroy fun(self: FakeSimpleView)

--- Install a PrettyUI fake on `_G` (module resolves globals via `_G`).
---@return { views: FakeSimpleView[] }
local function installFakePrettyUi()
  ---@type FakeSimpleView[]
  local views = {}

  ---@param choices table
  ---@param options table?
  ---@return FakeCheckbox
  local function newCheckbox(choices, options)
    ---@type FakeCheckbox
    local checkbox = {
      setSelectedCalls = {},
      onChange = options and options.onChange,
      SetSelected = function(self, value, selected)
        self.setSelectedCalls[#self.setSelectedCalls + 1] = {
          value = value,
          selected = selected,
        }
      end,
    }
    return checkbox
  end

  _G.prettyui = {
    SimpleView = {
      ---@param parent any
      ---@param options table?
      ---@return FakeSimpleView
      new = function(parent, options)
        ---@type FakeSimpleView
        local view = {
          parent = parent,
          options = options or {},
          titles = {},
          checkboxes = {},
          destroyed = false,
          AddTitle = function(self, text)
            self.titles[#self.titles + 1] = text
          end,
          AddCheckboxButton = function(self, choices, opts)
            local checkbox = newCheckbox(choices, opts)
            self.checkboxes[#self.checkboxes + 1] = checkbox
            return checkbox
          end,
          Destroy = function(self)
            self.destroyed = true
          end,
        }
        views[#views + 1] = view
        return view
      end,
    },
  }

  return { views = views }
end

describe("prettyui_host", function()
  ---@type { views: FakeSimpleView[] }
  local fake
  ---@type ui.Component
  local parent

  before_each(function()
    fake = installFakePrettyUi()
    -- Host only reads width/height from parent; full Component fields are unused.
    ---@diagnostic disable-next-line: missing-fields
    parent = { width = 320, height = 240 }
  end)

  after_each(function()
    _G.prettyui = nil
  end)

  it("errors when the root element is not a box", function()
    local title = element.h("title", { text = "Nope" })
    assert.has_error(function()
      prettyui_host.mount(parent, title)
    end, "prettyui_host.mount expects a box element")
  end)

  it("mounts title and checkbox_group under SimpleView", function()
    local vnode = element.h("box", { width = 320, height = 240 }, {
      element.h("title", { text = "NPC Smartphone" }),
      element.h("checkbox_group", {
        choices = {
          { text = "Hide chatheads", value = "hideChatheads", selected = true },
        },
      }),
    })

    prettyui_host.mount(parent, vnode)

    assert.are.equal(1, #fake.views)
    local view = fake.views[1]
    assert.are.equal(parent, view.parent)
    assert.are.equal(320, view.options.width)
    assert.are.equal(240, view.options.height)
    assert.are.same({ "NPC Smartphone" }, view.titles)
    assert.are.equal(1, #view.checkboxes)
  end)

  it("maps PrettyUI onChange to element onChange(value, selected)", function()
    local calls = {}
    local vnode = element.h("box", { width = 1, height = 1 }, {
      element.h("checkbox_group", {
        choices = {
          { text = "Hide chatheads", value = "hideChatheads", selected = false },
        },
        onChange = function(value, selected)
          calls[#calls + 1] = { value = value, selected = selected }
        end,
      }),
    })

    prettyui_host.mount(parent, vnode)
    local checkbox = fake.views[1].checkboxes[1]
    checkbox.onChange(checkbox, {}, "hideChatheads", true)

    assert.are.same({
      { value = "hideChatheads", selected = true },
    }, calls)
  end)

  it("update rebinds onChange and SetSelected only when selection changes", function()
    local firstCalls = {}
    local secondCalls = {}

    local handle = prettyui_host.mount(
      parent,
      element.h("box", { width = 1, height = 1 }, {
        element.h("checkbox_group", {
          choices = {
            { text = "Hide chatheads", value = "hideChatheads", selected = false },
          },
          onChange = function(value, selected)
            firstCalls[#firstCalls + 1] = { value = value, selected = selected }
          end,
        }),
      })
    )

    local checkbox = fake.views[1].checkboxes[1]

    handle.update(element.h("box", { width = 1, height = 1 }, {
      element.h("checkbox_group", {
        choices = {
          { text = "Hide chatheads", value = "hideChatheads", selected = true },
        },
        onChange = function(value, selected)
          secondCalls[#secondCalls + 1] = { value = value, selected = selected }
        end,
      }),
    }))

    assert.are.same({
      { value = "hideChatheads", selected = true },
    }, checkbox.setSelectedCalls)

    -- Same selection again: compare-before-set skips SetSelected.
    handle.update(element.h("box", { width = 1, height = 1 }, {
      element.h("checkbox_group", {
        choices = {
          { text = "Hide chatheads", value = "hideChatheads", selected = true },
        },
        onChange = function(value, selected)
          secondCalls[#secondCalls + 1] = { value = value, selected = selected }
        end,
      }),
    }))

    assert.are.equal(1, #checkbox.setSelectedCalls)

    checkbox.onChange(checkbox, {}, "hideChatheads", false)
    assert.are.same({}, firstCalls)
    assert.are.same({
      { value = "hideChatheads", selected = false },
    }, secondCalls)
  end)

  it("mirrors selection before calling onChange so update does not re-enter SetSelected", function()
    local handle = prettyui_host.mount(
      parent,
      element.h("box", { width = 1, height = 1 }, {
        element.h("checkbox_group", {
          choices = {
            { text = "Hide chatheads", value = "hideChatheads", selected = false },
          },
          onChange = function() end,
        }),
      })
    )

    local checkbox = fake.views[1].checkboxes[1]
    checkbox.onChange(checkbox, {}, "hideChatheads", true)

    handle.update(element.h("box", { width = 1, height = 1 }, {
      element.h("checkbox_group", {
        choices = {
          { text = "Hide chatheads", value = "hideChatheads", selected = true },
        },
      }),
    }))

    assert.are.equal(0, #checkbox.setSelectedCalls)
  end)

  it("destroy tears down the SimpleView", function()
    local handle = prettyui_host.mount(
      parent,
      element.h("box", { width = 1, height = 1 }, {
        element.h("title", { text = "NPC Smartphone" }),
      })
    )

    handle.destroy()
    assert.is_true(fake.views[1].destroyed)
  end)
end)
