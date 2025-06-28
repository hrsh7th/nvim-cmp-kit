local ScheduledTimer = require('cmp-kit.kit.Async.ScheduledTimer')

---Get current ms.
---@return integer
local function now_ms()
  return vim.uv.hrtime() / 1e6
end

---@class cmp-kit.kit.Async.Timing.Handle
---@field public timeout_ms integer
---@field public timer cmp-kit.kit.Async.ScheduledTimer

---@alias cmp-kit.kit.Async.Timing.TimingFunction fun() | cmp-kit.kit.Async.Timing.Handle

local Timing = {}

---Create debounced callback.
---@param callback fun()
---@param timeout_ms integer
---@return cmp-kit.kit.Async.Timing.TimingFunction
function Timing.debounce(callback, timeout_ms)
  local timer = ScheduledTimer.new()
  local arguments --[=[@as unknown[]?]=]
  return setmetatable({
    timeout_ms = timeout_ms,
    timer = timer,
    flush = function()
      if arguments then
        timer:stop()
        callback(unpack(arguments))
        arguments = nil
      end
    end,
  }, {
    __call = function(self, ...)
      arguments = { ... }

      timer:stop()
      timer:start(self.timeout_ms, 0, function()
        timer:stop()
        callback(unpack(arguments))
        arguments = nil
      end)
    end,
  })
end

---Create throttled callback.
---First call will be called immediately.
---@param callback fun()
---@param timeout_ms integer
---@return cmp-kit.kit.Async.Timing.TimingFunction
function Timing.throttle(callback, timeout_ms)
  local timer = ScheduledTimer.new()
  local arguments --[=[@as unknown[]?]=]
  local last_ms = 0
  return setmetatable({
    timeout_ms = timeout_ms,
    timer = timer,
    flush = function()
      if arguments then
        timer:stop()
        callback(unpack(arguments))
        arguments = nil
      end
    end
  }, {
    __call = function(self, ...)
      arguments = { ... }

      local delay_ms = self.timeout_ms - (now_ms() - last_ms)
      timer:stop()
      timer:start(math.max(delay_ms, 0), 0, function()
        timer:stop()
        last_ms = now_ms()
        callback(unpack(arguments))
        arguments = nil
      end)
    end,
  })
end

return Timing
