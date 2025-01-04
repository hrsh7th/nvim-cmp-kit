local Async = require('cmp-kit.kit.Async')

---@class cmp-kit.ext.source.lsp_signature_help.Option
---@field public client cmp-kit.kit.LSP.Client
---@param option cmp-kit.ext.source.lsp_signature_help.Option
return function(option)
  local client = assert(option.client, '`option.client` is required.')

  ---@type cmp-kit.core.CompletionSource
  return {
    name = 'lsp/signature_help',
    capable = function()
      return not not client.client.server_capabilities.signatureHelpProvider
    end,
    complete = function()
      local position_params = vim.lsp.util.make_position_params(0, )
      return Async.run(function()
        client:textDocument_signatureHelp({
        })
      end)
    end
  }
end
