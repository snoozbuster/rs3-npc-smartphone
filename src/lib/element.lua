--[[
  Host-agnostic UI element (vnode) helpers.
  Components return trees of { type, props, children }; hosts bind them.
]]

local element = {}

---@class ElementChoice
---@field text string
---@field value any
---@field selected boolean?

---@class BoxElementProps
---@field width number?
---@field height number?

---@class TitleElementProps
---@field text string

---@class CheckboxGroupElementProps
---@field choices ElementChoice[]
---@field onChange (fun(value: any, selected: boolean))?

---@class BoxElement
---@field type "box"
---@field props BoxElementProps
---@field children Element[]|nil

---@class TitleElement
---@field type "title"
---@field props TitleElementProps
---@field children nil

---@class CheckboxGroupElement
---@field type "checkbox_group"
---@field props CheckboxGroupElementProps
---@field children nil

---@alias Element BoxElement|TitleElement|CheckboxGroupElement
---@alias ElementType "box"|"title"|"checkbox_group"

--- Create an element node.
---@overload fun(type_: "box", props: BoxElementProps|nil, children: Element[]|nil): BoxElement
---@overload fun(type_: "title", props: TitleElementProps|nil, children: nil): TitleElement
---@overload fun(type_: "checkbox_group", props: CheckboxGroupElementProps|nil, children: nil): CheckboxGroupElement
---@param type_ ElementType|string
---@param props table|nil
---@param children Element[]|nil
---@return Element
function element.h(type_, props, children)
  return {
    type = type_,
    props = props or {},
    children = children,
  }
end

return element
