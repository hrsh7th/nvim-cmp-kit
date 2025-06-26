local DefaultView = require('cmp-kit.completion.ext.DefaultView')
local DefaultSorter = require('cmp-kit.completion.ext.DefaultSorter')
local DefaultMatcher = require('cmp-kit.completion.ext.DefaultMatcher')

---@type cmp-kit.completion.CompletionService.Config
return {
  view = DefaultView.new(),
  sorter = DefaultSorter.sorter,
  matcher = DefaultMatcher.matcher,
  is_macro_executing = function()
    return vim.fn.reg_executing() ~= ''
  end,
  is_macro_recording = function()
    return vim.fn.reg_recording() ~= ''
  end,
  preselect = true,
  performance = {
    fetch_waiting_ms = 64,
    menu_show_throttle_ms = 32,
    menu_hide_debounce_ms = 160,
  },
  default_keyword_pattern = [[\%(-\?\d\+\%(\.\d\+\)\?\|\h\w*\%(-\w*\)*\)]],
}
