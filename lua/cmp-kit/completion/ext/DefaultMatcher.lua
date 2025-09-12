local kit = require('cmp-kit.kit')
local Character = require('cmp-kit.kit.App.Character')

local Config = {
  score_adjuster = 0.001,
  max_semantic_indexes = 200,
}

local cache = {
  score_memo = {},
  semantic_indexes = {},
}

---Get semantic indexes for the text.
---@param text string
---@param char_map table<integer, boolean>
---@return integer[]
local function parse_semantic_indexes(text, char_map)
  local is_semantic_index = Character.is_semantic_index

  local M = math.min(#text, Config.max_semantic_indexes)
  local semantic_indexes = kit.clear(cache.semantic_indexes)
  for ti = 1, M do
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
  local score_adjuster = Config.score_adjuster

  local function dfs(qi, si, prev_ti, part_score, part_chunks)
    -- match
    if qi > Q then
      local score = part_score - part_chunks * score_adjuster
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

      local strict_bonus = 0
      local mi = 0
      while ti + mi <= T and qi + mi <= Q do
        local t_char = text:byte(ti + mi)
        local q_char = query:byte(qi + mi)
        if not match_icase(t_char, q_char) then
          break
        end
        mi = mi + 1
        strict_bonus = strict_bonus + (t_char == q_char and score_adjuster * 0.1 or 0)

        local inner_score, inner_ranges = dfs(
          qi + mi,
          si + 1,
          ti + mi,
          part_score + mi + strict_bonus,
          part_chunks + 1
        )

        -- custom
        do
          -- prefix unmatch penalty
          if qi == 1 and ti ~= 1 then
            inner_score = inner_score - score_adjuster * T
          end

          -- gap length penalty
          if ti - prev_ti > 0 then
            inner_score = inner_score - (score_adjuster * math.max(0, (ti - prev_ti)))
          end
        end

        if inner_score > best_score then
          best_score = inner_score
          best_range_s = ti
          best_range_e = ti + mi
          best_ranges = inner_ranges
        end
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
  return dfs(1, 1, math.huge, 0, -1)
end

---Parse a query string into parts.
---@type table|(fun(query: string): string, table<integer, boolean>)
local parse_query = setmetatable({
  cache_query = nil,
  cache_char_map = {},
}, {
  __call = function(self, query)
    if self.cache_query == query then
      return query, self.cache_char_map
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
    self.cache_char_map = char_map

    return query, self.cache_char_map
  end,
})

local DefaultMatcher = {}

DefaultMatcher.Config = Config

---Match query against text and return a score.
---@param input string
---@param text string
---@return integer
function DefaultMatcher.match(input, text)
  if input == '' then
    return 1
  end

  local query, char_map = parse_query(input)
  local semantic_indexes = parse_semantic_indexes(text, char_map)
  local score = compute(query, text, semantic_indexes, false)
  if score <= 0 then
    return 0
  end
  return score
end

---Match query against text and return a score.
---@param input string
---@param text string
---@return { [1]: integer, [2]: integer }[]
function DefaultMatcher.decor(input, text)
  if input == '' then
    return {}
  end

  local query, char_map = parse_query(input)
  local semantic_indexes = parse_semantic_indexes(text, char_map)
  local score, ranges = compute(query, text, semantic_indexes, true)
  if score <= 0 then
    return {}
  end
  return ranges or {}
end

return DefaultMatcher
