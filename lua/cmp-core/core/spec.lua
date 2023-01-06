local LSP = require('cmp-core.kit.LSP')
local CompletionProvider = require('cmp-core.core.CompletionProvider')
local CompletionItem = require('cmp-core.core.CompletionItem')
local LineContext = require('cmp-core.core.LineContext')
local Async = require('cmp-core.kit.Async')

local spec = {}

---@class cmp-core.core.spec.setup.Option
---@field public mode? 'i' | 'c'
---@field public input? string
---@field public buffer_text string[]
---@field public keyword_pattern? string
---@field public position_encoding_kind? cmp-core.kit.LSP.PositionEncodingKind
---@field public resolve? fun(item: cmp-core.kit.LSP.CompletionItem): cmp-core.kit.Async.AsyncTask cmp-core.kit.LSP.CompletionItem
---@field public item_defaults? cmp-core.kit.LSP.CompletionList.itemDefaults
---@field public item cmp-core.kit.LSP.CompletionItem

---@param option cmp-core.core.spec.setup.Option
---@return cmp-core.LineContext, cmp-core.CompletionItem
function spec.setup(option)
  option.mode = option.mode or 'i'

  --Create buffer.
  vim.cmd.enew({ bang = true, args = {} })
  vim.o.virtualedit = 'onemore'
  vim.o.swapfile = false

  --Setup context and buffer text and cursor position.
  if option.mode == 'i' then
    vim.api.nvim_buf_set_lines(0, 0, -1, false, option.buffer_text)
    for i = 1, #option.buffer_text do
      local s = option.buffer_text[i]:find('|', 1, true)
      if s then
        vim.api.nvim_win_set_cursor(0, { i, s - 1 })
        vim.api.nvim_set_current_line((option.buffer_text[i]:gsub('|', '')))
        break
      end
    end
  elseif option.mode == 'c' then
    local pos = option.buffer_text[1]:find('|', 1, true)
    local text = option.buffer_text[1]:gsub('|', '')
    vim.fn.setcmdline(text, pos)
  end

  local context = LineContext.create()
  if not option.item then
    return context, { label = 'dummy' }
  end

  local provider = CompletionProvider.new({
    get_position_encoding_kind = function(_)
      return option.position_encoding_kind or LSP.PositionEncodingKind.UTF8
    end,
    get_keyword_pattern = function(_)
      return option.keyword_pattern or [[\%(-\?\d\+\%(\.\d\+\)\?\|\h\w*\%(-\w*\)*\)]]
    end,
    resolve = function(item)
      if not option.resolve then
        return Async.resolve(item)
      end
      return option.resolve(item)
    end,
    complete = function(_)
      return Async.resolve({
        items = { option.item },
        itemDefaults = option.item_defaults,
        isIncomplete = false,
      })
    end,
  })
  local list = provider:complete(context):sync() --[[@as cmp-core.kit.LSP.CompletionList]]
  local item = CompletionItem.new(context, provider, list, list.items[1])

  if option.mode ~= 'c' and option.input then
    local text = vim.api.nvim_get_current_line()
    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    local before = text:sub(1, col - 1)
    local after = text:sub(col)
    vim.api.nvim_set_current_line(before .. option.input .. after)
    vim.api.nvim_win_set_cursor(0, { row, col + #option.input })
  end

  return context, item
end

return spec
