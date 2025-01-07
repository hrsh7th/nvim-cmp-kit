local kit = require('cmp-kit.kit')
local LSP = require('cmp-kit.kit.LSP')
local Async = require('cmp-kit.kit.Async')
local Position = require('cmp-kit.kit.LSP.Position')
local LinePatch = require('cmp-kit.core.LinePatch')
local TriggerContext = require('cmp-kit.core.TriggerContext')
local Character = require('cmp-kit.core.Character')
local SelectText = require('cmp-kit.core.SelectText')
local SnippetText = require('cmp-kit.core.SnippetText')

---Trim whitespace.
---@param text string
---@return string
local function trim_white(text)
  local s = 1
  for i = 1, #text do
    if not Character.is_white(text:byte(i)) then
      s = i
      break
    end
  end
  local e = #text
  for i = #text, 1, -1 do
    if not Character.is_white(text:byte(i)) then
      e = i
      break
    end
  end
  if s ~= 1 or e ~= #text then
    return text:sub(s, e)
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

---@alias cmp-kit.core.ExpandSnippet fun(s: string, option: { item: cmp-kit.core.CompletionItem })

---@class cmp-kit.core.CompletionItem
---@field private _trigger_context cmp-kit.core.TriggerContext
---@field private _provider cmp-kit.core.CompletionProvider
---@field private _completion_list cmp-kit.kit.LSP.CompletionList
---@field private _item cmp-kit.kit.LSP.CompletionItem
---@field private _cache table<string, any>
---@field private _resolving cmp-kit.kit.Async.AsyncTask
local CompletionItem = {}
CompletionItem.__index = CompletionItem

