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
      local trigger_characters = kit.get(option.client, {
        'server_capabilities',
        'signatureHelpProvider',
        'triggerCharacters',
      }, {})
      local retrigger_characters = kit.get(option.client, {
        'server_capabilities',
        'signatureHelpProvider',
        'retriggerCharacters',
      }, {})
      return {
        position_encoding_kind = option.client.offset_encoding,
        trigger_characters = trigger_characters,
        retrigger_characters = kit.concat(trigger_characters, retrigger_characters),
      }
    end,
    capable = function(_)
      if not option.client.server_capabilities then
        return false
      end
      if not option.client.server_capabilities.signatureHelpProvider then
        return false
      end
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
