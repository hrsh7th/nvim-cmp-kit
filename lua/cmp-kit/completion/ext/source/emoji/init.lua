local IO = require('cmp-kit.kit.IO')
local Async = require('cmp-kit.kit.Async')
local TriggerContext = require('cmp-kit.core.TriggerContext')

local cache = {}

local function script_path()
  return debug.getinfo(2, 'S').source:sub(2):match('(.*/)')
end

local function restore()
  if not cache.items then
    cache.items = vim.json.decode(IO.read_file(
      IO.join(script_path(), 'emoji.json')
    ):await())
  end
  return cache.items
end


return function()
  ---@type cmp-kit.completion.CompletionSource
  return {
    name = 'emoji',
    get_configuration = function()
      return {
        trigger_characters = { ':' },
        keyword_pattern = [=[\%(^\|[^[:alnum:]]\)\zs:\w\w*]=],
      }
    end,
    complete = function(_, _, callback)
      local trigger_context = TriggerContext.create()
      if not vim.regex([=[\%(^\|[^[:alnum:]]\)\zs:\w*$]=]):match_str(trigger_context.text_before) then
        return callback(nil, nil)
      end
      Async.run(function()
        callback(nil, {
          isIncomplete = false,
          items = restore(),
        })
      end):dispatch(callback, function()
        callback(nil, nil)
      end)
    end
  }
end
