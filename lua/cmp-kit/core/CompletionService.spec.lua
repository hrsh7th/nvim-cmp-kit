local spec = require('cmp-kit.spec')
local CompletionService = require('cmp-kit.core.CompletionService')

describe('cmp-kit.core', function()
  describe('CompletionService', function()
    it('should work on basic case', function()
      local trigger_context, source = spec.setup({
        input = 'w',
        buffer_text = {
          'key|',
        },
        items = {
          { label = 'keyword' },
          { label = 'dummy' },
        },
      })
      local state = {}
      local service = CompletionService.new({
        view = {
          show = function(_, matches)
            state.matches = matches
          end,
          hide = function()
          end,
          is_visible = function()
            return true
          end,
          select = function()
          end,
          dispose = function()
          end,
        }
      })
      service:register_source(source)
      service:complete(trigger_context)
      assert.equals(#state.matches, 1)
      assert.equals(state.matches[1].item:get_insert_text(), 'keyword')
    end)
  end)
end)
