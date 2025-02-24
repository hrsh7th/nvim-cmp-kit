local DefaultView = require('cmp-kit.core.DefaultView')
local DefaultSorter = require('cmp-kit.core.DefaultSorter')
local DefaultMatcher = require('cmp-kit.core.DefaultMatcher')

---@type cmp-kit.core.CompletionService.Config
return {
  view = DefaultView.new(),
  sorter = DefaultSorter.sorter,
  matcher = DefaultMatcher.matcher,
  sync_mode = function()
    return vim.fn.reg_executing() ~= ''
  end,
  performance = {
    fetching_timeout_ms = 280
  },
  default_keyword_pattern = [[\%(-\?\d\+\%(\.\d\+\)\?\|\h\w*\%(-\w*\)*\)]],
}

