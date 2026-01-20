local kit = require('cmp-kit.kit')
local Client = require('cmp-kit.kit.LSP.Client')
local Async = require('cmp-kit.kit.Async')

---@class cmp-kit.signature_help.ext.source.lsp.signature_help.Option

---@class cmp-kit.signature_help.ext.source.lsp.signature_help.OptionWithClient: cmp-kit.signature_help.ext.source.lsp.signature_help.Option
---@field public client vim.lsp.Client

---Create a signature help source for LSP client.
---@param option cmp-kit.signature_help.ext.source.lsp.signature_help.OptionWithClient
return function(option)
  local client = Client.new(option.client)

  local request = nil ---@type (cmp-kit.kit.Async.AsyncTask|{ cancel: fun(): nil })?

  ---@type cmp-kit.signature_help.SignatureHelpSource
  return {
    name = option.client.name,
    get_configuration = function()
      local options = {}
      -- static.
      local static_registration = vim.tbl_get(client.client.server_capabilities, 'signatureHelpProvider')
      if static_registration then
        options = vim.tbl_deep_extend('force', options, static_registration)
      end
      -- dynamic.
      for _, dynamic_registration in ipairs(client.client:_get_registrations(client.client:_registration_provider('textDocument/signatureHelp'), 0) or {}) do
        options = vim.tbl_deep_extend('force', options, dynamic_registration.registerOptions or {})
      end
      return {
        position_encoding_kind = option.client.offset_encoding,
        trigger_characters = options.triggerCharacters or {},
        retrigger_characters = kit.concat(options.triggerCharacters or {}, options.retriggerCharacters or {}),
      }
    end,
    capable = function(_)
      return option.client:supports_method('textDocument/signatureHelp', vim.api.nvim_get_current_buf())
    end,
    fetch = function(_, signature_help_context, callback)
      if request then
        request.cancel()
        request = nil
      end

      local position_params = vim.lsp.util.make_position_params(0, option.client.offset_encoding)
      Async.run(function()
        request = client:textDocument_signatureHelp({
          textDocument = {
            uri = position_params.textDocument.uri,
          },
          position = {
            line = position_params.position.line,
            character = position_params.position.character,
          },
          context = signature_help_context,
        })
        return request:catch(function()
          return nil
        end)
      end):dispatch(function(res)
        callback(nil, res)
      end, function(err)
        callback(err, nil)
      end)
    end,
  }
end
