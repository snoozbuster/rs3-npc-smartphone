--[[
  Generic key/value store with compare-before-set and subscribe/notify.
]]

local tables = require("lib/tables")

local observable = {}

--- In-memory observable map keyed by `K` with values of type `V`.
--- LuaLS has no `keyof`/`T[K]`, so relate get/set via `K`/`V` instead of a map shape.
---@class Observable<K, V>
---@field get fun(self: Observable<K, V>, key: K): V
---@field set fun(self: Observable<K, V>, key: K, value: V): boolean
---@field subscribe fun(self: Observable<K, V>, fn: fun(key: K, value: V)): fun()

--- Create an observable store.
---@generic K, V
---@param initial table<K, V>|nil optional initial key → value map
---@return Observable<K, V>
function observable.new(initial)
  local values = tables.clone(initial) or {}
  local subscribers = {}
  local store = {}

  function store:get(key)
    return values[key]
  end

  --- Set a value. Notifies subscribers only when the value changes.
  ---@return boolean true if the value changed
  function store:set(key, value)
    if values[key] == value then
      return false
    end
    values[key] = value

    -- Copy so unsubscribe during notify does not skip listeners.
    local snapshot = tables.clone(subscribers)
    for i = 1, #snapshot do
      snapshot[i](key, value)
    end
    return true
  end

  --- Subscribe to changes. `fn(key, value)` runs after a successful set.
  ---@return fun() unsubscribe
  function store:subscribe(fn)
    subscribers[#subscribers + 1] = fn
    return function()
      tables.removeValue(subscribers, fn)
    end
  end

  return store
end

return observable
