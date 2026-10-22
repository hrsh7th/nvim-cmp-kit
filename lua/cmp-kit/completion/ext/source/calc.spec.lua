local calc_source = require('cmp-kit.completion.ext.source.calc')
local spec = require('cmp-kit.spec')
local LSP = require('cmp-kit.kit.LSP')
local Async = require('cmp-kit.kit.Async')
local CompletionService = require('cmp-kit.completion.CompletionService')

describe('cmp-kit.completion.ext.source.calc', function()
  local source = calc_source()

  ---@param lines string[]
  local function complete(lines)
    spec.setup({ buffer_text = lines })
    return Async.new(function(resolve, reject)
      source:complete({ triggerKind = LSP.CompletionTriggerKind.Invoked }, function(err, res)
        if err then
          reject(err)
        else
          resolve(res)
        end
      end)
    end):sync(2 * 1000)
  end

  ---@param text string
  ---@param output number?
  local function assert_output(text, output)
    local response = complete({ text })
    if output == nil then
      assert.are_equal(0, #response.items)
    else
      assert.are_equal(2, #response.items)
      assert.are_equal(tostring(output), response.items[1].textEdit.newText)
    end
  end

  ---@param lines string[]
  ---@param expected string[]
  local function assert_replacements(lines, expected)
    local response = complete(lines)
    local replacements = {}
    for _, item in ipairs(response.items) do
      local edit = item.textEdit
      local line = vim.api.nvim_buf_get_lines(0, edit.range.start.line, edit.range.start.line + 1, false)[1]
      table.insert(replacements, line:sub(1, edit.range.start.character) .. edit.newText .. line:sub(edit.range['end'].character + 1))
    end
    assert.are.same(expected, replacements)
  end

  it('basic usage', function()
    assert_output('1 + 2|', 3)
    assert_output('5 - 2|', 3)
    assert_output('2 * 3|', 6)
    assert_output('6 / 2|', 3)
    assert_output('7 % 3|', 1)
    assert_output('2 ^ 3|', 8)
    assert_output('-2 + 3|', 1)
    assert_output('1 + 2 * (3 - 1)|', 5)
    assert_output('pow(2, 3)|', 8)
  end)

  it('does not offer results for standalone numbers or invalid expressions', function()
    assert_output('5|', nil)
    assert_output('0.5|', nil)
    assert_output('1,200|', nil)
    assert_output('1, 2)|', nil)
  end)

  it('evaluates decimal arithmetic', function()
    assert_output('0.5 + 0.25|', 0.75)
    assert_output('1.5 - 0.25|', 1.25)
    assert_output('0.5 * 0.25|', 0.125)
    assert_output('0.75 / 0.5|', 1.5)
    assert_output('1.25 % 0.5|', 0.25)
    assert_output('0.5 ^ 2|', 0.25)
  end)

  it('accepts decimal notation and negative decimals', function()
    assert_output('.5 + .25|', 0.75)
    assert_output('1. + .5|', 1.5)
    assert_output('-0.5 * 2|', -1)
  end)

  it('preserves function arguments while removing thousands separators', function()
    assert_output('1,200 + pow(2, 3)|', 1208)
  end)

  it('does not offer results for dates', function()
    assert_output('2024-01-30|', nil)
    assert_output('2024/01/30|', nil)
    assert_output('01/30/2024|', nil)
  end)

  describe('expression completion', function()
    it('offers a result or an expression annotated with //', function()
      assert_replacements({ '1 + 2|' }, { '3', '1 + 2 // 3' })
    end)

    it('preserves the assignment and text after the cursor', function()
      assert_replacements({ '🗿 v = 1 + 2| suffix' }, {
        '🗿 v = 3 suffix',
        '🗿 v = 1 + 2 // 3 suffix',
      })
    end)

    it('replaces an old annotation instead of appending another result', function()
      assert_replacements({ '1 + 2 // 999|' }, { '3', '1 + 2 // 3' })
      assert_replacements({ '1 + 2| // 999' }, { '3', '1 + 2 // 3' })
    end)

    it('evaluates exponentiation from right to left', function()
      assert_replacements({ '2^3^2|' }, { '512', '2^3^2 // 512' })
    end)

    it('exposes math functions directly and through math', function()
      assert_replacements({ 'sqrt(9) + math.pow(2, 3)|' }, {
        '11',
        'sqrt(9) + math.pow(2, 3) // 11',
      })
      assert_replacements({ 'cos(0) + pi - math.pi|' }, {
        '1',
        'cos(0) + pi - math.pi // 1',
      })
    end)

    it('recalculates variables instead of trusting old annotations', function()
      assert_replacements({ 'p = 0.5', 'v = p * (1 - p) // 999', 'v * 4|' }, {
        '1',
        'v * 4 // 1',
      })
    end)

    it('resolves dependencies regardless of declaration order', function()
      assert_replacements({
        'SE = SD / sqrt(N)|',
        'SD = sqrt(v)',
        'v = p * (1 - p)',
        'N = 100',
        'p = 0.5',
      }, { 'SE = 0.05', 'SE = SD / sqrt(N) // 0.05' })
    end)

    it('resolves dependencies on both sides of the current line', function()
      assert_replacements({
        'Left = Base + 1',
        'Left + Right|',
        'Right = Base * 2',
        'Base = 3',
      }, { '10', 'Left + Right // 10' })
    end)

    it('does not offer a result for a circular dependency', function()
      assert_replacements({ 'A = B + 1', 'B = A + 1', 'A * 2|' }, {})
    end)

    it('does not offer a result for a self reference', function()
      assert_replacements({ 'A = A + 1|' }, {})
    end)

    it('does not offer a result for an unresolved dependency', function()
      assert_replacements({ 'A = Missing + 1', 'A * 2|' }, {})
    end)

    it('does not evaluate only the valid suffix of an expression', function()
      assert_replacements({ 'Missing + 2 * 3|' }, {})
    end)

    it('evaluates independent variables even when another dependency is circular', function()
      assert_replacements({
        'A = B + 1',
        'B = A + 1',
        'Count = 3',
        'Count * 2|',
      }, { '6', 'Count * 2 // 6' })
    end)

    it('uses the last definition in the block regardless of the reference position', function()
      assert_replacements({
        'Count = 2',
        'Count * 2|',
        'Count = 3',
      }, {
        '6',
        'Count * 2 // 6',
      })
    end)

    it('uses the last definition when evaluating another variable', function()
      assert_replacements({
        'Count = 2',
        'Total = Count * 2',
        'Total + 1|',
        'Count = 3',
      }, { '7', 'Total + 1 // 7' })
    end)

    it('does not fall back to an earlier definition when the last one is incomplete', function()
      assert_replacements({ 'Count = 3', 'Count * 2|', 'Count =' }, {})
    end)

    it('includes expressions, assignments, blank lines and comment lines in the block', function()
      assert_replacements({
        'Price = 3',
        '1 + 2 // 3',
        '',
        '  // 数量と価格から計算する',
        'Price * Count|',
        '',
        '// 数量',
        'Count = 2',
      }, { '6', 'Price * Count // 6' })
    end)

    it('includes the current line even when its expression is embedded in text', function()
      assert_replacements({
        'Scale = 1.2',
        'font-size: 10 * Scale + Count|;',
        'Count = 3',
      }, {
        'font-size: 15;',
        'font-size: 10 * Scale + Count // 15;',
      })
    end)

    it('treats expressions embedded in surrounding text as block boundaries', function()
      assert_replacements({
        'Scale = 100',
        'font-size: 10 * 1.2',
        'Count * 2|',
        'Count = 3',
        'font-size: 10 * 1.2',
        'Count = 200',
      }, { '6', 'Count * 2 // 6' })
    end)

    it('includes definitions more than ten lines away in either direction', function()
      for _, above in ipairs({ true, false }) do
        local lines = { above and 'Count = 3' or 'Count * 2|' }
        for _ = 1, 12 do
          table.insert(lines, '')
        end
        table.insert(lines, above and 'Count * 2|' or 'Count = 3')
        assert_replacements(lines, { '6', 'Count * 2 // 6' })
      end
    end)

    it('stops the block at ordinary text above the current line', function()
      assert_replacements({ 'Count = 3', 'ここから別の計算', 'Count * 2|' }, {})
    end)

    it('stops the block at ordinary text below the current line', function()
      assert_replacements({ 'Count * 2|', 'ここから別の計算', 'Count = 3' }, {})
    end)

    it('does not let definitions outside the block override its variables', function()
      assert_replacements({
        'Count = 100',
        '前の計算',
        'Count = 3',
        'Count * 2|',
        '次の計算',
        'Count = 200',
      }, { '6', 'Count * 2 // 6' })
    end)

    it('does not carry variables between completion requests', function()
      assert_replacements({ 'Count = 3', 'Count * 2|' }, { '6', 'Count * 2 // 6' })
      assert_replacements({ 'Count * 2|' }, {})
    end)

    it('preserves built-in names', function()
      assert_replacements({
        'sqrt = 100',
        'Count = 3',
        'sqrt(Count * Count)|',
      }, { '3', 'sqrt(Count * Count) // 3' })
    end)

    it('does not expose the global environment', function()
      assert_replacements({ 'math.abs(_G.math.pi)|' }, {})
    end)

    it('does not expose vim', function()
      assert_replacements({ 'math.abs(vim.api.nvim_get_current_buf())|' }, {})
    end)

    it('does not execute Lua function expressions', function()
      assert_replacements({ 'math.abs((function() return 1 end)())|' }, {})
    end)

    it('does not expose random functions', function()
      assert_replacements({ 'random()|' }, {})
      assert_replacements({ 'math.random()|' }, {})
      assert_replacements({ 'randomseed(1)|' }, {})
      assert_replacements({ 'math.randomseed(1)|' }, {})
    end)

    it('does not offer non-finite results', function()
      assert_replacements({ '1 / 0|' }, {})
      assert_replacements({ 'sqrt(-1)|' }, {})
    end)
  end)

  for _, prefix in ipairs({ 'a: ', 'あ: ', '🗿: ' }) do
    it(('starts completion after the prefix %q'):format(prefix), function()
      for _, expression in ipairs({ '1 + 2', '1234567890 + 2' }) do
        spec.setup({ buffer_text = { prefix .. expression .. '|' } })
        local service = CompletionService.new({})
        service:register_source(calc_source())
        service:complete({ force = true }):sync(2 * 1000)
        service:matching()

        local matches = service:get_matches()
        assert.are_equal(2, #matches)
        for _, match in ipairs(matches) do
          local range = match.item:get_insert_range()
          assert.are_equal(#prefix, range.start.character)
          assert.are_equal(#prefix + #expression, range['end'].character)
        end
      end
    end)
  end
end)
