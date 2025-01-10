---@diagnostic disable: invisible
local kit = require('cmp-kit.kit')
local LSP = require('cmp-kit.kit.LSP')
local Async = require('cmp-kit.kit.Async')
local Keymap = require('cmp-kit.kit.Vim.Keymap')
local LinePatch = require('cmp-kit.core.LinePatch')
local Character = require('cmp-kit.core.Character')
local DefaultView = require('cmp-kit.core.DefaultView')
local DefaultSorter = require('cmp-kit.core.DefaultSorter')
local DefaultMatcher = require('cmp-kit.core.DefaultMatcher')
local TriggerContext = require('cmp-kit.core.TriggerContext')
local CompletionProvider = require('cmp-kit.core.CompletionProvider')

---@class cmp-kit.core.CompletionService.ProviderConfiguration
---@field public index integer
---@field public group integer
---@field public priority integer
---@field public item_count integer
---@field public dedup boolean
---@field public keyword_length integer
---@field public provider cmp-kit.core.CompletionProvider

---@class cmp-kit.core.CompletionService.Config
---@field public view cmp-kit.core.View
---@field public sorter cmp-kit.core.Sorter
---@field public matcher cmp-kit.core.Matcher
---@field public performance { fetching_timeout_ms: number }
---@field public sync_mode? fun(): boolean
---@field public expand_snippet? cmp-kit.core.ExpandSnippet

---@class cmp-kit.core.CompletionService.State
---@field public complete_trigger_context cmp-kit.core.TriggerContext
---@field public update_trigger_context cmp-kit.core.TriggerContext
---@field public selection cmp-kit.core.Selection
---@field public matches cmp-kit.core.Match[]

---@class cmp-kit.core.CompletionService
---@field private _preventing integer
---@field private _state cmp-kit.core.CompletionService.State
---@field private _config cmp-kit.core.CompletionService.Config
---@field private _keys table<string, string>
---@field private _macro_completion cmp-kit.kit.Async.AsyncTask[]
---@field private _provider_configurations cmp-kit.core.CompletionService.ProviderConfiguration[]
---@field private _debounced_update fun(): nil
local CompletionService = {}
CompletionService.__index = CompletionService

