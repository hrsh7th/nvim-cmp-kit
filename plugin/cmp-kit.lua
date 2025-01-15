local debugger = require('cmp-kit.core.debugger')

vim.api.nvim_create_user_command('CmpKitDebuggerOpen', function()
  debugger.open()
end, {
  nargs = '*'
})

vim.api.nvim_create_user_command('CmpKitDebuggerToggle', function()
  debugger.enable(not debugger.enable())
end, {
  nargs = '*'
})
