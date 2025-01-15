local LSP = require('cmp-kit.kit.LSP')
local CompletionProvider = require('cmp-kit.core.CompletionProvider')
local TriggerContext = require('cmp-kit.core.TriggerContext')
local Async = require('cmp-kit.kit.Async')
local assert = select(2, pcall(require, 'luassert')) or _G.assert
local LinePatch = require('cmp-kit.core.LinePatch')
local CompletionService = require('cmp-kit.core.CompletionService')
local DefaultConfig = require('cmp-kit.core.DefaultConfig')

local profiling = {}

local spec = {}

---Reset test environment.
function spec.reset()
  --Create buffer.
  vim.cmd.enew({ bang = true, args = {} })
  vim.o.virtualedit = 'onemore'
  vim.o.swapfile = false
end

---@class cmp-kit.core.spec.setup.Option
---@field public buffer_text string[]
---@field public mode? 'i' | 'c'
---@field public input? string
---@field public keyword_pattern? string
---@field public position_encoding_kind? cmp-kit.kit.LSP.PositionEncodingKind
---@field public resolve? fun(item: cmp-kit.kit.LSP.CompletionItem): cmp-kit.kit.Async.AsyncTask cmp-kit.kit.LSP.CompletionItem
---@field public item_defaults? cmp-kit.kit.LSP.CompletionItemDefaults
---@field public is_incomplete? boolean
---@field public items? cmp-kit.kit.LSP.CompletionItem[]

---Setup for spec.
---@param option cmp-kit.core.spec.setup.Option
---@return cmp-kit.core.TriggerContext, cmp-kit.core.CompletionProvider, cmp-kit.core.CompletionService
function spec.setup(option)
  option.mode = option.mode or 'i'

  --Reset test environment.
  spec.reset()

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

  local target_items = option.items or { { label = 'dummy' } }

  -- Create provider.
  local provider = CompletionProvider.new({
    name = 'dummy',
    get_configuration = function()
      return {
        keyword_pattern = option.keyword_pattern or DefaultConfig.default_keyword_pattern,
        completion_options = {
          triggerCharacters = { '.' },
        },
      }
    end,
    get_position_encoding_kind = function(_)
      return option.position_encoding_kind or LSP.PositionEncodingKind.UTF8
    end,
    resolve = function(_, item)
      if not option.resolve then
        return Async.resolve(item)
      end
      return option.resolve(item)
    end,
    complete = function(_)
      return Async.resolve({
        items = target_items,
        itemDefaults = option.item_defaults,
        isIncomplete = option.is_incomplete or false,
      })
    end,
  })

  -- Create service.
  local service = CompletionService.new({})
  service:register_provider(provider, {
    group = 1,
    item_count = math.huge,
  })

  service:complete({ force = true }):sync(5000)

  -- Insert filtering query after request.
  if option.input then
    LinePatch.apply_by_func(vim.api.nvim_get_current_buf(), 0, 0, option.input):sync(5000)
  end

  ---@diagnostic disable-next-line: invisible
  return TriggerContext.create(), provider, service
end

---@param buffer_text string[]
function spec.assert(buffer_text)
  ---@type { [1]: integer, [2]: integer }
  local cursor = vim.api.nvim_win_get_cursor(0)
  for i = 1, #buffer_text do
    local s = buffer_text[i]:find('|', 1, true)
    if s then
      cursor[1] = i
      cursor[2] = s - 1
      buffer_text[i] = buffer_text[i]:gsub('|', '')
      break
    end
  end

  local ok1, err1 = pcall(function()
    assert.are.same(buffer_text, vim.api.nvim_buf_get_lines(0, 0, -1, false))
  end)
  local ok2, err2 = pcall(function()
    assert.are.same(cursor, vim.api.nvim_win_get_cursor(0))
  end)
  if not ok1 or not ok2 then
    local err = ''
    if err1 then
      if type(err1) == 'string' then
        err = err .. '\n' .. err1
      else
        ---@diagnostic disable-next-line: need-check-nil
        err = err .. err1.message
      end
    end
    if err2 then
      if type(err2) == 'string' then
        err = err .. '\n' .. err2
      else
        ---@diagnostic disable-next-line: need-check-nil
        err = err .. err2.message
      end
    end
    error(err, 2)
  end
end

function spec.start_profile()
  profiling = {}
end

function spec.on_call(name)
  if not profiling then
    return
  end
  if not profiling[name] then
    profiling[name] = 0
  end
  profiling[name] = profiling[name] + 1
end

function spec.print_profile()
  vim.print(vim.inspect(profiling))
end

return spec
