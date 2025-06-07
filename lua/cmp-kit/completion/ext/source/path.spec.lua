local path_source = require('cmp-kit.completion.ext.source.path')
local spec = require('cmp-kit.spec')
local LSP = require('cmp-kit.kit.LSP')
local Async = require('cmp-kit.kit.Async')

describe('cmp-kit.completion.ext.source.path', function()
  local source = path_source()

  ---Invoke completion.
  ---@param source cmp-kit.completion.CompletionSource
  ---@param completion_context cmp-kit.kit.LSP.CompletionContext
  ---@return cmp-kit.kit.LSP.TextDocumentCompletionResponse
  local function complete(source, completion_context)
    return Async.new(function(resolve, reject)
      source:complete(completion_context, function(err, res)
        if err then
          reject(err)
        else
          resolve(res)
        end
      end)
    end):sync(2 * 1000)
  end

  describe('skip unexpected absolute path completion', function()
    it('any symbols', function()
      spec.setup({ buffer_text = { '#|' } })
      assert.are_same(complete(source, {
        triggerKind = LSP.CompletionTriggerKind.Invoked,
        triggerCharacter = '/'
      }), {})
    end)

    it('protocol scheme', function()
      spec.setup({ buffer_text = { 'https://|' } })
      assert.are_same(complete(source, {
        triggerKind = LSP.CompletionTriggerKind.Invoked,
        triggerCharacter = '/'
      }), {})

      spec.setup({ buffer_text = { 'file:///|' } })
      assert.are_not.same(complete(source, {
        triggerKind = LSP.CompletionTriggerKind.Invoked,
        triggerCharacter = '/'
      }), {})
    end)

    it('html closing tag', function()
      spec.setup({ buffer_text = { '</|' } })
      assert.are_same(complete(source, {
        triggerKind = LSP.CompletionTriggerKind.Invoked,
        triggerCharacter = '/'
      }), {})
    end)

    it('math expression', function()
      spec.setup({ buffer_text = { '1 /|' } })
      assert.are_same(complete(source, {
        triggerKind = LSP.CompletionTriggerKind.Invoked,
        triggerCharacter = '/'
      }), {})

      spec.setup({ buffer_text = { '(1 + 2) /|' } })
      assert.are_same(complete(source, {
        triggerKind = LSP.CompletionTriggerKind.Invoked,
        triggerCharacter = '/'
      }), {})
    end)

    it('commentstring=// %s', function()
      -- should not complete
      do
        spec.setup({ buffer_text = { '  /|' } })
        vim.o.commentstring = '// %s'
        assert.are_same(complete(source, {
          triggerKind = LSP.CompletionTriggerKind.Invoked,
          triggerCharacter = '/'
        }), {})

        spec.setup({ buffer_text = { '  //|' } })
        vim.o.commentstring = '// %s'
        assert.are_same(complete(source, {
          triggerKind = LSP.CompletionTriggerKind.Invoked,
          triggerCharacter = '/'
        }), {})

        spec.setup({ buffer_text = { '  */|' } })
        vim.o.commentstring = '// %s'
        assert.are_same(complete(source, {
          triggerKind = LSP.CompletionTriggerKind.Invoked,
          triggerCharacter = '/'
        }), {})
      end

      -- should complete.
      do
        spec.setup({ buffer_text = { '  // /|' } })
        vim.o.commentstring = '// %s'
        assert.are_not.same(complete(source, {
          triggerKind = LSP.CompletionTriggerKind.Invoked,
          triggerCharacter = '/'
        }), {})
      end
    end)
  end)
end)
