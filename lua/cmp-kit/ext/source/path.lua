local kit = require('cmp-kit.kit')
local IO = require('cmp-kit.kit.IO')
local Async = require('cmp-kit.kit.Async')
local TriggerContext = require('cmp-kit.core.TriggerContext')

local escape_chars = {
  [' '] = true,
  ['\\'] = true,
  ['*'] = true,
  ['?'] = true,
  ['['] = true,
  [']'] = true,
  ['{'] = true,
  ['}'] = true,
  ['|'] = true,
  ['<'] = true,
  ['>'] = true,
  [';'] = true,
  ['&'] = true,
  ['"'] = true,
  ["'"] = true,
  ['`'] = true,
  ['#'] = true,
  ['!'] = true,
}

---Return path components before the cursor.
---@param before_text string
---@return string[], string
local function parse_components(before_text)
  local chars = vim.iter(vim.fn.str2list(before_text, true)):map(function(n)
    return vim.fn.nr2char(n, true)
  end):totable()

  local path_parts = {}
  local name_chars = {}
  local i = #chars
  while i > 0 do
    local prev_char = chars[i - 1] or ''
    local curr_char = chars[i]
    if curr_char == '/' then
      table.insert(path_parts, 1, table.concat(name_chars))
      name_chars = {}
    elseif escape_chars[curr_char] then
      if prev_char == '\\' then
        table.insert(name_chars, 1, curr_char)
        table.insert(name_chars, 1, '\\')
        i = i - 1
      else
        break
      end
    else
      table.insert(name_chars, 1, curr_char)
    end
    i = i - 1
  end
  table.insert(path_parts, 1, table.concat(name_chars))
  return path_parts, table.concat(kit.slice(chars, 1, i), '')
end

---@class cmp-kit.ext.source.path.Option
---@field public get_cwd? fun(): string
---@field public enable_file_document? boolean
---@param option? cmp-kit.ext.source.path.Option
return function(option)
  option = option or {}
  option.get_cwd = option.get_cwd or function()
    local bufname = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ':p')
    if vim.fn.filereadable(bufname) == 1 then
      return vim.fn.fnamemodify(bufname, ':h')
    end
    if vim.fn.isdirectory(bufname) == 1 then
      return bufname
    end
    return vim.fn.getcwd()
  end
  option.enable_file_document = option.enable_file_document == nil and true or option.enable_file_document

  ---@type cmp-kit.completion.CompletionSource
  return {
    name = 'path',
    get_configuration = function()
      return {
        keyword_pattern = [=[[^/]*]=],
        trigger_characters = { '/' },
      }
    end,
    complete = function()
      return Async.run(function()
        local trigger_context = TriggerContext.create()

        -- ignore by text_before.
        if trigger_context.text_before:match('^%s*//%s*$') then
          return {}
        end

        -- parse path components.
        local path_components, prefix = parse_components(trigger_context.text_before)
        if #path_components <= 0 then
          return {}
        end

        -- check path_components is valid.
        local is_valid_path = false
        is_valid_path = is_valid_path or path_components[1] == ''
        is_valid_path = is_valid_path or path_components[1] == 'file:'
        is_valid_path = is_valid_path or path_components[1]:match('%$[%w_]+')
        is_valid_path = is_valid_path or path_components[1]:match('%${[%w_]}+')
        is_valid_path = is_valid_path or path_components[1] == '.'
        is_valid_path = is_valid_path or path_components[1] == '..'
        is_valid_path = is_valid_path or path_components[1] == '~'
        if not is_valid_path then
          return {}
        end

        local dirname = table.concat(kit.slice(path_components, 1, #path_components - 1), '/') .. '/'

        -- skip or convert by condition.
        do
          -- html tag.
          if prefix:match('<$') then
            return {}
          end
          -- comment
          if prefix:match('^%s*$') and dirname:match('^/') and (vim.o.commentstring:gsub('^%s*', '')):sub(1, 1) == '/' then
            return {}
          end
          -- math expression.
          if prefix:match('[)%d]%s*$') and dirname:match('^/') then
            return {}
          end
          -- fix file://.
          if dirname:match('^file://') then
            dirname = dirname:sub(8)
          end
        end

        -- normalize dirname.
        if dirname:match('^%./') or dirname:match('^%.%./') then
          dirname = vim.fn.fnamemodify(option.get_cwd() .. '/' .. dirname, ':p')
        end
        dirname = vim.fn.expand(dirname)

        -- invalid dirname.
        if vim.fn.isdirectory(dirname) == 0 then
          return {}
        end

        -- convert to LSP items.
        local items = {}
        for entry in IO.iter_scandir(dirname):await() do
          local kind = vim.lsp.protocol.CompletionItemKind.File
          if entry.type == 'directory' then
            kind = vim.lsp.protocol.CompletionItemKind.Folder
          end
          table.insert(items, {
            label = vim.fs.basename(entry.path),
            kind = kind,
            data = entry,
          })
          Async.interrupt(8, 16)
        end
        table.sort(items, function(a, b)
          local is_directory_a = a.data.type == 'directory'
          local is_directory_b = b.data.type == 'directory'
          if is_directory_b ~= is_directory_a then
            return is_directory_a
          end
          return a.label < b.label
        end)
        return items
      end)
    end,
    resolve = function(_, item)
      return Async.run(function()
        if item.data.type == 'file' and option.enable_file_document then
          -- read file.
          local contents = vim.split(IO.read_file(item.data.path):catch(function()
            return ''
          end):await(), '\n')

          -- resolve filetype
          local filetype = vim.filetype.match({
            contents = contents,
            filename = item.data.path,
          })

          -- trim contents.
          if #contents > 120 then
            contents = vim.list_slice(contents, 1, 10)
            table.insert(contents, '...')
          end

          -- markdown.
          table.insert(contents, 1, ('```%s'):format(filetype))
          table.insert(contents, '```')

          return kit.merge(item, {
            documentation = {
              kind = vim.lsp.protocol.MarkupKind.Markdown,
              value = table.concat(contents, '\n'),
            },
          })
        end
      end)
    end
  }
end
