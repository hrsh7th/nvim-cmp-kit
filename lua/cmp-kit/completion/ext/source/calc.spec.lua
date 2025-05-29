local calc_source = require('cmp-kit.completion.ext.source.calc')
local spec = require('cmp-kit.spec')
local LSP = require('cmp-kit.kit.LSP')

describe('cmp-kit.completion.ext.source.calc', function()
  local source = calc_source()

  ---@param text string
  ---@param output number?
  local function assert_output(text, output)
    for _, buffer_text in ipairs({ text, ('%s '):format(text) }) do
      spec.setup({ buffer_text = { buffer_text } })
      local response = source:complete({ triggerKind = LSP.CompletionTriggerKind.Invoked }):sync(2 * 1000)
      if output == nil then
        assert.is_not_nil(response)
        assert.are_equal(#response.items, 0)
      else
        assert.is_not_nil(response)
        assert.are_equal(#response.items, 2)
        assert.is_truthy(response.items[1].label:match(('= %s$'):format(vim.pesc(tostring(output)))))
        assert.is_truthy(response.items[2].label:match(('= %s$'):format(vim.pesc(tostring(output)))))
      end
    end
  end

  it('basic usage', function()
    assert_output('5|', nil)
    assert_output('5 * 100|', 5 * 100)
    assert_output('5 * math.pow(1, 2)|', 5 * math.pow(1, 2))
  end)
end)
