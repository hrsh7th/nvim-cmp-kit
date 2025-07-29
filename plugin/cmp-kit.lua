local debugger = require('cmp-kit.core.debugger')

vim.api.nvim_create_user_command('CmpKitDebuggerOpen', function()
  debugger.open()
end, {
  nargs = '*'
})

---@param name string
---@param parents string[]
---@param keys string[]
---@param opts vim.api.keyset.highlight
local function inherit_hl(name, parents, keys, opts)
  local parent = vim.iter(parents):find(function(parent_name)
    if vim.fn.hlexists(parent_name) == 1 then
      return true
    end
    return false
  end)
  if parent then
    local synid = vim.fn.synIDtrans(vim.fn.hlID(parent))
    for _, key in ipairs(keys) do
      if not opts[key] then
        local v = vim.fn.synIDattr(synid, key) --[[@as string|boolean]]
        if key == 'fg' or key == 'bg' or key == 'sp' then
          local n = tonumber(tostring(v), 10)
          v = type(n) == 'number' and tostring(n) or v
        else
          v = v == 1
        end
        opts[key] = v == '' and 'NONE' or v
      end
    end
  end
  if vim.fn.hlexists(name) == 0 then
    vim.api.nvim_set_hl(0, name, opts)
  end
end

local function on_color_scheme()
  -- markdown rendering utilities.
  inherit_hl('CmpKitMarkdownAnnotateUnderlined', { 'Special' }, { 'fg', 'bg' }, {
    default = true,
    sp = 'fg',
    underline = true,
  })
  inherit_hl('CmpKitMarkdownAnnotateBold', { 'Special' }, { 'fg', 'bg' }, {
    default = true,
    bold = true,
  })
  inherit_hl('CmpKitMarkdownAnnotateEm', { 'Special' }, { 'fg', 'bg' }, {
    default = true,
    sp = 'fg',
    bold = true,
    underline = true,
  })
  inherit_hl('CmpKitMarkdownAnnotateStrong', { 'Visual' }, { 'fg', 'bg' }, {
    default = true,
    sp = 'fg',
    bold = true,
  })
  inherit_hl('CmpKitMarkdownAnnotateCodeBlock', { 'CursorColumn' }, { 'bg' }, {
    default = true,
    blend = 30,
  })
  for _, i in ipairs({ 1, 2, 3, 4, 5, 6 }) do
    inherit_hl(('CmpKitMarkdownAnnotateHeading%s'):format(i), { 'Title' }, { 'fg', 'bg' }, {
      default = true,
      blend = 30,
    })
  end

  -- completion utilities.
  inherit_hl('CmpKitDeprecated', { 'CmpItemAbbrDeprecated', 'Comment' }, { 'fg' }, {
    default = true,
    sp = 'fg',
    strikethrough = true,
  })
  inherit_hl('CmpKitCompletionItemLabel', { 'CmpItemAbbr', 'Pmenu' }, { 'fg' }, {
    default = true,
  })
  inherit_hl('CmpKitCompletionItemDescription', { 'CmpItemMenu', 'PmenuExtra' }, { 'fg' }, {
    default = true,
  })
  inherit_hl('CmpKitCompletionItemMatch', { 'CmpItemAbbrMatch', 'PmenuMatch' }, { 'fg' }, {
    default = true,
  })
  inherit_hl('CmpKitCompletionItemExtra', { 'CmpItemMenu', 'PmenuExtra' }, { 'fg' }, {
    default = true,
  })

  -- completion item kinds.
  local LSP = require('cmp-kit.kit.LSP')
  for name in pairs(LSP.CompletionItemKind) do
    local kit_name = ('CmpKitCompletionItemKind_%s'):format(name)
    local cmp_name = ('CmpItemKind%s'):format(name)
    inherit_hl(kit_name, { cmp_name, 'PmenuKind' }, { 'fg', 'bg' }, {
      default = true
    })
  end
end
vim.api.nvim_create_autocmd({ 'ColorScheme', 'UIEnter' }, {
  pattern = '*',
  callback = on_color_scheme,
})
