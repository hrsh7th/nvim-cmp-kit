local Async = require('cmp-kit.kit.Async')
local LSP = require('cmp-kit.kit.LSP')
local TriggerContext = require('cmp-kit.core.TriggerContext')

local PATTERN = [=[[A-Za-z0-9_.,()*/+^%\-][A-Za-z0-9_.,()*/+^% \t\-]*\%(\s*//.*\)\?]=]
local INVALID = { isIncomplete = false, items = {} }

local get_candidate, get_replacements, collect_block, create_evaluator

local function new()
  ---@type cmp-kit.completion.CompletionSource
  return {
    name = 'calc',
    get_configuration = function()
      return {
        position_encoding_kind = LSP.PositionEncodingKind.UTF8,
        keyword_pattern = PATTERN,
        trigger_characters = { ')', '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '.', ' ', '=' },
      }
    end,
    complete = function(_, _, callback)
      Async.run(function()
        -- カーソル直前の式候補を取り出し、日付は補完しない。
        local ctx = TriggerContext.create()
        local expression, offset = get_candidate(ctx)
        if not expression then
          return INVALID
        end
        for _, pattern in ipairs({ '%d%d%d%d%-%d%d%-%d%d$', '%d%d%d%d/%d%d/%d%d$', '%d%d/%d%d/%d%d%d%d$' }) do
          if expression:match(pattern) then
            return INVALID
          end
        end

        -- ブロックを上から評価し、各行より前に定義された値を使って結果を更新する。
        local evaluate = create_evaluator()
        local output
        local updates = {}
        for _, entry in ipairs(collect_block(ctx)) do
          local current = entry.line == ctx.line
          local value = evaluate(current and expression or entry.expression, entry.name)
          local annotation = entry.annotation
          if current then
            output = value
          elseif value ~= nil and annotation and tonumber(tostring(value)) ~= annotation.value then
            table.insert(updates, {
              newText = tostring(value),
              range = {
                start = { line = entry.line, character = annotation.first },
                ['end'] = { line = entry.line, character = annotation.last },
              },
            })
          end
        end

        -- 単体の値は、他行に実際の更新がある場合だけ補完する。
        local scalar = tonumber((expression:gsub(',', ''))) or expression:match('^[A-Za-z_][A-Za-z0-9_.]*$')
        if output == nil or (scalar and #updates == 0) then
          return INVALID
        end

        -- 式と結果注記を置き換え、コメントの文章は残す。
        local replacements, finish = get_replacements(ctx, expression, offset, output)
        local items = {}
        for i, text in ipairs(replacements) do
          items[i] = {
            label = text,
            filterText = ctx.text_before:sub(offset),
            sortText = tostring(i),
            nvim_previewText = text,
            additionalTextEdits = updates,
            textEdit = {
              newText = text,
              range = {
                start = { line = ctx.line, character = offset - 1 },
                ['end'] = { line = ctx.line, character = finish },
              },
            },
          }
        end
        return { isIncomplete = true, items = items }
      end):dispatch(function(res)
        callback(nil, res)
      end, function(err)
        callback(err, nil)
      end)
    end,
  }
end

---@param ctx cmp-kit.core.TriggerContext
---@return string?, integer?
function get_candidate(ctx)
  if ctx.text_before:match('^%s*//') then
    return nil
  end
  local offset = ctx:get_keyword_offset(PATTERN)
  if not offset then
    return nil
  end
  local text = ctx.text_before:sub(offset)
  local expression = vim.trim((text:gsub('//.*$', '')))
  if expression == '' then
    return nil
  end
  return expression, offset
end

---@param text string
---@return { value: number, first: integer, last: integer }?
local function parse_annotation(text)
  local marker = text:find('//', 1, true)
  if not marker then
    return nil
  end
  -- 角括弧が1組だけあり、その中身が数値であるコメントを更新対象にする。
  local prefix, value = text:sub(marker):match('^([^%[%]]*)%[([^%[%]]+)%][^%[%]]*$')
  if not value or not tonumber(value) then
    return nil
  end
  return { value = tonumber(value), first = marker + #prefix, last = marker + #prefix + #value }
end

---@param ctx cmp-kit.core.TriggerContext
---@param expression string
---@param offset integer
---@param output number
---@return string[], integer
function get_replacements(ctx, expression, offset, output)
  local result = tostring(output)
  local comment = ctx.text:find('//', offset, true)
  if not comment or (comment > ctx.character and not ctx.text_after:match('^%s*//')) then
    return { result, ('%s // [%s]'):format(expression, result) }, ctx.character
  end

  local note = ctx.text:sub(comment)
  local gap = ctx.text:sub(offset, comment - 1):match('%s*$')
  local annotation = parse_annotation(ctx.text)
  if annotation then
    note = ctx.text:sub(comment, annotation.first) .. result .. ctx.text:sub(annotation.last + 1)
  end
  local annotated = annotation and note or ('// [%s]%s'):format(result, note:sub(3))
  return { result .. gap .. note, expression .. gap .. annotated }, #ctx.text
end

---@param text string
---@return string?, string?
local function parse_line(text)
  local annotated = text:find('//', 1, true)
  text = vim.trim((text:gsub('//.*$', '')))
  local name, expression = text:match('^([A-Za-z_][A-Za-z0-9_]*)%s*=%s*(.*)$')
  expression = expression or text
  if expression:find('[^A-Za-z0-9_.,()*/+^%%%s%-]') then
    return nil
  end
  -- 注記のない名前だけの行は、通常の文章と区別できないため境界にする。
  if not name and not annotated and expression:match('^[A-Za-z_][A-Za-z0-9_%s]*$') then
    return nil
  end
  return expression, name
end

---@param ctx cmp-kit.core.TriggerContext
---@return { line: integer, expression: string?, name: string?, annotation: { value: number, first: integer, last: integer }? }[]
function collect_block(ctx)
  local lines = ctx.mode == 'c' and { ctx.text } or vim.api.nvim_buf_get_lines(ctx.bufnr, 0, -1, false)
  local row = ctx.mode == 'c' and 1 or ctx.line + 1
  local first, last = row, row
  while first > 1 and parse_line(lines[first - 1]) do
    first = first - 1
  end
  while last < #lines and parse_line(lines[last + 1]) do
    last = last + 1
  end

  local block = {}
  for i = first, last do
    local expression, name = parse_line(lines[i])
    table.insert(block, { line = i - 1, expression = expression, name = name, annotation = parse_annotation(lines[i]) })
  end
  return block
end

---@param expression string
---@return string
local function normalize(expression)
  local parts = {}
  local offset = 1
  while offset <= #expression do
    local s, e = expression:find('[A-Za-z_][A-Za-z0-9_.]*%s*%b()', offset)
    table.insert(parts, (expression:sub(offset, s and s - 1):gsub(',', '')))
    if not s then
      break
    end
    table.insert(parts, expression:sub(s, e))
    offset = e + 1
  end
  return table.concat(parts)
end

---@return fun(expression: string?, name: string?): number?
function create_evaluator()
  -- 計算専用の環境に、副作用のない math 関数と定数を公開する。
  local builtins = vim.tbl_extend('force', {}, math)
  builtins.random, builtins.randomseed = nil, nil
  builtins.math = vim.tbl_extend('force', {}, builtins)
  local env = setmetatable({}, { __index = builtins })

  -- Lua の文を実行する関数式は受け付けず、数値を返す式だけを評価する。
  local function run(program)
    assert(not program:match('%f[%w_]function%f[^%w_]'), 'function expressions are not supported')
    local chunk = assert(loadstring(('return (%s)'):format(normalize(program)), 'calc'))
    setfenv(chunk, env)
    local value = chunk()
    assert(type(value) == 'number' and value == value and math.abs(value) ~= math.huge, 'expected a finite number')
    return value
  end

  -- 定義は評価後に登録する。失敗した再定義でも、それ以前の値は残さない。
  return function(expression, name)
    local ok, value = pcall(run, expression)
    if name and builtins[name] == nil then
      env[name] = ok and value or nil
    end
    return ok and value or nil
  end
end

return new
