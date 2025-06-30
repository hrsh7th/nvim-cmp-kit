---@diagnostic disable: invisible

local ScheduledTimer = require('cmp-kit.kit.Async.ScheduledTimer')
local debugger = require('cmp-kit.core.debugger')

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

---@class cmp-kit.completion.Buffer.Indexer
---@field private _bufnr integer
---@field private _regex string
---@field private _words string[][]
---@field private _timer cmp-kit.kit.Async.ScheduledTimer
---@field private _s_idx integer?
---@field private _e_idx integer?
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
    _timer = ScheduledTimer.new(),
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
    on_detach = function()
      self:dispose()
    end,
  })

  do
    local is_current_win = bufnr == vim.api.nvim_get_current_buf()
    if is_current_win then
      self._s_idx = vim.fn.line('w0')
      self._e_idx = vim.fn.line('w$')
      self:_run_index()
    end
  end
  self._s_idx = 1
  self._e_idx = vim.api.nvim_buf_line_count(bufnr) + 1
  self:_run_index()
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
  return self._timer:is_running()
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
  if self._s_idx and self._e_idx then
    self:_run_index()
  end
end

---Run indexing.
---NOTE: Extract anonymous functions because they impact LuaJIT performance.
function Indexer:_run_index()
  if self._disposed then
    return
  end
  if not self._s_idx or not self._e_idx then
    return
  end

  local s = vim.uv.hrtime() / 1e6
  local c = 0
  local regex = get_regex(self._regex)
  local cursor = vim.api.nvim_win_get_cursor(0)
  cursor[2] = cursor[2] + 1 -- Convert to 1-based index
  local is_inserting = vim.api.nvim_get_mode().mode == 'i'
  for i = self._s_idx, self._e_idx do
    if self._words[i] == nil then
      self._words[i] = {}
      local text = vim.api.nvim_buf_get_lines(self._bufnr, i - 1, i, false)[1] or ''
      local off = 0
      while true do
        local sidx, eidx = regex:match_str(text)
        if sidx and eidx then
          if not is_inserting or cursor[1] ~= i or cursor[2] < (off + sidx) or (off + eidx) < cursor[2] then
            local word = text:sub(sidx + 1, eidx)
            table.insert(self._words[i], word)

            -- → neovim-completion-engine
            --   → neovim
            --   → neovim-completion
            --   → completion-engine
            --   → engine
            local p = 1
            while true do
              local s_pos, e_pos = word:find('[_-]', p)
              if not s_pos or not e_pos then
                break
              end
              table.insert(self._words[i], word:sub(1, s_pos - 1))
              table.insert(self._words[i], word:sub(e_pos + 1))
              p = e_pos + 1
            end
          end
          off = off + eidx

          local prev = text
          text = text:sub(eidx + 1)
          if text == prev then
            break
          end
        else
          break
        end
      end
      self._s_idx = i + 1

      c = c + 1
      if c >= 100 then
        c = 0
        local n = vim.uv.hrtime() / 1e6
        if n - s > 10 then
          self._timer:start(16, 0, function()
            self:_run_index()
          end)
          return
        end
      end
    end
  end

  self._s_idx = nil
  self._e_idx = nil
  self:_finish_index()
end

---Finish indexing.
function Indexer:_finish_index()
  if debugger.enable() then
    for i, words in ipairs(self._words) do
      local text = vim.api.nvim_buf_get_lines(self._bufnr, i - 1, i, false)[1] or ''
      for _, word in ipairs(words) do
        if not text:match(vim.pesc(word)) then
          debugger.add('cmp-kit.completion.Buffer.Indexer', {
            desc = 'buffer is not synced collectly',
            bufnr = self._bufnr,
            regex = self._regex,
            row = i,
            text = text,
            words = words,
          })
        end
      end
    end
  end
end

---@class cmp-kit.completion.Buffer
---@field private _bufnr integer
---@field private _indexers table<string, cmp-kit.completion.Buffer.Indexer>
---@field private _disposed boolean
local Buffer = {}
Buffer.__index = Buffer

local internal = {
  bufs = {},--[[@as table<integer, cmp-kit.completion.Buffer>]]
}

---Get or create buffer instance.
---@param bufnr integer
---@return cmp-kit.completion.Buffer
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
    end,
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
