local LSP = require('cmp-kit.kit.LSP')
local Async = require('cmp-kit.kit.Async')

---@enum cmp-kit.signature_help.SignatureHelpProvider.RequestState
local RequestState = {
  Waiting = 'Waiting',
  Fetching = 'Fetching',
  Completed = 'Completed',
}

---@class cmp-kit.signature_help.SignatureHelpProvider.State
---@field public request_state cmp-kit.signature_help.SignatureHelpProvider.RequestState
---@field public trigger_context? cmp-kit.core.TriggerContext
---@field public active_signature_help? cmp-kit.kit.LSP.SignatureHelp

---@class cmp-kit.signature_help.SignatureHelpProvider
---@field private _source cmp-kit.signature_help.SignatureHelpSource
---@field private _state cmp-kit.signature_help.SignatureHelpProvider.State
local SignatureHelpProvider = {}
SignatureHelpProvider.__index = SignatureHelpProvider
SignatureHelpProvider.RequestState = RequestState

---Create SignatureHelpProvider.
---@param source cmp-kit.signature_help.SignatureHelpSource
function SignatureHelpProvider.new(source)
  return setmetatable({
    _source = source,
    _state = {
      request_state = RequestState.Waiting,
      trigger_context = nil,
      active_signature_help = nil,
    },
  }, SignatureHelpProvider)
end

---Fetch signature help.
---@param trigger_context cmp-kit.core.TriggerContext
---@return cmp-kit.kit.Async.AsyncTask cmp-kit.kit.LSP.CompletionContext?
function SignatureHelpProvider:fetch(trigger_context)
  return Async.run(function()
    self._state.trigger_context = trigger_context

    local is_retrigger = self._state.request_state ~= RequestState.Waiting
    local is_triggered = is_retrigger or not not self._state.active_signature_help

    local trigger_kind --[[@as cmp-kit.kit.LSP.SignatureHelpTriggerKind]]
    local trigger_character --[[@as string?]]
    if trigger_context.force then
      trigger_kind = LSP.SignatureHelpTriggerKind.Invoked
    elseif vim.tbl_contains(self:get_trigger_characters(), trigger_context.trigger_character) or (is_triggered and vim.tbl_contains(self:get_retrigger_characters(), trigger_context.trigger_character)) then
      trigger_kind = LSP.SignatureHelpTriggerKind.TriggerCharacter
      trigger_character = trigger_context.trigger_character
    elseif is_triggered then
      trigger_kind = LSP.SignatureHelpTriggerKind.ContentChange
    end

    if not trigger_kind then
      return
    end

    local context = {
      triggerKind = trigger_kind,
      triggerCharacter = trigger_character,
      isRetrigger = is_retrigger,
      activeSignatureHelp = self._state.active_signature_help,
    } --[[@as cmp-kit.kit.LSP.SignatureHelpContext]]
    self._state.request_state = RequestState.Fetching
    local response = self._source:fetch(context):await() --[[@as cmp-kit.kit.LSP.TextDocumentSignatureHelpResponse]]
    if self._state.trigger_context ~= trigger_context then
      return
    end
    if not response or not response.signatures or #response.signatures == 0 then
      self._state.request_state = RequestState.Waiting
      self._state.active_signature_help = nil
      return
    end
    self._state.request_state = RequestState.Completed
    self._state.active_signature_help = response

    return context
  end)
end

---Clear signature help.
function SignatureHelpProvider:clear()
  self._state = {
    request_state = RequestState.Waiting,
    trigger_context = nil,
    active_signature_help = nil,
  }
end

---Check if the provider is capable for the trigger context.
---@param trigger_context cmp-kit.core.TriggerContext
---@return boolean
function SignatureHelpProvider:capable(trigger_context)
  if self._source.capable and not self._source:capable(trigger_context) then
    return false
  end
  return true
end

---Select specified signature.
---@param index integer # 1-origin
function SignatureHelpProvider:select(index)
  if not self._state.active_signature_help then
    return
  end
  index = index - 1 -- to 0-origin
  index = math.max(index, 0)
  index = math.min(index, #self._state.active_signature_help.signatures - 1)
  self._state.active_signature_help.activeSignature = index
end

---Get active signature data.
---@return cmp-kit.signature_help.ActiveSignatureData?
function SignatureHelpProvider:get_active_signature_data()
  local active_signature_help = self._state.active_signature_help
  if not active_signature_help then
    return
  end
  local active_signature_index = self:get_active_signature_index()
  if not active_signature_index then
    return
  end
  local signature = active_signature_help.signatures[active_signature_index]
  if not signature then
    return
  end
  return {
    signature = signature,
    parameter_index = self:get_active_parameter_index(),
    signature_index = active_signature_index,
    signature_count = #active_signature_help.signatures,
  }
end

---Return active signature index.
---@return integer? 1-origin index
function SignatureHelpProvider:get_active_signature_index()
  if not self._state.active_signature_help then
    return
  end
  local index = self._state.active_signature_help.activeSignature or 0
  index = math.max(index, 0)
  index = math.min(index, #self._state.active_signature_help.signatures)
  return index + 1
end

---Return active parameter index.
---@return integer? 1-origin index
function SignatureHelpProvider:get_active_parameter_index()
  local active_signature_index = self:get_active_signature_index()
  if not active_signature_index then
    return
  end
  local signature = self._state.active_signature_help.signatures[active_signature_index]
  if not signature then
    return
  end
  local index = signature.activeParameter or self._state.active_signature_help.activeParameter or 0
  index = math.max(index, 0)
  index = math.min(index, #signature.parameters)
  return index + 1
end

---Get trigger_characters.
---@return string[]
function SignatureHelpProvider:get_trigger_characters()
  if not self._source.get_configuration then
    return {}
  end
  return self._source:get_configuration().trigger_characters or {}
end

---Get retrigger_characters.
---@return string[]
function SignatureHelpProvider:get_retrigger_characters()
  if not self._source.get_configuration then
    return {}
  end
  return self._source:get_configuration().retrigger_characters or {}
end

return SignatureHelpProvider
