local DefaultMatcher = require('cmp-kit.completion.ext.DefaultMatcher')

local Bonus = {
  exact = 10 * DefaultMatcher.Config.score_adjuster,
  preselect = 8 * DefaultMatcher.Config.score_adjuster,
  locality = 4 * DefaultMatcher.Config.score_adjuster,
  sort_text = DefaultMatcher.Config.score_adjuster / 2,
}

---Compare two items.
---@param a cmp-kit.completion.Match
---@param b cmp-kit.completion.Match
---@param context cmp-kit.completion.SorterContext
---@param cache table<string, any>
---@return boolean
local function compare(a, b, context, cache)
  local a_cache = cache[a.item] or {
    just_completion = a.provider:get_keyword_offset() == a.item:get_offset(),
    preselect = a.item:is_preselect(),
    exact = context.trigger_context:get_query(a.item:get_offset()) == a.item:get_filter_text(),
    locality = context.locality_map[a.item:get_preview_text()] or math.huge,
    sort_text = a.item:get_sort_text(),
    label_text = a.item:get_label_text(),
  }
  cache[a.item] = a_cache
  local b_cache = cache[b.item] or {
    just_completion = b.provider:get_keyword_offset() == b.item:get_offset(),
    preselect = b.item:is_preselect(),
    exact = context.trigger_context:get_query(b.item:get_offset()) == b.item:get_filter_text(),
    locality = context.locality_map[b.item:get_preview_text()] or math.huge,
    sort_text = b.item:get_sort_text(),
    label_text = b.item:get_label_text(),
  }

  if a_cache.just_completion ~= b_cache.just_completion then
    return a_cache.just_completion
  end

  local sort_text_bonus_a = 0
  local sort_text_bonus_b = 0
  if a_cache.sort_text and not b_cache.sort_text then
    sort_text_bonus_a = Bonus.sort_text
  end
  if not a_cache.sort_text and b_cache.sort_text then
    sort_text_bonus_b = Bonus.sort_text
  end
  if a_cache.sort_text and b_cache.sort_text then
    if a_cache.sort_text < b_cache.sort_text then
      sort_text_bonus_a = Bonus.sort_text
    elseif a_cache.sort_text > b_cache.sort_text then
      sort_text_bonus_b = Bonus.sort_text
    end
  end

  local score_bonus_a = 0
  local score_bonus_b = 0
  score_bonus_a = score_bonus_a + (a_cache.preselect and Bonus.preselect or 0)
  score_bonus_b = score_bonus_b + (b_cache.preselect and Bonus.preselect or 0)
  score_bonus_a = score_bonus_a + a_cache.locality < b_cache.locality and Bonus.locality or 0
  score_bonus_b = score_bonus_b + a_cache.locality > b_cache.locality and Bonus.locality or 0
  score_bonus_a = score_bonus_a + (a_cache.exact and Bonus.exact or 0)
  score_bonus_b = score_bonus_b + (b_cache.exact and Bonus.exact or 0)
  score_bonus_a = score_bonus_a + sort_text_bonus_a
  score_bonus_b = score_bonus_b + sort_text_bonus_b

  local score_a = a.score + score_bonus_a
  local score_b = b.score + score_bonus_b
  if score_a ~= score_b then
    return score_a > score_b
  end

  if a_cache.label_text ~= b_cache.label_text then
    return a_cache.label_text < b_cache.label_text
  end
  return a.index < b.index
end

local DefaultSorter = {}

---Sort matches.
---@param matches cmp-kit.completion.Match[]
---@param context cmp-kit.completion.SorterContext
---@return cmp-kit.completion.Match[]
function DefaultSorter.sort(matches, context)
  -- sort matches.
  local cache = {}
  table.sort(matches, function(a, b)
    return compare(a, b, context, cache)
  end)

  return matches
end

return DefaultSorter
