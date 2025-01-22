local Async = require('cmp-kit.kit.Async')
local CompletionService = require('cmp-kit.core.CompletionService')

describe('cmp-kit.core', function()
  describe('init', function()
    it('should work on basic case', function()
      vim.cmd.enew({ bang = true })

      local service = CompletionService.new({})
      service:register_source({
        name = 'test',
        complete = function()
          return Async.run(function()
            if vim.fn.reg_executing() ~= '' then
              Async.timeout(16):await()
            end
            return {
              { label = 'label1' },
              { label = 'label2' }
            }
          end)
        end
      })
      vim.keymap.set('i', '<Plug>(complete)', function()
        service:complete({ force = true })
      end, { buffer = 0 })
      vim.keymap.set('i', '<Plug>(select_next)', function()
        local selection = service:get_selection()
        service:select(selection.index + 1, false)
      end, { buffer = 0 })

      vim.api.nvim_feedkeys('qx', 'nt', true)
      vim.api.nvim_feedkeys('o', 'nt', true)
      vim.api.nvim_feedkeys(vim.keycode('<Plug>(complete)'), 'nt', true)
      vim.api.nvim_feedkeys(vim.keycode('<Plug>(select_next)'), 'nt', true)
      vim.api.nvim_feedkeys(vim.keycode('<Esc>'), 'nt', true)
      vim.api.nvim_feedkeys('q', 'nt', true)
      vim.api.nvim_feedkeys('@x', 'nt', true)
      vim.api.nvim_feedkeys('', 'x', true)
      assert.are.same({ '', 'label1', 'label1' }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
    end)
  end)
end)
