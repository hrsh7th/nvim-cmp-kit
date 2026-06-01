local lsp_completion = require('cmp-kit.completion.ext.source.lsp.completion')

describe('cmp-kit.completion.ext.source.lsp', function()
  describe('completion', function()
    it('should keep latest request cancellable after stale request settles', function()
      local requests = {}
      local client = {
        name = 'test-lsp',
        offset_encoding = 'utf-8',
        server_capabilities = {
          completionProvider = {},
        },
        _registration_provider = function(_, method)
          return method
        end,
        _get_registrations = function()
          return {}
        end,
        supports_method = function()
          return true
        end,
        request = function(_, _, _, callback)
          local request = {
            id = #requests + 1,
            callback = callback,
            cancelled = false,
          }
          table.insert(requests, request)
          return true, request.id
        end,
        cancel_request = function(_, request_id)
          requests[request_id].cancelled = true
          vim.schedule(function()
            requests[request_id].callback('cancelled', nil)
          end)
        end,
      }
      local source = lsp_completion({ client = client })

      source:complete({}, function() end)
      source:complete({}, function() end)
      vim.wait(100, function()
        return false
      end)
      source:complete({}, function() end)

      assert.is_true(requests[1].cancelled)
      assert.is_true(requests[2].cancelled)
      assert.is_false(requests[3].cancelled)
    end)
  end)
end)
