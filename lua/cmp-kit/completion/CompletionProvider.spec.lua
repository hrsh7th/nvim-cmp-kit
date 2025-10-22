local spec = require('cmp-kit.spec')
local Keymap = require('cmp-kit.kit.Vim.Keymap')
local TriggerContext = require('cmp-kit.core.TriggerContext')
local DefaultConfig = require('cmp-kit.completion.ext.DefaultConfig')
local CompletionProvider = require('cmp-kit.completion.CompletionProvider')

---@class cmp-kit.completion.CompletionProvider.spec.Option
---@field public keyword_pattern? string

---@param option? cmp-kit.completion.CompletionProvider.spec.Option
---@return cmp-kit.completion.CompletionProvider, { set_response: fun(response: cmp-kit.kit.LSP.CompletionList) }
local function create_provider(option)
  option = option or {}

  local response ---@type cmp-kit.kit.LSP.CompletionList
  local provider = CompletionProvider.new({
    name = 'dummy',
    get_configuration = function()
      return {
        keyword_pattern = option.keyword_pattern or DefaultConfig.default_keyword_pattern,
        trigger_characters = { '.' },
      }
    end,
    complete = function(_, _, callback)
      callback(nil, response)
    end,
  })
  return provider, {
    ---@param response_ cmp-kit.kit.LSP.CompletionList
    set_response = function(response_)
      response = response_
    end,
  }
end

describe('cmp-kit.completion', function()
  describe('CompletionProvider', function()
    it('should determine completion timing', function()
      spec.reset()

      local provider, ctx = create_provider()
      Keymap.spec(function()
        Keymap.send('i'):await()

        -- no_completion: keyword_pattern=false.
        Keymap.send(' '):await()
        ctx.set_response({ isIncomplete = false, items = { { label = 'foobarbaz' } } })
        assert.is_nil(provider:complete(TriggerContext.create()):await())

        -- completion: keyword_pattern=true.
        Keymap.send('f'):await()
        ctx.set_response({ isIncomplete = true, items = { { label = 'foobarbaz' } } })
        assert.are_not.is_nil(provider:complete(TriggerContext.create()):await())

        -- completion: keyword_pattern=true, alreadyCompleted=true, prevIsIncomplete=true
        Keymap.send('o'):await()
        ctx.set_response({ isIncomplete = false, items = { { label = 'foobarbaz' } } })
        assert.are_not.is_nil(provider:complete(TriggerContext.create()):await())

        -- no_completion: keyword_pattern=true, alreadyCompleted=true, prevIsIncomplete=false
        Keymap.send('o'):await()
        ctx.set_response({ isIncomplete = false, items = { { label = 'foobarbaz' } } })
        assert.is_nil(provider:complete(TriggerContext.create()):await())

        -- completion: force.
        Keymap.send('b'):await()
        ctx.set_response({ isIncomplete = false, items = { { label = 'foobarbaz' } } })
        assert.are_not.is_nil(provider:complete(TriggerContext.create({ force = true })):await())

        -- completion: trigger_char
        Keymap.send('.'):await()
        ctx.set_response({ isIncomplete = false, items = { { label = 'foobarbaz' } } })
        assert.are_not.is_nil(provider:complete(TriggerContext.create()):await())
      end)
    end)

    it('completion state: keyword pattern will be cleared if keyword_pattern=false', function()
      spec.reset()

      local provider, ctx = create_provider()
      Keymap.spec(function()
        Keymap.send('i'):await()

        -- completion.
        Keymap.send('f'):await()
        ctx.set_response({ isIncomplete = false, items = { { label = 'foobarbaz' } } })
        provider:complete(TriggerContext.create()):await()
        assert.are_not.same({}, provider:get_items())

        -- keep: keyword_pattern=true.
        Keymap.send('o'):await()
        ctx.set_response({ isIncomplete = false, items = { { label = 'foobarbaz' } } })
        provider:complete(TriggerContext.create()):await()
        assert.are_not.same({}, provider:get_items())

        -- clear: keyword_pattern=false.
        Keymap.send(Keymap.termcodes('<BS><BS>')):await()
        ctx.set_response({ isIncomplete = false, items = { { label = 'foobarbaz' } } })
        provider:complete(TriggerContext.create()):await()
        assert.are.same({}, provider:get_items())
      end)
    end)

    it('completion state: trigger_characters does not clear even if keyword_pattern=false', function()
      spec.reset()

      local provider, ctx = create_provider()
      Keymap.spec(function()
        Keymap.send('i'):await()

        -- completion.
        Keymap.send('.'):await()
        ctx.set_response({ isIncomplete = false, items = { { label = 'foobarbaz' } } })
        provider:complete(TriggerContext.create()):await()
        assert.is_true(provider:in_trigger_character_completion())
        assert.are_not.same({}, provider:get_items())

        -- keep: keyword_pattern=true.
        Keymap.send('f'):await()
        ctx.set_response({ isIncomplete = false, items = { { label = 'foobarbaz' } } })
        provider:complete(TriggerContext.create()):await()
        assert.is_true(provider:in_trigger_character_completion())
        assert.are_not.same({}, provider:get_items())

        -- keep: keyword_pattern=true.
        Keymap.send('o'):await()
        ctx.set_response({ isIncomplete = false, items = { { label = 'foobarbaz' } } })
        provider:complete(TriggerContext.create()):await()
        assert.is_true(provider:in_trigger_character_completion())
        assert.are_not.same({}, provider:get_items())

        -- keep: keyword_pattern=false.
        Keymap.send(Keymap.termcodes('<BS><BS>')):await()
        ctx.set_response({ isIncomplete = false, items = { { label = 'foobarbaz' } } })
        provider:complete(TriggerContext.create()):await()
        assert.is_true(provider:in_trigger_character_completion())
        assert.are_not.same({}, provider:get_items())
      end)
    end)
  end)
end)
