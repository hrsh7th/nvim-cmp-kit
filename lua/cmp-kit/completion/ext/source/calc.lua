local Async = require('cmp-kit.kit.Async')
local LSP = require('cmp-kit.kit.LSP')
local TriggerContext = require('cmp-kit.core.TriggerContext')

local PATTERN = [=[[A-Za-z0-9_.,()*/+^%\-][A-Za-z0-9_.,()*/+^% \t\-]*\%(\s*=>\s*\[[^]]*\][A-Za-z0-9_.,()*/+^% \t\-]*\)*]=]
local PLACEHOLDER = '()=>%s*%[()([^%[%]]+)()%]()'
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
        trigger_characters = { ')', ']', '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '.', ' ', '=' },
      }
    end,
    complete = function(_, _, callback)
      Async.run(function()
        -- カーソル直前の式候補を取り出し、コメントや日付は補完しない。
        local ctx = TriggerContext.create()
        local expression, offset, finish = get_candidate(ctx)
        if not expression then
          return INVALID
        end
        for _, pattern in ipairs({ '%d%d%d%d%-%d%d%-%d%d$', '%d%d%d%d/%d%d/%d%d$', '%d%d/%d%d/%d%d%d%d$' }) do
          if expression:match(pattern) then
            return INVALID
          end
        end

        -- 各行を順に評価し、現在行の補完結果と、範囲の重ならない同期編集を求める。
        local evaluate = create_evaluator()
        local output, placeholders
        local updates = {}
        for _, entry in ipairs(collect_block(ctx)) do
          local current = entry.line == ctx.line
          if current then
            output, placeholders = evaluate(expression)
          end
          local _, edits = evaluate(entry.expression or expression, entry.name)
          local base = (entry.offset or offset) - 1
          for _, edit in ipairs(edits) do
            local first, last = base + edit.first, base + edit.last
            if not current or last <= offset - 1 or first >= finish then
              table.insert(updates, {
                newText = edit.newText,
                range = {
                  start = { line = entry.line, character = first },
                  ['end'] = { line = entry.line, character = last },
                },
              })
            end
          end
        end

        -- 単体の値は、他の結果に実際の更新がある場合だけ補完する。
        local scalar = tonumber((expression:gsub(',', ''))) or expression:match('^[A-Za-z_][A-Za-z0-9_.]*$')
        if output == nil or (scalar and #updates == 0) then
          return INVALID
        end

        -- 数値への置換と、式を残した結果プレースホルダの追加を提示する。
        local items = {}
        for i, text in ipairs(get_replacements(expression, output, placeholders)) do
          local range = {
            start = { line = ctx.line, character = offset - 1 },
            ['end'] = { line = ctx.line, character = finish },
          }
          items[i] = {
            label = text,
            filterText = ctx.text_before:sub(offset),
            sortText = tostring(i),
            nvim_previewText = text,
            additionalTextEdits = updates,
            textEdit = {
              newText = text,
              insert = range,
              replace = range,
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
---@return string?, integer?, integer?
function get_candidate(ctx)
  if ctx.text_before:find('//', 1, true) then
    return nil
  end
  local offset = ctx:get_keyword_offset(PATTERN)
  if not offset then
    return nil
  end
  local suffix, value = ctx.text_after:match('^(%s*=>%s*%[([^%[%]]+)%])')
  local finish = ctx.character + (tonumber(value) and #suffix or 0)
  return vim.trim(ctx.text:sub(offset, finish)), offset, finish
end

---@param expression string
---@param output number
---@param edits { first: integer, last: integer, newText: string }[]
---@return string[]
function get_replacements(expression, output, edits)
  local text = expression
  for i = #edits, 1, -1 do
    local edit = edits[i]
    text = text:sub(1, edit.first) .. edit.newText .. text:sub(edit.last + 1)
  end
  if not text:match('=>%s*%[[^%[%]]+%]%s*$') then
    text = ('%s => [%s]'):format(text, output)
  end
  return { tostring(output), text }
end

---@param text string
---@return string?, string?, integer?
local function parse_line(text)
  local code = text:match('^(.-)//') or text
  local leading = #code:match('^%s*')
  code = vim.trim(code)
  local name, operator, offset, expression = code:match('^([A-Za-z_][A-Za-z0-9_]*)%s*(=>?)%s*()(.*)$')
  if operator ~= '=' then
    name, offset, expression = nil, 1, code
  end
  local candidate = expression:gsub('=>%s*%[([^%[%]]+)%]', function(value)
    return tonumber(value) and '' or '!'
  end)
  if candidate:find('[^A-Za-z0-9_.,()*/+^%%%s%-]') then
    return nil
  end
  -- 注記のない名前だけの行は、通常の文章と区別できないため境界にする。
  if not name and candidate == expression and expression:match('^[A-Za-z_][A-Za-z0-9_%s]*$') then
    return nil
  end
  return expression, name, leading + (offset or 1)
end

---@param ctx cmp-kit.core.TriggerContext
---@return { line: integer, expression: string?, name: string?, offset: integer? }[]
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
    local expression, name, offset = parse_line(lines[i])
    table.insert(block, { line = i - 1, expression = expression, name = name, offset = offset })
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

---@return fun(expression: string?, name: string?): number?, table[]
function create_evaluator()
  -- 計算専用の環境に、副作用のない math 関数と定数を公開する。
  local builtins = vim.tbl_extend('force', {}, math)
  builtins.random, builtins.randomseed = nil, nil
  builtins.math = vim.tbl_extend('force', {}, builtins)
  local env = setmetatable({}, { __index = builtins })

  -- Lua の文を実行する関数式は受け付けず、数値を返す式だけを評価する。
  local function calculate(program)
    assert(not program:match('%f[%w_]function%f[^%w_]'), 'function expressions are not supported')
    local chunk = assert(loadstring(('return (%s)'):format(normalize(program)), 'calc'))
    setfenv(chunk, env)
    local value = chunk()
    assert(type(value) == 'number' and value == value and math.abs(value) ~= math.huge, 'expected a finite number')
    return value
  end

  -- 表示値は入力に使わず、左の計算結果を次の区間に渡してプレースホルダを更新する。
  local function run(expression)
    local value
    local edits = {}
    local offset = 1
    for first, start, displayed, finish, after in expression:gmatch(PLACEHOLDER) do
      assert(tonumber(displayed), 'expected a numeric placeholder')
      local part = expression:sub(offset, first - 1)
      value = calculate(value and ('(%.17g)%s'):format(value, part) or part)
      if tonumber(tostring(value)) ~= tonumber(displayed) then
        table.insert(edits, { first = start - 1, last = finish - 1, newText = tostring(value) })
      end
      offset = after
    end
    local part = expression:sub(offset)
    if value == nil or part:match('%S') then
      value = calculate(value and ('(%.17g)%s'):format(value, part) or part)
    end
    return value, edits
  end

  -- 定義は最終結果の評価後に登録する。失敗した再定義でも、それ以前の値は残さない。
  return function(expression, name)
    local ok, value, edits = pcall(run, expression)
    if name and builtins[name] == nil then
      env[name] = ok and value or nil
    end
    return ok and value or nil, ok and edits or {}
  end
end

return new
