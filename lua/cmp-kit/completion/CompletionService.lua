---@diagnostic disable: invisible
local kit = require('cmp-kit.kit')
local Async = require('cmp-kit.kit.Async')
local ScheduledTimer = require('cmp-kit.kit.Async.ScheduledTimer')
local Timing = require('cmp-kit.kit.Async.Timing')
local Keymap = require('cmp-kit.kit.Vim.Keymap')
local Buffer = require('cmp-kit.core.Buffer')
local LinePatch = require('cmp-kit.core.LinePatch')
local Character = require('cmp-kit.kit.App.Character')
local DefaultConfig = require('cmp-kit.completion.ext.DefaultConfig')
local TriggerContext = require('cmp-kit.core.TriggerContext')
local CompletionProvider = require('cmp-kit.completion.CompletionProvider')

local tmp_tbls = {
  dedup_map = {},
}

---Emit events.
---@generic T
---@param events fun(payload: T)[]
---@param payload T
local function emit(events, payload)
  for _, event in ipairs(events or {}) do
    event(payload)
  end
end

---@class cmp-kit.completion.CompletionService.RegisterProviderParams
---@field group? integer
---@field priority? integer
---@field dedup? boolean
---@field keyword_length? integer
---@field item_count? integer

---@class cmp-kit.completion.CompletionService.ProviderConfiguration
---@field public group integer
---@field public priority integer
---@field public provider cmp-kit.completion.CompletionProvider

---@class cmp-kit.completion.CompletionService.Config.Performance
---@field public fetching_timeout_ms? integer
---@field public menu_update_throttle_ms? integer

---@class cmp-kit.completion.CompletionService.Config
---@field public expand_snippet? cmp-kit.completion.ExpandSnippet
---@field public is_macro_recording? fun(): boolean
---@field public is_macro_executing? fun(): boolean
---@field public preselect? boolean
---@field public view cmp-kit.completion.CompletionView
---@field public sorter cmp-kit.completion.Sorter
---@field public matcher cmp-kit.completion.Matcher
---@field public performance cmp-kit.completion.CompletionService.Config.Performance
---@field public default_keyword_pattern string

---@class cmp-kit.completion.CompletionService.State
---@field public complete_trigger_context cmp-kit.core.TriggerContext
---@field public matching_trigger_context cmp-kit.core.TriggerContext
---@field public selection cmp-kit.completion.Selection
---@field public matches cmp-kit.completion.Match[]

---@class cmp-kit.completion.CompletionService
---@field private _id integer
---@field private _ns integer
---@field private _disposed boolean
---@field private _preventing integer
---@field private _events table<string, function[]>
---@field private _config cmp-kit.completion.CompletionService.Config
---@field private _state cmp-kit.completion.CompletionService.State
---@field private _provider_configurations (cmp-kit.completion.CompletionService.ProviderConfiguration|{ index: integer })[]
---@field private _keys table<string, string>
---@field private _macro_completions cmp-kit.kit.Async.AsyncTask[]
---@field private _matching_throttled cmp-kit.kit.Async.Timing.TimingFunction
---@field private _menu_hide_timer cmp-kit.kit.Async.ScheduledTimer
local CompletionService = {}
CompletionService.__index = CompletionService