---Create new CompletionItem.
---@param trigger_context cmp-kit.core.TriggerContext
---@param provider cmp-kit.core.CompletionProvider
---@param list cmp-kit.kit.LSP.CompletionList
---@param item cmp-kit.kit.LSP.CompletionItem
function CompletionItem.new(trigger_context, provider, list, item)
  return setmetatable({
    _trigger_context = trigger_context,
    _provider = provider,
    _completion_list = list,
    _item = item,
    _cache = {},
    _resolving = nil,
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
  local cache_key = 'get_offset'
  if not self._cache[cache_key] then
    local keyword_offset = self._trigger_context:get_keyword_offset(self._provider:get_keyword_pattern()) or
        self._trigger_context.character + 1
    if not self:has_text_edit() then
      self._cache[cache_key] = keyword_offset
      local filter_text = self:get_filter_text()
      if Character.is_symbol(filter_text:byte(1)) then
        local min_i = math.max(1, keyword_offset - #filter_text)
        for i = math.min(#self._trigger_context.text_before, keyword_offset), min_i, -1 do
          if Character.is_semantic_index(self._trigger_context.text, i) then
            local m = true
            local max_j = math.min(i + #filter_text - 1, #self._trigger_context.text_before)
            for j = i, max_j do
              if self._trigger_context.text_before:byte(j) ~= filter_text:byte(1 + j - i) then
                m = false
                break
              end
            end
            if m then
              self._cache[cache_key] = i
              break
            end
          end
        end
      end
    else
      local insert_range = self:get_insert_range()
      local trigger_context_cache_key = string.format('%s:%s:%s', 'get_offset', keyword_offset,
        insert_range.start.character)
      if not self._trigger_context.cache[trigger_context_cache_key] then
        local offset = insert_range.start.character + 1
        for i = offset, keyword_offset do
          offset = i
          if not Character.is_white(self._trigger_context.text:byte(i)) then
            break
          end
        end
        self._trigger_context.cache[trigger_context_cache_key] = math.min(offset, keyword_offset)
      end
      self._cache[cache_key] = self._trigger_context.cache[trigger_context_cache_key]
    end
  end
  return self._cache[cache_key]
end

---Return label text.
---@return string
function CompletionItem:get_label_text()
  return self._item.label
end

---Return label details.
---@return cmp-kit.kit.LSP.CompletionItemLabelDetails
function CompletionItem:get_label_details()
  local cache_key = 'get_label_details'
  if not self._cache[cache_key] then
    local details = {} --[[@type cmp-kit.kit.LSP.CompletionItemLabelDetails]]
    if self._item.labelDetails then
      details.detail = details.detail or self._item.labelDetails.detail
      details.description = details.description or self._item.labelDetails.description
    end
    if self._item.detail then
      details.detail = details.detail or self._item.detail
    end
    self._cache[cache_key] = details
  end
  return self._cache[cache_key]
end

---Return sort_text.
---@return string?
function CompletionItem:get_sort_text()
  return self._item.sortText
end

---Return select text that will be inserted if the item is selected.
---NOTE: VSCode does not need this because it doesn't insert the text when the item is selected. But vim's completion usually inserts the text when the item is selected.
---@return string
function CompletionItem:get_select_text()
  local cache_key = 'get_select_text'
  if not self._cache[cache_key] then
    local text = self:get_insert_text()
    if self:get_insert_text_format() == LSP.InsertTextFormat.Snippet then
      text = tostring(SnippetText.parse(text)) --[[@as string]]
    end

    local select_text = SelectText.create(text)

    -- NOTE: cmp-kit's special implementation. Removes special characters so that they can be pressed after selecting an item.
    local chars = {}
    for _, c in ipairs(self:get_commit_characters()) do
      chars[c] = true
    end
    for _, c in ipairs(self._provider:get_completion_options().triggerCharacters or {}) do
      chars[c] = true
    end
    if chars[select_text:sub(-1, -1)] then
      select_text = select_text:sub(1, -2)
    end
    self._cache[cache_key] = select_text
  end
  return self._cache[cache_key]
end

---Return filter text that will be used for matching.
function CompletionItem:get_filter_text()
  local cache_key = 'get_filter_text'
  if not self._cache[cache_key] then
    local text = trim_white(self._item.filterText or self._item.label)

    -- NOTE: This is cmp-kit's specific implementation and can have some of the pitfalls.
    -- Fix filter_text for non-VSCode compliant servers such as clangd.
    local keyword_offset = self._trigger_context:get_keyword_offset(self._provider:get_keyword_pattern()) or
        self._trigger_context.character + 1
    if self:has_text_edit() then
      local delta = keyword_offset - self:get_offset()
      if delta > 0 then
        if Character.is_symbol(self._trigger_context.text:byte(self:get_offset())) then
          local prefix = self._trigger_context.text:sub(self:get_offset(), keyword_offset - 1)
          if text:sub(1, #prefix) ~= prefix then
            text = prefix .. text
          end
        end
      end
    end
    self._cache[cache_key] = text
  end
  return self._cache[cache_key]
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
  local cache_key = 'get_commit_characters'
  if not self._cache[cache_key] then
    local commit_characters = {}
    for _, c in ipairs(self._item.commitCharacters or {}) do
      table.insert(commit_characters, c)
    end
    for _, c in ipairs(self._provider:get_completion_options().allCommitCharacters or {}) do
      table.insert(commit_characters, c)
    end
    self._cache[cache_key] = commit_characters
  end
  return self._cache[cache_key]
end

---Return item is preselect or not.
---@return boolean
function CompletionItem:is_preselect()
  return not not self._item.preselect
end

---Return item is deprecated or not.
---@return boolean
function CompletionItem:is_deprecated()
  local cache_key = 'is_deprecated'
  if not self._cache[cache_key] then
    if self._item.deprecated then
      self._cache[cache_key] = { output = true }
    elseif vim.tbl_contains(self._item.tags, LSP.CompletionItemTag.Deprecated) then
      self._cache[cache_key] = { output = true }
    else
      self._cache[cache_key] = { output = false }
    end
  end
  return self._cache[cache_key].output
end

---Return item's documentation.
---@return cmp-kit.kit.LSP.MarkupContent?
function CompletionItem:get_documentation()
  local cache_key = 'get_documentation'
  if not self._cache[cache_key] then
    local documentation = { kind = LSP.MarkupKind.Markdown, value = '' } --[[@as cmp-kit.kit.LSP.MarkupContent]]

    -- CompletionItem.documentation.
    if self._item.documentation then
      if type(self._item.documentation) == 'string' then
        documentation.value = self._item.documentation --[[@as string]]
      else
        documentation.kind = self._item.documentation.kind
        documentation.value = self._item.documentation.value
      end
    end

    -- CompletionItem.detail.
    local label_details = self:get_label_details()
    if label_details.detail then
      local has_already = documentation.value:find(label_details.detail, 1, true)
      if not has_already then
        local value = ('```%s\n%s\n```'):format(
          vim.api.nvim_get_option_value('filetype', { buf = self._trigger_context.bufnr }), label_details.detail)
        if documentation.value ~= '' then
          value = ('%s\n%s'):format(value, documentation.value)
        end
        documentation.value = value
      end
    end

    -- return nil if documentation does not provided.
    if documentation.value == '' then
      documentation = nil
    else
      documentation.value = documentation.value
        :gsub('\r\n', '\n')
        :gsub('\r', '\n')
    end
    self._cache[cache_key] = { output = documentation }
  end
  return self._cache[cache_key].output
end

---Resolve completion item (completionItem/resolve).
---@return cmp-kit.kit.Async.AsyncTask
function CompletionItem:resolve()
  self._resolving = self._resolving or (function()
    return self._provider:resolve(kit.merge({}, self._item)):next(function(resolved_item)
      if resolved_item then
        -- Merge resolved item to original item.
        self._item = kit.merge(resolved_item, self._item)
        self._cache = {}
      else
        -- Clear resolving cache if null was returned from server.
        self._resolving = nil
      end
    end)
  end)()
  return self._resolving
end

---Execute command (workspace/executeCommand).
---@return cmp-kit.kit.Async.AsyncTask
function CompletionItem:execute()
  if self._provider.execute and self._item.command then
    return self._provider:execute(self._item.command):catch(function() end)
  end
  return Async.resolve()
end

---Commit item.
---@param option? { replace?: boolean, expand_snippet?: cmp-kit.core.ExpandSnippet }
---@return cmp-kit.kit.Async.AsyncTask
function CompletionItem:commit(option)
  option = option or {}
  option.replace = option.replace or false

  local bufnr = vim.api.nvim_get_current_buf()
  return Async.run(function()
    -- Try resolve item (this must be sync process for supporting macro).
    pcall(function()
      Async.race({ self:resolve(), Async.timeout(500) }):sync(501)
    end)

    local trigger_context --[[@as cmp-kit.core.TriggerContext]]

    -- Create initial undo point.
    vim.o.undolevels = vim.o.undolevels

    -- Create select_text undopoint.
    trigger_context = TriggerContext.create()
    LinePatch.apply_by_keys(bufnr, trigger_context.character - (self:get_offset() - 1), 0, self:get_select_text()):await()
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
            range = self:_convert_range_encoding(text_edit.range),
            newText = text_edit.newText,
          }
        end)
        :totable(),
        bufnr,
        LSP.PositionEncodingKind.UTF8
      )
    end

    -- Expansion (Snippet / PlainText).
    if self:get_insert_text_format() == LSP.InsertTextFormat.Snippet then
      if option.expand_snippet then
        -- Snippet: remove range of text and expand snippet.
        LinePatch.apply_by_func(bufnr, before, after, ''):await()
        option.expand_snippet(self:get_insert_text(), { item = self })
      else
        --
        -- Snippet: fallback to insert select_text (if `expand_snippet` wasn't provided).
        ---NOTE: This is cmp-kit's specific implementation. if user doesn't provide `expand_snippet`, cmp-kit will fallback to insert `select_text`.
        local parsed_insert_text = tostring(SnippetText.parse(self:get_insert_text()))
        if parsed_insert_text == self:get_insert_text() then
          LinePatch.apply_by_func(bufnr, before, after, parsed_insert_text):await()
        else
          LinePatch.apply_by_func(bufnr, before, after, self:get_select_text()):await()
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
              vim.lsp.util.apply_text_edits(
                kit
                .iter(self._item.additionalTextEdits)
                :map(function(text_edit)
                  return {
                    range = self:_convert_range_encoding(text_edit.range),
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
    self:execute():await()
  end)
end

---Return this has textEdit or not.
---@return boolean
function CompletionItem:has_text_edit()
  return not not (self._item.textEdit or (self._completion_list.itemDefaults and self._completion_list.itemDefaults.editRange))
end

---Return insert range.
---NOTE: This method ignores the `position.line` because CompletionItem does not consider line posision.
---NOTE: This range is utf-8 byte length based.
---@return cmp-kit.kit.LSP.Range
function CompletionItem:get_insert_range()
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
    return self:_convert_range_encoding(range)
  else
    local default_range = self._provider:get_default_insert_range()
    default_range.start.character = self:get_offset() - 1
    return default_range
  end
end

---Return replace range.
---NOTE: This method ignores the `position.line` because CompletionItem does not consider line posision.
---NOTE: This range is utf-8 byte length based.
---@return cmp-kit.kit.LSP.Range
function CompletionItem:get_replace_range()
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
  return create_expanded_range({ self._provider:get_default_replace_range(), range })
end

---Convert range encoding to LSP.PositionEncodingKind.UTF8.
---NOTE: This method ignores the `position.line` because CompletionItem does not consider line posision.
---NOTE: This range is utf-8 byte length based.
---@param range cmp-kit.kit.LSP.Range
---@return cmp-kit.kit.LSP.Range
function CompletionItem:_convert_range_encoding(range)
  local from_encoding = self._provider:get_position_encoding_kind()
  if from_encoding == LSP.PositionEncodingKind.UTF8 then
    return range
  end

  local cache_key = string.format('%s:%s', 'CompletionItem:_convert_range_encoding', range.start.character,
    range['end'].character, from_encoding)
  if not self._trigger_context.cache[cache_key] then
    local start_cache_key = string.format('%s:%s:%s', 'CompletionItem:_convert_range_encoding:start',
      range.start.character, from_encoding)
    if not self._trigger_context.cache[start_cache_key] then
      self._trigger_context.cache[start_cache_key] = Position.to_utf8(self._trigger_context.text, range.start,
        from_encoding)
    end
    local end_cache_key = string.format('%s:%s:%s', 'CompletionItem:_convert_range_encoding:end', range['end'].character,
      from_encoding)
    if not self._trigger_context.cache[end_cache_key] then
      self._trigger_context.cache[end_cache_key] = Position.to_utf8(self._trigger_context.text, range['end'],
        from_encoding)
    end
    self._trigger_context.cache[cache_key] = {
      start = self._trigger_context.cache[start_cache_key],
      ['end'] = self._trigger_context.cache[end_cache_key],
    }
  end
  return self._trigger_context.cache[cache_key]
end

return CompletionItem
