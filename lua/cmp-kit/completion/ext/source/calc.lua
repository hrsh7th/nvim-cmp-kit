local Async = require('cmp-kit.kit.Async')
local LSP = require('cmp-kit.kit.LSP')
local TriggerContext = require('cmp-kit.core.TriggerContext')

local INT_PART = [=[\%(\d\{1,3\}\%(,\d\{3\}\)\+\|\d\+\)]=]
local DECIMAL_PART = [=[\.\d\+]=]
local NUM2 = ([=[%s\%%(%s\)\?]=]):format(INT_PART, DECIMAL_PART)
local DIGIT_ONLY = ([=[^\s*%s\s*$]=]):format(NUM2)
local MATH_FUNCTION_CALL = [=[math\.\w\+([^)]*)]=]
local PATTERN = ([=[\%%(^\|\s*\)\zs\%%( \|%s\|math\.\w\+\|%s\|[()*/+\-]\)\+\s*\%%(\s*=\s*\)\?]=]):format(
  MATH_FUNCTION_CALL,
  NUM2
)

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
        position_encoding_kind = LSP.PositionEncodingKind.UTF8,
        keyword_pattern = PATTERN,
        trigger_characters = { ')', '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '.', ' ', '=' },
      }
    end,
    complete = function(_, _, callback)
      Async.run(function()
        local ctx = TriggerContext.create()
        local off = ctx:get_keyword_offset(PATTERN)
        if not off then
          return INVALID
        end
        local leading_text = ctx.text_before:sub(off)

        --- ignore if prefix pattern matches the date-like strings
        do
          for _, pat in ipairs({
            '%d%d%d%d%-%d%d%-%d%d%s*$', -- 2024-01-30
            '%d%d%d%d/%d%d/%d%d%s*$',   -- 2024/01/30
            '%d%d/%d%d/%d%d%d%d%s*$',   -- 01/30/2024
          }) do
            if leading_text:match(pat) then
              return INVALID
            end
          end
        end

        local ok_idx = 1
        local stack = {}
        for i = #leading_text, 1, -1 do
          local char = leading_text:sub(i, i)
          if char == ')' then
            table.insert(stack, {
              idx = i,
              char = char,
            })
          elseif char == '(' then
            if #stack == 0 then
              ok_idx = i + 1
              break
            end
            table.remove(stack)
          end
        end

        local program = leading_text:gsub('%s*=%s*$', ''):sub(ok_idx)
        if #stack > 0 then
          program = leading_text:sub(stack[#stack].idx)
        end
        program = program:gsub('^%s*', ''):gsub('%s*$', '')

        if program == '' then
          return INVALID
        end

        if vim.regex(DIGIT_ONLY):match_str(program) then
          return INVALID
        end

        -- remove , except in math functions
        local fixed_program_parts = {}
        local i = 1
        while i <= #program do
          local func_s, func_e = program:find('math%.%w+%b()', i)
          if type(func_s) == 'number' and func_s == i then
            table.insert(fixed_program_parts, program:sub(func_s, func_e))
            i = func_e + 1
          else
            if program:sub(i, i) ~= ',' then
              table.insert(fixed_program_parts, program:sub(i, i))
            end
            i = i + 1
          end
        end
        program = table.concat(fixed_program_parts)

        local chunk = loadstring(('return %s'):format(program), 'calc')
        if not chunk then
          return INVALID
        end
        local ok, output = pcall(chunk)
        if not ok then
          return INVALID
        end
        if type(output) ~= 'number' then
          return INVALID
        end

        return {
          isIncomplete = true,
          items = {
            {
              label = ('= %s'):format(output),
              filterText = leading_text,
              sortText = '1',
              nvim_previewText = tostring(output),
              textEdit = {
                newText = tostring(output),
                range = {
                  start = {
                    line = ctx.line,
                    character = off + ok_idx - 2,
                  },
                  ['end'] = {
                    line = ctx.line,
                    character = ctx.character,
                  },
                },
              },
            },
            {
              label = ('%s = %s'):format((program:gsub('%s*$', '')), output),
              filterText = leading_text,
              sortText = '2',
              nvim_previewText = ('%s = %s'):format((program:gsub('%s*$', '')), output),
              commitCharacters = { '=' },
              textEdit = {
                newText = ('%s = %s'):format((program:gsub('%s*$', '')), output),
                range = {
                  start = {
                    line = ctx.line,
                    character = off + ok_idx - 2,
                  },
                  ['end'] = {
                    line = ctx.line,
                    character = ctx.character,
                  },
                },
              },
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
