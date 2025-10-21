local empty = {}
local kit = require('cmp-kit.kit')
local LSP = require('cmp-kit.kit.LSP')
local Async = require('cmp-kit.kit.Async')
local Range = require('cmp-kit.kit.LSP.Range')
local Position = require('cmp-kit.kit.LSP.Position')
local debugger = require('cmp-kit.core.debugger')
local LinePatch = require('cmp-kit.core.LinePatch')
local TriggerContext = require('cmp-kit.core.TriggerContext')
local Character = require('cmp-kit.kit.App.Character')
local PreviewText = require('cmp-kit.completion.PreviewText')
local SnippetText = require('cmp-kit.completion.SnippetText')

---Trim whitespace.
---@param text string
---@return string
local function trim_prewhite(text)
  local s = 1
  for i = 1, #text do
    if not Character.is_white(text:byte(i)) then
      s = i
      break
    end
  end
  if s ~= 1 then
    return text:sub(s)
  end
  return text
end

---Get expanded range.
---@param ranges { [1]: cmp-kit.kit.LSP.Range } | cmp-kit.kit.LSP.Range[]
---@return cmp-kit.kit.LSP.Range
local function create_expanded_range(ranges)
  local max --[[@as cmp-kit.kit.LSP.Range]]
  for _, range in ipairs(ranges) do
    if range then
      if not max then
        max = kit.clone(range)
      else
        if range.start.character < max.start.character then
          max.start.character = range.start.character
        end
        if max['end'].character < range['end'].character then
          max['end'].character = range['end'].character
        end
      end
    end
  end
  return max
end

---Chop string by newline.
---@param s string
---@return string
local function oneline(s)
  for i = 1, #s do
    if s:byte(i) == 10 then
      return s:sub(1, i - 1)
    end
  end
  return s
end

---@alias cmp-kit.completion.ExpandSnippet fun(s: string, option: { item: cmp-kit.completion.CompletionItem })

---@class cmp-kit.completion.CompletionItem
---@field private _trigger_context cmp-kit.core.TriggerContext
---@field private _provider cmp-kit.completion.CompletionProvider
---@field private _completion_list cmp-kit.kit.LSP.CompletionList
---@field private _item cmp-kit.kit.LSP.CompletionItem|{ nvim_previewText?: string }
---@field private _resolving cmp-kit.kit.Async.AsyncTask
---@field public cache table<string, any>
local CompletionItem = {}
CompletionItem.__index = CompletionItem

---Create new CompletionItem.
---@param trigger_context cmp-kit.core.TriggerContext
---@param provider cmp-kit.completion.CompletionProvider
---@param list cmp-kit.kit.LSP.CompletionList
---@param item cmp-kit.kit.LSP.CompletionItem | { nvim_previewText?: string }
function CompletionItem.new(trigger_context, provider, list, item)
  return setmetatable({
    _trigger_context = trigger_context,
    _provider = provider,
    _completion_list = list,
    _item = item,
    _resolving = nil,
    cache = {},
  }, CompletionItem)
end

---Get source name.
---@return string
function CompletionItem:get_source_name()
  return self._provider:get_name()
end

