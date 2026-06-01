local kit = require('cmp-kit.kit')

local escape_chars = {
  [' '] = true,
  ['\\'] = true,
  ['*'] = true,
  ['?'] = true,
  ['['] = true,
  [']'] = true,
  ['('] = true,
  [')'] = true,
  ['{'] = true,
  ['}'] = true,
  ['|'] = true,
  ['<'] = true,
  ['>'] = true,
  [';'] = true,
  ['&'] = true,
  ['"'] = true,
  ["'"] = true,
  ['`'] = true,
  ['#'] = true,
  ['!'] = true,
}

---Return path components before the cursor.
---@param before_text string
---@return string[], string
local function parse_components(before_text)
  local chars = vim
    .iter(vim.fn.str2list(before_text, true))
    :map(function(n)
      return vim.fn.nr2char(n, true)
    end)
    :totable()

  local path_parts = {}
  local name_chars = {}
  local i = #chars
  while i > 0 do
    local prev_char = chars[i - 1] or ''
    local curr_char = chars[i]
    if curr_char == '/' then
      table.insert(path_parts, 1, table.concat(name_chars))
      name_chars = {}
    elseif escape_chars[curr_char] then
      if prev_char == '\\' then
        table.insert(name_chars, 1, curr_char)
        table.insert(name_chars, 1, '\\')
        i = i - 1
      else
        break
      end
    else
      table.insert(name_chars, 1, curr_char)
    end
    i = i - 1
  end
  table.insert(path_parts, 1, table.concat(name_chars))
  return path_parts, table.concat(kit.slice(chars, 1, i), '')
end

return parse_components
