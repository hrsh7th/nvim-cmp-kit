local kit = require('cmp-kit.kit')
local Client = require('cmp-kit.kit.LSP.Client')
local Async = require('cmp-kit.kit.Async')

---@class cmp-kit.ext.source.lsp.completion.Option
---@field public client vim.lsp.Client
---@param option cmp-kit.ext.source.lsp.completion.Option
return function(option)
  local client = Client.new(option.client)

  local request = nil ---@type (cmp-kit.kit.Async.AsyncTask|{ cancel: fun(): nil })?

  ---@type cmp-kit.core.CompletionSource
  return {
    name = option.client.name,
    get_configuration = function()
      return {
        position_encoding_kind = option.client.offset_encoding,
        trigger_characters = kit.get(option.client, {
          'server_capabilities',
          'completionProvider',
          'triggerCharacters'
        }, {}),
      }
    end,
    capable = function(_, trigger_context)
      if not option.client.server_capabilities then
        return false
      end
      if not option.client.server_capabilities.completionProvider then
        return false
      end
      return option.client:supports_method('textDocument/completion', trigger_context.bufnr)
    end,
    resolve = function(_, item)
      return Async.run(function()
        if option.client.server_capabilities.completionProvider.resolveProvider then
          return client:completionItem_resolve(item):await()
        end
        return item
      end)
    end,
    execute = function(_, command)
      return Async.run(function()
        return client:workspace_executeCommand({
          command = command.command,
          arguments = command.arguments
        }):await()
      end)
    end,
    complete = function(_, completion_context)
      if request then
        request.cancel()
      end

      local position_params = vim.lsp.util.make_position_params(0, option.client.offset_encoding)
      return Async.run(function()
        request = client:textDocument_completion({
          textDocument = {
            uri = position_params.textDocument.uri,
          },
          position = {
            line = position_params.position.line,
            character = position_params.position.character,
          },
          context = completion_context
        })
        local response = request:catch(function()
          return nil
        end):await()
        return response
      end)
    end
  }
end