---Get suggest offset position 1-origin utf-8 byte index.
---NOTE: VSCode does not need this because it always shows the completion menu relative to the cursor position. But vim's completion usually shows the menu aligned with the keyword.
---@return number
function CompletionItem:get_offset()
  if not self.cache.get_offset then
    local keyword_offset = self._provider:get_keyword_offset() or self._trigger_context.character + 1
    if not self:has_text_edit() then
      self.cache.get_offset = keyword_offset

      -- if filter_text starts with symbol, we search symbol position from buffer text.
      local filter_text = self:get_filter_text()
      local filter_text_char1 = filter_text:byte(1)
      if Character.is_symbol(filter_text_char1) then
        local min_i = math.max(1, keyword_offset - #filter_text)
        for i = keyword_offset, min_i, -1 do
          local trigger_text_char = self._trigger_context.text_before:byte(i)
          if trigger_text_char == filter_text_char1 then
            local matched = true
            for j = i + 1, keyword_offset - 1 do
              if self._trigger_context.text_before:byte(j) ~= filter_text:byte(1 + j - i) then
                matched = false
                break
              end
            end
            if matched then
              self.cache.get_offset = i
              break
            end
          end
        end
      end
    else
      -- Use `textEdit.range.start.character` as offset but We ignore leading whitespace characters.
      local insert_range = self:get_insert_range()
      self._trigger_context.cache.CompletionItem_get_offset = self._trigger_context.cache.CompletionItem_get_offset or {}
      self._trigger_context.cache.CompletionItem_get_offset[keyword_offset] =
          self._trigger_context.cache.CompletionItem_get_offset[keyword_offset] or {}
      local cache = self._trigger_context.cache.CompletionItem_get_offset[keyword_offset]
      if not cache[insert_range.start.character] then
        local offset = insert_range.start.character + 1
        for i = offset, keyword_offset do
          offset = i
          if not Character.is_white(self._trigger_context.text:byte(i)) then
            break
          end
        end
        cache[insert_range.start.character] = math.min(offset, keyword_offset)
      end
      self.cache.get_offset = cache[insert_range.start.character]
    end
  end
  return self.cache.get_offset
end

---Return label text.
---@return string
function CompletionItem:get_label_text()
  if not self.cache.get_label_text then
    self.cache.get_label_text = oneline(self._item.label)
  end
  return self.cache.get_label_text
end

---Return label details.
---@return cmp-kit.kit.LSP.CompletionItemLabelDetails
function CompletionItem:get_label_details()
  if not self.cache.get_label_details then
    local details = nil --[[@type cmp-kit.kit.LSP.CompletionItemLabelDetails?]]
    if self._item.labelDetails then
      details = details or {}
      details.detail = details.detail or self._item.labelDetails.detail
      details.description = details.description or self._item.labelDetails.description
    end
    if self._item.detail then
      details = details or {}
      details.detail = details.detail or self._item.detail
    end
    self.cache.get_label_details = details or empty
  end
  return self.cache.get_label_details
end

---Return sort_text.
---@return string?
function CompletionItem:get_sort_text()
  return self._item.sortText
end

---Return preview text that will be inserted if the item is selected.
---NOTE: VSCode does not need this because it doesn't insert the text when the item is selected. But vim's completion usually inserts the text when the item is selected.
---@return string
function CompletionItem:get_preview_text()
  if not self.cache.get_preview_text then
    local preview_text --[[@as string]]
    if self._item.nvim_previewText then
      preview_text = trim_prewhite(self._item.nvim_previewText) --[[@as string]]
    else
      local text --[[@as string]]
      if self._item.filterText then
        text = trim_prewhite(self._item.filterText) --[[@as string]]
      elseif self._item.insertText then
        text = trim_prewhite(self._item.insertText) --[[@as string]]
      else
        text = self:get_insert_text()
        if self:get_insert_text_format() == LSP.InsertTextFormat.Snippet then
          text = tostring(SnippetText.parse(text)) --[[@as string]]
        end
      end

      -- NOTE: In string syntax, We use raw insertText.
      if self._trigger_context.in_string then
        preview_text = oneline(text)
      else
        preview_text = PreviewText.create({
          insert_text = text,
          before_text = self._trigger_context:substr(1, self:get_offset()),
          after_text = self._trigger_context.text_after,
        })
      end

      -- NOTE: cmp-kit's special implementation. Removes special characters so that they can be pressed after selecting an item.
      -- local chars = self:_get_commit_and_trigger_character_map()
      -- if chars[preview_text:byte(-1)] then
      --   preview_text = preview_text:sub(1, -2)
      -- end
    end
    self.cache.get_preview_text = preview_text
  end
  return self.cache.get_preview_text
end

---Return filter text that will be used for matching.
function CompletionItem:get_filter_text()
  if not self.cache.get_filter_text then
    local text = trim_prewhite(self._item.filterText or self._item.label)

    -- NOTE: This is cmp-kit's specific implementation and can have some of the pitfalls.
    -- Fix filter_text for non-VSCode compliant servers such as clangd.
    local keyword_offset = self._provider:get_keyword_offset() or self._trigger_context.character + 1
    if self:has_text_edit() then
      local offset = self:get_offset()
      -- NOTE: get_filter_text and get_offset reference each other, but calling get_offset here does NOT cause an infinite loop.
      local delta = keyword_offset - offset
      if delta > 0 then
        if Character.is_symbol(self._trigger_context.text:byte(offset)) then
          local prefix = self._trigger_context:substr(offset, keyword_offset - 1)
          if not vim.startswith(text, prefix) then
            text = prefix .. text
          end
        end
      elseif delta < 0 then
        text = text:sub(1 + math.abs(delta))
      end
    end
    self.cache.get_filter_text = text
  end
  return self.cache.get_filter_text
end

---Return insert text that will be inserted if the item is confirmed.
---@return string
function CompletionItem:get_insert_text()
  if self._item.textEditText then
    return self._item.textEditText
  elseif self._item.textEdit and self._item.textEdit.newText then
    return self._item.textEdit.newText
  elseif self._item.insertText then
    return self._item.insertText
  end
  return self._item.label
end

---Return insertTextFormat.
---@return cmp-kit.kit.LSP.InsertTextFormat
function CompletionItem:get_insert_text_format()
  if self._item.insertTextFormat then
    return self._item.insertTextFormat
  end
  if self._completion_list.itemDefaults and self._completion_list.itemDefaults.insertTextFormat then
    return self._completion_list.itemDefaults.insertTextFormat
  end
  return LSP.InsertTextFormat.PlainText
end

---Return insertTextMode.
---@return cmp-kit.kit.LSP.InsertTextMode
function CompletionItem:get_insert_text_mode()
  if self._item.insertTextMode then
    return self._item.insertTextMode
  end
  if self._completion_list.itemDefaults and self._completion_list.itemDefaults.insertTextMode then
    return self._completion_list.itemDefaults.insertTextMode
  end
  return LSP.InsertTextMode.asIs
end

---Return detail text.
---@return cmp-kit.kit.LSP.CompletionItemKind?
function CompletionItem:get_kind()
  return self._item.kind
end

---Return commit characters.
---@return string[]
function CompletionItem:get_commit_characters()
  if not self.cache.get_commit_characters then
    local uniq
    local commit_characters
    for _, c in ipairs(self._provider:get_all_commit_characters()) do
      uniq = uniq or {}
      if not uniq[c] then
        uniq[c] = true
        commit_characters = commit_characters or {}
        table.insert(commit_characters, c)
      end
    end
    if self._item.commitCharacters then
      for _, c in ipairs(self._item.commitCharacters) do
        uniq = uniq or {}
        if not uniq[c] then
          uniq[c] = true
          commit_characters = commit_characters or {}
          table.insert(commit_characters, c)
        end
      end
    elseif self._completion_list.itemDefaults and self._completion_list.itemDefaults.commitCharacters then
      for _, c in ipairs(self._completion_list.itemDefaults.commitCharacters) do
        uniq = uniq or {}
        if not uniq[c] then
          uniq[c] = true
          commit_characters = commit_characters or {}
          table.insert(commit_characters, c)
        end
      end
    end
    self.cache.get_commit_characters = commit_characters or empty
  end
  return self.cache.get_commit_characters
end

---Return text edit.
---@return (cmp-kit.kit.LSP.InsertReplaceEdit|cmp-kit.kit.LSP.TextEdit)?
function CompletionItem:get_text_edit()
  if not self.cache.get_text_edit then
    if self._item.textEdit then
      self.cache.get_text_edit = self._item.textEdit
    end
    if self._item.textEditText then
      if self._completion_list.itemDefaults and self._completion_list.itemDefaults.editRange then
        if self._completion_list.itemDefaults.editRange.start then
          self.cache.get_text_edit = {
            range = self._completion_list.itemDefaults.editRange,
            newText = self._item.textEditText,
          }
        elseif self._completion_list.itemDefaults.editRange.insert then
          self.cache.get_text_edit = {
            insert = self._completion_list.itemDefaults.editRange.insert,
            replace = self._completion_list.itemDefaults.editRange.replace,
            newText = self._item.textEditText,
          }
        end
      end
    end
  end
  return self.cache.get_text_edit
end

---Return item is preselect or not.
---@return boolean
function CompletionItem:is_preselect()
  return not not self._item.preselect
end

---Get completion item tags.
---@return table<cmp-kit.kit.LSP.CompletionItemTag, boolean>
function CompletionItem:get_tags()
  if not self.cache.get_tags then
    local tags
    for _, tag in ipairs(self._item.tags or {}) do
      tags = tags or {}
      tags[tag] = true
    end
    if self._item.deprecated then
      tags = tags or {}
      tags[LSP.CompletionItemTag.Deprecated] = true
    end
    self.cache.get_tags = tags or empty
  end
  return self.cache.get_tags
end

---Return item's documentation.
---@return cmp-kit.kit.LSP.MarkupContent?
function CompletionItem:get_documentation()
  if not self.cache.get_documentation then
    local kind = LSP.MarkupKind.PlainText
    local value = ''

    -- CompletionItem.documentation.
    if self._item.documentation then
      if type(self._item.documentation) == 'string' then
        value = self._item.documentation --[[@as string]]
      else
        kind = self._item.documentation.kind
        value = self._item.documentation.value
      end
    end

    -- CompletionItem.detail.
    local label_details = self:get_label_details()
    if label_details.detail then
      local has_already = value:find(label_details.detail, 1, true)
      if not has_already then
        local detail_value = ('```%s\n%s\n```'):format(
          vim.api.nvim_get_option_value('filetype', { buf = self._trigger_context.bufnr }),
          label_details.detail
        )
        if value ~= '' then
          detail_value = ('%s\n---\n%s'):format(detail_value, value)
        end
        value = detail_value
      end
    end

    -- return nil if documentation does not provided.
    if value == '' then
      self.cache.get_documentation = empty
    else
      self.cache.get_documentation = {
        kind = kind,
        value = value,
      }
    end
  end
  return self.cache.get_documentation.value and self.cache.get_documentation
end

---Resolve completion item (completionItem/resolve).
---@return cmp-kit.kit.Async.AsyncTask
function CompletionItem:resolve()
  self._resolving = self._resolving
      or (function()
        return self._provider
            :resolve(kit.merge({
              commitCharacters = self:get_commit_characters(),
              textEdit = self:get_text_edit(),
              insertTextFormat = self:get_insert_text_format(),
              insertTextMode = self:get_insert_text_mode(),
              data = self._item.data or (self._completion_list.itemDefaults and self._completion_list.itemDefaults.data),
            }, self._item))
            :dispatch(function(resolved_item)
              if debugger.enable() then
                debugger.add('cmp-kit.completion.CompletionItem:resolve.next', {
                  item = self._item,
                  resolved_item = resolved_item,
                  trigger_context = self._trigger_context,
                })
              end
              if resolved_item then
                self._item = kit.merge(resolved_item, self._item)
                self.cache = {}
              else
                -- Clear resolving cache if null was returned from server.
                self._resolving = nil
              end
            end, function(err)
              if debugger.enable() then
                debugger.add('cmp-kit.completion.CompletionItem:resolve.catch', {
                  item = self._item,
                  resolved_item = nil,
                  trigger_context = self._trigger_context,
                  err = err,
                })
              end
            end)
      end)()
  return self._resolving
end

---Execute command (workspace/executeCommand).
---@return cmp-kit.kit.Async.AsyncTask
function CompletionItem:execute()
  if self._provider.execute and self._item.command then
    return self:resolve():next(function()
      return self._provider:execute(self._item.command):catch(function() end)
    end)
  end
  return Async.resolve()
end

---Commit item.
---@param option? { replace?: boolean, expand_snippet?: cmp-kit.completion.ExpandSnippet }
---@return cmp-kit.kit.Async.AsyncTask
function CompletionItem:commit(option)
  option = option or {}
  option.replace = option.replace or false

  if debugger.enable() then
    debugger.add('cmp-kit.completion.CompletionItem:commit', {
      item = self._item,
      trigger_context = self._trigger_context,
      offset = self:get_offset(),
      query = self._trigger_context:get_query(self:get_offset()),
      filter_text = self:get_filter_text(),
      insert_text = self:get_insert_text(),
      preview_text = self:get_preview_text(),
      insert_range = self:get_insert_range(),
      replace_range = self:get_replace_range(),
      option = option,
    })
  end

  local bufnr = vim.api.nvim_get_current_buf()
  return Async.run(function()
    -- Try resolve item (this must be sync process for supporting macro).
    pcall(function()
      Async.race({ self:resolve(), Async.timeout(500) }):sync(501)
    end)

    local trigger_context --[[@as cmp-kit.core.TriggerContext]]

    -- Create initial undo point.
    vim.o.undolevels = vim.o.undolevels

    -- Create preview_text undopoint.
    trigger_context = TriggerContext.create()
    LinePatch.apply_by_keys(bufnr, trigger_context.character - (self:get_offset() - 1), 0, self:get_preview_text())
        :await()
    vim.o.undolevels = vim.o.undolevels

    -- Restore the the buffer content to the state it was in when the request was sent.
    -- NOTE: this must not affect the dot-repeat.
    trigger_context = TriggerContext.create()
    LinePatch.apply_by_func(bufnr, trigger_context.character, 0, self._trigger_context.text_before):await()

    -- Make overwrite information.
    local range = option.replace and self:get_replace_range() or self:get_insert_range()
    local before = self._trigger_context.character - range.start.character
    local after = range['end'].character - self._trigger_context.character

    -- Apply sync additionalTextEdits if provied.
    if self._item.additionalTextEdits then
      vim.lsp.util.apply_text_edits(
        vim
        .iter(self._item.additionalTextEdits)
        :map(function(text_edit)
          return {
            range = Range.to_buf(self._trigger_context.bufnr, text_edit.range,
              self._provider:get_position_encoding_kind()),
            newText = text_edit.newText,
          }
        end)
        :totable(),
        bufnr,
        LSP.PositionEncodingKind.UTF8
      )
    end

    -- Expansion (Snippet / PlainText).
    vim.cmd.undojoin()
    if self:get_insert_text_format() == LSP.InsertTextFormat.Snippet then
      if option.expand_snippet then
        -- Snippet: remove range of text and expand snippet.
        LinePatch.apply_by_func(bufnr, before, after, ''):await()
        option.expand_snippet(self:get_insert_text(), { item = self })
      else
        ---NOTE: This is cmp-kit's specific implementation. if user doesn't provide `expand_snippet`, cmp-kit will fallback to insert `preview_text`.
        local parsed_insert_text = tostring(SnippetText.parse(self:get_insert_text()))
        if parsed_insert_text == self:get_insert_text() then
          LinePatch.apply_by_func(bufnr, before, after, parsed_insert_text):await()
        else
          LinePatch.apply_by_func(bufnr, before, after, self:get_preview_text()):await()
        end
      end
    else
      -- PlainText: insert text.
      LinePatch.apply_by_func(bufnr, before, after, self:get_insert_text()):await()
    end

    -- Apply async additionalTextEdits if provided.
    if not self._item.additionalTextEdits then
      do
        local prev_trigger_context = TriggerContext.create()
        self:resolve():next(function()
          if self._item.additionalTextEdits then
            -- Check cursor is moved during resolve request proceeding.
            local next_trigger_context = TriggerContext.create()
            local should_skip = false
            should_skip = should_skip or (prev_trigger_context.line ~= next_trigger_context.line)
            should_skip = should_skip or #vim.iter(self._item.additionalTextEdits):filter(function(text_edit)
              return text_edit.range.start.line >= next_trigger_context.line
            end) > 0
            if not should_skip then
              vim.cmd.undojoin()
              vim.lsp.util.apply_text_edits(
                vim
                .iter(self._item.additionalTextEdits)
                :map(function(text_edit)
                  return {
                    range = Range.to_buf(self._trigger_context.bufnr, text_edit.range,
                      self._provider:get_position_encoding_kind()),
                    newText = text_edit.newText,
                  }
                end)
                :totable(),
                bufnr,
                LSP.PositionEncodingKind.UTF8
              )
            end
          end
        end)
      end
    end

    -- Execute command.
    self:execute()
  end)
