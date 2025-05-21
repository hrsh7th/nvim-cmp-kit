local Async = require('cmp-kit.kit.Async')
local LSP = require('cmp-kit.kit.LSP')
local Position = require('cmp-kit.kit.LSP.Position')
local Client = require('cmp-kit.kit.LSP.Client')
local TriggerContext = require('cmp-kit.core.TriggerContext')

---@class cmp-kit.completion.SignatureHelpService.State
---@field public trigger_context cmp-kit.completion.TriggerContext
---@field public source any

---@class cmp-kit.completion.SignatureHelpService.Config

---@class cmp-kit.completion.SignatureHelpService
---@field private _disposed boolean
---@field private _preventing integer
---@field private _state cmp-kit.completion.SignatureHelpService.State
---@field private _config cmp-kit.completion.SignatureHelpService.Config
local SignatureHelpService = {}
SignatureHelpService.__index = SignatureHelpService

---Create a new SignatureHelpService.
---@param config? cmp-kit.completion.SignatureHelpService.Config|{}
---@return cmp-kit.completion.SignatureHelpService
function SignatureHelpService.new(config)
  return setmetatable({
    _disposed = false,
    _preventing = 0,
    _config = config,
    _state = {
      trigger_context = TriggerContext.create_empty_context(),
      source = nil,
    },
  }, SignatureHelpService)
end

---Trigger.
---@param params? { force?: boolean }
---@return cmp-kit.kit.Async.AsyncTask
function SignatureHelpService:trigger(params)
  params = params or {}
  params.force = params.force or false

  local trigger_context = TriggerContext.create({ force = params.force })
  return Async.run(function()
    local raw_clients = vim.lsp.get_clients({
      method = 'textDocument/signatureHelp',
    })
    for _, raw_client in ipairs(raw_clients) do
      local client = Client.new(raw_client)
      local trigger_characters = vim.tbl_get(raw_client.server_capabilities, 'signatureHelpProvider', 'triggerCharacters') or {}
      local retrigger_characters = vim.tbl_get(raw_client.server_capabilities, 'signatureHelpProvider', 'retriggerCharacters') or {}
      local context
      if vim.tbl_contains(trigger_characters, trigger_context.before_character) then
        
      end
      client:textDocument_signatureHelp({
        textDocument = {
          uri = vim.uri_from_bufnr(trigger_context.bufnr)
        },
        position = Position.cursor(raw_client.offset_encoding or LSP.PositionEncodingKind.UTF16),
        context = {
          isRetrigger = self._state.source == client,
        }
      }):await()
    end
  end)
end

return SignatureHelpService
