--[[
  PrettyUI host: mount / update / destroy for the element protocol.

  Currently very overfit to the settings UI's use case.
]]

local prettyui_host = {}

---@alias PrettyUiHostHandle { update: (fun(vnode: Element)), destroy: (fun()) }

--- Map element choices into PrettyUI choice records.
---@param choices ElementChoice[]|nil
---@return prettyui.Choice[]
local function toPrettyChoices(choices)
  local out = {}
  if choices == nil then
    return out
  end
  for i = 1, #choices do
    local c = choices[i]
    out[i] = {
      text = c.text,
      value = c.value,
      selected = c.selected == true,
    }
  end
  return out
end

--- Mount a box element tree under `parent`.
---@param parent ui.Component
---@param vnode Element
---@return PrettyUiHostHandle
function prettyui_host.mount(parent, vnode)
  if vnode == nil or vnode.type ~= "box" then
    error("prettyui_host.mount expects a box element")
  end

  local props = vnode.props or {}
  local simpleView = prettyui.SimpleView.new(parent, {
    width = props.width,
    height = props.height,
  })

  ---@type table<any, boolean>
  local selectedByValue = {}
  ---@type (fun(value: any, selected: boolean))?
  local checkboxOnChange = nil
  ---@type prettyui.CheckboxButton|nil
  local checkbox = nil

  local children = vnode.children or {}
  for i = 1, #children do
    local child = children[i]
    if child.type == "title" then
      simpleView:AddTitle(child.props.text or "")
    elseif child.type == "checkbox_group" then
      local choices = child.props.choices or {}
      for j = 1, #choices do
        local c = choices[j]
        selectedByValue[c.value] = c.selected == true
      end
      checkboxOnChange = child.props.onChange
      checkbox = simpleView:AddCheckboxButton(toPrettyChoices(choices), {
        onChange = function(_, _, value, isSelected)
          local nextSelected = isSelected and true or false
          -- Mirror before set so our own update does not re-enter SetSelected.
          selectedByValue[value] = nextSelected
          local handler = checkboxOnChange
          if handler ~= nil then
            handler(value, nextSelected)
          end
        end,
      })
    end
  end

  --- Patch mutable bits from a new vnode (same fixed tree shape).
  ---@param next Element
  local function update(next)
    if next == nil or next.type ~= "box" then
      return
    end

    local nextChildren = next.children or {}
    for i = 1, #nextChildren do
      local child = nextChildren[i]
      if child.type == "checkbox_group" then
        checkboxOnChange = child.props.onChange
        local choices = child.props.choices or {}
        for j = 1, #choices do
          local c = choices[j]
          local nextSelected = c.selected == true
          if selectedByValue[c.value] ~= nextSelected then
            selectedByValue[c.value] = nextSelected
            if checkbox ~= nil then
              pcall(function()
                checkbox:SetSelected(c.value, nextSelected)
              end)
            end
          end
        end
      end
    end
  end

  return {
    update = update,
    destroy = function()
      simpleView:Destroy()
    end,
  }
end

return prettyui_host
