local kit = require('cmp-kit.kit')
local LSP = require('cmp-kit.kit.LSP')
local FloatingWindow = require('cmp-kit.kit.Vim.FloatingWindow')
local TriggerContext = require('cmp-kit.core.TriggerContext')
local Markdown = require('cmp-kit.core.Markdown')

---Create winhighlight.
---@param map table<string, string>
---@return string
local function winhighlight(map)
  return vim
    .iter(pairs(map))
    :map(function(k, v)
      return ('%s:%s'):format(k, v)
    end)
    :join(',')
end
local winhl_bordered = winhighlight({
  CursorLine = 'Visual',
  Search = 'None',
  EndOfBuffer = '',
})
local winhl_pum = winhighlight({
  NormalFloat = 'Pmenu',
  Normal = 'Pmenu',
  FloatBorder = 'Pmenu',
  CursorLine = 'PmenuSel',
  Search = 'None',
  EndOfBuffer = '',
})

---Convert documentation to string.
---@param doc cmp-kit.kit.LSP.MarkupContent|string|nil
---@return string
local function doc_to_string(doc)
  if doc then
    if type(doc) == 'string' then
      return doc
    elseif type(doc) == 'table' and doc.value then
      return doc.value
    end
  end
  return ''
end

---side padding border.
local border_padding_side = { '', '', '', ' ', '', '', '', ' ' }

---@class cmp-kit.signature_help.ext.DefaultView.Config
local default_config = {
  max_width_ratio = 0.8,
  max_height_ratio = 8 / vim.o.lines,
}

---@class cmp-kit.signature_help.ext.DefaultView: cmp-kit.signature_help.SignatureHelpView
---@field private _ns integer
---@field private _window cmp-kit.kit.Vim.FloatingWindow
local DefaultView = {}
DefaultView.__index = DefaultView

---Create a new DefaultView instance.
---@param config? cmp-kit.signature_help.ext.DefaultView.Config|{}
---@return cmp-kit.signature_help.ext.DefaultView
function DefaultView.new(config)
  local self = setmetatable({
    _ns = vim.api.nvim_create_namespace('cmp-kit.signature_help.ext.DefaultView'),
    _window = FloatingWindow.new(),
    _config = kit.merge(config or {}, default_config),
  }, DefaultView)

  self._window:set_buf_option('buftype', 'nofile')
  self._window:set_buf_option('tabstop', 1)
  self._window:set_buf_option('shiftwidth', 1)
  self._window:set_win_option('scrolloff', 0)
  self._window:set_win_option('conceallevel', 2)
  self._window:set_win_option('concealcursor', 'n')
  self._window:set_win_option('cursorlineopt', 'line')
  self._window:set_win_option('foldenable', false)
  self._window:set_win_option('wrap', true)

  self._window:set_win_option(
    'winhighlight',
    winhighlight({
      NormalFloat = 'PmenuSbar',
      Normal = 'PmenuSbar',
      EndOfBuffer = 'PmenuSbar',
      Search = 'None',
    }),
    'scrollbar_track'
  )
  self._window:set_win_option(
    'winhighlight',
    winhighlight({
      NormalFloat = 'PmenuThumb',
      Normal = 'PmenuThumb',
      EndOfBuffer = 'PmenuThumb',
      Search = 'None',
    }),
    'scrollbar_thumb'
  )

  return self
end

---Return if the window is visible.
---@return boolean
function DefaultView:is_visible()
  return self._window:is_visible()
end

