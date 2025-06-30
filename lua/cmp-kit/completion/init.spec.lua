local Async = require('cmp-kit.kit.Async')
local CompletionService = require('cmp-kit.completion.CompletionService')

describe('cmp-kit.completion', function()
  describe('init', function()
    local function create_source(name, delay)
      return {
        name = name,
        complete = function(_, _, callback)
          vim.print('complete\n')
          Async.run(function()
            Async.timeout(delay):await()
            return {
              { label = ('label-%s'):format(name) },
            }
          end):dispatch(function(res)
            callback(nil, res)
          end, function(err)
            callback(err, nil)
          end)
        end,
      }
    end

    it('should work with macro', function()
      vim.cmd.enew({ bang = true })

      local service = CompletionService.new({
        performance = {
          fetch_waiting_ms = 120,
        },
      })
      service:register_source(create_source('group1-slow-high', 80), {
        group = 1,
        priority = 1000,
      })
      service:register_source(create_source('group1-fast-low', 20), {
        group = 1,
        priority = 1,
      })
      vim.keymap.set('i', '<Plug>(complete)', function()
        if vim.fn.reg_executing() ~= '' then
          return
        end
        service:complete({ force = true })
      end, { buffer = 0 })
      vim.keymap.set('i', '<Plug>(select_next)', function()
        local selection = service:get_selection()
        service:select(selection.index + 1, false)
      end, { buffer = 0 })
      vim.keymap.set('i', '<Plug>(wait:200)', function()
        if vim.fn.reg_executing() ~= '' then
          return
        end
        vim.wait(200)
      end, { buffer = 0 })
      vim.keymap.set('n', '<Plug>(clear)', function()
        service:clear()
      end, { buffer = 0 })
      vim.keymap.set('i', '<Plug>(show_state)', function()
        vim.print(('reg_exec="%s", count="%s", line="%s"\n'):format(vim.fn.reg_executing(), #service:get_matches(), vim.api.nvim_get_current_line()))
      end, { buffer = 0 })

      vim.api.nvim_feedkeys('qx', 'n', true)
      vim.api.nvim_feedkeys(vim.keycode('o'), 'nt', true)
      vim.api.nvim_feedkeys(vim.keycode('l'), 'nt', true)
      vim.api.nvim_feedkeys(vim.keycode('<Plug>(complete)'), 'n', true)
      vim.api.nvim_feedkeys(vim.keycode('<Plug>(wait:200)'), 'n', true)
      vim.api.nvim_feedkeys(vim.keycode('<Plug>(select_next)<Plug>(show_state)'), 'nt', true)
      vim.api.nvim_feedkeys(vim.keycode('<Plug>(select_next)<Plug>(show_state)'), 'nt', true)
      vim.api.nvim_feedkeys(vim.keycode('<Plug>(select_next)<Plug>(show_state)'), 'nt', true)
      vim.api.nvim_feedkeys(vim.keycode('<Plug>(select_next)<Plug>(show_state)'), 'nt', true)
      vim.api.nvim_feedkeys(vim.keycode('<Esc>'), 'nt', true)
      vim.api.nvim_feedkeys('q', 'n', true)
      vim.api.nvim_feedkeys(vim.keycode('<Plug>(clear)'), 'n', true) -- 1st
      vim.api.nvim_feedkeys('', 'x', true)
      assert.are.same({
        '',
        'label-group1-slow-high',
      }, vim.api.nvim_buf_get_lines(0, 0, -1, false))

      -- force release prevension.
      vim.api.nvim_exec_autocmds('SafeState', { modeline = false })

      vim.api.nvim_feedkeys('@x', 'nx', true)
      assert.are.same({
        '',
        'label-group1-slow-high',
        'label-group1-slow-high',
      }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
    end)
  end)
end)
