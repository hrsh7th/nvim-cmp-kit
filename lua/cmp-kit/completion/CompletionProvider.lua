---@diagnostic disable: invisible
local kit = require('cmp-kit.kit')
local LSP = require('cmp-kit.kit.LSP')
local Async = require('cmp-kit.kit.Async')
local RegExp = require('cmp-kit.kit.Vim.RegExp')
local debugger = require('cmp-kit.core.debugger')
local CompletionItem = require('cmp-kit.completion.CompletionItem')
local DefaultConfig = require('cmp-kit.completion.ext.DefaultConfig')

---@enum cmp-kit.completion.CompletionProvider.RequestState
local RequestState = {
  Waiting = 'Waiting',
  Fetching = 'Fetching',
  Completed = 'Completed',
}

---Convert completion response to LSP.CompletionList.
---@param response (cmp-kit.kit.LSP.CompletionList|cmp-kit.kit.LSP.CompletionItem[])?
---@return cmp-kit.kit.LSP.CompletionList
local function to_completion_list(response)
  response = response or {}
  if response.items then
    response.isIncomplete = response.isIncomplete or false
    response.items = response.items or {}
    return response
  end
  return {
    isIncomplete = false,
    items = response or {},
  }
end

---Extract keyword pattern range for requested line context.
---@param trigger_context cmp-kit.core.TriggerContext
---@param keyword_pattern string
---@return { [1]: integer, [2]: integer } 1-origin utf8 byte index
local function extract_keyword_range(trigger_context, keyword_pattern)
  local cache_key = string.format('%s:%s', 'CompletionProvider:extract_keyword_range', keyword_pattern)
  if not trigger_context.cache[cache_key] then
    local c = trigger_context.character + 1
    local _, s, e = RegExp.extract_at(trigger_context.text, keyword_pattern, c)
    trigger_context.cache[cache_key] = { s or c, e or c }
  end
  return trigger_context.cache[cache_key]
end

---@class cmp-kit.completion.CompletionProvider.State
---@field public request_state cmp-kit.completion.CompletionProvider.RequestState
---@field public request_time integer
---@field public response_revision integer
---@field public completion_context? cmp-kit.kit.LSP.CompletionContext
---@field public completion_offset? integer
---@field public keyword_offset? integer
---@field public trigger_context? cmp-kit.core.TriggerContext
---@field public is_incomplete? boolean
---@field public is_trigger_character_completion boolean
---@field public dedup_map table<string, boolean>
---@field public items cmp-kit.completion.CompletionItem[]
---@field public matches cmp-kit.completion.Match[]
---@field public matches_items cmp-kit.completion.CompletionItem[]
---@field public matches_before_text? string

---@class cmp-kit.completion.CompletionProvider.Config
---@field public dedup boolean
---@field public item_count integer
---@field public keyword_length integer

---@class cmp-kit.completion.CompletionProvider
---@field public config cmp-kit.completion.CompletionProvider.Config
---@field private _source cmp-kit.completion.CompletionSource
---@field private _state cmp-kit.completion.CompletionProvider.State
local CompletionProvider = {}
CompletionProvider.__index = CompletionProvider
CompletionProvider.RequestState = RequestState

---Create new CompletionProvider.
---@param source cmp-kit.completion.CompletionSource
---@param config? cmp-kit.completion.CompletionProvider.Config
---@return cmp-kit.completion.CompletionProvider
function CompletionProvider.new(source, config)
  local self = setmetatable({
    config = kit.merge(config or {}, {
      dedup = false,
      item_count = math.huge,
      keyword_length = 1,
    }),
    _source = source,
    _state = {
      is_trigger_character_completion = false,
      request_state = RequestState.Waiting,
      request_time = 0,
      response_revision = 0,
      dedup_map = {},
      items = {},
      matches = {},
      matches_items = {},
      matches_before_text = nil,
    } --[[@as cmp-kit.completion.CompletionProvider.State]],
  }, CompletionProvider)
  return self
end

---Get provider name.
---@return string
function CompletionProvider:get_name()
  return self._source.name
end

