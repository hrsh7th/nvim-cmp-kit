local Character = require('cmp-kit.kit.App.Character')

local PreviewText = {}

---@type table<integer, boolean>
PreviewText.StopCharacters = {
  [string.byte("'")] = true,
  [string.byte('"')] = true,
  [string.byte('=')] = true,
  [string.byte('(')] = true,
  [string.byte(')')] = true,
  [string.byte('[')] = true,
  [string.byte(']')] = true,
  [string.byte('<')] = true,
  [string.byte('>')] = true,
  [string.byte('{')] = true,
  [string.byte('}')] = true,
  [string.byte('\t')] = true,
  [string.byte(' ')] = true,
}

---@type table<integer, boolean>
PreviewText.ForceStopCharacters = {
  [string.byte('\n')] = true,
  [string.byte('\r')] = true,
}

---@type table<integer, integer>
PreviewText.Pairs = {
  [string.byte('(')] = string.byte(')'),
  [string.byte('[')] = string.byte(']'),
  [string.byte('{')] = string.byte('}'),
  [string.byte('"')] = string.byte('"'),
  [string.byte("'")] = string.byte("'"),
  [string.byte('<')] = string.byte('>'),
}

---Create preview text.
---@param params { offset: integer, insert_text: string, before_text: string, after_text: string, in_string: boolean }
---@return string
function PreviewText.create(params)
  local insert_text = params.insert_text
  local after_text = params.after_text
  local is_alnum_consumed = false

  local is_after_symbol = Character.is_symbol(after_text:byte(1))

  -- consume if before text is same as the inser text parts in ingnoring white spaces.
  local before_idx = params.offset
  local insert_idx = 1
  while insert_idx <= #insert_text do
    while before_idx <= #params.before_text and Character.is_white(params.before_text:byte(before_idx)) do
      before_idx = before_idx + 1
    end
    while insert_idx <= #insert_text and Character.is_white(insert_text:byte(insert_idx)) do
      insert_idx = insert_idx + 1
    end
    if before_idx > #params.before_text or insert_idx > #insert_text then
      break
    end
    if params.before_text:byte(before_idx) ~= insert_text:byte(insert_idx) then
      break
    end
    before_idx = before_idx + 1
    insert_idx = insert_idx + 1
  end

  if not params.in_string then
    local pairs_stack = {}
    for i = insert_idx, #insert_text do
      local byte = insert_text:byte(i)
      if PreviewText.ForceStopCharacters[byte] then
        return insert_text:sub(1, i - 1)
      end
      local is_alnum = Character.is_alnum(byte)

      if is_alnum_consumed and is_after_symbol and after_text:byte(1) == byte then
        return insert_text:sub(1, i - 1)
      end

      if byte == pairs_stack[#pairs_stack] then
        table.remove(pairs_stack, #pairs_stack)
      elseif not is_alnum_consumed and PreviewText.Pairs[byte] then
        table.insert(pairs_stack, PreviewText.Pairs[byte])
      elseif is_alnum_consumed and not is_alnum and #pairs_stack == 0 then
        if PreviewText.StopCharacters[byte] then
          return insert_text:sub(1, i - 1)
        end
      else
        is_alnum_consumed = is_alnum_consumed or is_alnum
      end
    end
  end

  -- check after symbol.
  local skip_suffix_idx = 1
  if not is_alnum_consumed then
    if insert_text:byte(-1) == after_text:byte(1) then
      skip_suffix_idx = 2
    end
  end

  if skip_suffix_idx ~= 1 then
    return insert_text:sub(1, #insert_text - (skip_suffix_idx - 1))
  end
  return insert_text
end

return PreviewText
