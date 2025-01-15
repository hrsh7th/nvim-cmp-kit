local spec = require('cmp-kit.spec')
local Async = require('cmp-kit.kit.Async')
local Keymap = require('cmp-kit.kit.Vim.Keymap')
local DefaultConfig = require('cmp-kit.core.DefaultConfig')
local TriggerContext = require('cmp-kit.core.TriggerContext')
local CompletionProvider = require('cmp-kit.core.CompletionProvider')

---@class cmp-kit.core.CompletionProvider.spec.Option
---@field public keyword_pattern? string

---@param option? cmp-kit.core.CompletionProvider.spec.Option
---@return cmp-kit.core.CompletionProvider, { set_response: fun(response: cmp-kit.kit.LSP.CompletionList) }
local function create_provider(option)
  option = option or {}

  local response ---@type cmp-kit.kit.LSP.CompletionList
  local provider = CompletionProvider.new({
    name = 'dummy',
    get_configuration = function()
      return {
        completion_options = {
          triggerCharacters = { '.' },
        },
        keyword_pattern = option.keyword_pattern or DefaultConfig.default_keyword_pattern,
      }
    end,
    complete = function(_)
      return Async.resolve(response)
    end,
  })
  return provider, {
    ---@param response_ cmp-kit.kit.LSP.CompletionList
    set_response = function(response_)
      response = response_
    end,
  }
end

describe('cmp-kit.core', function()
  describe('CompletionProvider', function()
    it('should determine completion timing', function()
      spec.reset()

      local provider, ctx = create_provider()
      Keymap.spec(function()
        Keymap.send('i'):await()
        assert.is_nil(provider:complete(TriggerContext.create()):await())

        -- no_completion.
        Keymap.send(' '):await()
        assert.is_nil(provider:complete(TriggerContext.create()):await())

        -- no_completion -> keyword_pattern & incmp-kit.
        Keymap.send('f'):await()
        ctx.set_response({ isIncomplete = true, items = {} })
        assert.are_not.is_nil(provider:complete(TriggerContext.create()):await())

        -- keyword_pattern & incomplete -> keyword_pattern.
        Keymap.send('o'):await()
        ctx.set_response({ isIncomplete = false, items = {} })
        assert.are_not.is_nil(provider:complete(TriggerContext.create()):await())

        -- keyword_pattern -> force.
        Keymap.send('o'):await()
        ctx.set_response({ isIncomplete = false, items = {} })
        assert.are_not.is_nil(provider:complete(TriggerContext.create({ force = true })):await())

        -- keyword_pattern & force -> keyword_pattern
        Keymap.send('o'):await()
        ctx.set_response({ isIncomplete = false, items = {} })
        assert.are_not.is_nil(provider:complete(TriggerContext.create()):await())

        -- keyword_pattern -> trigger_character
        Keymap.send('.'):await()
        assert.are_not.is_nil(provider:complete(TriggerContext.create()):await())
      end)
    end)
  end)
end)
