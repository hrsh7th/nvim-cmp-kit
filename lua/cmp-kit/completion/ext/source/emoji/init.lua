local IO = require('cmp-kit.kit.IO')
local Async = require('cmp-kit.kit.Async')

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
        keyword_pattern = [=[\%(^\|[^[:alnum:]]\)\zs:\w\+]=],
      }
    end,
    complete = function(_, _, callback)
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
