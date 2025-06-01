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
      v = vim.fn.synIDattr(vim.fn.synIDtrans(vim.fn.hlID(source)), key)
      if key == 'fg' or key == 'bg' or key == 'sp' then
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

inherit_hl('CmpKitDeprecated', 'Comment', { 'fg', 'bg' }, {
  default = true,
  sp = 'fg',
  strikethrough = true,
})

inherit_hl('CmpKitMarkdownAnnotateUnderlined', 'SpecialKey', { 'fg', 'bg' }, {
  default = true,
  sp = 'fg',
  underline = true,
})

inherit_hl('CmpKitMarkdownAnnotateBold', 'SpecialKey', { 'fg', 'bg' }, {
  default = true,
  bold = true,
})

inherit_hl('CmpKitMarkdownAnnotateEm', 'SpecialKey', { 'fg', 'bg' }, {
  default = true,
  sp = 'fg',
  italic = true,
  underline = true,
})

inherit_hl('CmpKitMarkdownAnnotateStrong', 'SpecialKey', { 'fg', 'bg' }, {
  default = true,
  sp = 'fg',
  italic = true,
  bold = true,
  underline = true,
})