---Completion (textDocument/completion).
---@param trigger_context cmp-kit.core.TriggerContext
---@param on_step? fun(step: 'skip-completion' | 'send-request' | 'ignore-outdated' | 'adopt-response')
---@return cmp-kit.kit.Async.AsyncTask cmp-kit.kit.LSP.CompletionContext?
function CompletionProvider:complete(trigger_context, on_step)
  on_step = on_step or function() end

  return Async.run(function()
    if not self:in_completion_context(trigger_context) then
      self:clear()
    end

    local trigger_characters = self:get_trigger_characters()
    local keyword_pattern = self:get_keyword_pattern()
    local keyword_offset = trigger_context:get_keyword_offset(keyword_pattern)
    local is_same_completion_offset = not not (keyword_offset and keyword_offset == self._state.completion_offset)
    local is_same_keyword_offset = not not (keyword_offset and keyword_offset == self._state.keyword_offset)

    ---Check should complete for new trigger context or not.
    local completion_context ---@type cmp-kit.kit.LSP.CompletionContext
    local completion_offset ---@type integer?
    if trigger_context.force then
      -- manual based completion
      completion_context = {
        triggerKind = LSP.CompletionTriggerKind.Invoked,
      }
      completion_offset = keyword_offset or (trigger_context.character + 1)
    elseif vim.tbl_contains(trigger_characters, trigger_context.trigger_character) then
      -- trigger character based completion.
      completion_context = {
        triggerKind = LSP.CompletionTriggerKind.TriggerCharacter,
        triggerCharacter = trigger_context.trigger_character,
      }
      completion_offset = trigger_context.character + 1
    else
      -- keyword based completion.
      if keyword_offset and (trigger_context.character + 1 - keyword_offset) >= self.config.keyword_length then
        if is_same_keyword_offset and self._state.is_incomplete then
          -- keyword completion for incomplete completion.
          completion_context = {
            triggerKind = LSP.CompletionTriggerKind.TriggerForIncompleteCompletions,
          }
          completion_offset = keyword_offset
        elseif not is_same_keyword_offset then
          -- keyword completion for new keyword offset.
          completion_context = {
            triggerKind = LSP.CompletionTriggerKind.Invoked,
          }
          completion_offset = keyword_offset
        end
      end
    end

    -- do not invoke new completion.
    if not completion_context then
      if not keyword_offset then
        self:clear()
      end
      on_step('skip-completion')
      return
    end

    -- update is_trigger_character_completion
    local is_trigger_char = false
    is_trigger_char = is_trigger_char or (
      completion_context.triggerKind == LSP.CompletionTriggerKind.TriggerCharacter
    )
    is_trigger_char = is_trigger_char or (self:in_trigger_character_completion() and is_same_completion_offset)
    self._state.is_trigger_character_completion = is_trigger_char

    -- update request state.
    if completion_context.triggerKind ~= LSP.CompletionTriggerKind.TriggerForIncompleteCompletions then
      self._state.request_state = RequestState.Fetching
      self._state.request_time = vim.uv.hrtime() / 1e6
    end

    -- update state.
    self._state.trigger_context = trigger_context
    self._state.completion_context = completion_context
    self._state.completion_offset = completion_offset
    self._state.keyword_offset = keyword_offset

    -- invoke completion.
    on_step('send-request')
    local raw_response = Async.new(function(resolve)
      self._source:complete(completion_context, function(err, res)
        if err then
          debugger.add('cmp-kit.completion.CompletionProvider:complete', err)
          resolve(nil)
        else
          resolve(res)
        end
      end)
    end):await() --[[@as cmp-kit.kit.LSP.TextDocumentCompletionResponse]]

    -- ignore outdated response.
    if self._state.trigger_context ~= trigger_context then
      on_step('ignore-outdated')
      return
    end

    -- adopt response.
    local list = to_completion_list(raw_response)
    self:_adopt_response(trigger_context, completion_context, list)

    -- clear if response is empty for no keyword completion.
    -- it needed to re-completion for new keyword.
    -- e.g.: `table.` is empty but `table.i` should be new completion.
    if #self._state.items == 0 and not keyword_offset then
      self:clear()
    end

    on_step('adopt-response')

    return completion_context
  end)
end

