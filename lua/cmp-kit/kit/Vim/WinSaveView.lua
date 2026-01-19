---@alias cmp-kit.kit.Vim.WinSaveView.Signature cmp-kit.kit.Vim.WinSaveView.Signature.Branch | cmp-kit.kit.Vim.WinSaveView.Signature.Leaf
---@alias cmp-kit.kit.Vim.WinSaveView.Signature.Branch { [1]: 'row' | 'col', [2]: cmp-kit.kit.Vim.WinSaveView.Signature.Leaf[] }
---@alias cmp-kit.kit.Vim.WinSaveView.Signature.Leaf { [1]: 'leaf' }

---@alias cmp-kit.kit.Vim.WinSaveView.Dimension table<number, { width: number, height: number }>

---Get a size related window layout information.
---@return cmp-kit.kit.Vim.WinSaveView.Dimension, cmp-kit.kit.Vim.WinSaveView.Signature[]
local function get_win_dimensions_and_signatures()
  ---@type cmp-kit.kit.Vim.WinSaveView.Dimension
  local dimensions = {}

  ---@param info vim.fn.winlayout.ret
  local function traverse(info)
    if info[1] == 'leaf' then
      local win = info[2] --[[@as integer]]
      if vim.api.nvim_win_is_valid(win) then
        dimensions[win] = {
          width = vim.api.nvim_win_get_width(win),
          height = vim.api.nvim_win_get_height(win)
        }
      end
      return { 'leaf' }
    elseif info[1] == 'row' or info[1] == 'col' then
      local children = {}
      for i = 1, #info[2] do
        table.insert(children, traverse(info[2][i]))
      end
      return { info[1], children }
    end
  end
  local signatures = traverse(vim.fn.winlayout())
  return dimensions, signatures
end

---@class cmp-kit.kit.Vim.WinSaveView
---@field private _mode string
---@field private _view table
---@field private _win number
---@field private _cur table
---@field private _dimensions cmp-kit.kit.Vim.WinSaveView.Dimension
---@field private _signatures cmp-kit.kit.Vim.WinSaveView.Signature[]
local WinSaveView = {}
WinSaveView.__index = WinSaveView

---Create WinSaveView.
function WinSaveView.new()
  local dimensions, signatures = get_win_dimensions_and_signatures()
  return setmetatable({
    _mode = vim.api.nvim_get_mode().mode,
    _view = vim.fn.winsaveview(),
    _win = vim.api.nvim_get_current_win(),
    _cur = vim.api.nvim_win_get_cursor(0),
    _dimensions = dimensions,
    _signatures = signatures,
  }, WinSaveView)
end

---Restore saved window.
function WinSaveView:restore()
  if vim.api.nvim_win_is_valid(self._win) then
    vim.api.nvim_set_current_win(self._win)
  end

  -- restore modes.
  if vim.api.nvim_get_mode().mode ~= self._mode then
    if self._mode == 'i' then
      vim.cmd.startinsert()
    elseif vim.tbl_contains({ 'v', 'V', vim.keycode('<C-v>') }, self._mode) then
      vim.cmd.normal({ 'gv', bang = true })
    end
  end

  -- restore current window view.
  vim.api.nvim_win_set_cursor(0, self._cur)
  vim.fn.winrestview(self._view)

  -- restore window dimensions.
  local _, signatures = get_win_dimensions_and_signatures()
  if vim.json.encode(signatures) == vim.json.encode(self._signatures) then
    for win, dim in pairs(self._dimensions) do
      if vim.api.nvim_win_is_valid(win) then
        pcall(vim.api.nvim_win_set_width, win, dim.width)
        pcall(vim.api.nvim_win_set_height, win, dim.height)
      end
    end
  end
end

return WinSaveView