end

---Return this has textEdit or not.
---@return boolean
function CompletionItem:has_text_edit()
  if self._item.textEdit then
    return true
  end
  if self._completion_list.itemDefaults then
    if self._completion_list.itemDefaults.editRange then
      return true
    end
  end
  return false
end

---Return this has additionalTextEdits or not.
---@return boolean
function CompletionItem:has_additional_text_edits()
  return not not self._item.additionalTextEdits
end

---Return insert range.
---NOTE: This method ignores the `position.line` because CompletionItem does not consider line posision.
---NOTE: This range is utf-8 byte length based.
---@return cmp-kit.kit.LSP.Range
function CompletionItem:get_insert_range()
  if not self.cache.get_insert_range then
    ---@type cmp-kit.kit.LSP.Range
    local range
    if self._item.textEdit then
      if self._item.textEdit.insert then
        range = self._item.textEdit.insert
      else
        range = self._item.textEdit.range
      end
    elseif self._completion_list.itemDefaults and self._completion_list.itemDefaults.editRange then
      if self._completion_list.itemDefaults.editRange.insert then
        range = self._completion_list.itemDefaults.editRange.insert
      else
        range = self._completion_list.itemDefaults.editRange --[[@as cmp-kit.kit.LSP.Range]]
      end
    end
    if range then
      self.cache.get_insert_range = self._trigger_context:convert_range_as_utf8(
        self._provider:get_position_encoding_kind(),
        range
      )
    else
      -- NOTE: get_insert_range and get_offset reference each other, but calling get_offset here does NOT cause an infinite loop.
      local default_range = kit.clone(self._provider:get_default_insert_range())
      default_range.start.character = self:get_offset() - 1
      self.cache.get_insert_range = {
        start = {
          line = default_range.start.line,
          character = self:get_offset() - 1,
        },
        ['end'] = default_range['end'],
      }
    end
  end
  return self.cache.get_insert_range
