local Async = require('cmp-kit.kit.Async')
local CompletionService = require('cmp-kit.core.CompletionService')
local CompletionProvider = require('cmp-kit.core.CompletionProvider')

return {
  setup = function()
    ---@type table<integer, { service: cmp-kit.core.CompletionService }>
    local buf_state = {}

    ---@return { service: cmp-kit.core.CompletionService }
    local function get(specified_buf)
      local buf = (specified_buf == nil or specified_buf == 0) and vim.api.nvim_get_current_buf() or specified_buf
      if not buf_state[buf] then
        local service = CompletionService.new({
          sync_mode = function()
            local ok, automa = pcall(require, 'automa')
            return vim.fn.reg_executing() ~= '' or (ok and automa.executing())
          end,
          expand_snippet = function(snippet)
            vim.fn['vsnip#anonymous'](snippet)
          end
        })
        buf_state[buf] = { service = service }

        do
          local ticket = 0
          vim.api.nvim_create_autocmd('CmdlineChanged', {
            pattern = ('<buffer=%s>'):format(buf),
            callback = function()
              ticket = ticket + 1
              local my_ticket = ticket
              vim.schedule(function()
                if vim.api.nvim_get_mode().mode == 'c' then
                  if my_ticket == ticket then
                    service:complete()
                  end
                end
              end)
            end
          })
        end

        vim.api.nvim_create_autocmd('TextChangedI', {
          pattern = ('<buffer=%s>'):format(buf),
          callback = function()
            service:complete()
          end
        })

        vim.api.nvim_create_autocmd('CursorMovedI', {
          pattern = ('<buffer=%s>'):format(buf),
          callback = function()
            service:complete()
          end
        })

        vim.api.nvim_create_autocmd('ModeChanged', {
          callback = function(e)
            if e.match == 'i:n' then
              service:clear()
            elseif e.match == 'c:n' then
              service:clear()
            end
          end
        })

        --- register buffer source.
        if true then
          service:register_provider(CompletionProvider.new(require('cmp-kit.ext.source.buffer')({
            keyword_pattern = [[\%(-\?\d\+\%(\.\d\+\)\?\|\h\w*\%(-\w*\)*\)]],
            min_keyword_length = 3,
          })), {
            dedup = true,
            keyword_length = 4,
          })
          service:register_provider(CompletionProvider.new(require('cmp-kit.ext.source.path')()))
          service:register_provider(CompletionProvider.new(require('cmp-kit.ext.source.cmdline')()), {
            priority = 1000
          })
        end

        -- register test source.
        if false then
          service:register_provider(CompletionProvider.new({
            name = 'test',
            complete = function(_)
              return Async.run(function()
                return {
                  items = {
                    {
                      label = '\\date',
                      insertText = os.date('%Y-%m-%d'),
                    }
                  }
                }
              end)
            end
          }))
        end
      end
      return buf_state[buf]
    end

    vim.api.nvim_create_autocmd('InsertEnter', {
      callback = function()
        get(0)
      end
    })

    vim.api.nvim_create_autocmd('LspAttach', {
      callback = function(e)
        local client = vim.lsp.get_clients({
          bufnr = e.buf,
          id = e.data.client_id
        })[1]
        if client then
          get(e.buf).service:register_provider(CompletionProvider.new(require('cmp-kit.ext.source.lsp.completion')({
            client = client
          })), {
            priority = 100
          })
        end
      end
    })

    do
      local select = function(option)
        option = option or {}
        option.delta = option.delta or 1
        option.preselect = option.preselect or false
        return {
          action = function()
            local selection = get().service:get_selection()
            get().service:select(selection.index + option.delta, option.preselect)
          end
        }
      end
      local commit = function(option)
        option = option or {}
        option.replace = option.replace or false
        option.select_first = option.select_first or false
        return {
          enabled = function()
            local select_first = option.select_first and vim.api.nvim_get_mode().mode ~= 'c'
            return get().service and (get().service:get_selection().index > 0 or select_first)
          end,
          action = function(ctx)
            local select_first = option.select_first and vim.api.nvim_get_mode().mode ~= 'c'
            local selection = get().service:get_selection()
            if selection then
              local match = get().service:get_match_at(selection.index)
              if not match and select_first then
                match = get().service:get_match_at(1)
              end
              if match then
                get().service:commit(match.item, {
                  replace = option.replace,
                }):await()
                return
              end
            end
            ctx.next()
          end
        }
      end

      local ok, insx = pcall(require, 'insx')
      if ok then
        insx.add('<C-n>', select({ delta = 1, preselect = false }), { mode = { 'i', 'c' } })
        insx.add('<C-p>', select({ delta = -1, preselect = false }), { mode = { 'i', 'c' } })
        insx.add('<Down>', select({ delta = 1, preselect = true }), { mode = { 'i' } })
        insx.add('<Up>', select({ delta = -1, preselect = true }), { mode = { 'i' } })
        insx.add('<CR>', commit({ select_first = true, replace = false }))
        insx.add('<C-y>', commit({ select_first = true, replace = true }), { mode = { 'i', 'c' } })
        insx.add('<C-n>', {
          enabled = function()
            return not get().service:get_match_at(1)
          end,
          action = function()
            get().service:complete({ force = true })
          end
        }, { mode = { 'i', 'c' } })
        insx.add('<C-Space>', function()
          get().service:complete({ force = true })
        end, { mode = { 'i', 'c' } })
      end
    end
  end
}
