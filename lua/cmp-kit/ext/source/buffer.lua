local Async = require('cmp-kit.kit.Async')
local Buffer = require('cmp-kit.core.Buffer')

---@class cmp-kit.ext.source.buffer.Option
---@field public keyword_pattern? string
---@field public min_keyword_length? integer
---@param option cmp-kit.ext.source.buffer.Option
return function(option)
  local keyword_pattern = option and option.keyword_pattern or [[\k\+]]
  local min_keyword_length = option and option.min_keyword_length or 3

  ---@param bufs integer[]
  ---@return cmp-kit.kit.LSP.CompletionList
  local function get_items(bufs)
    local is_indexing = false
    local uniq = {}
    local items = {}
    for _, buf in ipairs(bufs) do
      is_indexing = is_indexing or Buffer.ensure(buf):is_indexing(keyword_pattern)
      local max = vim.api.nvim_buf_line_count(buf)
      for i = 0, max do
        for _, word in ipairs(Buffer.ensure(buf):get_words(keyword_pattern, i)) do
          if not uniq[word] then
            uniq[word] = true
            if #word >= min_keyword_length then
              table.insert(items, {
                label = word
              })
            end
            Async.interrupt(1, 16)
          end
        end
      end
    end
    return {
      isIncomplete = is_indexing,
      items = items,
    }
  end

  ---@type cmp-kit.core.CompletionSource
  return {
    name = 'buffer',
    complete = function()
      return Async.run(function()
        return get_items({ vim.api.nvim_get_current_buf() })
      end)
    end
  }
end
