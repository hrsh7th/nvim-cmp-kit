local DefaultView = require('cmp-kit.completion.DefaultView')
local DefaultSorter = require('cmp-kit.completion.DefaultSorter')
local DefaultMatcher = require('cmp-kit.completion.DefaultMatcher')

---@type cmp-kit.completion.CompletionService.Config
return {
  view = DefaultView.new(),
  sorter = DefaultSorter.sorter,
  matcher = DefaultMatcher.matcher,
  sync_mode = function()
    return vim.fn.reg_executing() ~= ''
  end,
  performance = {
    fetching_timeout_ms = 120
  },
  default_keyword_pattern = [[\%(-\?\d\+\%(\.\d\+\)\?\|\h\w*\%(-\w*\)*\)]],
}