end

---Return replace range.
---NOTE: This method ignores the `position.line` because CompletionItem does not consider line posision.
---NOTE: This range is utf-8 byte length based.
---@return cmp-kit.kit.LSP.Range
function CompletionItem:get_replace_range()
  if not self.cache.get_replace_range then
    local range --[[@as cmp-kit.kit.LSP.Range]]
    if self._item.textEdit then
      if self._item.textEdit.replace then
        range = self._item.textEdit.replace
      end
    elseif self._completion_list.itemDefaults and self._completion_list.itemDefaults.editRange then
      if self._completion_list.itemDefaults.editRange.replace then
        range = self._completion_list.itemDefaults.editRange.replace
      end
    end
    range = range or self:get_insert_range()
    self.cache.get_replace_range = create_expanded_range({ self._provider:get_default_replace_range(), range })
  end
  return self.cache.get_replace_range
end

---Check this item has inline additionalTextEdits.
---NOTE: This is a cmp-kit's specific implementation.
---@return boolean
function CompletionItem:_has_inline_additional_text_edits()
  if not self.cache._has_inline_additional_text_edits then
    self.cache._has_inline_additional_text_edits = false
    if self._item.additionalTextEdits then
      for _, text_edit in ipairs(self._item.additionalTextEdits) do
        if text_edit.range.start.line == self._trigger_context.line then
          self.cache._has_inline_additional_text_edits = true
          break
        end
        if text_edit.range['end'].line == self._trigger_context.line then
          self.cache._has_inline_additional_text_edits = true
          break
        end
      end
    end
  end
  return self.cache._has_inline_additional_text_edits
end

---Create commitCharacters and triggerCharacters map.
---@return table<integer, boolean>
function CompletionItem:_get_commit_and_trigger_character_map()
  if not self.cache._get_commit_and_trigger_character_map then
    local chars
    for _, c in ipairs(self:get_commit_characters()) do
      chars = chars or {}
      chars[c:byte(1)] = true
    end
    for _, c in ipairs(self._provider:get_trigger_characters()) do
      chars = chars or {}
      chars[c:byte(1)] = true
    end
    self.cache._get_commit_and_trigger_character_map = chars or empty
  end
  return self.cache._get_commit_and_trigger_character_map
end

return CompletionItem
