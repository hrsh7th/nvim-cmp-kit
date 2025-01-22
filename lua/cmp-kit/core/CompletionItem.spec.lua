local spec = require('cmp-kit.spec')
local LSP = require('cmp-kit.kit.LSP')
local Async = require('cmp-kit.kit.Async')
local Keymap = require('cmp-kit.kit.Vim.Keymap')
local TriggerContext = require('cmp-kit.core.TriggerContext')

---@return cmp-kit.kit.LSP.Range
local function range(sl, sc, el, ec)
  return {
    start = {
      line = sl,
      character = sc,
    },
    ['end'] = {
      line = el,
      character = ec,
    },
  }
end

describe('cmp-kit.core', function()
  describe('CompletionItem', function()
    describe('#commit', function()
      it('should support dot-to-arrow completion (clangd)', function()
        Keymap.spec(function()
          Keymap.send('i'):await()
          local _, _, service = spec.setup({
            input = 'p',
            buffer_text = { 'obj.|for' },
            items = { {
              label = 'prop',
              textEdit = {
                newText = '->prop',
                range = range(0, 3, 0, 4),
              },
            } },
          })
          local trigger_context = TriggerContext.create()
          local match = service:get_match_at(1)
          assert.equals(match.item:get_offset(), #'obj' + 1)
          assert.equals(trigger_context:get_query(match.item:get_offset()), '.p')
          assert.equals(match.item:get_filter_text(), '.prop')
          assert.equals(match.item:get_select_text(), '->prop')
          match.item:commit({ replace = true }):await()
          spec.assert({ 'obj->prop|' })
          Keymap.send(Keymap.termcodes('<Esc>')):await()
        end)
      end)

      it('should support symbol reference completion (typescript-language-server)', function()
        Keymap.spec(function()
          Keymap.send('i'):await()
          local _, _, service = spec.setup({
            input = 'S',
            buffer_text = { '[].|foo' },
            items = { {
              label = 'Symbol',
              filterText = '.Symbol',
              textEdit = {
                newText = '[Symbol]',
                range = range(0, 2, 0, 3),
              },
            } },
          })
          local trigger_context = TriggerContext.create()
          local match = service:get_match_at(1)
          assert.equals(match.item:get_offset(), #'[]' + 1)
          assert.equals(trigger_context:get_query(match.item:get_offset()), '.S')
          assert.equals(match.item:get_filter_text(), '.Symbol')
          assert.equals(match.item:get_select_text(), '[Symbol]')
          match.item:commit({ replace = true }):await()
          spec.assert({ '[][Symbol]|' })
          Keymap.send(Keymap.termcodes('<Esc>')):await()
        end)
      end)

      it('should support indent fixing completion (vscode-html-language-server)', function()
        Keymap.spec(function()
          Keymap.send('i'):await()
          local _, _, service = spec.setup({
            input = 'd',
            buffer_text = {
              '<div>',
              '\t</|foo>',
            },
            items = { {
              label = '/div',
              filterText = '\t</div',
              textEdit = {
                newText = '</div',
                range = range(1, 0, 1, 3),
              },
            } },
          })
          local trigger_context = TriggerContext.create()
          local match = service:get_match_at(1)
          assert.equals(match.item:get_offset(), #'\t' + 1)
          assert.equals(trigger_context:get_query(match.item:get_offset()), '</d')
          assert.equals(match.item:get_select_text(), '</div')
          assert.equals(match.item:get_filter_text(), '</div')
          match.item:commit({ replace = true }):await()
          assert.equals('</div>', vim.api.nvim_get_current_line())
          spec.assert({
            '<div>',
            '</div|>',
          })
          Keymap.send(Keymap.termcodes('<Esc>')):await()
        end)
      end)

      it('should support extreme additionalTextEdits completion (rust-analyzer)', function()
        Keymap.spec(function()
          Keymap.send('i'):await()
          local _, _, service = spec.setup({
            input = 'd',
            buffer_text = {
              'fn main() {',
              '  let s = ""',
              '    .|foo',
              '}',
            },
            items = { {
              label = 'dbg',
              filterText = 'dbg',
              insertTextFormat = LSP.InsertTextFormat.Snippet,
              textEdit = {
                newText = 'dbg!("")',
                insert = range(2, 5, 2, 8),
                replace = range(2, 5, 2, 8),
              },
            } },
            resolve = function(item)
              local clone = vim.tbl_deep_extend('keep', {}, item)
              clone.additionalTextEdits = {
                {
                  newText = '',
                  range = range(1, 10, 2, 5),
                },
              }
              return Async.resolve(clone)
            end,
          })
          local trigger_context = TriggerContext.create()
          local match = service:get_match_at(1)
          assert.equals(match.item:get_offset(), #'    .' + 1)
          assert.equals(trigger_context:get_query(match.item:get_offset()), 'd')
          assert.equals(match.item:get_select_text(), 'dbg!')
          assert.equals(match.item:get_filter_text(), 'dbg')
          match.item:commit({ replace = true }):await()
          spec.assert({
            'fn main() {',
            '  let s = dbg!("")|',
            '}',
          })
          Keymap.send(Keymap.termcodes('<Esc>')):await()
        end)
      end)

      it('should support EmmyLua annotation completion (lua-language-server)', function()
        -- This test verifies that the filterText correction for clangd does not cause any problems with lua-language-server completion.
        Keymap.spec(function()
          Keymap.send('i'):await()
          local _, _, service = spec.setup({
            input = '',
            buffer_text = {
              '---@param a cmp-kit.|',
            },
            items = {
              {
                label = "cmp-kit.kit.LSP.CompletionItemLabelDetails",
                textEdit = {
                  newText = "cmp-kit.kit.LSP.CompletionItemLabelDetails",
                  range = range(0, 12, 0, 21)
                }
              },
              {
                label = "dansa.kit.LSP.CompletionItemLabelDetails",
                textEdit = {
                  newText = "dansa.kit.LSP.CompletionItemLabelDetails",
                  range = range(0, 12, 0, 21)
                }
              }
            },
          })
          local trigger_context = TriggerContext.create()
          assert.are_not.is_nil(service:get_match_at(1))
          assert.are.is_nil(service:get_match_at(2))
          local match = service:get_match_at(1)
          assert.equals(match.item:get_offset(), #'---@param a ' + 1)
          assert.equals(trigger_context:get_query(match.item:get_offset()), 'cmp-kit.')
          assert.equals(match.item:get_select_text(), 'cmp-kit.kit.LSP.CompletionItemLabelDetails')
          assert.equals(match.item:get_filter_text(), 'cmp-kit.kit.LSP.CompletionItemLabelDetails')
          match.item:commit({ replace = true }):await()
          spec.assert({
            '---@param a cmp-kit.kit.LSP.CompletionItemLabelDetails',
          })
          Keymap.send(Keymap.termcodes('<Esc>')):await()
        end)
      end)
    end)

    it('should support symbolic keyword completion (special feature)', function()
      -- This test verifies that the filterText correction for clangd does not cause any problems with lua-language-server completion.
      Keymap.spec(function()
        Keymap.send('i'):await()
        local _, _, service = spec.setup({
          input = 'd',
          buffer_text = {
            '\\|',
          },
          items = {
            {
              label = '\\date',
              insertText = '2024-12-25',
            }
          },
        })
        local trigger_context = TriggerContext.create()
        local match = service:get_match_at(1)
        assert.equals(match.item:get_offset(), #'' + 1)
        assert.equals(trigger_context:get_query(match.item:get_offset()), '\\d')
        assert.equals(match.item:get_select_text(), '2024-12-25')
        assert.equals(match.item:get_filter_text(), '\\date')
        match.item:commit({ replace = true }):await()
        spec.assert({
          '2024-12-25',
        })
        Keymap.send(Keymap.termcodes('<Esc>')):await()
      end)
    end)
  end)
end)