---Create a new CompletionService.
---@param config? cmp-kit.completion.CompletionService.Config|{}
---@return cmp-kit.completion.CompletionService
function CompletionService.new(config)
  local id = kit.unique_id()
  local self = setmetatable({
    _id = id,
    _ns = vim.api.nvim_create_namespace(('cmp-kit:%s'):format(id)),
    _disposed = false,
    _preventing = 0,
    _events = {},
    _state = {
      complete_trigger_context = TriggerContext.create_empty_context(),
      matching_trigger_context = TriggerContext.create_empty_context(),
      selection = {
        index = 0,
        preselect = true,
        text_before = '',
      },
      matches = {},
    },
    _config = kit.merge(config or {}, DefaultConfig),
    _provider_configurations = {},
    _keys = {},
    _macro_completions = {},
    _menu_hide_timer = ScheduledTimer.new(),
  }, CompletionService)

  -- create throttled matching function.
  do
    local throttled = Timing.throttle(function()
      self:matching()
    end, {
      timeout_ms = self._config.performance.menu_update_throttle_ms
    })
    self._matching_throttled = function()
      if self._config.is_macro_executing() then
        self:matching()
      else
        throttled()
      end
    end
  end

  -- support macro.
  do
    self._keys.macro_complete_auto = ('<Plug>(cmp-kit:c:%s:auto)'):format(self._id)
    self._keys.macro_complete_auto_termcodes = Keymap.termcodes(self._keys.macro_complete_auto)
    vim.keymap.set({ 'i', 's', 'c', 'n', 'x', 't' }, self._keys.macro_complete_auto, function()
      local is_valid_mode = vim.tbl_contains({ 'i', 'c' }, vim.api.nvim_get_mode().mode)
      if is_valid_mode and self._config.is_macro_executing() then
        self:complete({ force = false })
      end
    end)
    self._keys.macro_complete_force = ('<Plug>(cmp-kit:c:%s:force)'):format(self._id)
    self._keys.macro_complete_force_termcodes = Keymap.termcodes(self._keys.macro_complete_force)
    vim.keymap.set({ 'i', 's', 'c', 'n', 'x', 't' }, self._keys.macro_complete_force, function()
      local is_valid_mode = vim.tbl_contains({ 'i', 'c' }, vim.api.nvim_get_mode().mode)
      if is_valid_mode and self._config.is_macro_executing() then
        self:complete({ force = true })
      end
    end)
  end

  -- support commitCharacters.
  vim.on_key(function(_, typed)
    if not typed or #typed ~= 1 then
      return
    end
    local b = typed:byte(1)
    if not (32 <= b and b <= 126) then
      return
    end

    local selection = self:get_selection()
    if selection.index > 0 then
      local match = self:get_matches()[selection.index]
      if match and match.item then
        if vim.tbl_contains(match.item:get_commit_characters(), typed) then
          -- remove typeahead.
          while true do
            local c = vim.fn.getcharstr(0)
            if c == '' then
              break
            end
          end

          local pre_trigger_context = TriggerContext.create()
          self
              :commit(match.item, {
                replace = false,
              })
              :next(function()
                -- NOTE: cmp-kit's specific implementation.
                -- after commit character, send canceled key if possible.
                local trigger_context = TriggerContext.create()
                local added_text = trigger_context.text_before:sub(pre_trigger_context.character + 1)
                local preview_text = match.item:get_preview_text()

                local can_feedkeys = true
                can_feedkeys = can_feedkeys and trigger_context.mode == 'i'
                can_feedkeys = can_feedkeys and trigger_context.text_before:sub(- #preview_text) == preview_text
                can_feedkeys = can_feedkeys and not added_text:find(typed)
                if can_feedkeys then
                  vim.api.nvim_feedkeys(typed, 'i', true)
                end
              end)
          return ''
        end
      end
    end
  end, vim.api.nvim_create_namespace(('cmp-kit:%s'):format(self._id)), {})

  return self
end

---Set config.
---@param config cmp-kit.completion.CompletionService.Config
function CompletionService:set_config(config)
  self._config = config
end

---Get config.
---@return cmp-kit.completion.CompletionService.Config
function CompletionService:get_config()
  return self._config
end

---Register on_menu_show event.
---@param callback fun(payload: { service: cmp-kit.completion.CompletionService })
---@return fun()
function CompletionService:on_menu_show(callback)
  self._events = self._events or {}
  self._events.on_menu_hide = self._events.on_menu_hide or {}
  table.insert(self._events.on_menu_hide, callback)
  return function()
    for i, c in ipairs(self._events.on_menu_hide) do
      if c == callback then
        table.remove(self._events.on_menu_hide, i)
        break
      end
    end
  end
end

---Register on_menu_hide event.
---@param callback fun(payload: { service: cmp-kit.completion.CompletionService })
---@return fun()
function CompletionService:on_menu_hide(callback)
  self._events = self._events or {}
  self._events.on_menu_hide = self._events.on_menu_hide or {}
  table.insert(self._events.on_menu_hide, callback)
  return function()
    for i, c in ipairs(self._events.on_menu_hide) do
      if c == callback then
        table.remove(self._events.on_menu_hide, i)
        break
      end
    end
  end
end

---Register on_menu_update event.
---@param callback fun(payload: { service: cmp-kit.completion.CompletionService })
---@return fun()
function CompletionService:on_menu_update(callback)
  self._events = self._events or {}
  self._events.on_menu_update = self._events.on_menu_update or {}
  table.insert(self._events.on_menu_update, callback)
  return function()
    for i, c in ipairs(self._events.on_menu_update) do
      if c == callback then
        table.remove(self._events.on_menu_update, i)
        break
      end
    end
  end
end

---Register on_commit event.
---@param callback fun(payload: { service: cmp-kit.completion.CompletionService })
---@return fun()
function CompletionService:on_commit(callback)
  self._events = self._events or {}
  self._events.on_commit = self._events.on_commit or {}
  table.insert(self._events.on_commit, callback)
  return function()
    for i, c in ipairs(self._events.on_commit) do
      if c == callback then
        table.remove(self._events.on_commit, i)
        break
      end
    end
  end
end

---Register on_dispose event.
---@param callback fun(payload: { service: cmp-kit.completion.CompletionService })
---@return fun()
function CompletionService:on_dispose(callback)
  self._events = self._events or {}
  self._events.on_dispose = self._events.on_dispose or {}
  table.insert(self._events.on_dispose, callback)
  return function()
    for i, c in ipairs(self._events.on_dispose) do
      if c == callback then
        table.remove(self._events.on_dispose, i)
        break
      end
    end
  end
end

---Dispose completion service.
function CompletionService:dispose()
  if self._disposed then
    return
  end
  self._disposed = true

  self:clear()
  self._config.view:dispose()
  vim.on_key(nil, self._ns, {})

  emit(self._events.on_dispose, { service = self })
end

---Register source.
---@param source cmp-kit.completion.CompletionSource
---@param params? cmp-kit.completion.CompletionService.RegisterProviderParams
---@return fun(): nil
function CompletionService:register_source(source, params)
  ---@type cmp-kit.completion.CompletionService.ProviderConfiguration|{ index: integer }
  local provider_configuration = {
    index = #self._provider_configurations + 1,
    group = params and params.group or 0,
    priority = params and params.priority or 0,
    provider = CompletionProvider.new(source, {
      dedup = params and params.dedup or false,
      item_count = params and params.item_count or math.huge,
      keyword_length = params and params.keyword_length or 1,
    }),
  }
  table.insert(self._provider_configurations, provider_configuration)
  return function()
    for i, c in ipairs(self._provider_configurations) do
      if c == provider_configuration then
        table.remove(self._provider_configurations, i)
        break
      end
    end
  end
end

---Clear completion.
function CompletionService:clear()
  for _, provider_group in ipairs(self:_get_provider_groups()) do
    for _, provider_configuration in ipairs(provider_group) do
      provider_configuration.provider:clear()
    end
  end

  -- reset current TriggerContext for preventing new completion in same context.
  self._state = {
    complete_trigger_context = TriggerContext.create(),
    matching_trigger_context = TriggerContext.create(),
    selection = {
      index = 0,
      preselect = true,
      text_before = '',
    },
    matches = kit.clear(self._state.matches),
  }

  self._menu_hide_timer:stop()
  local is_menu_visible = self._config.view:is_menu_visible()
  self._config.view:hide()
  if is_menu_visible then
    emit(self._events.on_menu_hide, { service = self })
  end
end

---Is menu visible.
---@return boolean
function CompletionService:is_menu_visible()
  return self._config.view:is_menu_visible()
end

---Is docs visible.
---@return boolean
function CompletionService:is_docs_visible()
  return self._config.view:is_docs_visible()
end

---Show documentation window.
function CompletionService:show_docs()
  self._config.view:show_docs()
end

---Hide documentation window.
function CompletionService:hide_docs()
  self._config.view:hide_docs()
end

---Select completion.
---@param index integer
---@param preselect? boolean
---@return cmp-kit.kit.Async.AsyncTask
function CompletionService:select(index, preselect)
  if self._config.is_macro_executing() then
    self:_wait_for_stable()
    self._state.matching_trigger_context = TriggerContext.create_empty_context()
    self:matching()
  end

  local prev_index = self._state.selection.index
  local next_index = index % (#self._state.matches + 1)
  if prev_index == next_index then
    return Async.resolve()
  end

  -- store current leading text for de-selecting.
  local text_before = self._state.selection.text_before
  if prev_index == 0 then
    text_before = TriggerContext.create().text_before
  end
  self:_update_selection(next_index, not not preselect, text_before)

  -- inesrt selection.
  return Async.run(function()
    if not preselect then
      local prev_match = self._state.matches[prev_index]
      local next_match = self._state.matches[next_index]
      self:_insert_selection(
        self._state.selection.text_before,
        next_match and next_match.item,
        prev_match and prev_match.item
      ):await()
    end
  end)
end

---Scroll docs window.
---@param delta integer
function CompletionService:scroll_docs(delta)
  self._config.view:scroll_docs(delta)
end

---Get selection.
---@return cmp-kit.completion.Selection
function CompletionService:get_selection()
  if self._config.is_macro_executing() then
    self:_wait_for_stable()
    self._state.matching_trigger_context = TriggerContext.create_empty_context()
    self:matching()
  end
  return kit.clone(self._state.selection)
end

---Get matches.
---@return cmp-kit.completion.Match[]
function CompletionService:get_matches()
  return self._state.matches
end

do
  ---@param self cmp-kit.completion.CompletionService
  ---@param trigger_context cmp-kit.core.TriggerContext
  local function complete_inner(self, trigger_context)
    -- reset selection for new completion.
    self._state.selection = {
      index = 0,
      preselect = false,
      text_before = trigger_context.text_before,
    }

    -- trigger.
    local tasks = {} --[=[@type cmp-kit.kit.Async.AsyncTask[]]=]
    local invoked = false
    for _, group in ipairs(self:_get_provider_groups()) do
      for _, cfg in ipairs(group) do
        if cfg.provider:capable() then
          table.insert(
            tasks,
            cfg.provider:complete(trigger_context, function(step)
              if step == 'send-request' then
                invoked = true
              end
              if step == 'adopt-response' then
                if not self:_is_prior_provider_fetching(cfg.provider) then
                  self._state.matching_trigger_context = TriggerContext.create_empty_context()
                  self._matching_throttled()
                end
              end
            end)
          )
        end
      end
    end

    if invoked then
      if not self._config.is_macro_executing() then
        if trigger_context.force then
          vim.api.nvim_feedkeys(self._keys.macro_complete_force_termcodes, 'int', true)
        else
          vim.api.nvim_feedkeys(self._keys.macro_complete_auto_termcodes, 'int', true)
        end
      end
      table.insert(
        tasks,
        Async.timeout(self._config.performance.fetching_timeout_ms):next(function()
          self._matching_throttled()
        end)
      )
    else
      self._matching_throttled()
    end

    return Async.all(tasks)
  end

  ---Invoke completion.
  ---@param option? { force: boolean? }
  ---@return cmp-kit.kit.Async.AsyncTask
  function CompletionService:complete(option)
    if self:_dispose_or_preventing() then
      return Async.resolve()
    end

    local trigger_context = TriggerContext.create(option)
    local changed = self._state.complete_trigger_context:changed(trigger_context)
    if not changed then
      return Async.resolve()
    end
    self._state.complete_trigger_context = trigger_context

    local task = Async.run(function()
      return complete_inner(self, trigger_context)
    end)
    if self._config.is_macro_executing() then
      table.insert(self._macro_completions, task)
    end
    return task
  end
end

---Match completion items.
function CompletionService:matching()
  if self:_dispose_or_preventing() then
    return
  end
  if self:_is_active_selection() then
    return
  end

  local trigger_context = TriggerContext.create()
  local changed = self._state.matching_trigger_context:changed(trigger_context)
  if not changed then
    return
  end
  self._state.matching_trigger_context = trigger_context

  local is_menu_visible = self:is_menu_visible()

  -- update matches.
  self._state.matches = {}
  local is_completion_fetching = false
  local in_trigger_character_completion = false
  for _, group in ipairs(self:_get_provider_groups()) do
    local cfgs_keyword = {} --[=[@type cmp-kit.completion.CompletionService.ProviderConfiguration[]]=]
    local cfgs_trigger_character = {} --[=[@type cmp-kit.completion.CompletionService.ProviderConfiguration[]]=]
    for _, cfg in ipairs(group) do
      if cfg.provider:capable() then
        if not is_menu_visible and not trigger_context.force then
          local is_fetching = true
          is_fetching = is_fetching and cfg.provider:is_fetching(self._config.performance.fetching_timeout_ms)
          is_fetching = is_fetching and #cfg.provider:get_items() == 0
          if is_fetching then
            is_completion_fetching = true
            break
          end
        end
        if cfg.provider:in_trigger_character_completion() then
          table.insert(cfgs_trigger_character, cfg)
          in_trigger_character_completion = true
        else
          table.insert(cfgs_keyword, cfg)
        end
      end
    end

    -- gather trigger character items.
    local offsets = {}
    for _, cfg in ipairs(cfgs_trigger_character) do
      local score_boost = self:_get_score_boost(cfg.provider)
      for _, match in ipairs(cfg.provider:get_matches(trigger_context, self._config)) do
        match.score = match.score + score_boost
        self._state.matches[#self._state.matches + 1] = match
        offsets[match.item:get_offset()] = true
        match.index = #self._state.matches
      end
    end

    -- gather keyword items.
    for _, cfg in ipairs(cfgs_keyword) do
      if #self._state.matches == 0 or not offsets[cfg.provider:get_completion_offset()] or trigger_context.force then
        local score_boost = self:_get_score_boost(cfg.provider)
        for _, match in ipairs(cfg.provider:get_matches(trigger_context, self._config)) do
          match.score = match.score + score_boost
          self._state.matches[#self._state.matches + 1] = match
          match.index = #self._state.matches
        end
      end
    end

    -- check should use this group?
    if #self._state.matches > 0 or in_trigger_character_completion then
      break
    end
    if is_completion_fetching then
      break
    end
  end

  self._menu_hide_timer:stop()

  -- check this group should be accepted?
  if #self._state.matches > 0 then
    -- group matches are found.
    local locality_map = {}
    if not self._config.is_macro_executing() and not self._config.is_macro_recording() then
      local cur_above = vim.api.nvim_win_get_cursor(0)[1] - 1
      local min_row = math.max(1, cur_above - 30)
      local max_row = cur_above
      for row = min_row, max_row do
        for _, word in ipairs(Buffer.ensure(0):get_words(self._config.default_keyword_pattern, row)) do
          locality_map[word] = math.min(locality_map[word] or math.huge, math.abs(cur_above - row))
        end
      end
    end
    local sorted_matches = self._config.sorter.sort(self._state.matches, {
      locality_map = locality_map,
      trigger_context = trigger_context,
    })

    -- 1. search preselect_index.
    -- 2. check item_count.
    -- 3. check dedup.
    local preselect_index = nil --[[@as integer?]]
    do
      local item_count_per_provider = {}

      local dedup_map = kit.clear(tmp_tbls.dedup_map)
      local limited_matches = {}
      for j, match in ipairs(sorted_matches) do
        -- set first preselect index.
        if self._config.preselect then
          if not preselect_index and match.item:is_preselect() then
            preselect_index = j
          end
        end

        -- check dedup & count.
        local is_dedup_ok = not match.provider.config.dedup or not dedup_map[match.item:get_label_text()]
        local is_count_ok = match.provider.config.item_count >= (item_count_per_provider[match.provider] or 0)
        if is_count_ok and is_dedup_ok then
          table.insert(limited_matches, match)
          item_count_per_provider[match.provider] = (item_count_per_provider[match.provider] or 0) + 1
        end
        dedup_map[match.item:get_label_text()] = true
      end
      self._state.matches = limited_matches
    end

    -- emit selection.
    if preselect_index then
      self:_update_selection(preselect_index --[[@as integer]], true)
    end

    -- completion found.
    if not self._config.is_macro_executing() then
      self._config.view:show({
        matches = self._state.matches,
        selection = self._state.selection,
      })
      emit(self._events.on_menu_update, { service = self })
      if not is_menu_visible then
        emit(self._events.on_menu_show, { service = self })
      end
      -- re-emit selection.
      if preselect_index then
        self:_update_selection(preselect_index --[[@as integer]], true)
      end
    end
  else
    if not self._config.is_macro_executing() then
      local timeout_ms = 1
      for _, group in ipairs(self:_get_provider_groups()) do
        for _, cfg in ipairs(group) do
          if cfg.provider:is_fetching(self._config.performance.fetching_timeout_ms) then
            timeout_ms = self._config.performance.fetching_timeout_ms
          end
        end
      end
      self._menu_hide_timer:start(timeout_ms, 0, function()
        is_menu_visible = self:is_menu_visible()
        self._config.view:hide()
        if is_menu_visible then
          emit(self._events.on_menu_hide, { service = self })
        end
      end)
    end
  end
end

---Commit completion.
---@param item cmp-kit.completion.CompletionItem
---@param option? { replace?: boolean, no_snippet?: boolean }
function CompletionService:commit(item, option)
  option = option or {}
  option.replace = option.replace or false
  option.no_snippet = option.no_snippet or false

  if self._config.is_macro_executing() then
    self:_wait_for_stable()
    self._state.matching_trigger_context = TriggerContext.create_empty_context()
    self:matching()
  end

  return item
      :commit({
        replace = option and option.replace,
        expand_snippet = not option.no_snippet and self._config.expand_snippet or nil,
      })
      :next(self:prevent())
      :next(function()
        self:clear()
        emit(self._events.on_commit, { service = self })

        -- re-trigger completion for trigger characters.
        local trigger_context = TriggerContext.create()
        if trigger_context.trigger_character and Character.is_symbol(trigger_context.trigger_character:byte(1)) then
          for _, provider_group in ipairs(self:_get_provider_groups()) do
            for _, cfg in ipairs(provider_group) do
              if cfg.provider:capable() then
                if vim.tbl_contains(cfg.provider:get_trigger_characters(), trigger_context.trigger_character) then
                  self._state.complete_trigger_context = TriggerContext.create_empty_context()
                  return self:complete()
                end
              end
            end
          end
        end
      end)
end

---Prevent completion.
---@return fun(): cmp-kit.kit.Async.AsyncTask
function CompletionService:prevent()
  self._preventing = self._preventing + 1
  self._state.complete_trigger_context = TriggerContext.create()
  self._state.matching_trigger_context = TriggerContext.create()
  return function()
    return Async.run(function()
      if not self._config.is_macro_executing() then
        Async.new(function(resolve)
          vim.api.nvim_create_autocmd('SafeState', {
            once = true,
            callback = resolve,
          })
        end):await()
      end
      self._state.complete_trigger_context = TriggerContext.create()
      self._state.matching_trigger_context = TriggerContext.create()
      self._preventing = self._preventing - 1
    end)
  end
end

---Is active selection.
---@return boolean
function CompletionService:_is_active_selection()
  local selection = self._state.selection
  return not selection.preselect and selection.index > 0
end

---Get provider groups.
---@return cmp-kit.completion.CompletionService.ProviderConfiguration[][]
function CompletionService:_get_provider_groups()
  -- sort by group.
  table.sort(self._provider_configurations, function(a, b)
    if a.group ~= b.group then
      return a.group < b.group
    end
    if a.priority ~= b.priority then
      return a.priority > b.priority
    end
    return a.index < b.index
  end)

  -- group by group.
  local groups = {}
  for _, provider_configuration in ipairs(self._provider_configurations) do
    if not groups[provider_configuration.group] then
      groups[provider_configuration.group] = {}
    end
    table.insert(groups[provider_configuration.group], provider_configuration)
  end

  -- create group_index.
  local group_indexes = vim.tbl_keys(groups)
  table.sort(group_indexes)

  -- sort by group.
  local sorted_groups = {}
  for _, group_index in ipairs(group_indexes) do
    table.insert(sorted_groups, groups[group_index])
  end
  return sorted_groups
end

---Get score boost.
---@param provider cmp-kit.completion.CompletionProvider
---@return number
function CompletionService:_get_score_boost(provider)
  local boost = 0
  for _, group in ipairs(self:_get_provider_groups()) do
    for i, cfg in ipairs(group) do
      if cfg.provider == provider then
        boost = boost + (#group - i) * 5
        boost = boost + (provider:in_trigger_character_completion() and 10 or 0)
        break
      end
    end
  end
  return boost
end

---Update selection
---@param index integer
---@param preselect boolean
---@param text_before? string
function CompletionService:_update_selection(index, preselect, text_before)
  self._state.selection = {
    index = index,
    preselect = preselect,
    text_before = text_before or self._state.selection.text_before,
  }
  if not self._config.is_macro_executing() then
    if self._config.view:is_menu_visible() then
      self._config.view:select({ selection = self._state.selection })
    end
  end
end

---Insert selection.
---@param text_before string
---@param item_next? cmp-kit.completion.CompletionItem
---@param item_prev? cmp-kit.completion.CompletionItem
---@return cmp-kit.kit.Async.AsyncTask
function CompletionService:_insert_selection(text_before, item_next, item_prev)
  local trigger_context = TriggerContext.create()
  local prev_offset = item_prev and item_prev:get_offset() - 1 or #text_before
  local next_offset = item_next and item_next:get_offset() - 1 or #text_before
  local to_remove_offset = math.min(prev_offset, next_offset, #text_before)
  local resume = self:prevent()
  return LinePatch.apply_by_keys(
    0,
    trigger_context.character - to_remove_offset,
    0,
    ('%s%s'):format(
      text_before:sub(prev_offset + 1, next_offset),
      item_next and item_next:get_preview_text() or ''
    )):next(resume)
end

---Wait for stable state.
---@param timeout? integer
function CompletionService:_wait_for_stable(timeout)
  timeout = timeout or (2 * 1000)

  local tasks = self._macro_completions
  self._macro_completions = {}
  Async.all(tasks):sync(2 * 1000)
end

---Check invalid state.
---@return boolean
function CompletionService:_dispose_or_preventing()
  if self._disposed then
    return true
  end
  if self._preventing > 0 then
    return true
  end
  return false
end

---Check if prior provider is fetching.
---@param provider cmp-kit.completion.CompletionProvider
---@return boolean
function CompletionService:_is_prior_provider_fetching(provider)
  for _, group in ipairs(self:_get_provider_groups()) do
    for _, cfg in ipairs(group) do
      if cfg.provider == provider then
        return false
      end
      if cfg.provider:is_fetching(self._config.performance.fetching_timeout_ms) then
        return true
      end
    end
  end
  return false
end

return CompletionService
