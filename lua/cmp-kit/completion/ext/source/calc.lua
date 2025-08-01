local Async = require('cmp-kit.kit.Async')
local TriggerContext = require('cmp-kit.core.TriggerContext')

local PATTERN = [=[\s*\zs\%( \|math\.\w\+\|\d\+\%(\.\d\+\)\?\|[()*/+-,]\)\+\s*]=]

local DIGIT_ONLY = [=[^\s*\d\+\%(\.\d\+\)\?\s*$]=]

local INVALID = {
  isIncomplete = false,
  items = {},
}

---@class cmp-kit.completion.ext.source.calc.Option
return function()
  ---@type cmp-kit.completion.CompletionSource
  return {
    name = 'calc',
    get_configuration = function()
      return {
        keyword_pattern = PATTERN,
        trigger_characters = { ')', '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '.', ' ' },
      }
    end,
    complete = function(_, _, callback)
      Async.run(function()
        local ctx = TriggerContext.create()
        local off = ctx:get_keyword_offset(PATTERN)
        if not off then
          return INVALID
        end
        local candidate_text = ctx.text_before:sub(off)

        local stack = {}
        for i = #candidate_text, 1, -1 do
          local char = candidate_text:sub(i, i)
          if char == ')' then
            table.insert(stack, {
              idx = i,
              char = char,
            })
          elseif char == '(' then
            if #stack == 0 then
              return INVALID
            end
            table.remove(stack)
          end
        end

        local program = candidate_text
        if #stack > 0 then
          program = candidate_text:sub(stack[#stack].idx)
        end

        program = (program:gsub('^%s*', ''))

        if vim.regex(DIGIT_ONLY):match_str(program) then
          return INVALID
        end

        local output = assert(loadstring(('return %s'):format(program), 'calc'))()
        if type(output) ~= 'number' then
          return INVALID
        end

        return {
          isIncomplete = true,
          items = {
            {
              label = ('= %s'):format(output),
              insertText = tostring(output),
              filterText = candidate_text,
              sortText = '1',
              nvim_previewText = tostring(output),
            },
            {
              label = ('%s = %s'):format((candidate_text:gsub('%s*$', '')), output),
              insertText = ('%s = %s'):format((candidate_text:gsub('%s*$', '')), output),
              filterText = candidate_text,
              sortText = '2',
              nvim_previewText = ('%s = %s'):format((candidate_text:gsub('%s*$', '')), output),
            },
          },
        }
      end):dispatch(function(res)
        callback(nil, res)
      end, function(err)
        callback(err, nil)
      end)
    end,
  }
end
