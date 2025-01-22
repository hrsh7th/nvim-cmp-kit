local Async = require('cmp-kit.kit.Async')
local TriggerContext = require('cmp-kit.core.TriggerContext')

---@param patterns string[]
---@return vim.regex
local function create_head_regex(patterns)
  return vim.regex([[^\%(]] .. table.concat(patterns, [[\|]]) .. [[\)]])
end

---Remove by regex.
---@param text string
---@param regex vim.regex
---@return string
local function remove_regex(text, regex)
  local s, e = regex:match_str(text)
  if s and e then
    return text:sub(1, s) .. text:sub(e + 1)
  end
  return text
end

---Check if the option is boolean.
---@param o string
---@return boolean
local function is_boolean_option(o)
  local ok, v = pcall(function()
    return vim.o[o]
  end)
  if ok then
    return type(v) == 'boolean'
  end
  return false
end

local modifier_regex = create_head_regex({
  [=[\s*abo\%[veleft]\s*]=],
  [=[\s*bel\%[owright]\s*]=],
  [=[\s*bo\%[tright]\s*]=],
  [=[\s*bro\%[wse]\s*]=],
  [=[\s*conf\%[irm]\s*]=],
  [=[\s*hid\%[e]\s*]=],
  [=[\s*keepalt\s*]=],
  [=[\s*keeppa\%[tterns]\s*]=],
  [=[\s*lefta\%[bove]\s*]=],
  [=[\s*loc\%[kmarks]\s*]=],
  [=[\s*nos\%[wapfile]\s*]=],
  [=[\s*rightb\%[elow]\s*]=],
  [=[\s*sil\%[ent]\s*]=],
  [=[\s*tab\s*]=],
  [=[\s*to\%[pleft]\s*]=],
  [=[\s*verb\%[ose]\s*]=],
  [=[\s*vert\%[ical]\s*]=],
})

local count_range_regex = create_head_regex({
  [=[\s*\%(\d\+\|\$\)\%[,\%(\d\+\|\$\)]\s*]=],
  [=[\s*'\%[<,'>]\s*]=],
  [=[\s*\%(\d\+\|\$\)\s*]=],
})

local range_only_regex = create_head_regex({
  [=[\s*\%(\d\+\|\$\)\%[,\%(\d\+\|\$\)]\s*]=],
  [=[\s*'\%[<,'>]\s*]=],
  [=[\s*\%(\d\+\|\$\)\s*]=],
  [=[\s*%\s*]=],
})

local set_option_cmd_regex = create_head_regex({
  [=[\s*se\%[tlocal][^=]*]=],
})

local lua_expression_cmd_regex = create_head_regex({
  [=[\s*lua]=],
  [=[\s*lua=]=],
  [=[\s*luado]=],
})

local remove_last_arg_regex = vim.regex([=[[^[:blank:]]\+$]=])

---@class cmp-kit.ext.source.cmdline.Option
---@param option? cmp-kit.ext.source.cmdline.Option
return function(option)
  option = option or {}

  local cache = {
    cmdline = '',
    items = {},
  }

  ---@type cmp-kit.core.CompletionSource
  return {
    name = 'cmdline',
    get_configuration = function()
      return {
        keyword_pattern = [=[[^[:blank:]]\+]=]
      }
    end,
    capable = function()
      return vim.api.nvim_get_mode().mode == 'c'
    end,
    complete = function()
      return Async.run(function()
        -- create normalized cmdline.
        -- - remove modifiers
        --   - `keepalt bufdo` -> bufdo`
        -- - remove count range.
        --   - `1,$delete` -> `delete`
        -- - remove range only.
        --   - `'<,>'delete` -> `delete`
        local cmdline = TriggerContext.create().text_before
        while true do
          local prev = cmdline
          for _, regex in ipairs({ modifier_regex, count_range_regex, range_only_regex }) do
            cmdline = remove_regex(cmdline, regex)
          end
          if cmdline == prev then
            break
          end
        end
        cmdline = (cmdline:gsub('^%s+', ''))

        -- if cmd is not determined, return empty.
        local cmd = cmdline:match('^%S+') or ''
        if cmd == '' then
          return {}
        end

        -- get arg and fix for specific commands.
        local arg = cmdline:sub(#cmd + 1)
        do
          if lua_expression_cmd_regex:match_str(cmd) then
            -- - remove in-complete identifier.
            --   - `lua vim.api.nivmbuf` -> `lua vim.api.`
            arg = arg:match('%.') and (arg:gsub('%w*$', '')) or arg
          elseif set_option_cmd_regex:match_str(cmd) then
            -- - remove `no` prefix.
            --   - `set nonumber` -> `set number`
            arg = (arg:gsub('^%s*no', ''))
          end
        end

        -- invoke completion.
        local query_parts = { cmd }
        if arg ~= '' then
          table.insert(query_parts, arg)
        end
        local query = table.concat(query_parts, ' ')
        local completions = vim.fn.getcompletion(query, 'cmdline')

        -- get last argment for fixing lua expression completion.
        local offset = 0
        for i = #arg, 1, -1 do
          if arg:sub(i, i) == ' ' and arg:sub(i - 1, i - 1) ~= '\\' then
            offset = i
            break
          end
        end
        local last_arg = arg:sub(offset + 1)

        -- convert to LSP items.
        local items = {}
        local label_map = {}
        for _, completion in ipairs(completions) do
          local label = completion

          -- fix lua expression completion.
          if lua_expression_cmd_regex:match_str(cmd) then
            label = label:find(last_arg, 1, true) and label or last_arg .. label
          end

          label_map[label] = true
          table.insert(items, {
            label = label,
          })

          -- add `no` prefix for boolean options.
          if set_option_cmd_regex:match_str(cmd) and is_boolean_option(label) then
            label_map['no' .. completion] = true
            table.insert(items, {
              label = 'no' .. completion,
              filterText = completion,
            })
          end
        end

        -- append or discard cache.
        do
          local prev_leading_text = remove_regex(cache.cmdline, remove_last_arg_regex)
          local next_leading_text = remove_regex(cmdline, remove_last_arg_regex)
          if prev_leading_text == next_leading_text then
            for _, item in ipairs(cache.items) do
              if not label_map[item.label] then
                table.insert(items, item)
              end
            end
          else
            cache.cmdline = cmdline
            cache.items = items
          end
        end

        return {
          isIncomplete = true,
          items = items,
        }
      end)
    end
  }
end
