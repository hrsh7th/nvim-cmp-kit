---@diagnostic disable: invisible

local Async = require('cmp-kit.kit.Async')

---@type fun(regex: string): vim.regex
local get_regex
do
  local cache = {} ---@type table<string, vim.regex>
  get_regex = function(regex)
    if not cache[regex] then
      cache[regex] = vim.regex(regex)
    end
    return cache[regex] --[[@as vim.regex]]
  end
end

---@class cmp-kit.core.Buffer.Indexer
---@field private _bufnr integer
---@field private _regex string
---@field private _words string[][]
---@field private _indxing integer
---@field private _s_idx integer?
---@field private _e_idx integer?
---@field private _rev integer
---@field private _disposed boolean
local Indexer = {}
Indexer.__index = Indexer

---@param bufnr integer
---@param regex string
function Indexer.new(bufnr, regex)
  local self = setmetatable({
    _bufnr = bufnr,
    _regex = regex,
    _words = {},
    _indexing = 0,
    _s_idx = nil,
    _e_idx = nil,
    _rev = 0,
    _disposed = false,
  }, Indexer)
  vim.api.nvim_buf_attach(bufnr, false, {
    on_lines = function(_, _, _, toprow, botrow, botrow_updated)
      if not self._disposed then
        self:_update(toprow, botrow, botrow_updated)
      end
      return self._disposed
    end,
    on_reload = function()
      if not self._disposed then
        local max = vim.api.nvim_buf_line_count(bufnr)
        self:_update(0, max, max)
      end
    end,
  })

  do
    local is_current_win = bufnr == vim.api.nvim_get_current_buf()
    if is_current_win then
      self._s_idx = vim.fn.line('w0')
      self._e_idx = vim.fn.line('w$')
      self:_index()
    end
  end
  self._s_idx = 1
  self._e_idx = vim.api.nvim_buf_line_count(bufnr) + 1
  self:_index()
  return self
end

---Get indexed words for specified row.
---@param row integer
---@return string[]
function Indexer:get_words(row)
  return self._words[row + 1] or {}
end

---Return is indexing or not.
---@return boolean
function Indexer:is_indexing()
  return self._indexing > 0
end

---Dispose.
function Indexer:dispose()
  self._disposed = true
end

---Update range and start indexing.
---@param toprow integer
---@param botrow integer
---@param botrow_updated integer
function Indexer:_update(toprow, botrow, botrow_updated)
  local s = nil --[[@as integer?]]
  local e = nil --[[@as integer?]]
  if botrow < botrow_updated then
    local add_count = botrow_updated - botrow
    for i = botrow + 1, botrow + add_count do
      table.insert(self._words, i + 1, {})
    end
    for i = toprow + 1, botrow + 1 + add_count do
      self._words[i] = nil
      s = s or i
      e = i
    end
  elseif botrow_updated < botrow then
    local del_count = botrow - botrow_updated
    for i = botrow, botrow + 1 - del_count, -1 do
      table.remove(self._words, i)
    end
    for i = toprow + 1, botrow + 1 - del_count do
      self._words[i] = nil
      s = s or i
      e = i
    end
  else
    for i = toprow + 1, botrow + 1 do
      self._words[i] = nil
      s = s or i
      e = i
    end
  end
  self._s_idx = self._s_idx and math.min(self._s_idx, s) or s
  self._e_idx = self._e_idx and math.max(self._e_idx, e) or e
  self._rev = self._rev + 1
  if self._s_idx and self._e_idx then
    self:_index()
  end
end

---Start indexing.
function Indexer:_index()
  self._indexing = self._indexing + 1
  self._rev = self._rev + 1
  local rev = self._rev
  Async.run(function()
    self:_run_index(rev)
  end):catch(function() end):next(function()
    self:_finish_index()
  end)
end

---Run indexing.
---NOTE: Extract anonymous functions because they impact LuaJIT performance.
---@param rev integer
function Indexer:_run_index(rev)
  local regex = get_regex(self._regex)

  for i = self._s_idx, self._e_idx do
    if self._words[i] == nil then
      self._words[i] = {}
      local text = vim.api.nvim_buf_get_lines(self._bufnr, i - 1, i, false)[1] or ''
      local off = 0
      while true do
        local s, e = regex:match_str(text)
        if s and e then
          local cursor = vim.api.nvim_win_get_cursor(0)
          local is_inserting = vim.api.nvim_get_mode().mode == 'i'
          if not is_inserting or cursor[1] ~= i or cursor[2] < (off + s) or (off + e) < cursor[2] then
            table.insert(self._words[i], text:sub(s + 1, e))
          end
          off = off + e

          local prev = text
          text = text:sub(e + 1)
          if text == prev then
            break
          end
        else
          break
        end
        Async.interrupt(16, 16)
        if self._rev ~= rev then
          return
        end
      end
      self._s_idx = i + 1
    end
  end

  if self._rev == rev then
    self._s_idx = nil
    self._e_idx = nil
  end
end

---Finish indexing.
function Indexer:_finish_index()
  _G.debug_buffer_source = _G.debug_buffer_source or false
  if _G.debug_buffer_source then
    for i, words in ipairs(self._words) do
      local text = vim.api.nvim_buf_get_lines(self._bufnr, i - 1, i, false)[1] or ''
      for _, word in ipairs(words) do
        if not text:match(vim.pesc(word)) then
          error(('buffer is not synced collectly. #%s: %s vs %s'):format(i, text, table.concat(words, ', ')))
        end
      end
    end
  end
  self._indexing = self._indexing - 1
end

---@class cmp-kit.core.Buffer
---@field private _bufnr integer
---@field private _indexers table<string, cmp-kit.core.Buffer.Indexer>
---@field private _disposed boolean
local Buffer = {}
Buffer.__index = Buffer

local internal = {
  bufs = {} --[[@as table<integer, cmp-kit.core.Buffer>]]
}

---Get or create buffer instance.
---@param bufnr integer
---@return cmp-kit.core.Buffer
function Buffer.ensure(bufnr)
  bufnr = bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr
  if not internal.bufs[bufnr] or internal.bufs[bufnr]:is_disposed() then
    internal.bufs[bufnr] = Buffer.new(bufnr)
  end
  return internal.bufs[bufnr]
end

---Create new Buffer.
function Buffer.new(bufnr)
  local self = setmetatable({
    _bufnr = bufnr,
    _indexers = {},
    _disposed = false,
  }, Buffer)
  vim.api.nvim_create_autocmd('BufDelete', {
    once = true,
    pattern = ('<buffer=%s>'):format(bufnr),
    callback = function()
      self:dispose()
    end
  })
  return self
end

---Return bufnr.
---@return integer
function Buffer:get_buf()
  return self._bufnr
end

---Get words in row.
---@param regex string
---@param row integer
---@return string[]
function Buffer:get_words(regex, row)
  if not self._indexers[regex] then
    self._indexers[regex] = Indexer.new(self._bufnr, regex)
  end
  return self._indexers[regex]:get_words(row)
end

---Return is indexing or not.
---@param regex string
---@return boolean
function Buffer:is_indexing(regex)
  if not self._indexers[regex] then
    self._indexers[regex] = Indexer.new(self._bufnr, regex)
  end
  return self._indexers[regex]:is_indexing()
end

---Return if buffer is disposed.
---@return boolean
function Buffer:is_disposed()
  return self._disposed
end

---Dispose.
function Buffer:dispose()
  self._disposed = true
  for _, indexer in pairs(self._indexers) do
    indexer:dispose()
  end
  self._indexers = {}
end

return Buffer
