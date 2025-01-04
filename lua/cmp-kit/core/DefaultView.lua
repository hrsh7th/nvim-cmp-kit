local kit = require('cmp-kit.kit')
local LSP = require('cmp-kit.kit.LSP')
local Markdown = require('cmp-kit.core.Markdown')
local FloatingWindow = require('cmp-kit.kit.Vim.FloatingWindow')

---@class cmp-kit.core.DefaultView.Config
---@field border string
---@field menu_components { is_label?: boolean, padding_left: integer, padding_right: integer, align: 'left' | 'right', resolve: fun(item: cmp-kit.core.CompletionItem, config: cmp-kit.core.DefaultView.Config): { [1]: string, [2]?: string } }[]
---@field menu_padding_left integer
---@field menu_padding_right integer
---@field menu_gap integer
---@field menu_min_win_height integer
---@field menu_max_win_height integer
---@field docs_min_win_width_ratio number
---@field docs_max_win_width_ratio number
---@field docs_min_win_height_ratio number
---@field docs_max_win_height_ratio number
---@field icon_resolver fun(kind: cmp-kit.kit.LSP.CompletionItemKind): string, string?

---Lookup table for CompletionItemKind.
local CompletionItemKindLookup = {}
for k, v in pairs(LSP.CompletionItemKind) do
  CompletionItemKindLookup[v] = k
end

---Create winhighlight.
local function winhighlight(map)
  return vim.iter(pairs(map)):map(function(k, v)
    return ('%s:%s'):format(k, v)
  end):join(',')
end

---@type { clear_cache: fun() }|fun(text: string): integer
local get_strwidth
do
  local cache = {}
  get_strwidth = setmetatable({
    clear_cache = function()
      cache = {}
    end,
  }, {
    __call = function(_, text)
      if not cache[text] then
        cache[text] = vim.api.nvim_strwidth(text)
      end
      return cache[text]
    end
  })
end

---side padding border.
local border_padding_side = { '', '', '', ' ', '', '', '', ' ' }

---@type cmp-kit.core.DefaultView.Config
local default_config = {
  border = 'rounded',
  menu_components = {
    {
      padding_left = 0,
      padding_right = 0,
      align = 'right',
      resolve = function(item, config)
        local kind = item:get_kind() or LSP.CompletionItemKind.Text
        return { config.icon_resolver(kind) }
      end,
    },
    {
      is_label = true,
      padding_left = 0,
      padding_right = 0,
      align = 'left',
      resolve = function(item)
        return {
          vim.fn.strcharpart(item:get_label_text(), 0, 48),
          'CmpItemAbbr',
        }
      end,
    },
    {
      padding_left = 0,
      padding_right = 0,
      align = 'right',
      resolve = function(item)
        return {
          vim.fn.strcharpart(item:get_label_details().description or '', 0, 28),
          'Comment',
        }
      end,
    },
    {
      padding_left = 0,
      padding_right = 0,
      align = 'right',
      resolve = function(item)
        return { item:get_source_name(), 'NonText' }
      end,
    },
  },
  menu_padding_left = 1,
  menu_padding_right = 1,
  menu_gap = 1,
  menu_min_win_height = 10,
  menu_max_win_height = 18,
  docs_min_win_width_ratio = 0.25,
  docs_max_win_width_ratio = 0.55,
  docs_min_win_height_ratio = 0.25,
  docs_max_win_height_ratio = 0.55,
  icon_resolver = (function(completion_item_kind)
    local ok, MiniIcons = pcall(require, 'nvim-web-devicons')
    return function()
      if not ok then
        return '', ''
      end
      return MiniIcons.get('lsp', (CompletionItemKindLookup[completion_item_kind] or 'text'):lower())
    end
  end)(),
}

---@class cmp-kit.core.DefaultView: cmp-kit.core.View
---@field private _ns_id integer
---@field private _config cmp-kit.core.DefaultView.Config
---@field private _service cmp-kit.core.CompletionService
---@field private _menu_window cmp-kit.kit.Vim.FloatingWindow
---@field private _docs_window cmp-kit.kit.Vim.FloatingWindow
---@field private _matches cmp-kit.core.Match[]
---@field private _selected_item? cmp-kit.core.CompletionItem
local DefaultView = {}
DefaultView.__index = DefaultView

