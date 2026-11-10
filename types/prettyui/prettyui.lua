---@meta
---Synthesized EmmyLua stubs for the PrettyUI dependency plugin (mod.io 6398181).
---Source: https://prettyui.j3.gg/ — covers the surface used by npc-smartphone plus
---common SimpleView / checkbox helpers. Not a complete PrettyUI API mirror.

---@class prettyui
prettyui = {}

---@class prettyui.LayoutOptions
---@field categoryID integer|string|nil
---@field x integer?
---@field y integer?
---@field width integer?
---@field height integer?
---@field scrollable boolean?
---@field contentHeight integer?
---@field scrollStep integer?

---@class prettyui.Choice
---@field text string?
---@field label string?
---@field value any
---@field selected boolean?
---@field disabled boolean?
---@field tooltip string?

---@class prettyui.TextOptions
---@field text string?
---@field colour integer?
---@field marginTop integer?
---@field font any?

---@class prettyui.CheckboxButtonOptions
---@field selectedValues any[]|table<any, boolean>|nil
---@field inline boolean?
---@field disabled boolean?
---Called after a user change: (group, values, changedValue, selected)
---@field onChange (fun(group: prettyui.CheckboxButton, values: any[], changedValue: any, selected: boolean))?

---@class prettyui.RadioButtonOptions
---@field selectedValue any
---@field inline boolean?
---@field disabled boolean?
---@field onChange (fun(group: prettyui.RadioButton, value: any))?

---@class prettyui.CheckboxButton
prettyui.CheckboxButton = {}

---@param parent ui.Component
---@param choices prettyui.Choice[]|any[]
---@param options prettyui.CheckboxButtonOptions?
---@return prettyui.CheckboxButton
function prettyui.CheckboxButton.new(parent, choices, options) end

---@return any[]
function prettyui.CheckboxButton:GetSelectedValues() end

---@param value any
---@return boolean
function prettyui.CheckboxButton:IsSelected(value) end

---@param value any
---@param selected boolean
function prettyui.CheckboxButton:SetSelected(value, selected) end

---@param disabled boolean
function prettyui.CheckboxButton:SetDisabled(disabled) end

---@param value any
---@param tooltip string|nil
function prettyui.CheckboxButton:SetOptionTooltip(value, tooltip) end

function prettyui.CheckboxButton:Destroy() end

---@class prettyui.RadioButton
prettyui.RadioButton = {}

---@param parent ui.Component
---@param choices prettyui.Choice[]|any[]
---@param options prettyui.RadioButtonOptions?
---@return prettyui.RadioButton
function prettyui.RadioButton.new(parent, choices, options) end

---@return any
function prettyui.RadioButton:GetSelectedValue() end

---@param value any|nil
function prettyui.RadioButton:SetSelectedValue(value) end

---@param value any
---@return boolean
function prettyui.RadioButton:IsSelected(value) end

---@param disabled boolean
function prettyui.RadioButton:SetDisabled(disabled) end

---@param value any
---@param tooltip string|nil
function prettyui.RadioButton:SetOptionTooltip(value, tooltip) end

function prettyui.RadioButton:Destroy() end

---Unstyled scrollable content host with PrettyUI flow layout.
---@class prettyui.SimpleView
---@field content ui.Component
---@field viewport ui.Component
---@field scrollbarVisible boolean
---@field scrollY number
---@field contentHeight number
---@field contentWidth number
prettyui.SimpleView = {}

---@param parent ui.Component
---@param options prettyui.LayoutOptions?
---@return prettyui.SimpleView
function prettyui.SimpleView.new(parent, options) end

---@param value string|prettyui.TextOptions
---@return ui.Component
function prettyui.SimpleView:AddTitle(value) end

---@param value string|prettyui.TextOptions
---@return ui.Component
function prettyui.SimpleView:AddText(value) end

---@param choices prettyui.Choice[]|any[]
---@param options prettyui.CheckboxButtonOptions?
---@return prettyui.CheckboxButton
function prettyui.SimpleView:AddCheckboxButton(choices, options) end

---@param choices prettyui.Choice[]|any[]
---@param options prettyui.RadioButtonOptions?
---@return prettyui.RadioButton
function prettyui.SimpleView:AddRadioButton(choices, options) end

---@param labelOrSprite string|integer
---@param onClick (fun(self: any, ...: any))?
---@return any
function prettyui.SimpleView:AddSimpleButton(labelOrSprite, onClick) end

---@param y number
function prettyui.SimpleView:SetScrollPosition(y) end

---@param delta number
function prettyui.SimpleView:ScrollBy(delta) end

---@param child ui.Component
---@param topOffset number?
function prettyui.SimpleView:ScrollToChild(child, topOffset) end

---@param height number
function prettyui.SimpleView:SetContentHeight(height) end

---@param value boolean
function prettyui.SimpleView:SetScrollable(value) end

---@param width integer
---@param height integer
function prettyui.SimpleView:SetSize(width, height) end

function prettyui.SimpleView:Destroy() end

---Deprecated alias for SimpleView; removed in PrettyUI 1.0.
prettyui.Scrollbar = prettyui.SimpleView
