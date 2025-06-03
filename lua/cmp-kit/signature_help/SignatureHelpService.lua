local kit = require('cmp-kit.kit')
local Async = require('cmp-kit.kit.Async')
local TriggerContext = require('cmp-kit.core.TriggerContext')
local DefaultConfig = require('cmp-kit.signature_help.ext.DefaultConfig')
local SignatureHelpProvider = require('cmp-kit.signature_help.SignatureHelpProvider')

---Emit events.
---@generic T
---@param events fun(payload: T)[]
---@param payload T
local function emit(events, payload)
  for _, event in ipairs(events or {}) do
    event(payload)
  end
end

---@class cmp-kit.signature_help.SignatureHelpService.Config
---@field public view cmp-kit.signature_help.SignatureHelpView

---@class cmp-kit.signature_help.SignatureHelpService.ProviderConfiguration
---@field public provider cmp-kit.signature_help.SignatureHelpProvider
---@field public priority? integer

---@class cmp-kit.signature_help.SignatureHelpService.State
---@field public trigger_context cmp-kit.core.TriggerContext
---@field public active_provider? cmp-kit.signature_help.SignatureHelpProvider

---@class cmp-kit.signature_help.SignatureHelpService
---@field private _disposed boolean
---@field private _preventing integer
---@field private _events table<string, function[]>
---@field private _config cmp-kit.signature_help.SignatureHelpService.Config
---@field private _provider_configurations (cmp-kit.completion.CompletionService.ProviderConfiguration|{ index: integer })[]
---@field private _state cmp-kit.signature_help.SignatureHelpService.State
local SignatureHelpService = {}
SignatureHelpService.__index = SignatureHelpService

---Create a new SignatureHelpService.
---@param config? cmp-kit.signature_help.SignatureHelpService.Config|{}
---@return cmp-kit.signature_help.SignatureHelpService
function SignatureHelpService.new(config)
  return setmetatable({
    _disposed = false,
    _preventing = 0,
    _events = {},
    _config = kit.merge(config or {}, DefaultConfig),
    _provider_configurations = {},
    _state = {
      trigger_context = TriggerContext.create_empty_context(),
      active_provider = nil,
    }
  }, SignatureHelpService)
end

---Register source.
---@param source cmp-kit.signature_help.SignatureHelpSource
---@param config? { priority?: integer, dedup?: boolean, keyword_length?: integer, item_count?: integer }
---@return fun(): nil
function SignatureHelpService:register_source(source, config)
  ---@type cmp-kit.signature_help.SignatureHelpService.ProviderConfiguration|{ index: integer }
  local provider_configuration = {
    index = #self._provider_configurations + 1,
    priority = config and config.priority or 0,
    provider = SignatureHelpProvider.new(source),
  }
  table.insert(self._provider_configurations, provider_configuration)
  return function()
    for i, c in ipairs(self._provider_configurations) do
      if c == provider_configuration then
        table.remove(self._provider_configurations, i)
        break
      end
    end
  end
end

---Trigger.
---@param params? { force?: boolean }
---@return cmp-kit.kit.Async.AsyncTask
function SignatureHelpService:trigger(params)
  params = params or {}
  params.force = params.force or false


  if self._disposed then
    return Async.resolve()
  end
  if self._preventing > 0 then
    return Async.resolve()
  end

  local trigger_context = TriggerContext.create({ force = params.force })
  if not self._state.trigger_context:changed(trigger_context) then
    return Async.run(function() end)
  end
  self._state.trigger_context = trigger_context

  if self._config.view:is_visible() then
    local active_signature_data = self._state.active_provider and self._state.active_provider:get_active_signature_data()
    if active_signature_data then
      self._config.view:show(active_signature_data)
    end
  end

  return Async.run(function()
    for _, cfg in ipairs(self:_get_providers()) do
      if cfg.provider:capable(trigger_context) then
        local response = cfg.provider:fetch(trigger_context):await()
        if response then
          self:_update_signature_help(cfg.provider)
          return
        end
      end
    end
    self:_update_signature_help(self._state.active_provider)
  end)
end

---Select specific signature.
---@param index integer 1-origin index
function SignatureHelpService:select(index)
  if not self._state.active_provider then
    return
  end
  self._state.active_provider:select(index)
  self:_update_signature_help(self._state.active_provider)
end

---Scroll signature help.
---@param delta integer
function SignatureHelpService:scroll(delta)
  if self._config.view:is_visible() then
    self._config.view:scroll(delta)
  end
end

---Return if the signature help is visible.
---@return boolean
function SignatureHelpService:is_visible()
  return self._config.view:is_visible()
end

---Get active signature data.
---@return cmp-kit.signature_help.ActiveSignatureData|nil
function SignatureHelpService:get_active_signature_data()
  if not self._state.active_provider then
    return nil
  end
  return self._state.active_provider:get_active_signature_data()
end

---Prevent signature help.
---@return fun(): cmp-kit.kit.Async.AsyncTask
function SignatureHelpService:prevent()
  self._preventing = self._preventing + 1
  return function()
    return Async.run(function()
      Async.new(function(resolve)
        vim.api.nvim_create_autocmd('SafeState', {
          once = true,
          callback = resolve
        })
      end):await()
      self._state.trigger_context = TriggerContext.create()
      self._preventing = self._preventing - 1
    end)
  end
end

---Clear signature help.
function SignatureHelpService:clear()
  self._state = {
    trigger_context = TriggerContext.create(),
    active_provider = nil,
  }
  self._config.view:hide()
end

---Register on_dispose event.
---@param callback fun(payload: { service: cmp-kit.completion.CompletionService })
---@return fun()
function SignatureHelpService:on_dispose(callback)
  self._events = self._events or {}
  self._events.on_dispose = self._events.on_dispose or {}
  table.insert(self._events.on_dispose, callback)
  return function()
    for i, c in ipairs(self._events.on_dispose) do
      if c == callback then
        table.remove(self._events.on_dispose, i)
        break
      end
    end
  end
end

---Dispose the service.
function SignatureHelpService:dispose()
  if self._disposed then
    return
  end
  self._disposed = true

  -- Clear state.
  self:clear()

  -- Emit dispose event.
  emit(self._events.on_dispose, { service = self })
end

---Update_signature_help
---@param provider? cmp-kit.signature_help.SignatureHelpProvider
function SignatureHelpService:_update_signature_help(provider)
  if not provider then
    self._state.active_provider = nil
    self._config.view:hide()
    return
  end
  local active_signature_data = provider:get_active_signature_data()
  if not active_signature_data then
    self._state.active_provider = nil
    self._config.view:hide()
    return
  end

  self._state.active_provider = provider
  self._config.view:show(active_signature_data)
end

---Get providers.
---@return cmp-kit.signature_help.SignatureHelpService.ProviderConfiguration[]
function SignatureHelpService:_get_providers()
  table.sort(self._provider_configurations, function(a, b)
    if a.priority ~= b.priority then
      return a.priority > b.priority
    end
    return a.index < b.index
  end)
  return self._provider_configurations
end

return SignatureHelpService
