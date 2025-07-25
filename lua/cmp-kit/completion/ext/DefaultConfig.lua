local DefaultView = require('cmp-kit.completion.ext.DefaultView')
local DefaultSorter = require('cmp-kit.completion.ext.DefaultSorter')
local DefaultMatcher = require('cmp-kit.completion.ext.DefaultMatcher')

---@type cmp-kit.completion.CompletionService.Config
return {
  view = DefaultView.new(),
  sorter = DefaultSorter,
  matcher = DefaultMatcher,
  is_macro_executing = function()
    return vim.fn.reg_executing() ~= ''
  end,
  is_macro_recording = function()
    return vim.fn.reg_recording() ~= ''
  end,
  preselect = true,
  performance = {
    fetching_timeout_ms = 300,
    menu_update_throttle_ms = 32,
  },
  default_keyword_pattern = [[\%(-\?\d\+\%(\.\d\+\)\?\|\h\w*\%(-\w*\)*\)]],
}
