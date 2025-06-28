local RegExp = require('cmp-kit.kit.Vim.RegExp')
local Character = require('cmp-kit.core.Character')

---@type { ns: integer, last_typed_char: string?, trigger_context: cmp-kit.core.TriggerContext? }
local state = {
  ns = vim.api.nvim_create_namespace('cmp-kit.core.TriggerContext'),
  last_typed_char = nil,
  trigger_context = nil
}

do
  vim.on_key(function(_, typed)
    if not typed or #typed ~= 1 then
      return
    end
    local b = typed:byte(1)
    if not (32 <= b and b <= 126) then
      return
    end
    state.last_typed_char = typed
  end, state.ns)
end

---The TriggerContext.
---@class cmp-kit.core.TriggerContext
---@field public mode string
---@field public line integer 0-origin
---@field public character integer 0-origin utf8 byte index
---@field public text string
---@field public text_before string
---@field public text_after string
---@field public bufnr integer
---@field public time integer
---@field public force? boolean
---@field public trigger_character? string
---@field public trigger_character_typed? string
---@field public in_string boolean
---@field public in_comment boolean
---@field public cache table<string, any>
local TriggerContext = {}
TriggerContext.__index = TriggerContext

---Create empty TriggerContext.
---@return cmp-kit.core.TriggerContext
function TriggerContext.create_empty_context()
  return TriggerContext.new('i', -1, -1, '', -1)
end

---Create new TriggerContext from current state.
---@param option? { force: boolean? }
---@return cmp-kit.core.TriggerContext
function TriggerContext.create(option)
  local mode = vim.api.nvim_get_mode().mode --[[@as string]]
  local bufnr = vim.api.nvim_get_current_buf()
  if mode == 'c' then
    return TriggerContext.new(mode, 0, vim.fn.getcmdpos() - 1, vim.fn.getcmdline(), bufnr, option)
  end
  local row1, col0 = unpack(vim.api.nvim_win_get_cursor(0))
  return TriggerContext.new(mode, row1 - 1, col0, vim.api.nvim_get_current_line(), bufnr, option)
end

---Create new TriggerContext.
---@param mode string
---@param line integer 0-origin
---@param character integer 0-origin
---@param text string
---@param bufnr integer
---@param option? { force?: boolean }
---@return cmp-kit.core.TriggerContext
function TriggerContext.new(mode, line, character, text, bufnr, option)
  local text_before = text:sub(1, character)
  local text_after = text:sub(character + 1)

  local in_string = false
  local in_comment = false
  if mode == 'i' then
    local captures = vim.treesitter.get_captures_at_pos(bufnr, line, character)
    for _, capture in ipairs(captures) do
      in_string = in_string or (capture.capture:match('string'))
      in_comment = in_comment or (capture.capture:match('comment'))
    end
    local hlname = vim.fn.synIDattr(vim.fn.synID(line + 1, character + 1, 1), 'name')
    if hlname then
      in_string = in_string or (hlname:match('String'))
      in_comment = in_comment or (hlname:match('Comment'))
    end
  end

  local trigger_character = text_before:match('^%s*$') and text_before:match('(.)$') or text_before:match('(.)%s*$')
  local trigger_character_typed = trigger_character == state.last_typed_char and trigger_character

  -- NOTE: cmp-kit's specific implementation.
  -- In the vim ecosystem, there is a convention of using <Tab> to exit a closing brackets, and to support this, `before character' is used as the trigger character.
  -- However, whitespace chars is only used `if actually typed'.
  if trigger_character and Character.is_white(trigger_character:byte(1)) then
    trigger_character = trigger_character_typed
  end

  local self = setmetatable({
    mode = mode,
    line = line,
    character = character,
    text = text,
    text_before = text_before,
    text_after = text_after,
    bufnr = bufnr,
    time = vim.uv.now(),
    force = not not (option and option.force),
    trigger_character = trigger_character,
    trigger_character_typed = trigger_character_typed,
    in_string = in_string,
    in_comment = in_comment,
    cache = {},
  }, TriggerContext)

  if state.trigger_context then
    local keep_cache = true
    keep_cache = keep_cache and state.trigger_context.mode == self.mode
    keep_cache = keep_cache and state.trigger_context.line == self.line
    keep_cache = keep_cache and state.trigger_context.character == self.character
    keep_cache = keep_cache and state.trigger_context.text == self.text
    keep_cache = keep_cache and state.trigger_context.bufnr == self.bufnr
    if keep_cache then
      self.cache = state.trigger_context.cache
    end
  end
  state.trigger_context = self

  return self
end

---Get query text.
---@param offset integer
---@return string
function TriggerContext:get_query(offset)
  return self.text:sub(offset, self.character)
end

---Check if trigger context is changed.
---@param new_trigger_context cmp-kit.core.TriggerContext
---@return boolean
function TriggerContext:changed(new_trigger_context)
  if new_trigger_context.force then
    return true
  end

  if new_trigger_context.line == -1 then
    return true
  end

  if self.bufnr ~= new_trigger_context.bufnr then
    return true
  end

  if self.mode ~= new_trigger_context.mode then
    return true
  end

  if self.line ~= new_trigger_context.line then
    return true
  end

  if self.character ~= new_trigger_context.character then
    return true
  end

  if self.text_before ~= new_trigger_context.text_before then
    return true
  end

  return false
end

---Get keyword offset.
---@param pattern string # does not need '$' at the end
---@return integer? 1-origin utf8 byte index
function TriggerContext:get_keyword_offset(pattern)
  local cache_key = string.format('%s:%s', 'get_keyword_offset', pattern)
  if not self.cache[cache_key] then
    local _, s = RegExp.extract_at(self.text, pattern, self.character + 1)
    if s then
      self.cache[cache_key] = { s = s }
    else
      self.cache[cache_key] = {}
    end
  end
  return self.cache[cache_key].s
end

return TriggerContext