---Create DefaultView
---@param config? cmp-kit.core.DefaultView.Config|{}
---@return cmp-kit.core.DefaultView
function DefaultView.new(config)
  local self = setmetatable({
    _ns_id = vim.api.nvim_create_namespace(('cmp-kit.core.DefaultView.%s'):format(vim.uv.now())),
    _config = kit.merge(config or {}, default_config) --[[@as cmp-kit.core.DefaultView.Config]],
    _menu_window = FloatingWindow.new(),
    _docs_window = FloatingWindow.new(),
    _matches = {},
  }, DefaultView)

  -- common window config.
  for _, win in ipairs({ self._menu_window, self._docs_window }) do
    win:set_buf_option('buftype', 'nofile')
    win:set_buf_option('tabstop', 1)
    win:set_buf_option('shiftwidth', 1)
    win:set_win_option('scrolloff', 0)
    win:set_win_option('conceallevel', 2)
    win:set_win_option('concealcursor', 'n')
    win:set_win_option('cursorlineopt', 'line')
    win:set_win_option('foldenable', false)
    win:set_win_option('wrap', false)
    if self._config.border then
      win:set_win_option('winhighlight', winhighlight({
        NormalFloat = 'Normal',
        Normal = 'Normal',
        FloatBorder = 'Normal',
        CursorLine = 'Visual',
        Search = 'None',
      }))
    else
      win:set_win_option('winhighlight', winhighlight({
        NormalFloat = 'Normal',
        Normal = 'Normal',
        FloatBorder = 'Normal',
        CursorLine = 'PmenuSel',
        Search = 'None',
      }))
    end
    win:set_win_option('winhighlight', winhighlight({
      NormalFloat = 'PmenuSbar',
      Normal = 'PmenuSbar',
      EndOfBuffer = 'PmenuSbar',
      Search = 'None',
    }), 'scrollbar_track')
    win:set_win_option('winhighlight', winhighlight({
      NormalFloat = 'PmenuThumb',
      Normal = 'PmenuThumb',
      EndOfBuffer = 'PmenuThumb',
      Search = 'None',
    }), 'scrollbar_thumb')
  end

  -- docs window config.
  self._docs_window:set_config({ markdown = true })
  self._docs_window:set_win_option('wrap', true)

  return self
end

---Return true if window is visible.
---@return boolean
function DefaultView:is_visible()
  return self._menu_window:is_visible()
end

