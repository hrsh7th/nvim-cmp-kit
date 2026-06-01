local spec = require('cmp-kit.spec')
local LSP = require('cmp-kit.kit.LSP')
local Async = require('cmp-kit.kit.Async')
local PreviewText = require('cmp-kit.completion.PreviewText')
local CompletionService = require('cmp-kit.completion.CompletionService')

local function create_view(state)
  state.visible = state.visible or false
  return {
    show = function(_, params)
      state.visible = true
      state.matches = params.matches
      state.selection = params.selection
    end,
    hide = function()
      state.visible = false
    end,
    is_menu_visible = function()
      return state.visible
    end,
    is_docs_visible = function()
      return false
    end,
    show_docs = function() end,
    hide_docs = function() end,
    select = function() end,
    scroll_docs = function() end,
    dispose = function() end,
  }
end

local function create_source(items)
  return {
    name = 'test',
    get_configuration = function()
      return {
        position_encoding_kind = LSP.PositionEncodingKind.UTF8,
      }
    end,
    complete = function(_, _, callback)
      callback(nil, {
        isIncomplete = false,
        items = items,
      })
    end,
  }
end

describe('cmp-kit.completion', function()
  describe('CompletionService', function()
    it('should work on basic case', function()
      local _, source = spec.setup({
        input = 'w',
        buffer_text = {
          'key|',
        },
        items = {
          { label = 'keyword' },
          { label = 'dummy' },
        },
      })
      local state = {}
      local service = CompletionService.new({
        view = {
          show = function(_, params)
            state.matches = params.matches
          end,
          hide = function() end,
          is_menu_visible = function()
            return true
          end,
          is_docs_visible = function()
            return false
          end,
          show_docs = function() end,
          hide_docs = function() end,
          select = function() end,
          scroll_docs = function() end,
          dispose = function() end,
        },
      })
      service:register_source(source)
      service:complete()
      vim.wait(500, function()
        return not not state.matches
      end)
      assert.are.equal(#state.matches, 1)
      assert.are.equal(state.matches[1].item:get_insert_text(), 'keyword')
    end)

    it('should update view on new response', function()
      local _, source = spec.setup({
        input = 'w',
        buffer_text = {
          'key|',
        },
        items = {
          { label = 'keyword' },
        },
      })
      local state = {}
      local service = CompletionService.new({
        view = {
          show = function()
            state.show_count = (state.show_count or 0) + 1
          end,
          hide = function() end,
          is_menu_visible = function()
            return true
          end,
          is_docs_visible = function()
            return false
          end,
          show_docs = function() end,
          hide_docs = function() end,
          select = function() end,
          scroll_docs = function() end,
          dispose = function() end,
        },
      })
      service:register_source(source)
      service:complete()
      vim.wait(500, function()
        return state.show_count == 1
      end)
      service:complete({ force = true })
      vim.wait(500, function()
        return state.show_count == 2
      end)
      assert.are.equal(state.show_count, 2)
    end)

    it('should emit menu show event on menu show', function()
      spec.reset()
      vim.api.nvim_set_current_line('a')
      vim.api.nvim_win_set_cursor(0, { 1, 1 })

      local state = {}
      local service = CompletionService.new({
        view = create_view(state),
      })
      local show_count = 0
      local hide_count = 0
      service:on_menu_show(function()
        show_count = show_count + 1
      end)
      service:on_menu_hide(function()
        hide_count = hide_count + 1
      end)
      service:register_source(create_source({ { label = 'abc' } }))

      service:complete({ force = true }):sync(500)
      service:matching()

      assert.are.equal(1, show_count)
      assert.are.equal(0, hide_count)
    end)

    it('should respect zero item_count', function()
      spec.reset()
      vim.api.nvim_set_current_line('a')
      vim.api.nvim_win_set_cursor(0, { 1, 1 })

      local state = {}
      local service = CompletionService.new({
        view = create_view(state),
      })
      service:register_source(create_source({ { label = 'abc' } }), {
        item_count = 0,
      })

      service:complete({ force = true }):sync(500)
      service:matching()

      assert.are.equal(0, #service:get_matches())
    end)

    it('should keep preselect index aligned after filtering', function()
      spec.reset()
      vim.api.nvim_set_current_line('a')
      vim.api.nvim_win_set_cursor(0, { 1, 1 })

      local state = {}
      local service = CompletionService.new({
        view = create_view(state),
      })
      service:register_source(
        create_source({
          { label = 'abc' },
          { label = 'abd', preselect = true },
        }),
        {
          item_count = 1,
        }
      )

      service:complete({ force = true }):sync(500)
      service:matching()

      assert.are.equal(1, #service:get_matches())
      assert.are.equal(0, service:get_selection().index)
    end)

    it('should not calculate preview text before selecting an item', function()
      spec.reset()
      vim.api.nvim_set_current_line('a')
      vim.api.nvim_win_set_cursor(0, { 1, 1 })

      local original_create = PreviewText.create
      local create_count = 0
      ---@diagnostic disable-next-line: duplicate-set-field
      PreviewText.create = function(...)
        create_count = create_count + 1
        return original_create(...)
      end

      local ok, err = pcall(function()
        local state = {}
        local service = CompletionService.new({
          view = create_view(state),
        })
        service._insert_selection = function(_, _, item_next)
          if item_next then
            item_next:get_preview_text()
          end
          return Async.resolve()
        end
        service:register_source(create_source({ {
          label = 'attr',
          insertText = 'attr="value"',
        } }))

        service:complete({ force = true }):sync(500)
        service:matching()

        assert.are.equal(1, #service:get_matches())
        assert.are.equal(0, create_count)

        service:select(1):sync(500)

        assert.are.equal(1, create_count)
      end)
      PreviewText.create = original_create
      if not ok then
        error(err)
      end
    end)
  end)
end)