---Accept completion response.
---@param trigger_context cmp-kit.core.TriggerContext
---@param completion_context cmp-kit.kit.LSP.CompletionContext
---@param list cmp-kit.kit.LSP.CompletionList
function CompletionProvider:_adopt_response(trigger_context, completion_context, list)
  self._state.request_state = RequestState.Completed
  self._state.is_incomplete = list.isIncomplete or false

  local prev_item_count = #self._state.items

  -- do not keep previous state if completion is not incomplete.
  if completion_context.triggerKind ~= LSP.CompletionTriggerKind.TriggerForIncompleteCompletions then
    kit.clear(self._state.items)
    kit.clear(self._state.dedup_map)
  end

  -- convert response to items.
  for _, item in ipairs(list.items) do
    local completion_item = CompletionItem.new(trigger_context, self, list, item)

    -- check insert range.
    local is_valid_range = true
    if completion_item:has_text_edit() then
      local range = completion_item:get_insert_range()
      local is_valid_s = range.start.line < trigger_context.line or (
        range.start.line == trigger_context.line and range.start.character <= trigger_context.character
      )
      local is_valid_e = trigger_context.line < range['end'].line or (
        range['end'].line == trigger_context.line and trigger_context.character <= range['end'].character
      )
      is_valid_range = is_valid_s and is_valid_e
    end

    -- check dedup.
    local is_deduped = false
    if completion_context.triggerKind == LSP.CompletionTriggerKind.TriggerForIncompleteCompletions then
      is_deduped = self._state.dedup_map[completion_item:get_label_text()]
    end
    if is_valid_range and not is_deduped then
      self._state.items[#self._state.items + 1] = completion_item
      self._state.dedup_map[completion_item:get_label_text()] = true
    end
  end

  -- clear matching state.
  kit.clear(self._state.matches)
  kit.clear(self._state.matches_items)
  self._state.matches_before_text = nil

  -- increase response_revision if changed.
  local next_item_count = #self._state.items
  if not (next_item_count == 0 and prev_item_count == 0) then
    self._state.response_revision = self._state.response_revision + 1
  end
end

---Resolve completion item (completionItem/resolve).
---@param item cmp-kit.kit.LSP.CompletionItem
---@return cmp-kit.kit.Async.AsyncTask
function CompletionProvider:resolve(item)
  if not self._source.resolve then
    return Async.resolve(item)
  end
  return Async.new(function(resolve, reject)
    self._source:resolve(item, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
end

---Execute command (workspace/executeCommand).
---@param command cmp-kit.kit.LSP.Command
---@return cmp-kit.kit.Async.AsyncTask
function CompletionProvider:execute(command)
  if not self._source.execute then
    return Async.resolve()
  end
  return Async.new(function(resolve, reject)
    self._source:execute(command, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
end

---Check if the provider is capable for the trigger context.
---@param trigger_context cmp-kit.core.TriggerContext
---@return boolean
function CompletionProvider:capable(trigger_context)
  if self._source.capable and not self._source:capable(trigger_context) then
    return false
  end
  return true
end

---Return LSP.PositionEncodingKind.
---@return cmp-kit.kit.LSP.PositionEncodingKind
function CompletionProvider:get_position_encoding_kind()
  if not self._source.get_configuration then
    return LSP.PositionEncodingKind.UTF16
  end
  local config = self._source:get_configuration()
  return config.position_encoding_kind or LSP.PositionEncodingKind.UTF16
end

---Return keyword pattern.
---@return string
function CompletionProvider:get_keyword_pattern()
  if not self._source.get_configuration then
    return DefaultConfig.default_keyword_pattern
  end
  local config = self._source:get_configuration()
  return config.keyword_pattern or DefaultConfig.default_keyword_pattern
end

---Return trigger characters.
---@return string[]
function CompletionProvider:get_trigger_characters()
  if not self._source.get_configuration then
    return {}
  end
  return self._source:get_configuration().trigger_characters or {}
end

---Return all commit characters.
---@return string[]
function CompletionProvider:get_all_commit_characters()
  if not self._source.get_configuration then
    return {}
  end
  return self._source:get_configuration().all_commit_characters or {}
end

---Return response revision.
---@return integer
function CompletionProvider:get_response_revision()
  return self._state.response_revision
end

---Clear completion state.
function CompletionProvider:clear()
  self._state = {
    is_trigger_character_completion = false,
    request_state = RequestState.Waiting,
    request_time = 0,
    response_revision = self._state.response_revision,
    dedup_map = kit.clear(self._state.dedup_map),
    items = kit.clear(self._state.items),
    matches = kit.clear(self._state.matches),
    matches_items = kit.clear(self._state.matches_items),
  }
end

---Return items.
---@return cmp-kit.completion.CompletionItem[]
function CompletionProvider:get_items()
  return self._state.items or {}
end

---Return current completion is triggered by character or not.
---@return boolean
function CompletionProvider:in_trigger_character_completion()
  local in_trigger_char = true
  in_trigger_char = in_trigger_char and self._state.is_trigger_character_completion
  in_trigger_char = in_trigger_char and #self:get_items() > 0
  return in_trigger_char
end

---Check if the provider is fetching.
---@param timeout integer
---@return boolean
function CompletionProvider:is_fetching(timeout)
  timeout = timeout or (5 * 1000)

  if self._state.request_state ~= RequestState.Fetching then
    return false
  end
  return ((vim.uv.hrtime() / 1e6) - self._state.request_time) < timeout
end

---Check the context is in completion.
---@param trigger_context cmp-kit.core.TriggerContext
---@return boolean
function CompletionProvider:in_completion_context(trigger_context)
  local character1 = trigger_context.character + 1
  local in_completion = true
  in_completion = in_completion and not not self._state.trigger_context
  in_completion = in_completion and self._state.trigger_context.bufnr == trigger_context.bufnr
  in_completion = in_completion and self._state.trigger_context.line == trigger_context.line
  in_completion = in_completion and self._state.completion_offset ~= nil
  in_completion = in_completion and self._state.completion_offset <= character1
  return in_completion
end

---Return matches.
---@param trigger_context cmp-kit.core.TriggerContext
---@param config cmp-kit.completion.CompletionService.Config
---@return cmp-kit.completion.Match[]
function CompletionProvider:get_matches(trigger_context, config)
  if not self:in_completion_context(trigger_context) then
    return {}
  end

  local next_before_text = trigger_context.text_before
  local prev_before_text = self._state.matches_before_text
  self._state.matches_before_text = next_before_text

  -- completely same situation.
  if prev_before_text and prev_before_text == next_before_text then
    return self._state.matches
  end

  -- filtering items.
  kit.clear(self._state.matches)
  kit.clear(self._state.matches_items)
  for _, item in ipairs(self._state.items) do
    local query_text = trigger_context:get_query(item:get_offset())
    local filter_text = item:get_filter_text()
    local score, match_positions = config.matcher(query_text, filter_text)
    if score > 0 then
      local label_text = item:get_label_text()
      if label_text ~= filter_text then
        query_text = trigger_context:get_query(self._state.completion_offset)
        _, match_positions = config.matcher(query_text, label_text)
      end
      self._state.matches_items[#self._state.matches_items + 1] = item
      self._state.matches[#self._state.matches + 1] = {
        provider = self,
        item = item,
        score = score,
        index = 0, -- assign later.
        match_positions = match_positions,
      }
    end
  end
  return self._state.matches
end

---Create default insert range from keyword pattern.
---@return cmp-kit.kit.LSP.Range utf8 byte index
function CompletionProvider:get_default_insert_range()
  if not self._state.trigger_context then
    error('The CompletionProvider: can only be called after completion has been called.')
  end

  local keyword_pattern = self:get_keyword_pattern()
  local cache_key = string.format('%s:%s', 'CompletionProvider:get_default_insert_range', keyword_pattern)
  if not self._state.trigger_context.cache[cache_key] then
    local r = extract_keyword_range(self._state.trigger_context, keyword_pattern)
    self._state.trigger_context.cache[cache_key] = {
      start = {
        line = self._state.trigger_context.line,
        character = r[1] - 1,
      },
      ['end'] = {
        line = self._state.trigger_context.line,
        character = self._state.trigger_context.character,
      },
    }
  end
  return self._state.trigger_context.cache[cache_key]
end

---Create default replace range from keyword pattern.
---@return cmp-kit.kit.LSP.Range utf8 byte index
function CompletionProvider:get_default_replace_range()
  if not self._state.trigger_context then
    error('The CompletionProvider: can only be called after completion has been called.')
  end

  local keyword_pattern = self:get_keyword_pattern()
  local cache_key = string.format('%s:%s', 'CompletionProvider:get_default_replace_range', keyword_pattern)
  if not self._state.trigger_context.cache[cache_key] then
    local r = extract_keyword_range(self._state.trigger_context, keyword_pattern)
    self._state.trigger_context.cache[cache_key] = {
      start = {
        line = self._state.trigger_context.line,
        character = r[1] - 1,
      },
      ['end'] = {
        line = self._state.trigger_context.line,
        character = r[2] - 1,
      },
    }
  end
  return self._state.trigger_context.cache[cache_key]
end

return CompletionProvider
