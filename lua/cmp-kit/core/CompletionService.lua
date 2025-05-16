---@diagnostic disable: invisible
local kit = require('cmp-kit.kit')
local Async = require('cmp-kit.kit.Async')
local Keymap = require('cmp-kit.kit.Vim.Keymap')
local ScheduledTimer = require('cmp-kit.kit.Async.ScheduledTimer')
local Buffer = require('cmp-kit.core.Buffer')
local LinePatch = require('cmp-kit.core.LinePatch')
local Character = require('cmp-kit.core.Character')
local DefaultConfig = require('cmp-kit.core.DefaultConfig')
local TriggerContext = require('cmp-kit.core.TriggerContext')
local CompletionProvider = require('cmp-kit.core.CompletionProvider')

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

---@class cmp-kit.core.CompletionService.ProviderConfiguration
---@field public group integer
---@field public priority integer
---@field public dedup boolean
---@field public item_count integer
---@field public provider cmp-kit.core.CompletionProvider

---@class cmp-kit.core.CompletionService.Config
---@field public expand_snippet? cmp-kit.core.ExpandSnippet
---@field public sync_mode? fun(): boolean
---@field public view cmp-kit.core.View
---@field public sorter cmp-kit.core.Sorter
---@field public matcher cmp-kit.core.Matcher
---@field public performance { fetching_timeout_ms?: integer }
---@field public default_keyword_pattern string

---@class cmp-kit.core.CompletionService.State
---@field public complete_trigger_context cmp-kit.core.TriggerContext
---@field public matching_trigger_context cmp-kit.core.TriggerContext
---@field public selection cmp-kit.core.Selection
---@field public matches cmp-kit.core.Match[]

---@class cmp-kit.core.CompletionService
---@field private _id integer
---@field private _ns integer
---@field private _disposed boolean
---@field private _preventing integer
---@field private _matching_timer cmp-kit.kit.Async.ScheduledTimer
---@field private _events table<string, function[]>
---@field private _state cmp-kit.core.CompletionService.State
---@field private _config cmp-kit.core.CompletionService.Config
---@field private _keys table<string, string>
---@field private _macro_completion cmp-kit.kit.Async.AsyncTask[]
---@field private _provider_configurations (cmp-kit.core.CompletionService.ProviderConfiguration|{ index: integer })[]
local CompletionService = {}
CompletionService.__index = CompletionService

