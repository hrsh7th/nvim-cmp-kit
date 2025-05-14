local path_source = require('cmp-kit.ext.source.path')
local spec = require('cmp-kit.spec')
local LSP = require('cmp-kit.kit.LSP')

local project_dir = (function()
  local p = vim.fs.abspath(debug.getinfo(1, 'S').source:match('^@?(.*/)'))
  p = vim.fs.dirname(p)
  p = vim.fs.dirname(p)
  p = vim.fs.dirname(p)
  p = vim.fs.dirname(p)
  p = vim.fs.dirname(p)
  return p
end)()

describe('cmp-kit.ext.source.path', function()
  local source = path_source({
    get_cwd = function()
      return project_dir
    end
  })

  describe('skip absolute path', function()
    it('protocol scheme', function()
      spec.setup({ buffer_text = { 'https://|' } })
      assert.are_same(source:complete({
        triggerKind = LSP.CompletionTriggerKind.Invoked,
        triggerCharacter = '/'
      }):sync(2 * 1000), {})

      spec.setup({ buffer_text = { 'file:///|' } })
      assert.are_not.same(source:complete({
        triggerKind = LSP.CompletionTriggerKind.Invoked,
        triggerCharacter = '/'
      }):sync(2 * 1000), {})
    end)

    it('html closing tag', function()
      spec.setup({ buffer_text = { '</|' } })
      assert.are_same(source:complete({
        triggerKind = LSP.CompletionTriggerKind.Invoked,
        triggerCharacter = '/'
      }):sync(2 * 1000), {})
    end)

    it('math expression', function()
      spec.setup({ buffer_text = { '1 /|' } })
      assert.are_same(source:complete({
        triggerKind = LSP.CompletionTriggerKind.Invoked,
        triggerCharacter = '/'
      }):sync(2 * 1000), {})

      spec.setup({ buffer_text = { '(1 + 2) /|' } })
      assert.are_same(source:complete({
        triggerKind = LSP.CompletionTriggerKind.Invoked,
        triggerCharacter = '/'
      }):sync(2 * 1000), {})
    end)

    it('commentstring=// %s', function()
      spec.setup({ buffer_text = { '  /|' } })
      vim.o.commentstring = '// %s'
      assert.are_same(source:complete({
        triggerKind = LSP.CompletionTriggerKind.Invoked,
        triggerCharacter = '/'
      }):sync(2 * 1000), {})

      spec.setup({ buffer_text = { '  //|' } })
      vim.o.commentstring = '// %s'
      assert.are_same(source:complete({
        triggerKind = LSP.CompletionTriggerKind.Invoked,
        triggerCharacter = '/'
      }):sync(2 * 1000), {})

      spec.setup({ buffer_text = { '  // /|' } })
      vim.o.commentstring = '// %s'
      assert.are_not.same(source:complete({
        triggerKind = LSP.CompletionTriggerKind.Invoked,
        triggerCharacter = '/'
      }):sync(2 * 1000), {})
    end)
  end)
end)
