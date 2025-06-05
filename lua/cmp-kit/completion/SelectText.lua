local Character = require('cmp-kit.core.Character')

local SelectText = {}

---@type table<integer, boolean>
SelectText.StopCharacters = {
  [string.byte("'")] = true,
  [string.byte('"')] = true,
  [string.byte('=')] = true,
  [string.byte('$')] = true,
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
SelectText.ForceStopCharacters = {
  [string.byte('\n')] = true,
  [string.byte('\r')] = true,
}

---@type table<integer, integer>
SelectText.Pairs = {
  [string.byte('(')] = string.byte(')'),
  [string.byte('[')] = string.byte(']'),
  [string.byte('{')] = string.byte('}'),
  [string.byte('"')] = string.byte('"'),
  [string.byte("'")] = string.byte("'"),
  [string.byte('<')] = string.byte('>'),
}

---Create select text.
---@param params { insert_text: string, before_text: string, after_text: string }
---@return string
function SelectText.create(params)
  local insert_text = params.insert_text
  local before_text = params.before_text
  local after_text = params.after_text
  local is_alnum_consumed = false

  -- skip if already inserted text is same as actual insert text.
  local insert_text_idx = 1
  local before_text_idx = 1
  while insert_text_idx <= #insert_text and before_text_idx <= #before_text do
    while true do
      if Character.is_white(insert_text:byte(insert_text_idx)) then
        insert_text_idx = insert_text_idx + 1
      else
        break
      end
    end
    while true do
      if Character.is_white(before_text:byte(before_text_idx)) then
        before_text_idx = before_text_idx + 1
      else
        break
      end
    end
    if insert_text:byte(insert_text_idx) == before_text:byte(before_text_idx) then
      if Character.is_alnum(insert_text:byte(insert_text_idx)) then
        is_alnum_consumed = true
      end
      insert_text_idx = insert_text_idx + 1
      before_text_idx = before_text_idx + 1
    else
      break
    end
  end

  local is_after_symbol = Character.is_symbol(after_text:byte(1))

  local pairs_stack = {}
  for i = insert_text_idx, #insert_text do
    local byte = insert_text:byte(i)
    if SelectText.ForceStopCharacters[byte] then
      return insert_text:sub(1, i - 1)
    end
    local alnum = Character.is_alnum(byte)

    if is_alnum_consumed and is_after_symbol and after_text:byte(1) == byte then
      return insert_text:sub(1, i - 1)
    end

    if byte == pairs_stack[#pairs_stack] then
      table.remove(pairs_stack, #pairs_stack)
    else
      if not is_alnum_consumed and SelectText.Pairs[byte] then
        table.insert(pairs_stack, SelectText.Pairs[byte])
      end
      if is_alnum_consumed and not alnum and #pairs_stack == 0 then
        if SelectText.StopCharacters[byte] then
          return insert_text:sub(1, i - 1)
        end
      else
        is_alnum_consumed = is_alnum_consumed or alnum
      end
    end
  end
  return insert_text
end

return SelectText
