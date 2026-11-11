--[[
  Bind a render function to a host, with optional re-render subscription.
  `mount(parent)` creates an instance.
]]

local bind = {}

---@alias BindHostHandle { update: (fun(vnode: Element)), destroy: (fun()) }
---@alias BindHost { mount: (fun(parent: ui.Component, vnode: Element): BindHostHandle) }
--- subscribe(listener) → unsubscribe. Omit for a one-shot mount.
---@alias BindSubscribe (fun(fn: fun(...: any)): fun())
---@alias BindOptions { host: BindHost, render: (fun(parent: ui.Component): Element), subscribe: BindSubscribe? }

---@class BoundViewInstance
---@field update fun(parent: ui.Component) remount under a new parent; keeps subscription
---@field unmount fun()

---@class BoundView
---@field mount fun(parent: ui.Component): BoundViewInstance

--- Create a bound view definition. Call `:mount(parent)` per surface instance.
---@param opts BindOptions
---@return BoundView
function bind.new(opts)
  local host = opts.host
  local render = opts.render
  local subscribe = opts.subscribe

  local bound = {}

  --- Attach under `parent`; subscribe (if provided) for re-renders.
  ---@param parent ui.Component
  ---@return BoundViewInstance
  function bound.mount(parent)
    local parentRef = parent
    local handle = host.mount(parentRef, render(parentRef))

    local unsubscribe = function() end
    if subscribe ~= nil then
      unsubscribe = subscribe(function()
        handle.update(render(parentRef))
      end)
    end

    local instance = {}

    --- Destroy the host tree and remount under `newParent` (same subscription).
    ---@param newParent ui.Component
    function instance.update(newParent)
      handle.destroy()
      parentRef = newParent
      handle = host.mount(parentRef, render(parentRef))
    end

    function instance.unmount()
      unsubscribe()
      handle.destroy()
    end

    return instance
  end

  return bound
end

return bind
