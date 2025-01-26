local DefaultView = require('cmp-kit.core.DefaultView')
local DefaultSorter = require('cmp-kit.core.DefaultSorter')
local DefaultMatcher = require('cmp-kit.core.DefaultMatcher')

return {
  view = DefaultView.new(),
  sorter = DefaultSorter.sorter,
  matcher = DefaultMatcher.matcher,
  sync_mode = function()
    return vim.fn.reg_executing() ~= ''
  end,
  default_keyword_pattern = [[\%(-\?\d\+\%(\.\d\+\)\?\|\h\w*\%(-\w*\)*\)]],
}

