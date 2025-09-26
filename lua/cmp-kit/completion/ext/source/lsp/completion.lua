local kit = require('cmp-kit.kit')
local Client = require('cmp-kit.kit.LSP.Client')
local Async = require('cmp-kit.kit.Async')

---@class cmp-kit.completion.ext.source.lsp.completion.Option
---@field public keyword_pattern? string

---@class cmp-kit.completion.ext.source.lsp.completion.OptionWithClient: cmp-kit.completion.ext.source.lsp.completion.Option
---@field public client vim.lsp.Client
---@param option cmp-kit.completion.ext.source.lsp.completion.OptionWithClient
return function(option)
  option = option or {}
  option.client = option.client
  option.keyword_pattern = option.keyword_pattern or nil

  local client = Client.new(option.client)

  local request = nil ---@type (cmp-kit.kit.Async.AsyncTask|{ cancel: fun(): nil })?

  ---@type cmp-kit.completion.CompletionSource
  return {
    name = option.client.name,
    get_configuration = function()
      local capabilities = option.client.dynamic_capabilities:get('textDocument/completion', {
        bufnr = vim.api.nvim_get_current_buf(),
      })
      return {
        position_encoding_kind = option.client.offset_encoding,
        keyword_pattern = option.keyword_pattern,
        trigger_characters = kit.concat(
          kit.get(capabilities, { 'registerOptions', 'triggerCharacters' }, {}),
          kit.get(option.client.server_capabilities, { 'completionProvider', 'triggerCharacters' }, {})
        ),
      }
    end,
    capable = function(_)
      return option.client:supports_method('textDocument/completion', vim.api.nvim_get_current_buf())
    end,
    resolve = function(_, item, callback)
      Async.run(function()
        local capabilities = option.client.dynamic_capabilities:get('textDocument/completion', {
          bufnr = vim.api.nvim_get_current_buf(),
        })
        if kit.get(capabilities, { 'registerOptions', 'resolveProvider' }) or kit.get(option.client.server_capabilities, { 'completionProvider', 'resolveProvider' }) then
          return client:completionItem_resolve(item):await()
        end
        return item
      end):dispatch(function(res)
        callback(nil, res)
      end, function(err)
        callback(err, nil)
      end)
    end,
    execute = function(_, command, callback)
      Async.new(function(resolve, reject)
        option.client:exec_cmd(command --[[@as lsp.Command]], {
          bufnr = vim.api.nvim_get_current_buf(),
        }, function(err, result)
          if err then
            reject(err)
          else
            resolve(result)
          end
        end)
      end):dispatch(function(res)
        callback(nil, res)
      end, function(err)
        callback(err, nil)
      end)
    end,
    complete = function(_, completion_context, callback)
      if request then
        request.cancel()
      end

      local position_params = vim.lsp.util.make_position_params(0, option.client.offset_encoding)
      request = client:textDocument_completion({
        textDocument = {
          uri = position_params.textDocument.uri,
        },
        position = {
          line = position_params.position.line,
          character = position_params.position.character,
        },
        context = completion_context,
      })
      request:dispatch(function(res)
        request = nil
        callback(nil, res)
      end, function(err)
        request = nil
        callback(err, nil)
      end)
    end,
  }
end
