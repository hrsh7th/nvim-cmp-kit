local Async = require('cmp-kit.kit.Async')
local LSP = require('cmp-kit.kit.LSP')
local TriggerContext = require('cmp-kit.core.TriggerContext')

local PATTERN = [=[[A-Za-z0-9_.,()*/+^% \t\-]\+]=]
local INVALID = { isIncomplete = false, items = {} }

local get_candidate, collect_definitions, evaluate

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
        -- カーソル直前の式候補を取り出し、単なる数値や日付は補完しない。
        local ctx = TriggerContext.create()
        local expression, offset = get_candidate(ctx)
        if not expression or tonumber((expression:gsub(',', ''))) then
          return INVALID
        end
        for _, pattern in ipairs({ '%d%d%d%d%-%d%d%-%d%d$', '%d%d%d%d/%d%d/%d%d$', '%d%d/%d%d/%d%d%d%d$' }) do
          if expression:match(pattern) then
            return INVALID
          end
        end

        -- 現在行を起点としたブロックから変数を集め、必要な依存先だけを評価する。
        local output = evaluate(expression, collect_definitions(ctx))
        if output == nil then
          return INVALID
        end

        -- 式候補の範囲だけを、数値または結果を注記した式に置き換える。
        local items = {}
        for i, text in ipairs({ tostring(output), ('%s // %s'):format(expression, output) }) do
          items[i] = {
            label = text,
            filterText = ctx.text_before:sub(offset),
            sortText = tostring(i),
            nvim_previewText = text,
            textEdit = {
              newText = text,
              range = {
                start = { line = ctx.line, character = offset - 1 },
                ['end'] = { line = ctx.line, character = ctx.character + #(ctx.text_after:match('^%s*//.*') or '') },
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
  local offset = ctx:get_keyword_offset(PATTERN)
  if not offset then
    return nil
  end
  local text = ctx.text_before:sub(offset)
  local expression = vim.trim((text:gsub('//.*$', '')))
  if expression == '' then
    return nil
  end
  return expression, offset + #text:match('^%s*')
end

---@param text string
---@return string?, string?
local function parse_line(text)
  text = vim.trim((text:gsub('//.*$', '')))
  local name, expression = text:match('^([A-Za-z_][A-Za-z0-9_]*)%s*=%s*(.*)$')
  expression = expression or text
  if expression:find('[^A-Za-z0-9_.,()*/+^%%%s%-]') then
    return nil
  end
  return expression, name
end

---@param ctx cmp-kit.core.TriggerContext
---@return table<string, string>
function collect_definitions(ctx)
  local lines = ctx.mode == 'c' and { ctx.text } or vim.api.nvim_buf_get_lines(ctx.bufnr, 0, -1, false)
  local row = ctx.mode == 'c' and 1 or ctx.line + 1
  local first, last = row, row
  while first > 1 and parse_line(lines[first - 1]) do
    first = first - 1
  end
  while last < #lines and parse_line(lines[last + 1]) do
    last = last + 1
  end

  local definitions = {}
  for i = first, last do
    local expression, name = parse_line(lines[i])
    if name then
      definitions[name] = expression
    end
  end
  return definitions
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

---@param expression string
---@param definitions table<string, string>
---@return number?
function evaluate(expression, definitions)
  local env = vim.tbl_extend('force', {}, math)
  env.random, env.randomseed = nil, nil
  env.math = vim.tbl_extend('force', {}, env)
  local resolving = {}

  local function run(program)
    -- Lua の文を実行する関数式は受け付けず、数値を返す式だけを評価する。
    assert(not program:match('%f[%w_]function%f[^%w_]'), 'function expressions are not supported')
    local chunk = assert(loadstring(('return (%s)'):format(normalize(program)), 'calc'))
    setfenv(chunk, env)
    local value = chunk()
    assert(type(value) == 'number' and value == value and math.abs(value) ~= math.huge, 'expected a finite number')
    return value
  end

  setmetatable(env, {
    __index = function(_, name)
      assert(definitions[name] and not resolving[name], 'undefined or circular variable: ' .. name)
      resolving[name] = true
      local value = run(definitions[name])
      resolving[name] = nil
      rawset(env, name, value)
      return value
    end,
  })
  local ok, value = pcall(run, expression)
  return ok and value or nil
end

return new