---Create a new CompletionService.
---@param config cmp-kit.core.CompletionService.Config|{}
---@return cmp-kit.core.CompletionService
function CompletionService.new(config)
  local self = setmetatable({
    _id = kit.unique_id(),
    _preventing = 0,
    _config = kit.merge(config or {}, {
      view = DefaultView.new(),
      sorter = DefaultSorter.sorter,
      matcher = DefaultMatcher.matcher,
      sync_mode = function()
        return vim.fn.reg_executing() ~= ''
      end,
      performance = {
        fetching_timeout_ms = 200,
      },
    }),
    _events = {},
    _provider_configurations = {},
    _keys = {},
    _macro_completion = {},
    _state = {
      complete_trigger_context = TriggerContext.create_empty_context(),
      update_trigger_context = TriggerContext.create_empty_context(),
      selection = {
        index = 0,
        preselect = true,
        text_before = '',
      },
      matches = {},
    },
  }, CompletionService)

  -- support macro.
  do
    self._keys.macro_complete_auto = ('<Plug>(complete:%s:mc-a)'):format(self._id)
    vim.keymap.set({ 'i', 's', 'c', 'n', 'x' }, self._keys.macro_complete_auto, function()
      local is_valid_mode = vim.tbl_contains({ 'i', 'c' }, vim.api.nvim_get_mode().mode)
      if is_valid_mode and self._config.sync_mode() then
        ---@diagnostic disable-next-line: invisible
        table.insert(self._macro_completion, self:complete({ force = false }))
      end
    end)
    self._keys.macro_complete_force = ('<Plug>(complete:%s:mc-f)'):format(self._id)
    vim.keymap.set({ 'i', 's', 'c', 'n', 'x' }, self._keys.macro_complete_force, function()
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
          match.item:commit({
            replace = false,
            expand_snippet = self._config.expand_snippet,
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

---Register provider.
---@param provider cmp-kit.core.CompletionProvider
---@param config? cmp-kit.core.CompletionService.ProviderConfiguration|{ provider: nil }
---@return fun(): nil
function CompletionService:register_provider(provider, config)
  table.insert(self._provider_configurations, {
    index = #self._provider_configurations + 1,
    group = config and config.group or 0,
    priority = config and config.priority or 0,
    item_count = config and config.item_count or math.huge,
    dedup = config and config.dedup or false,
    keyword_length = config and config.keyword_length or 1,
    provider = provider,
  })
  return function()
    for i, c in ipairs(self._provider_configurations) do
      if c.provider == provider then
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
    update_trigger_context = TriggerContext.create(),
    selection = {
      index = 0,
      preselect = true,
      text_before = '',
    },
    matches = {},
  }

  -- reset menu.
  if not self._config.sync_mode() then
    self._config.view:hide(self._state.matches, self._state.selection)
  end
end

---Is menu visible.
---@return boolean
function CompletionService:is_menu_visible()
  return self._config.view:is_visible()
end

---Is menu visible.
---@return boolean
function CompletionService:is_menu_visible()
  return self._config.view:is_visible()
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

---Get selection.
---@return cmp-kit.core.Selection
function CompletionService:get_selection()
  if self._config.sync_mode() then
    local tasks = self._macro_completion
    self._macro_completion = {}
    Async.all(tasks):sync(2 * 1000)
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
  ---@return cmp-kit.kit.Async.AsyncTask
  local function complete_inner(self, trigger_context)
    local changed = self._state.complete_trigger_context:changed(trigger_context)
    if not changed then
      return Async.resolve({})
    end
    self._state.complete_trigger_context = trigger_context

    -- reset selection for new completion.
    self:_update_selection(0, true, trigger_context.text_before)

    -- trigger.
    local fresh_completing_providers = {}
    local tasks = {} --[=[@type cmp-kit.kit.Async.AsyncTask[]]=]
    for _, provider_group in ipairs(self:_get_provider_groups()) do
      for _, provider_configuration in ipairs(provider_group) do
        if provider_configuration.provider:capable(trigger_context) then
          local prev_request_revision = provider_configuration.provider:get_request_revision()
          local prev_request_state = provider_configuration.provider:get_request_state()
          table.insert(
            tasks,
            provider_configuration.provider:complete(trigger_context):next(function(completion_context)
              -- update menu window if some of the conditions.
              -- 1. new completion was invoked.
              -- 2. change provider's `Completed` state. (true -> false or false -> true)
              local next_request_state = provider_configuration.provider:get_request_state()
              if completion_context or (prev_request_state == CompletionProvider.RequestState.Completed and next_request_state ~= CompletionProvider.RequestState.Completed) then
                self._state.update_trigger_context = TriggerContext.create_empty_context()
                self:update()
              end
            end)
          )

          -- gather new completion request was invoked providers.
          local next_request_revision = provider_configuration.provider:get_request_revision()
          if prev_request_revision ~= next_request_revision then
            table.insert(fresh_completing_providers, provider_configuration.provider)
          end
        end
      end
    end

    if #fresh_completing_providers == 0 then
      -- on-demand filter (if does not invoked new completion).
      if not self._config.sync_mode() then
        self:update()
      end
    else
      -- set new-completion position for macro.
      if not self._config.sync_mode() then
        if trigger_context.force then
          vim.api.nvim_feedkeys(Keymap.termcodes(self._keys.macro_complete_force), 'nit', true)
        else
          vim.api.nvim_feedkeys(Keymap.termcodes(self._keys.macro_complete_auto), 'nit', true)
        end
      end
    end

    return Async.all(tasks)
  end

  ---Invoke completion.
  ---@param option? { force: boolean? }
  ---@return cmp-kit.kit.Async.AsyncTask
  function CompletionService:complete(option)
    local trigger_context = TriggerContext.create(option)
    return Async.run(function()
      complete_inner(self, trigger_context):await()
    end)
  end
end

---Update completion.
---@param option? { force?: boolean }
function CompletionService:update(option)
  option = option or {}
  option.force = option.force or false

  local trigger_context = TriggerContext.create()

  -- check prev update_trigger_context.
  local changed = self._state.update_trigger_context:changed(trigger_context)
  if not changed and not option.force then
    return
  end
  self._state.update_trigger_context = trigger_context

  -- check user is selecting manually.
  if self:_is_active_selection() then
    return
  end

  -- basically, 1st group's higiher priority provider is preferred (for reducing flickering).
  -- but when it's response is too slow, we ignore it.

  self._state.matches = {}

  local has_fetching_provider = false
  local has_provider_triggered_by_character = false
  for _, provider_group in ipairs(self:_get_provider_groups()) do
    local fetching_timeout_remaining_ms = 0

    local provider_configurations = {} --[=[@type cmp-kit.core.CompletionService.ProviderConfiguration[]]=]
    for _, provider_configuration in ipairs(provider_group) do
      if provider_configuration.provider:capable(trigger_context) then
        -- check the provider was triggered by triggerCharacters.
        local completion_context = provider_configuration.provider:get_completion_context()
        if completion_context and completion_context.triggerKind == LSP.CompletionTriggerKind.TriggerCharacter then
          has_provider_triggered_by_character = has_provider_triggered_by_character or
              #provider_configuration.provider:get_items() > 0
        end

        -- if higher priority provider is fetching, skip the lower priority providers in same group. (reduce flickering).
        -- NOTE: the providers are ordered by priority.
        local elapsed_ms = vim.uv.hrtime() / 1000000 - provider_configuration.provider:get_request_time()
        fetching_timeout_remaining_ms = math.max(0, self._config.performance.fetching_timeout_ms - elapsed_ms)
        if provider_configuration.provider:get_request_state() == CompletionProvider.RequestState.Fetching then
          has_fetching_provider = true
          if completion_context and completion_context.triggerKind ~= LSP.CompletionTriggerKind.TriggerForIncompleteCompletions then
            break
          end
          table.insert(provider_configurations, provider_configuration)
        elseif provider_configuration.provider:get_request_state() == CompletionProvider.RequestState.Completed then
          table.insert(provider_configurations, provider_configuration)
        end
      end
    end

    -- if trigger character is found, remove non-trigger character providers (for UX).
    if has_provider_triggered_by_character then
      for j = #provider_configurations, 1, -1 do
        local completion_context = provider_configurations[j].provider:get_completion_context()
        if not (completion_context and completion_context.triggerKind == LSP.CompletionTriggerKind.TriggerCharacter) then
          table.remove(provider_configurations, j)
        end
      end
    end

    -- group providers are capable.
    if #provider_configurations ~= 0 then
      -- gather items.
      local preselect_item = nil
      local dedup_map = {}
      for _, provider_configuration in ipairs(provider_configurations) do
        local score_boost = self:_get_score_boost(provider_configuration.provider)
        for _, match in ipairs(provider_configuration.provider:get_matches(trigger_context, self._config.matcher)) do
          match.score = match.score + score_boost

          -- add item and consider de-duplication.
          local label_text = match.item:get_label_text()
          if not provider_configuration.dedup or not dedup_map[label_text] then
            dedup_map[label_text] = true
            self._state.matches[#self._state.matches + 1] = match
            if match.item:is_preselect() then
              preselect_item = preselect_item or match.item
            end
          end
        end
      end

      -- group matches are found.
      if #self._state.matches > 0 then
        -- sort items.
        self._state.matches = self._config.sorter(self._state.matches)

        -- preselect index.
        local preselect_index = nil --[[@as integer?]]
        if preselect_item then
          for j, match in ipairs(self._state.matches) do
            if match.item == preselect_item then
              preselect_index = j
              break
            end
          end
        end

        -- completion found.
        if not self._config.sync_mode() then
          self._config.view:show(self._state.matches, self._state.selection)
        end

        -- emit selection.
        if preselect_index then
          self:_update_selection(preselect_index --[[@as integer]], true)
        end
        return
      end
    end

    -- do not fallback to the next group if current group has fetching providers.
    if has_fetching_provider then
      if fetching_timeout_remaining_ms > 0 then
        vim.defer_fn(function()
          -- if trigger_context is not changed, update menu forcely.
          if self._state.update_trigger_context == trigger_context then
            self._state.update_trigger_context = TriggerContext.create_empty_context()
            self:update()
          end
        end, fetching_timeout_remaining_ms + 16)
      end
      return
    end
  end

  -- no completion found.
  if not self._config.sync_mode() then
    self._config.view:hide(self._state.matches, self._state.selection)
  end
end

---Commit completion.
---@param item cmp-kit.core.CompletionItem
---@param option? { replace?: boolean }
function CompletionService:commit(item, option)
  if self._config.sync_mode() then
    local tasks = self._macro_completion
    self._macro_completion = {}
    Async.all(tasks):sync(2 * 1000)
    self:update()
  end

  return item
      :commit({
        replace = option and option.replace,
        expand_snippet = self._config.expand_snippet,
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
              local completion_options = provider_configuration.provider:get_completion_options()
              if vim.tbl_contains(completion_options.triggerCharacters or {}, trigger_context.before_character) then
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
    self._state.update_trigger_context = TriggerContext.create()
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
    if self._config.view:is_visible() then
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
