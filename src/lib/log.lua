--[[
  Console logging with a caller-supplied prefix.
]]

local log = {}

---@class Logger
---@field f fun(fmt: string, ...: any)

---@param prefix string tag printed as [prefix]
---@return Logger
function log.new(prefix)
  local logger = {}

  ---@param fmt string
  ---@param ... any
  function logger.f(fmt, ...)
    print(string.format("[" .. prefix .. "] " .. fmt, ...))
  end

  return logger
end

return log
