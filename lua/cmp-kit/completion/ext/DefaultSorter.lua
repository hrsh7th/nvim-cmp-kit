local DefaultMatcher = require('cmp-kit.completion.ext.DefaultMatcher')

local Bonus = {
  exact = 10 * DefaultMatcher.Config.score_adjuster,
  preselect = 8 * DefaultMatcher.Config.score_adjuster,
  locality = 4 * DefaultMatcher.Config.score_adjuster,
  sort_text = DefaultMatcher.Config.score_adjuster,
}

---Compare two items.
---@param a cmp-kit.completion.Match
---@param b cmp-kit.completion.Match
---@param context cmp-kit.completion.SorterContext
---@return boolean
local function compare(a, b, context)
  local offset_a = a.item:get_offset()
  local offset_b = b.item:get_offset()
  if offset_a ~= offset_b then
    return offset_a < offset_b
  end

  local preselect_a = a.item:is_preselect()
  local preselect_b = b.item:is_preselect()

  local exact_a = context.trigger_context:get_query(a.item:get_offset()) == a.item:get_filter_text()
  local exact_b = context.trigger_context:get_query(b.item:get_offset()) == b.item:get_filter_text()

  local locality_a = context.locality_map[a.item:get_preview_text()] or math.huge
  local locality_b = context.locality_map[b.item:get_preview_text()] or math.huge

  local sort_text_a = a.item:get_sort_text()
  local sort_text_b = b.item:get_sort_text()

  local sort_text_bonus_a = 0
  local sort_text_bonus_b = 0
  if sort_text_a and not sort_text_b then
    sort_text_bonus_a = Bonus.sort_text
  end
  if not sort_text_a and sort_text_b then
    sort_text_bonus_b = Bonus.sort_text
  end
  if sort_text_a and sort_text_b then
    if sort_text_a < sort_text_b then
      sort_text_bonus_a = Bonus.sort_text
    elseif sort_text_a > sort_text_b then
      sort_text_bonus_b = Bonus.sort_text
    end
  end

  local score_bonus_a = 0
  local score_bonus_b = 0
  score_bonus_a = score_bonus_a + (preselect_a and Bonus.preselect or 0)
  score_bonus_b = score_bonus_b + (preselect_b and Bonus.preselect or 0)
  score_bonus_a = score_bonus_a + locality_a < locality_b and Bonus.locality or 0
  score_bonus_b = score_bonus_b + locality_a > locality_b and Bonus.locality or 0
  score_bonus_a = score_bonus_a + (exact_a and Bonus.exact or 0)
  score_bonus_b = score_bonus_b + (exact_b and Bonus.exact or 0)
  score_bonus_a = score_bonus_a + sort_text_bonus_a
  score_bonus_b = score_bonus_b + sort_text_bonus_b

  local score_a = a.score + score_bonus_a
  local score_b = b.score + score_bonus_b
  if score_a ~= score_b then
    return score_a > score_b
  end

  local label_text_a = a.item:get_label_text()
  local label_text_b = b.item:get_label_text()
  if label_text_a ~= label_text_b then
    return label_text_a < label_text_b
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
  table.sort(matches, function(a, b)
    return compare(a, b, context)
  end)

  return matches
end

return DefaultSorter
