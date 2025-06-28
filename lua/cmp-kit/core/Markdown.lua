-- Credits: https://github.com/folke/noice.nvim/blob/main/lua/noice/text/treesitter.lua

local kit = require('cmp-kit.kit')

---@class cmp-kit.completion.Markdown.Range
---@field public [1] integer
---@field public [2] integer
---@field public [3] integer
---@field public [4] integer

---@class cmp-kit.completion.Markdown.Extmark
---@field public row integer
---@field public col integer
---@field public end_row? integer
---@field public end_col? integer
---@field public hl_group? string
---@field public virt_text? deck.VirtualText[]
---@field public virt_text_pos? 'eol' | 'overlay' | 'right_align' | 'inline'
---@field public virt_text_win_col? integer
---@field public virt_text_hide? boolean
---@field public virt_text_repeat_linebreak? boolean
---@field public virt_lines? deck.VirtualText[][]
---@field public virt_lines_above? boolean
---@field public ephemeral? boolean
---@field public priority? integer
---@field public sign_text? string
---@field public sign_hl_group? string
---@field public number_hl_group? string
---@field public line_hl_group? string
---@field public conceal? string
---@field public url? string

---@class cmp-kit.completion.Markdown.CodeBlockSection
---@field public type 'code_block'
---@field public language? string
---@field public contents string[]
---@class cmp-kit.completion.Markdown.MarkdownSection
---@field public type 'markdown'
---@field public contents string[]
---@class cmp-kit.completion.Markdown.SeparatorSection
---@field public type 'separator'
---@class cmp-kit.completion.Markdown.HeadingSection
---@field public type 'heading'
---@field public level integer
---@field public title string
---@alias cmp-kit.completion.Markdown.Section cmp-kit.completion.Markdown.CodeBlockSection|cmp-kit.completion.Markdown.MarkdownSection|cmp-kit.completion.Markdown.SeparatorSection|cmp-kit.completion.Markdown.HeadingSection

local Markdown = {}

local escaped_characters = { '\\', '`', '*', '_', '{', '}', '[', ']', '<', '>', '(', ')', '#', '+', '-', '.', '!', '|' }

local special_highlights = {
  {
    s = '<u>',
    e = '</u>',
    hl_group = 'CmpKitMarkdownAnnotateUnderlined',
  },
  {
    s = '<b>',
    e = '</b>',
    hl_group = 'CmpKitMarkdownAnnotateBold',
  },
  {
    s = '<em>',
    e = '</em>',
    hl_group = 'CmpKitMarkdownAnnotateEm',
  },
  {
    s = '<strong>',
    e = '</strong>',
    hl_group = 'CmpKitMarkdownAnnotateStrong',
  },
}

---Trim empty lines.
---@param contents string[]
---@return string[]
local function trim_empty_lines(contents)
  contents = kit.clone(contents)
  for i = 1, #contents do
    if contents[i] == '' then
      table.remove(contents, i)
      i = i - 1
    else
      break
    end
  end
  for i = #contents, 1, -1 do
    if contents[i] == '' then
      table.remove(contents, i)
    else
      break
    end
  end
  return contents
end

---Resolve special highlights.
---@param text string
---@return string, cmp-kit.completion.Markdown.Extmark[]
local function resolve_special_highlights(text)
  local extmarks = {}
  for _, highlight in ipairs(special_highlights) do
    local s_idx1, s_idx2 = text:find(highlight.s, 1, true)
    if s_idx1 and s_idx2 then
      text = text:sub(1, s_idx1 - 1) .. text:sub(s_idx2 + 1)
      local e_idx1, e_idx2 = text:find(highlight.e, s_idx2 + 1, true)
      if e_idx1 and e_idx2 then
        text = text:sub(1, e_idx1 - 1) .. text:sub(e_idx2 + 1)
        table.insert(extmarks, {
          col = s_idx1 - 1,
          end_col = e_idx1 - 1,
          hl_group = highlight.hl_group,
          hl_mode = 'combine',
          priority = 20000,
        })
      end
    end
  end
  return text, extmarks
end