---@param data cmp-kit.signature_help.ActiveSignatureData
function DefaultView:show(data)
  local contents = {} --[=[@as cmp-kit.kit.LSP.MarkupContent[]]=]
  -- Create signature label.
  do
    local label = data.signature.label
    local parameter = data.signature.parameters[data.parameter_index]
    if parameter then
      local pos = parameter.label
      if type(pos) == 'string' then
        local s, e = label:find(pos, 1, true)
        if s and e then
          pos = { s - 1, e - 1 }
        end
      end
      if kit.is_array(pos) then
        local pos1 = pos[1]
        local pos2 = pos[2] or pos1
        local before = label:sub(1, pos1)
        local middle = label:sub(pos1 + 1, pos2)
        local after = label:sub(pos2 + 1)
        label = ('```%s\n%s<strong>%s</strong>%s\n```'):format(vim.bo.filetype, before, middle, after)
      end
    end
    table.insert(contents, {
      kind = LSP.MarkupKind.Markdown,
      value = label,
    })
  end

  -- Create parameter documentation.
  do
    local parameter = data.signature.parameters[data.parameter_index]
    if parameter then
      local doc_str = doc_to_string(parameter.documentation)
      if doc_str ~= '' then
        if #contents > 0 then
          table.insert(contents, {
            kind = LSP.MarkupKind.Markdown,
            value = '-----',
          })
        end
        table.insert(contents, {
          kind = LSP.MarkupKind.Markdown,
          value = doc_str,
        })
      end
    end
  end

  -- Create signature documentation.
  do
    local doc_str = doc_to_string(data.signature.documentation)
    if doc_str ~= '' then
      if #contents > 0 then
        table.insert(contents, {
          kind = LSP.MarkupKind.Markdown,
          value = '-----',
        })
      end
      table.insert(contents, {
        kind = LSP.MarkupKind.Markdown,
        value = doc_str,
      })
    end
  end

  if #contents == 0 then
    return self:hide()
  end

  -- Update buffer contents.
  Markdown.set(
    self._window:get_buf('main'),
    self._ns,
    vim.iter(contents):fold({}, function(acc, v)
      for _, t in ipairs(vim.split(v.value, '\n')) do
        table.insert(acc, t)
      end
      return acc
    end)
  )

  -- Compute screen position.
  local trigger_context = TriggerContext.create()
  local border = (vim.o.winborder ~= '' and vim.o.winborder ~= 'none') and vim.o.winborder or border_padding_side
  local border_size = FloatingWindow.get_border_size(border)
  local content_size = FloatingWindow.get_content_size({
    bufnr = self._window:get_buf('main'),
    wrap = true,
    max_inner_width = math.floor(vim.o.columns * default_config.max_width_ratio) - border_size.h,
    markdown = true,
  })
  local pos --[[@as { row: integer, col: integer }]]
  if vim.api.nvim_get_mode().mode ~= 'c' then
    pos = vim.fn.screenpos(0, trigger_context.line + 1, trigger_context.character + 1)
  else
    pos = {}
    pos.row = vim.o.lines
    pos.col = vim.fn.getcmdscreenpos()
  end
  local row = pos.row -- default row should be below the cursor. so we use 1-origin as-is.
  local col = pos.col
  local row_off = -1
  local col_off = -1
  local anchor = 'SW'
  local width = content_size.width
  width = math.min(width, math.floor(default_config.max_width_ratio * vim.o.columns))
  local height = math.min(math.floor(default_config.max_height_ratio * vim.o.lines), content_size.height)
  height = math.min(height, (row + row_off) - border_size.v)

  -- Check row space is enough.
  if (row + row_off - border_size.v) < 1 then
    return self:hide()
  end

  -- update border config.
  if vim.o.winborder ~= '' and vim.o.winborder ~= 'none' then
    self._window:set_win_option('winhighlight', winhl_bordered)
  else
    self._window:set_win_option('winhighlight', winhl_pum)
  end
  self._window:set_win_option('winblend', vim.o.pumblend ~= 0 and vim.o.pumblend or vim.o.winblend)

  self._window:show({
    row = row + row_off,
    col = col + col_off,
    anchor = anchor,
    width = width,
    height = height,
    border = border,
    footer = ('%s / %s'):format(data.signature_index, data.signature_count),
    footer_pos = 'right',
    style = 'minimal',
  })
  vim.api.nvim_win_set_cursor(self._window:get_win('main') --[[@as integer]], { 1, 0 })
end

---Hide the signature help view.
function DefaultView:hide()
  self._window:hide()
end

---Scroll the signature help view.
---@param delta integer
function DefaultView:scroll(delta)
  if self:is_visible() then
    self._window:scroll(delta)
  end
end

return DefaultView
