local kit = require('cmp-kit.kit')
local Character = require('cmp-kit.kit.App.Character')

local Config = {
  strict_bonus = 0.001,
  score_adjuster = 0.001,
  chunk_penalty = 0.01,
}

local cache = {
  score_memo = {},
  semantic_indexes = {},
}

---Parse a query string into parts.
---@type table|(fun(query: string): string, table<integer, boolean>)
local parse_query = setmetatable({
  cache_query = nil,
  cache_parsed = {
    char_map = {},
  }
}, {
  __call = function(self, query)
    if self.cache_query == query then
      return query, self.cache_parsed.char_map
    end
    self.cache_query = query

    local char_map = {}
    for i = 1, #query do
      local c = query:byte(i)
      char_map[c] = true
      if Character.is_upper(c) then
        char_map[c + 32] = true
      elseif Character.is_lower(c) then
        char_map[c - 32] = true
      end
    end
    self.cache_parsed.char_map = char_map

    return query, self.cache_parsed.char_map
  end,
})

---Get semantic indexes for the text.
---@param text string
---@param char_map table<integer, boolean>
---@return integer[]
local function parse_semantic_indexes(text, char_map)
  local T = #text
  local is_semantic_index = Character.is_semantic_index
  local semantic_indexes = kit.clear(cache.semantic_indexes)
  for ti = 1, T do
    if char_map[text:byte(ti)] and is_semantic_index(text, ti) then
      semantic_indexes[#semantic_indexes + 1] = ti
    end
  end
  return semantic_indexes
end

---Find best match with dynamic programming.
---@param query string
---@param text string
---@param semantic_indexes integer[]
---@param with_ranges boolean
---@return integer, { [1]: integer, [2]: integer }[]?
local function compute(
    query,
    text,
    semantic_indexes,
    with_ranges
)
  local Q = #query
  local T = #text
  local S = #semantic_indexes

  local run_id = kit.unique_id()
  local score_memo = cache.score_memo
  local match_icase = Character.match_icase
  local is_upper = Character.is_upper
  local is_wordlike = Character.is_wordlike
  local score_adjuster = Config.score_adjuster
  local chunk_penalty = Config.chunk_penalty

  local function longest(qi, ti)
    local p = 0
    local k = 0
    while qi + k <= Q and ti + k <= T do
      local q = query:byte(qi + k)
      local t = text:byte(ti + k)
      if not match_icase(q, t) then
        break
      end
      if q ~= t then
        p = p + score_adjuster
      end
      k = k + 1
    end
    return k, -p
  end

  local function dfs(qi, si, prev_ti, part_score, part_chunks)
    -- match
    if qi > Q then
      local score = part_score - part_chunks * chunk_penalty
      if with_ranges then
        return score, {}
      end
      return score
    end

    -- no match
    if si > S then
      return -1 / 0, nil
    end

    -- memo
    local idx = ((qi - 1) * S + si - 1) * 3 + 1
    if score_memo[idx + 0] == run_id then
      return score_memo[idx + 1], score_memo[idx + 2]
    end

    -- compute.
    local best_score = -1 / 0
    local best_range_s
    local best_range_e
    local best_ranges --[[@as { [1]: integer, [2]: integer }[]?]]
    while si <= S do
      local ti = semantic_indexes[si]

      local M, icase_penalty = longest(qi, ti)
      local mi = 1
      while mi <= M do
        local inner_score, inner_ranges = dfs(
          qi + mi,
          si + 1,
          ti + mi - 1,
          part_score + mi,
          part_chunks + 1
        )
        if inner_score > best_score then
          if is_upper(text:byte(ti)) and is_wordlike(text:byte(ti - 1)) then
            inner_score = inner_score - score_adjuster
          end
          inner_score = inner_score - (ti - prev_ti) / T * score_adjuster
          inner_score = inner_score + icase_penalty
          best_score = inner_score
          best_range_s = ti
          best_range_e = ti + mi
          best_ranges = inner_ranges
        end
        mi = mi + 1
      end
      si = si + 1
    end

    if best_ranges then
      best_ranges[#best_ranges + 1] = { best_range_s, best_range_e }
    end

    score_memo[idx + 0] = run_id
    score_memo[idx + 1] = best_score
    score_memo[idx + 2] = best_ranges

    return best_score, best_ranges
  end
  return dfs(1, 1, 1, 0, -1)
end

local DefaultMatcher = {}

---Match query against text and return a score.
---@param input string
---@param text string
---@return integer, cmp-kit.completion.MatchPosition[]
function DefaultMatcher.matcher(input, text)
  if input == '' then
    return 1, {}
  end

  local query, char_map  = parse_query(input)
  local semantic_indexes = parse_semantic_indexes(text, char_map)
  local score, ranges    = compute(query, text, semantic_indexes, true)
  if score <= 0 or not ranges then
    return 0, {}
  end
  return score, ranges
end

return DefaultMatcher
