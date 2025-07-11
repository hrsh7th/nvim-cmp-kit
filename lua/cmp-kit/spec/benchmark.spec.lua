local kit = require('cmp-kit.kit')
local tailwindcss_fixture = require('cmp-kit.spec.fixtures.tailwindcss')

-- luacheck: ignore 511
if false then
  ---@diagnostic disable-next-line: duplicate-set-field
  _G.describe = function(_, fn)
    fn()
  end
  ---@diagnostic disable-next-line: duplicate-set-field
  _G.it = function(_, fn)
    fn()
  end
end

local spec = require('cmp-kit.spec')

local function run(name, fn)
  collectgarbage('collect')
  collectgarbage('stop')
  local s = vim.uv.hrtime() / 1000000
  fn()
  local e = vim.uv.hrtime() / 1000000
  print(('[%s]: elapsed time: %sms, memory: %skb'):format(name, e - s, collectgarbage('count')))
  print('\n')
  collectgarbage('restart')
end

describe('cmp-kit.misc.spec.benchmark', function()
  local input = function(text)
    local cursor = vim.api.nvim_win_get_cursor(0)
    vim.api.nvim_buf_set_text(0, cursor[1] - 1, cursor[2], cursor[1] - 1, cursor[2], { text })
    vim.api.nvim_win_set_cursor(0, { cursor[1], cursor[2] + #text })
  end
  for _, isIncomplete in ipairs({ true, false }) do
    it(('isIncomplete=%s'):format(isIncomplete), function()
      local response = tailwindcss_fixture()
      local _, _, service = spec.setup({
        buffer_text = {
          '|',
        },
        item_defaults = response.itemDefaults,
        is_incomplete = response.isIncomplete,
        items = response.items,
      })
      service:set_config(kit.merge({
        performance = {
          fetching_timeout_ms = 0,
        },
      }, service:get_config()))
      for i = 1, 3 do
        vim.cmd.enew()
        run(('isIncomplete=%s: %s'):format(isIncomplete, i), function()
          require('cmp-kit.spec').start_profile()
          input('')
          service:complete({ force = true }):sync(1 * 1000)
          input('g')
          service:complete():sync(1 * 1000)
          input('r')
          service:complete():sync(1 * 1000)
          input('o')
          service:complete():sync(1 * 1000)
          input('u')
          service:complete():sync(1 * 1000)
          input('p')
          service:complete():sync(1 * 1000)
          require('cmp-kit.spec').print_profile()
        end)
      end
    end)
  end
end)