---Prepare markdown contents.
---@param raw_contents string[]
---@return string[], table<string, cmp-kit.completion.Markdown.Range[]>, cmp-kit.completion.Markdown.Extmark[]
local function prepare_markdown_contents(raw_contents)
  ---@type cmp-kit.completion.Markdown.Section[]
  local sections = {}

  -- parse sections.
  do
    ---@type cmp-kit.completion.Markdown.Section
    local current = {
      type = 'markdown',
      contents = {},
    }
    for _, content in ipairs(raw_contents) do
      if content:match('^```') then
        if current.type == 'markdown' then
          table.insert(sections, current)
          local language = content:match('^```(.*)')
          language = language:gsub('^%s*', ''):gsub('%s*$', '')
          language = language ~= '' and language or nil
          current = {
            type = 'code_block',
            language = language,
            contents = {},
          }
        else
          table.insert(sections, current)
          current = {
            type = 'markdown',
            contents = {},
          }
        end
      else
        if current.type == 'markdown' and content:match('^---+$') then
          table.insert(sections, current)
          table.insert(sections, {
            type = 'separator',
          })
          current = {
            type = 'markdown',
            contents = {},
          }
        elseif current.type == 'markdown' and content:match('^#+ .*$') then
          table.insert(sections, current)
          table.insert(sections, {
            type = 'heading',
            level = content:match('^#+'):len(),
            title = content:match('^#+%s*(.*)$'),
          })
          current = {
            type = 'markdown',
            contents = {},
          }
        else
          table.insert(current.contents, content)
        end
      end
    end
    table.insert(sections, current)
  end

  -- fix sections for readability.
  for i = #sections, 1, -1 do
    local section = sections[i]
    if section.type == 'code_block' then
      section.contents = trim_empty_lines(section.contents)
      if #section.contents == 0 then
        table.remove(sections, i)
      end
    elseif section.type == 'markdown' then
      section.contents = trim_empty_lines(section.contents)

      -- shrink linebreak for markdown rules.
      for j = #section.contents, 1, -1 do
        if section.contents[j - 1] ~= '' and section.contents[j] == '' then
          table.remove(section.contents, j)
        end
      end

      if #section.contents == 0 then
        table.remove(sections, i)
      end
    end
  end

  -- parse annotations.
  local contents = {} ---@type string[]
  local languages = {} ---@type table<string, cmp-kit.completion.Markdown.Range>
  local extmarks = {} ---@type cmp-kit.completion.Markdown.Extmark[]
  for i, section in ipairs(sections) do
    -- insert empty lines between different sections.
    if i > 1 and #sections > 1 and section.type ~= 'separator' and sections[i - 1].type ~= 'separator' then
      table.insert(contents, '')
    end

    if section.type == 'code_block' then
      -- add empty lines for top and bottom.
      if i > 1 and #contents > 1 then
        table.insert(section.contents, 1, '')
        table.insert(section.contents, '')
      end

      -- add concrete contents.
      local s = #contents + 1
      for _, content in ipairs(section.contents) do
        local sp_content, sp_marks = resolve_special_highlights(content)
        table.insert(contents, sp_content)
        for _, mark in ipairs(sp_marks) do
          mark.row = #contents - 1
          mark.end_row = #contents - 1
          table.insert(extmarks, mark)
        end
      end
      local e = #contents

      -- 1. first code_block does not have area highlight.
      -- 2. oneline code_block does not have area highlight.
      if i > 1 and #contents > 1 then
        table.insert(extmarks, {
          row = s - 1,
          col = 0,
          end_row = e,
          end_col = 0,
          hl_group = 'CmpKitMarkdownAnnotateCodeBlock',
          hl_eol = true,
        })
      else
        table.insert(extmarks, {
          row = s - 1,
          col = 0,
          end_row = e,
          end_col = 0,
          hl_group = 'Normal',
          hl_mode = 'combine',
        })
      end
      if section.language then
        languages[section.language] = languages[section.language] or {}
        table.insert(languages[section.language], { s - 1, 0, e - 1, #contents[#contents] })
      end
    elseif section.type == 'markdown' then
      local s = #contents + 1
      for _, content in ipairs(section.contents) do
        -- check conceals.
        for j = 1, #content do
          local c = content:sub(j, j)
          if c == '\\' then
            -- escape sequence.
            -- @see https://github.com/mattcone/markdown-guide/blob/master/_basic-syntax/escaping-characters.md
            local n = content:sub(j + 1, j + 1)
            if vim.tbl_contains(escaped_characters, n) then
              table.insert(extmarks, {
                row = #contents,
                col = j - 1,
                end_row = #contents,
                end_col = j,
                conceal = '',
              })
              j = j + 1
            end
          elseif c:match('%d') then
            -- TODO: hack for nvim's treesitter.
            -- emphasised text with %d pattern does not highlighted correctly. e.g.: `__some_text_123__`
            local n1 = content:sub(j + 1, j + 1)
            local n2 = content:sub(j + 2, j + 2)
            if n1 == '_' and n2 == '_' then
              content = ('%s.%s'):format(content:sub(1, j), content:sub(j + 1))
              table.insert(extmarks, {
                row = #contents,
                col = j,
                end_row = #contents,
                end_col = j + 1,
                conceal = '',
              })
              j = j + 2
            end
          elseif c == '[' then
            -- TODO: hack for neovim's conceal and wrap behavior.
            -- markdown's link syntax can have long concealed text. it makes text wrap by concealed text.
            -- so we trim markdown's link syntax here.
            local link_s, link_e = content:find('%b[]%b()', j)
            if link_s and link_e then
              local url = content:match('%b[](%b())', j):sub(2, -2)
              local name_s, name_e = content:find('%b[]')
              local name = content:sub(name_s + 1, name_e - 1)
              content = content:gsub('%b[]%b()', name)
              table.insert(extmarks, {
                row = #contents,
                col = j - 1,
                end_row = #contents,
                end_col = j + #name - 1,
                hl_group = '@markup.link.label.markdown_inline',
                hl_mode = 'combine',
                url = url,
              })
              j = j + #name - 1
            end
          end
        end
        local sp_content, sp_marks = resolve_special_highlights(content)
        table.insert(contents, sp_content)
        for _, mark in ipairs(sp_marks) do
          mark.row = #contents - 1
          mark.end_row = #contents - 1
          table.insert(extmarks, mark)
        end
      end
      local e = #contents
      languages['markdown_inline'] = languages['markdown_inline'] or {}
      table.insert(languages['markdown_inline'], { s - 1, 0, e - 1, #contents[#contents] })
    elseif section.type == 'separator' then
      table.insert(extmarks, {
        row = #contents - 1,
        col = 0,
        end_row = #contents - 1,
        end_col = 0,
        virt_lines = { { { ('─'):rep(vim.o.columns) } } }
      })
    elseif section.type == 'heading' then
      local heading_hl_group = ('CmpKitMarkdownAnnotateHeading%s'):format(section.level)
      table.insert(extmarks, {
        row = #contents - 1,
        col = 0,
        end_row = #contents - 1,
        end_col = 0,
        virt_lines = {
          {
            { ('#'):rep(section.level), heading_hl_group },
            { ' ' },
            { section.title,            heading_hl_group },
          },
          {
            { ('─'):rep(vim.o.columns) }
          }
        }
      })
    end
  end
  return contents, languages, extmarks
end

---Set markdown contents to the buffer.
---@param bufnr integer
---@param ns_id integer
---@param raw_contents string[]
function Markdown.set(bufnr, ns_id, raw_contents)
  vim.b[bufnr].cmp_kit_markdown_revision = vim.b[bufnr].cmp_kit_markdown_revision or 0
  vim.b[bufnr].cmp_kit_markdown_revision = vim.b[bufnr].cmp_kit_markdown_revision + 1

  -- language highlights.
  local contents, languages, extmarks = prepare_markdown_contents(raw_contents)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, contents)
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
  for maybe_language, ranges in pairs(languages) do
    local language = vim.treesitter.language.get_lang(maybe_language) or maybe_language
    local ok, parser = pcall(vim.treesitter.languagetree.new, bufnr, language)
    if ok then
      ---@diagnostic disable-next-line: invisible
      parser:set_included_regions(
        vim
        .iter(ranges)
        :map(function(range)
          return { range }
        end)
        :totable()
      )
      parser:parse(true, function(err)
        if vim.b[bufnr].cmp_kit_markdown_revision ~= vim.b[bufnr].cmp_kit_markdown_revision then
          parser:destroy()
          return
        end
        if err then
          return
        end
        parser:for_each_tree(function(tree, ltree)
          local highlighter = vim.treesitter.highlighter.new(ltree, {})
          local highlighter_query = highlighter:get_query(language)
          for capture, node, metadata in highlighter_query:query():iter_captures(tree:root(), bufnr) do
            ---@diagnostic disable-next-line: invisible
            local hl_id = highlighter_query:get_hl_from_capture(capture)
            if hl_id then
              local start_row, start_col, end_row, end_col = node:range(false)
              if end_row >= #contents then
                end_col = #contents[end_row + 1]
              end

              -- TODO: hack for nvim's treesitter.
              -- native treesitter highlights escaped-string and concealed-text but I don't expected it.
              local conceal = metadata.conceal or metadata[capture] and metadata[capture].conceal
              local capture_name = highlighter_query:query().captures[capture]
              if conceal or vim.tbl_contains({ 'string.escape' }, capture_name) then
                hl_id = nil
              end

              pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, start_row, start_col, {
                end_row = end_row,
                end_col = end_col,
                hl_group = hl_id,
                hl_mode = 'combine',
                priority = tonumber(metadata.priority or metadata[capture] and metadata[capture].priority),
                conceal = conceal,
              })
            end
          end
        end)
        parser:destroy()
      end)
    end
  end
  for _, extmark in ipairs(extmarks) do
    local row = extmark.row
    local col = extmark.col
    extmark.row = nil
    extmark.col = nil
    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, row, col, extmark --[[@as any]])
  end
end

return Markdown
