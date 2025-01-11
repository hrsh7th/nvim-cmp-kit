---Compare two items.
---@param a cmp-kit.core.Match
---@param b cmp-kit.core.Match
---@param context cmp-kit.core.SorterContext
---@return boolean
local function compare(a, b, context)
  local offset_a = a.item:get_offset()
  local offset_b = b.item:get_offset()
  if offset_a ~= offset_b then
    return offset_a < offset_b
  end

  local preselect_a = a.item:is_preselect()
  local preselect_b = b.item:is_preselect()
  if preselect_a ~= preselect_b then
    return preselect_a
  end

  local locality_a = context.locality_map[a.item:get_select_text()] or math.huge
  local locality_b = context.locality_map[b.item:get_select_text()] or math.huge

  local score_boost_a = locality_a < locality_b and 0.5 or 0
  local score_boost_b = locality_a < locality_b and 0 or 0.5

  local score_a = a.score + score_boost_a
  local score_b = b.score + score_boost_b
  if score_a ~= score_b then
    return score_a > score_b
  end

  local sort_text_a = a.item:get_sort_text()
  local sort_text_b = b.item:get_sort_text()
  if sort_text_a and not sort_text_b then
    return true
  end
  if not sort_text_a and sort_text_b then
    return false
  end
  if sort_text_a and sort_text_b then
    if sort_text_a ~= sort_text_b then
      return sort_text_a < sort_text_b
    end
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
---@param matches cmp-kit.core.Match[]
---@param context cmp-kit.core.SorterContext
---@return cmp-kit.core.Match[]
function DefaultSorter.sorter(matches, context)
  -- sort matches.
  table.sort(matches, function(a, b)
    return compare(a, b, context)
  end)

  return matches
end

return DefaultSorter
