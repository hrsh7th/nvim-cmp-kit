local debugger = {}

local private = {
  ---@type integer
  ns = vim.api.nvim_create_namespace('cmp-kit.debugger'),
  ---@type integer
  buf = vim.api.nvim_create_buf(false, true),
  ---@type integer
  win = nil,
  ---@type boolean
  enabled = false,
}

---Enable or disable debugger.
---@param enabled? boolean
---@return boolean
function debugger.enable(enabled)
  if type(enabled) == 'boolean' then
    private.enabled = enabled
  end
  return private.enabled
end

---Add debugger entry.
---@param name string
---@param entry any
function debugger.add(name, entry)
  local botrow = vim.api.nvim_buf_line_count(private.buf)
  local lines = {}
  local marks = {}

  -- insert name.
  table.insert(lines, name)
  table.insert(marks, {
    row = #lines - 1,
    col = 0,
    mark = {
      end_row = #lines - 1,
      end_col = #name,
      hl_group = 'Special'
    }
  })

  -- insert inspected values.
  local inspected = vim.inspect(entry)
  for _, s in ipairs(vim.split(inspected, '\n')) do
    table.insert(lines, s)
  end
  table.insert(lines, '')

  -- set lines.
  vim.api.nvim_buf_set_lines(private.buf, -1, -1, false, lines)

  -- set marks.
  for _, extmark in ipairs(marks) do
    pcall(vim.api.nvim_buf_set_extmark, private.buf, private.ns, extmark.row, extmark.col, extmark.mark)
  end

  -- locate cursor.
  if private.win and vim.api.nvim_win_is_valid(private.win) then
    vim.api.nvim_win_set_cursor(private.win, { botrow, 0 })
  end
end

---Open debugger logs.
function debugger.open()
  debugger.enable(true)
  if private.win then
    pcall(vim.api.nvim_win_close, private.win, true)
  end
  private.win = vim.api.nvim_open_win(private.buf, true, {
    vertical = true,
    split = 'right'
  })
end

return debugger