---Create a new CompletionService.
---@param config? cmp-kit.core.CompletionService.Config|{}
---@return cmp-kit.core.CompletionService
function CompletionService.new(config)
  local id = kit.unique_id()
  local self = setmetatable({
    _id = id,
    _ns = vim.api.nvim_create_namespace(('cmp-kit:%s'):format(id)),
    _disposed = false,
    _preventing = 0,
    _matching_timer = ScheduledTimer.new(),
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
    _macro_completion = {},
  } --[[@as cmp-kit.core.CompletionService]], CompletionService)

  -- support macro.
  do
    self._keys.macro_complete_auto = ('<Plug>(cmp-kit:complete:%s:a)'):format(self._id)
    self._keys.macro_complete_auto_termcodes = Keymap.termcodes(self._keys.macro_complete_auto)
    vim.keymap.set({ 'i', 's', 'c', 'n', 'x', 't' }, self._keys.macro_complete_auto, function()
      local is_valid_mode = vim.tbl_contains({ 'i', 'c' }, vim.api.nvim_get_mode().mode)
      if is_valid_mode and self._config.sync_mode() then
        ---@diagnostic disable-next-line: invisible
        table.insert(self._macro_completion, self:complete({ force = false }))
      end
    end)
    self._keys.macro_complete_force = ('<Plug>(cmp-kit:complete:%s:f)'):format(self._id)
    self._keys.macro_complete_force_termcodes = Keymap.termcodes(self._keys.macro_complete_force)
    vim.keymap.set({ 'i', 's', 'c', 'n', 'x', 't' }, self._keys.macro_complete_force, function()
      local is_valid_mode = vim.tbl_contains({ 'i', 'c' }, vim.api.nvim_get_mode().mode)
      if is_valid_mode and self._config.sync_mode() then
        ---@diagnostic disable-next-line: invisible
        table.insert(self._macro_completion, self:complete({ force = true }))
      end
    end)
  end

  -- support commitCharacters.
  vim.on_key(function(_, typed)
    if not typed or typed == '' then
      return
    end

    local selection = self:get_selection()
    if selection.index > 0 then
      local match = self:get_match_at(selection.index)
      if match and match.item then
        if vim.tbl_contains(match.item:get_commit_characters(), typed) then
          while true do
            local c = vim.fn.getcharstr(0)
            if c == '' then
              break
            end
          end
          self:commit(match.item, {
            replace = false,
          }):next(function()
            -- NOTE: cmp-kit's specific implementation.
            -- after commit character, send canceled key if possible.
            local trigger_context = TriggerContext.create()
            local select_text = match.item:get_select_text()

            local can_feedkeys = true
            can_feedkeys = can_feedkeys and trigger_context.mode == 'i'
            can_feedkeys = can_feedkeys and trigger_context.text_before:sub(- #select_text) == select_text
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
---@param config cmp-kit.core.CompletionService.Config
function CompletionService:set_config(config)
  self._config = config
end

---Get config.
---@return cmp-kit.core.CompletionService.Config
function CompletionService:get_config()
  return self._config
end

---Register on_menu_show event.
---@param callback fun(payload: { service: cmp-kit.core.CompletionService })
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
---@param callback fun(payload: { service: cmp-kit.core.CompletionService })
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

---Dispose completion service.
function CompletionService:dispose()
  if self._disposed then
    return
  end
  self._disposed = true

  self._config.view:dispose()
  vim.on_key(nil, self._ns, {})
end

---Register source.
---@param source cmp-kit.core.CompletionSource
---@param config? { group?: integer, priority?: integer, dedup?: boolean, keyword_length?: integer, item_count?: integer }
---@return fun(): nil
function CompletionService:register_source(source, config)
  ---@type cmp-kit.core.CompletionService.ProviderConfiguration|{ index: integer }
  local provider_configuration = {
    index = #self._provider_configurations + 1,
    group = config and config.group or 0,
    priority = config and config.priority or 0,
    dedup = config and config.dedup or false,
    item_count = config and config.item_count or math.huge,
    provider = CompletionProvider.new(source, {
      keyword_length = config and config.keyword_length or 1,
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

  -- reset menu.
  local is_menu_visible = self._config.view:is_menu_visible()
  if not self._config.sync_mode() then
    self._config.view:hide(self._state.matches, self._state.selection)
  end
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

---Select completion.
---@param index integer
---@param preselect? boolean
---@return cmp-kit.kit.Async.AsyncTask
function CompletionService:select(index, preselect)
  if self._config.sync_mode() then
    local tasks = self._macro_completion
    self._macro_completion = {}
    Async.all(tasks):sync(2 * 1000)
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
    self:_update_selection(next_index, not not preselect, text_before)
  end)
end

---Scroll docs window.
---@param delta integer
function CompletionService:scroll_docs(delta)
  self._config.view:scroll_docs(delta)
end

---Get selection.
---@return cmp-kit.core.Selection
function CompletionService:get_selection()
  if self._config.sync_mode() then
    local tasks = self._macro_completion
    self._macro_completion = {}
    Async.all(tasks):sync(2 * 1000)
    self:matching()
  end
  return kit.clone(self._state.selection)
end

---Get match at index.
---@param index integer
---@return cmp-kit.core.Match
function CompletionService:get_match_at(index)
  return self._state.matches[index]
end

do
  ---@param self cmp-kit.core.CompletionService
  ---@param trigger_context cmp-kit.core.TriggerContext
  local function complete_inner(self, trigger_context)
    local changed = self._state.complete_trigger_context:changed(trigger_context)
    if not changed then
      return Async.resolve({})
    end
    self._state.complete_trigger_context = trigger_context

    -- reset selection for new completion.
    self:_update_selection(0, true, trigger_context.text_before)

    -- trigger.
    local tasks = {} --[=[@type cmp-kit.kit.Async.AsyncTask[]]=]
    for _, group in ipairs(self:_get_provider_groups()) do
      local priority = group[1].priority
      for _, cfg in ipairs(group) do
        if cfg.provider:capable(trigger_context) then
          -- wait for high priority provider.
          if cfg.priority ~= priority then
            Async.all(tasks):await()
            if self._state.complete_trigger_context ~= trigger_context then
              return
            end
          end
          priority = cfg.priority

          -- invoke completion.
          local prev_item_count = #cfg.provider:get_items()
          local prev_request_revision = cfg.provider:get_request_revision()
          table.insert(
            tasks,
            Async.race({
              Async.timeout(self._config.performance.fetching_timeout_ms),
              cfg.provider:complete(trigger_context, self._config):next(function()
                local next_item_count = #cfg.provider:get_items()
                if prev_item_count == 0 and next_item_count == 0 then
                  return
                end
                local next_request_revision = cfg.provider:get_request_revision()
                if prev_request_revision ~= next_request_revision then
                  self._state.matching_trigger_context = TriggerContext.create_empty_context()
                  if not self._config.sync_mode() then
                    self:matching()
                  end
                end
              end)
            })
          )
        end
      end

      -- wait for high priority group.
      Async.all(tasks):await()
      if self._state.complete_trigger_context ~= trigger_context then
        return
      end
    end

    -- set new-completion position for macro.
    if not self._config.sync_mode() then
      if trigger_context.force then
        vim.api.nvim_feedkeys(self._keys.macro_complete_force_termcodes, 'nit', true)
      else
        vim.api.nvim_feedkeys(self._keys.macro_complete_auto_termcodes, 'nit', true)
      end
      self:matching() -- if in sync_mode, matching will be done in `select` method.
    end
  end

  ---Invoke completion.
  ---@param option? { force: boolean? }
  ---@return cmp-kit.kit.Async.AsyncTask
  function CompletionService:complete(option)
    local trigger_context = TriggerContext.create(option)
    return Async.run(function()
      complete_inner(self, trigger_context)
    end)
  end
end

---Match completion items.
function CompletionService:matching()
  local trigger_context = TriggerContext.create()

  -- check prev matching_trigger_context.
  local changed = self._state.matching_trigger_context:changed(trigger_context)
  if not changed then
    return
  end
  self._state.matching_trigger_context = trigger_context

  -- check user is selecting manually.
  if self:_is_active_selection() then
    return
  end

  kit.clear(self._state.matches)

  -- check trigger character completion.
  local has_trigger_character_completion = false
  for _, group in ipairs(self:_get_provider_groups()) do
    for _, cfg in ipairs(group) do
      local is = true
      is = is and cfg.provider:capable(trigger_context)
      is = is and cfg.provider:in_trigger_character_completion(trigger_context, self._config)
      if is then
        has_trigger_character_completion = true
        break
      end
    end
    if has_trigger_character_completion then
      break
    end
  end

  -- matching and show.
  for _, group in ipairs(self:_get_provider_groups()) do
    local cfgs = {} --[=[@type cmp-kit.core.CompletionService.ProviderConfiguration[]]=]
    for _, cfg in ipairs(group) do
      if cfg.provider:capable(trigger_context) then
        table.insert(cfgs, cfg)
      end
    end

    if #cfgs ~= 0 then
      -- gather items.
      for _, provider_configuration in ipairs(cfgs) do
        local score_boost = self:_get_score_boost(provider_configuration.provider)
        for _, match in ipairs(provider_configuration.provider:get_matches(trigger_context, self._config)) do
          match.score = match.score + score_boost
          self._state.matches[#self._state.matches + 1] = match
        end
      end

      -- group matches are found.
      if #self._state.matches > 0 then
        local locality_map = {}

        -- For macro, the sorting should be stable.
        if not self._config.sync_mode() and vim.fn.reg_recording() == '' and vim.api.nvim_get_mode().mode == 'i' then
          local cur = vim.api.nvim_win_get_cursor(0)[1] - 1
          local min_row = math.max(1, cur - 30)
          local max_row = cur
          for row = min_row, max_row do
            for _, word in ipairs(Buffer.ensure(0):get_words(self._config.default_keyword_pattern, row)) do
              locality_map[word] = math.min(locality_map[word] or math.huge, math.abs(cur - row))
            end
          end
        end

        local sorted_matches = self._config.sorter(self._state.matches, {
          locality_map = locality_map,
          trigger_context = trigger_context,
        })

        -- 1. search preselect_index.
        -- 2. check item_count.
        -- 3. check dedup.
        local preselect_index = nil --[[@as integer?]]
        do
          local provider_item_count_map = vim.iter(cfgs):fold({},
            function(acc, provider_configuration)
              acc[provider_configuration.provider] = provider_configuration.item_count
              return acc
            end) --[[@as table<cmp-kit.core.CompletionProvider, integer>]]
          local provider_dedup_map = vim.iter(cfgs):fold({}, function(acc, provider_configuration)
            acc[provider_configuration.provider] = provider_configuration.dedup
            return acc
          end) --[[@as table<cmp-kit.core.CompletionProvider, boolean>]]

          local dedup_map = kit.clear(tmp_tbls.dedup_map)
          local limited_matches = {}
          for j, match in ipairs(sorted_matches) do
            if not preselect_index and match.item:is_preselect() then
              preselect_index = j
            end

            local is_count_ok = provider_item_count_map[match.provider] >= 0
            local is_dedup_ok = not provider_dedup_map[match.provider] or not dedup_map[match.item:get_label_text()]
            if is_count_ok and is_dedup_ok then
              table.insert(limited_matches, match)
              provider_item_count_map[match.provider] = provider_item_count_map[match.provider] - 1
            end
            dedup_map[match.item:get_label_text()] = true
          end
          self._state.matches = limited_matches
        end

        -- completion found.
        local is_menu_visible = self._config.view:is_menu_visible()
        if not self._config.sync_mode() then
          self._config.view:show(self._state.matches, self._state.selection)
        end
        if not is_menu_visible then
          emit(self._events.on_menu_show, { service = self })
        end

        -- emit selection.
        if preselect_index then
          self:_update_selection(preselect_index --[[@as integer]], true)
        end
        return
      end
    end
  end

  -- no completion found.
  local is_menu_visible = self._config.view:is_menu_visible()
  if is_menu_visible then
    if not self._config.sync_mode() then
      self._config.view:hide(self._state.matches, self._state.selection)
    end
    emit(self._events.on_menu_hide, { service = self })
  end
end

---Commit completion.
---@param item cmp-kit.core.CompletionItem
---@param option? { replace?: boolean, no_snippet?: boolean }
function CompletionService:commit(item, option)
  option = option or {}
  option.replace = option.replace or false
  option.no_snippet = option.no_snippet or false

  if self._config.sync_mode() then
    local tasks = self._macro_completion
    self._macro_completion = {}
    Async.all(tasks):sync(2 * 1000)
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

        -- re-trigger completion for trigger characters.
        local trigger_context = TriggerContext.create()
        if trigger_context.before_character and Character.is_symbol(trigger_context.before_character:byte(1)) then
          for _, provider_group in ipairs(self:_get_provider_groups()) do
            local provider_configurations = {} --[=[@type cmp-kit.core.CompletionService.ProviderConfiguration[]]=]
            for _, provider_configuration in ipairs(provider_group) do
              if provider_configuration.provider:capable(trigger_context) then
                table.insert(provider_configurations, provider_configuration)
              end
            end
            for _, provider_configuration in ipairs(provider_configurations) do
              if vim.tbl_contains(provider_configuration.provider:get_trigger_characters(), trigger_context.before_character) then
                return self:complete()
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
  return function()
    self._preventing = self._preventing - 1
    self._state.complete_trigger_context = TriggerContext.create()
    self._state.matching_trigger_context = TriggerContext.create()
    return Async.resolve()
  end
end

---Is active selection.
---@return boolean
function CompletionService:_is_active_selection()
  local selection = self._state.selection
  return not selection.preselect and selection.index > 0
end

---Get provider groups.
---@return cmp-kit.core.CompletionService.ProviderConfiguration[][]
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
---@param provider cmp-kit.core.CompletionProvider
---@return number
function CompletionService:_get_score_boost(provider)
  local cur_priority = 0
  local max_priority = 0
  for _, provider_configuration in ipairs(self._provider_configurations) do
    max_priority = math.max(max_priority, provider_configuration.priority or 0)
    if provider == provider_configuration.provider then
      cur_priority = provider_configuration.priority
    end
  end
  if max_priority == 0 then
    return 0
  end
  return 5 * (cur_priority / max_priority)
end

---Update selection
---@param index integer
---@param preselect boolean
---@param text_before? string
function CompletionService:_update_selection(index, preselect, text_before)
  self._state.selection = {
    index = index,
    preselect = preselect,
    text_before = text_before or self._state.selection.text_before
  }
  if not self._config.sync_mode() then
    if self._config.view:is_menu_visible() then
      self._config.view:select(self._state.matches, self._state.selection)
    end
  end
end

---Insert selection.
---@param text_before string
---@param item_next? cmp-kit.core.CompletionItem
---@param item_prev? cmp-kit.core.CompletionItem
---@return cmp-kit.kit.Async.AsyncTask
function CompletionService:_insert_selection(text_before, item_next, item_prev)
  local trigger_context = TriggerContext.create()
  local prev_offset = item_prev and item_prev:get_offset() - 1 or #text_before
  local next_offset = item_next and item_next:get_offset() - 1 or #text_before
  local to_remove_offset = math.min(prev_offset, next_offset, #text_before)
  return LinePatch.apply_by_keys(
    0,
    trigger_context.character - to_remove_offset,
    0,
    ('%s%s'):format(
      text_before:sub(prev_offset + 1, next_offset),
      item_next and item_next:get_select_text() or ''
    )
  ):next(self:prevent())
end

return CompletionService