---Show completion menu.
---@param matches cmp-kit.core.Match[]
---@param selection cmp-kit.core.Selection
function DefaultView:show(matches, selection)
  -- hide window if no matches.
  self._matches = matches
  if #self._matches == 0 then
    self:hide()
    return
  end

  -- init columns.
  ---@type { is_label?: boolean, display_width: integer, padding_left: integer, padding_right: integer, align: 'left' | 'right', resolved: { [1]: string, [2]?: string }[] }[]
  local columns = {}
  for _, component in ipairs(self._config.menu_components) do
    table.insert(columns, {
      is_label = component.is_label,
      display_width = 0,
      padding_left = component.padding_left,
      padding_right = component.padding_right,
      align = component.align,
      resolved = {},
    })
  end

  -- compute columns.
  local min_offset = math.huge
  for i, match in ipairs(self._matches) do
    min_offset = math.min(min_offset, match.item:get_offset())
    for j, component in ipairs(self._config.menu_components) do
      local resolved = component.resolve(match.item, self._config)
      columns[j].display_width = math.max(columns[j].display_width, get_strwidth(resolved[1]))
      columns[j].resolved[i] = resolved
    end
  end

  -- remove empty columns.
  for i = #columns, 1, -1 do
    if columns[i].display_width == 0 then
      table.remove(columns, i)
    end
  end

  -- set decoration provider.
  vim.api.nvim_set_decoration_provider(self._ns_id, {
    on_win = function(_, _, buf, toprow, botrow)
      if buf ~= self._menu_window:get_buf() then
        return
      end

      for row = toprow, botrow do
        local off = self._config.menu_padding_left
        for _, column in ipairs(columns) do
          off = off + column.padding_left

          local resolved = column.resolved[row + 1]
          local column_byte_width = #resolved[1] + column.display_width - get_strwidth(resolved[1])
          vim.api.nvim_buf_set_extmark(buf, self._ns_id, row, off, {
            end_row = row,
            end_col = off + column_byte_width,
            hl_group = resolved[2],
            hl_mode = 'blend',
            ephemeral = true,
          })
          if column.is_label then
            for _, pos in ipairs(self._matches[row + 1].match_positions) do
              vim.api.nvim_buf_set_extmark(buf, self._ns_id, row, off + pos.start_index - 1, {
                end_row = row,
                end_col = off + pos.end_index,
                hl_group = pos.hl_group or 'CmpItemAbbrMatch',
                hl_mode = 'blend',
                ephemeral = true,
              })
            end
          end
          off = off + column_byte_width + column.padding_right + self._config.menu_gap
        end
      end
    end,
  })

  -- create formatting.
  local parts = {}
  table.insert(parts, (' '):rep(self._config.menu_padding_left or 1))
  for i, column in ipairs(columns) do
    table.insert(parts, (' '):rep(column.padding_left or 0))
    table.insert(parts, '%s%s')
    if i ~= #columns then
      table.insert(parts, (' '):rep(self._config.menu_gap or 1))
    end
  end
  table.insert(parts, (' '):rep(self._config.menu_padding_right or 1))
  local formatting = table.concat(parts, '')

  -- draw lines.
  local display_width = 0
  local lines = {}
  for i in ipairs(self._matches) do
    local args = {}
    for _, column in ipairs(columns) do
      local resolved = column.resolved[i]
      if column.align == 'right' then
        table.insert(args, (' '):rep(column.display_width - get_strwidth(resolved[1])))
        table.insert(args, resolved[1])
      else
        table.insert(args, resolved[1])
        table.insert(args, (' '):rep(column.display_width - get_strwidth(resolved[1])))
      end
    end
    local line = formatting:format(unpack(args))
    table.insert(lines, line)
    display_width = math.max(display_width, get_strwidth(line))
  end
  vim.api.nvim_buf_set_lines(self._menu_window:get_buf(), 0, -1, false, lines)

  -- show window.
  local border_size = FloatingWindow.get_border_size(self._config.border)
  local leading_text = vim.api.nvim_get_current_line():sub(min_offset, vim.fn.col('.') - 1)
  local pos = vim.fn.screenpos(0, vim.fn.line('.'), vim.fn.col('.'))
  local row = pos.row - 1 -- default row should be below the cursor. so we use 1-origin as-is.
  local col = pos.col - vim.api.nvim_strwidth(leading_text)

  -- setup default position offset.
  local row_off = 1
  local col_off = (function()
    local label_off = self._config.menu_padding_left
    for i, column in ipairs(columns) do
      if column.is_label then
        break
      end
      label_off = label_off + (i > 1 and self._config.menu_gap and 1 or 0) + column.padding_left + column.display_width +
          column.padding_right
    end
    return -label_off
  end)()
  local anchor = 'NW'

  local outer_height --[[@as integer]]
  do
    local can_bottom = row + row_off + self._config.menu_min_win_height <= vim.o.lines
    if not can_bottom then
      anchor = 'SW'
      row_off = 0
      local top_space = math.min(self._config.menu_max_win_height, row - 1)
      outer_height = math.min(#self._matches + border_size.v, top_space)
    else
      local bottom_space = math.min(self._config.menu_max_win_height, vim.o.lines - (row + row_off))
      outer_height = math.min(#self._matches + border_size.v, bottom_space)
    end
  end

  self._menu_window:show({
    row = row + row_off,
    col = col + col_off,
    width = display_width,
    height = outer_height - border_size.v,
    anchor = anchor,
    style = 'minimal',
    border = self._config.border,
  })
  self._menu_window:set_win_option('cursorline', selection.index ~= 0)
end

---Hide window.
function DefaultView:hide()
  get_strwidth.clear_cache()
  self._menu_window:hide()
  self._docs_window:hide()
end

---Apply selection.
---@param matches cmp-kit.core.Match[]
---@param selection cmp-kit.core.Selection
function DefaultView:select(matches, selection)
  if not self._menu_window:is_visible() then
    return
  end

  -- apply selection.
  if selection.index == 0 then
    self._menu_window:set_win_option('cursorline', false)
    vim.api.nvim_win_set_cursor(self._menu_window:get_win() --[[@as integer]], { 1, 0 })
  else
    self._menu_window:set_win_option('cursorline', true)
    vim.api.nvim_win_set_cursor(self._menu_window:get_win() --[[@as integer]], { selection.index, 0 })
  end

  -- show documentation.
  local match = matches[selection.index]
  self:_update_docs(match and match.item)
end

---Update documentation.
---@param item? cmp-kit.core.CompletionItem
function DefaultView:_update_docs(item)
  self._selected_item = item

  if not item then
    self._docs_window:hide()
    return
  end

  item:resolve():next(vim.schedule_wrap(function()
    if item ~= self._selected_item then
      return
    end

    if not self._menu_window:is_visible() then
      self._docs_window:hide()
      return
    end

    local documentation = item:get_documentation()
    if not documentation then
      self._docs_window:hide()
      return
    end

    -- set buffer contents.
    Markdown.set(self._docs_window:get_buf(), self._ns_id, vim.split(documentation.value, '\n', { plain = true }))

    -- prepare some sizes.
    local min_width = math.floor(vim.o.columns * self._config.docs_min_win_width_ratio)
    local max_width = math.floor(vim.o.columns * self._config.docs_max_win_width_ratio)
    local max_height = math.floor(vim.o.lines * self._config.docs_max_win_width_ratio)
    local menu_viewport = self._menu_window:get_viewport()
    local docs_border = menu_viewport.border and menu_viewport.border or border_padding_side
    local border_size = FloatingWindow.get_border_size(docs_border)
    local content_size = FloatingWindow.get_content_size({
      bufnr = self._docs_window:get_buf(),
      wrap = self._docs_window:get_win_option('wrap'),
      max_inner_width = max_width - border_size.h,
      markdown = self._docs_window:get_config().markdown,
    })

    -- compute restricted size for directions.
    local restricted_size --[[@as { outer_width: integer, outer_height: integer, inner_width: integer, inner_height: integer }]]
    do
      local possible_scrollbar_space = 1
      local left_space = menu_viewport.col - 1 - possible_scrollbar_space
      local right_space = (vim.o.columns - (menu_viewport.col + menu_viewport.outer_width)) - possible_scrollbar_space
      if right_space > min_width then
        restricted_size = FloatingWindow.compute_restricted_size({
          border_size = border_size,
          content_size = content_size,
          max_outer_width = math.min(right_space, max_width),
          max_outer_height = max_height,
        })
      elseif left_space > min_width then
        restricted_size = FloatingWindow.compute_restricted_size({
          border_size = border_size,
          content_size = content_size,
          max_outer_width = math.min(left_space, max_width),
          max_outer_height = max_height,
        })
      else
        self._docs_window:hide()
        return
      end
    end

    local row = menu_viewport.row
    local col = menu_viewport.col + menu_viewport.outer_width
    if row + restricted_size.outer_height > vim.o.lines then
      row = vim.o.lines - restricted_size.outer_height
    end
    if col + restricted_size.outer_width > vim.o.columns then
      col = menu_viewport.col - restricted_size.outer_width
    end

    self._docs_window:show({
      row = row, --[[@as integer]]
      col = col,
      width = restricted_size.inner_width,
      height = restricted_size.inner_height,
      border = docs_border,
      style = 'minimal',
    })
  end))
end

return DefaultView
