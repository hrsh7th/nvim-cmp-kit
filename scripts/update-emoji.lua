if vim.fn.executable('curl') == 0 then
  print('curl is not installed. Please install curl to update emojis.')
  return
end

local function script_path()
  return debug.getinfo(2, 'S').source:sub(2):match('(.*/)')
end

local data_path = ('%s/../lua/cmp-kit/completion/ext/source/emoji/emoji.json'):format(script_path())

local function to_string(chars)
  local nrs = {}
  for _, char in ipairs(chars) do
    table.insert(nrs, vim.fn.eval(([[char2nr("\U%s")]]):format(char)))
  end
  return vim.fn.list2str(nrs, true)
end

local function fetch()
  vim.fn.system({
    'curl',
    '-s',
    'https://raw.githubusercontent.com/iamcal/emoji-data/master/emoji.json',
    '-o',
    data_path,
  })
end

local function update()
  local data = vim.json.decode(table.concat(vim.fn.readfile(data_path), '\n'))

  local emojis = {}
  for _, emoji in ipairs(data) do
    local chars = to_string(vim.split(emoji.unified, '-'))
    if vim.api.nvim_strwidth(chars) <= 2 then
      emojis[#emojis + 1] = {
        kind = 21,
        label = (' %s :%s:'):format(chars, emoji.short_name),
        insertText = ('%s'):format(chars),
        filterText = (':%s:'):format(table.concat(emoji.short_names, ' ')),
      }
    end
  end
  vim.fn.writefile({ vim.json.encode(emojis) }, data_path)
end

local function main()
  fetch()
  update()
end
main()
