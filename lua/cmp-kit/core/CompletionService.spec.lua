local spec = require('cmp-kit.spec')
local CompletionService = require('cmp-kit.core.CompletionService')

describe('cmp-kit.core', function()
  describe('CompletionService', function()
    it('should work on basic case', function()
      local _, source = spec.setup({
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
      service:complete()
      assert.are.equal(#state.matches, 1)
      assert.are.equal(state.matches[1].item:get_insert_text(), 'keyword')
    end)

    it('should update view on new response', function()
      local _, source = spec.setup({
        input = 'w',
        buffer_text = {
          'key|',
        },
        items = {
          { label = 'keyword' },
        },
      })
      local state = {}
      local service = CompletionService.new({
        view = {
          show = function()
            state.show_count = (state.show_count or 0) + 1
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
      service:complete()
      service:complete({ force =true })
      assert.are.equal(state.show_count, 2)
    end)
  end)
end)
