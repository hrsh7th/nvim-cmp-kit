local Async = require('cmp-kit.kit.Async')
local Buffer = require('cmp-kit.core.Buffer')
local DefaultConfig = require('cmp-kit.completion.ext.DefaultConfig')

---@class cmp-kit.completion.ext.source.buffer.Option
---@field public keyword_pattern? string
---@field public gather_keyword_length? integer
---@field public get_bufnrs? fun(): integer[]
---@field public label_details? cmp-kit.kit.LSP.CompletionItemLabelDetails
---@param option? cmp-kit.completion.ext.source.buffer.Option
return function(option)
  local keyword_pattern = option and option.keyword_pattern or DefaultConfig.default_keyword_pattern
  local gather_keyword_length = option and option.gather_keyword_length or 3
  local get_bufnrs = option and option.get_bufnrs or function()
    return vim.iter(vim.api.nvim_list_wins()):map(vim.api.nvim_win_get_buf):totable()
  end

  ---@param bufs integer[]
  ---@return cmp-kit.kit.LSP.CompletionList
  local function get_items(bufs)
    local is_indexing = false
    local uniq = {}
    local items = {}
    for _, buf in ipairs(bufs) do
      local max = vim.api.nvim_buf_line_count(buf)
      for i = 0, max do
        for _, word in ipairs(Buffer.ensure(buf):get_words(keyword_pattern, i)) do
          if not uniq[word] then
            uniq[word] = true
            if #word >= gather_keyword_length then
              table.insert(items, {
                label = word,
                labelDetails = option and option.label_details,
              } --[[@as cmp-kit.kit.LSP.CompletionItem]])
            end
            Async.interrupt(8, 16)
          end
        end
      end
      is_indexing = is_indexing or Buffer.ensure(buf):is_indexing(keyword_pattern)
    end
    return {
      isIncomplete = is_indexing,
      items = items,
    }
  end

  ---@type cmp-kit.completion.CompletionSource
  return {
    name = 'buffer',
    get_configuration = function()
      return {
        keyword_pattern = keyword_pattern,
      }
    end,
    complete = function(_, _, callback)
      Async.run(function()
        return get_items(get_bufnrs())
      end):dispatch(function(res)
        callback(nil, res)
      end, function(err)
        callback(err, nil)
      end)
    end,
  }
end
