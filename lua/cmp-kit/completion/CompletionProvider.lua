---@diagnostic disable: invisible
local kit            = require('cmp-kit.kit')
local LSP            = require('cmp-kit.kit.LSP')
local Async          = require('cmp-kit.kit.Async')
local RegExp         = require('cmp-kit.kit.Vim.RegExp')
local CompletionItem = require('cmp-kit.completion.CompletionItem')
local DefaultConfig  = require('cmp-kit.completion.ext.DefaultConfig')

---@enum cmp-kit.completion.CompletionProvider.RequestState
local RequestState   = {
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
---@return cmp-kit.kit.Async.AsyncTask cmp-kit.kit.LSP.CompletionContext?
function CompletionProvider:complete(trigger_context)
  return Async.run(function()
    local trigger_characters = self:get_trigger_characters()
    local keyword_pattern = self:get_keyword_pattern()
    local keyword_offset = trigger_context:get_keyword_offset(keyword_pattern)
    local is_same_offset = keyword_offset and keyword_offset == self._state.completion_offset

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
        if is_same_offset and self._state.is_incomplete then
          -- keyword completion for incomplete completion.
          completion_context = {
            triggerKind = LSP.CompletionTriggerKind.TriggerForIncompleteCompletions,
          }
          completion_offset = keyword_offset
        elseif not is_same_offset then
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
      return
    end

    local is_trigger_char = false
    is_trigger_char = is_trigger_char or (
      completion_context.triggerKind == LSP.CompletionTriggerKind.TriggerCharacter
    )
    is_trigger_char = is_trigger_char or (
      self:in_trigger_character_completion() and
      completion_context.triggerKind == LSP.CompletionTriggerKind.TriggerForIncompleteCompletions
    )
    self._state.is_trigger_character_completion = is_trigger_char
    if completion_context.triggerKind ~= LSP.CompletionTriggerKind.TriggerForIncompleteCompletions then
      self._state.request_state = RequestState.Fetching
      self._state.request_time = vim.uv.hrtime() / 1e6
    end
    self._state.trigger_context = trigger_context
    self._state.completion_context = completion_context
    self._state.completion_offset = completion_offset

    -- invoke completion.
    local raw_response = self._source:complete(completion_context):await()

    -- ignore obsolete response.
    if self._state.trigger_context ~= trigger_context then
      return
    end

    -- adopt response.
    self:_adopt_response(trigger_context, completion_context, to_completion_list(raw_response))

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

  -- do not keep previous state if completion is not incomplete.
  if completion_context.triggerKind ~= LSP.CompletionTriggerKind.TriggerForIncompleteCompletions then
    kit.clear(self._state.dedup_map)
    kit.clear(self._state.items)
  end

  -- convert response to items.
  local cursor = { line = trigger_context.line, character = trigger_context.character }
  for _, item in ipairs(list.items) do
    local completion_item = CompletionItem.new(trigger_context, self, list, item)

    -- check insert range.
    local r = completion_item:get_insert_range()
    local s = (r.start.line == cursor.line and r.start.character <= cursor.character) or r.start.line < cursor.line
    local e = (r['end'].line == cursor.line and r['end'].character >= cursor.character) or r['end'].line > cursor.line
    local is_valid_range = s and e

    -- check dedup.
    local is_deduped = false
    if completion_context.triggerKind == LSP.CompletionTriggerKind.TriggerForIncompleteCompletions then
      is_deduped = self._state.dedup_map[completion_item:get_label_text()]
    end
    self._state.dedup_map[completion_item:get_label_text()] = true
    if is_valid_range and not is_deduped then
      self._state.items[#self._state.items + 1] = completion_item
    end
  end

  -- clear matching state.
  kit.clear(self._state.matches)
  kit.clear(self._state.matches_items)
  self._state.matches_before_text = nil

  -- increase response_revision if changed.
  self._state.response_revision = self._state.response_revision + 1
end

---Resolve completion item (completionItem/resolve).
---@param item cmp-kit.kit.LSP.CompletionItem
---@return cmp-kit.kit.Async.AsyncTask
function CompletionProvider:resolve(item)
  if not self._source.resolve then
    return Async.resolve(item)
  end
  return self._source:resolve(item)
end

---Execute command (workspace/executeCommand).
---@param command cmp-kit.kit.LSP.Command
---@return cmp-kit.kit.Async.AsyncTask
function CompletionProvider:execute(command)
  if not self._source.execute then
    return Async.resolve()
  end
  return self._source:execute(command)
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

---Return request state.
---@return cmp-kit.completion.CompletionProvider.RequestState
function CompletionProvider:get_request_state()
  return self._state.request_state
end

---Return request state.
---@return integer
function CompletionProvider:get_request_time()
  return self._state.request_time
end

---Return response revision.
---@return integer
function CompletionProvider:get_response_revision()
  return self._state.response_revision
end

---Return current completion context.
---@return cmp-kit.kit.LSP.CompletionContext?
function CompletionProvider:get_completion_context()
  return self._state.completion_context
end

---Clear completion state.
function CompletionProvider:clear()
  self._state = {
    is_trigger_character_completion = false,
    request_state = RequestState.Waiting,
    request_time = 0,
    response_revision = self._state.response_revision + (#self._state.items == 0 and 0 or 1),
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
  return self._state.is_trigger_character_completion and #self:get_items() > 0
end

---Return matches.
---@param trigger_context cmp-kit.core.TriggerContext
---@param config cmp-kit.completion.CompletionService.Config
---@return cmp-kit.completion.Match[]
function CompletionProvider:get_matches(trigger_context, config)
  local is_acceptable = not not self._state.trigger_context
  is_acceptable = is_acceptable and self._state.trigger_context.bufnr == trigger_context.bufnr
  is_acceptable = is_acceptable and self._state.trigger_context.line == trigger_context.line
  is_acceptable = is_acceptable and self._state.completion_offset ~= nil
  is_acceptable = is_acceptable and self._state.completion_offset <= trigger_context.character + 1
  if not is_acceptable then
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
  for i, item in ipairs(self._state.items) do
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
        index = i,
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
