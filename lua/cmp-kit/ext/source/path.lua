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

  local path_components = {}
  local name_components = {}
  local i = #chars
  while i > 0 do
    local prev = chars[i - 1] or ''
    local curr = chars[i]
    if curr == '/' then
      table.insert(path_components, 1, table.concat(name_components))
      name_components = {}
    elseif escape_chars[curr] then
      if prev == '\\' then
        table.insert(name_components, 1, curr)
        table.insert(name_components, 1, '\\')
        i = i - 1
      else
        break
      end
    else
      table.insert(name_components, 1, curr)
    end
    i = i - 1
  end
  if #name_components ~= 0 then
    table.insert(path_components, 1, table.concat(name_components))
  end
  return path_components, table.concat(kit.slice(chars, 1, i), '')
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

  ---@type cmp-kit.core.CompletionSource
  return {
    name = 'path',
    get_configuration = function()
      return {
        completion_options = {
          triggerCharacters = { '/' }
        },
        keyword_pattern = [=[[^/]*]=]
      }
    end,
    complete = function()
      return Async.run(function()
        local trigger_context = TriggerContext.create()

        -- ignore by text_before.
        if trigger_context.text_before:match('^%s*//%s*$') then
          return {}
        end

        local path_components, prefix = parse_components(trigger_context.text_before)

        if #path_components <= 1 then
          return {}
        end

        -- ignore by remaining prefix pattern.
        do
          -- protocol scheme.
          if prefix:match('://$') then
            return {}
          end
          -- html tag.
          if prefix:match('<$') then
            return {}
          end
        end


        -- relative paths.
        local dirname = table.concat(kit.slice(path_components, 1, #path_components - 1), '/') .. '/'
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
