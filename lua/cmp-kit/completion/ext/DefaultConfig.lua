local DefaultView = require('cmp-kit.completion.ext.DefaultView')
local DefaultSorter = require('cmp-kit.completion.ext.DefaultSorter')
local DefaultMatcher = require('cmp-kit.completion.ext.DefaultMatcher')

---@type cmp-kit.completion.CompletionService.Config
return {
  view = DefaultView.new(),
  sorter = DefaultSorter.sorter,
  matcher = DefaultMatcher.matcher,
  sync_mode = function()
    return vim.fn.reg_executing() ~= ''
  end,
  preselect = true,
  performance = {
    fetching_timeout_ms = 48
  },
  default_keyword_pattern = [[\%(-\?\d\+\%(\.\d\+\)\?\|\h\w*\%(-\w*\)*\)]],
}

