--[[
  Domain state store for NPC Smartphone options.
  Loads/persists via PersistentDB-shaped `db`; notifies via lib/observable.
]]

local observable = require("lib/observable")

local state = {}

---@alias StateKey "hideChatheads"
---@alias StateMap table<StateKey, boolean>

---@type StateKey
local KEY_HIDE_CHATHEADS = "hideChatheads"

---@type table<StateKey, boolean>
local ALLOWED_KEYS = {
  [KEY_HIDE_CHATHEADS] = true,
}

--- Persistence surface state actually uses (PersistentDB or a test fake).
--- Each `fun` is parenthesized so LuaLS does not treat `, SetBool` as a second return.
---@alias StateDb { GetBool: (fun(self: any, key: string): boolean?), SetBool: (fun(self: any, key: string, value: boolean)) }

---@alias StateSubscriber fun(key: StateKey, value: boolean)

---@class StateStore
---@field get fun(self: StateStore, key: StateKey): boolean|nil
---@field set fun(self: StateStore, key: StateKey, value: boolean): boolean
---@field subscribe fun(self: StateStore, fn: StateSubscriber): fun()

---@param db StateDb
---@return boolean
local function loadHideChatheads(db)
  local value = db:GetBool(KEY_HIDE_CHATHEADS)

  if value == nil then
    value = true
    db:SetBool(KEY_HIDE_CHATHEADS, value)
  end

  return value
end

--- Create the domain store.
---@param db StateDb
---@return StateStore
function state.new(db)
  local hideChatheads = loadHideChatheads(db)
  ---@type Observable<StateKey, boolean>
  local notifier = observable.new({
    [KEY_HIDE_CHATHEADS] = hideChatheads,
  })

  notifier:subscribe(function(key, value)
    db:SetBool(key, value)
  end)

  local store = {}

  ---@param key StateKey
  ---@return boolean|nil
  function store:get(key)
    return notifier:get(key)
  end

  ---@param fn StateSubscriber
  ---@return fun()
  function store:subscribe(fn)
    return notifier:subscribe(fn)
  end

  --- Persist known keys on change, then notify.
  --- Unknown keys are ignored (no mutate, no notify).
  ---@param key StateKey
  ---@param value boolean
  ---@return boolean true if the value changed
  function store:set(key, value)
    if not ALLOWED_KEYS[key] then
      return false
    end

    if notifier:get(key) == value then
      return false
    end

    return notifier:set(key, value)
  end

  return store
end

return state
