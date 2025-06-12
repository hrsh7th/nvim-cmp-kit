local spec = require('cmp-kit.spec')
local CompletionService = require('cmp-kit.completion.CompletionService')

describe('cmp-kit.completion', function()
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
          is_menu_visible = function()
            return true
          end,
          is_docs_visible = function()
            return false
          end,
          select = function()
          end,
          scroll_docs = function()
          end,
          dispose = function()
          end,
        }
      })
      service:_set_schedule_fn(vim.schedule)
      service:register_source(source)
      service:complete()
      vim.wait(500, function()
        return not not state.matches
      end)
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
          is_menu_visible = function()
            return true
          end,
          is_docs_visible = function()
            return false
          end,
          select = function()
          end,
          scroll_docs = function()
          end,
          dispose = function()
          end,
        }
      })
      service:_set_schedule_fn(vim.schedule)
      service:register_source(source)
      service:complete()
      vim.wait(500, function()
        return state.show_count == 1
      end)
      service:complete({ force = true })
      vim.wait(500, function()
        return state.show_count == 2
      end)
      assert.are.equal(state.show_count, 2)
    end)
  end)
end)
