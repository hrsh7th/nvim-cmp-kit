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

---@param name string
---@param source string
---@param keys string[]
---@param opts vim.api.keyset.highlight
local function inherit_hl(name, source, keys, opts)
  for _, key in ipairs(keys) do
    if not opts[key] then
      local v ---@type string|boolean
      v = vim.fn.synIDattr(vim.fn.hlID(source), key)
      if key == 'fg' or key == 'bg' then
        local n = tonumber(v, 10)
        v = type(n) == 'number' and tostring(n) or v
      else
        v = v == 1
      end
      opts[key] = v == '' and 'NONE' or v
    end
  end
  vim.api.nvim_set_hl(0, name, opts)
end

inherit_hl('CmpKitMarkdownAnnotate01', 'Search', { 'bg', 'fg' }, {
  default = true,
  italic = true,
  underline = true,
})
