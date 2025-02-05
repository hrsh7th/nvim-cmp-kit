local kit = require('cmp-kit.kit')
local LSP = require('cmp-kit.kit.LSP')
local Async = require('cmp-kit.kit.Async')
local Markdown = require('cmp-kit.core.Markdown')
local TriggerContext = require('cmp-kit.core.TriggerContext')
local FloatingWindow = require('cmp-kit.kit.Vim.FloatingWindow')

---@class cmp-kit.core.DefaultView.WindowPosition
---@field public row integer
---@field public col integer
---@field public anchor 'NW' | 'NE' | 'SW' | 'SE'

---@class cmp-kit.core.DefaultView.Extmark
---@field public col integer
---@field public end_col integer
---@field public hl_group? string
---@field public priority? integer
---@field public conceal? string

---@class cmp-kit.core.DefaultView.MenuComponent
---@field padding_left integer
---@field padding_right integer
---@field align 'left' | 'right'
---@field get_text fun(match: cmp-kit.core.Match, config: cmp-kit.core.DefaultView.Config): string
---@field get_extmarks fun(match: cmp-kit.core.Match, config: cmp-kit.core.DefaultView.Config): cmp-kit.core.DefaultView.Extmark[]

---@class cmp-kit.core.DefaultView.Config
---@field border string
---@field menu_components cmp-kit.core.DefaultView.MenuComponent[]
---@field menu_padding_left integer
---@field menu_padding_right integer
---@field menu_gap integer
---@field menu_min_win_height integer
---@field menu_max_win_height integer
---@field docs_min_win_width_ratio number
---@field docs_max_win_width_ratio number
---@field get_menu_position fun(preset: { offset: cmp-kit.core.DefaultView.WindowPosition, cursor: cmp-kit.core.DefaultView.WindowPosition }): cmp-kit.core.DefaultView.WindowPosition
---@field icon_resolver fun(kind: cmp-kit.kit.LSP.CompletionItemKind): { [1]: string, [2]?: string }?

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

---Redraw for cmdline.
---@param win integer?
local function redraw_for_cmdline(win)
  if vim.fn.mode(1):sub(1, 1) == 'c' then
    if vim.tbl_contains({ '/', '?' }, vim.fn.getcmdtype()) and vim.o.incsearch then
      vim.api.nvim_feedkeys(vim.keycode('<Cmd>redraw<CR><C-r>=""<CR>'), 'ni', true)
    else
      pcall(vim.api.nvim__redraw, { valid = true, win = win })
    end
  end
end

---Get string char part.
local function strcharpart(str, start, finish)
  return vim.fn.strcharpart(str, start, finish)
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
      get_text = function(match, config)
        return config.icon_resolver(match.item:get_kind() or LSP.CompletionItemKind.Text)[1]
      end,
      get_extmarks = function(match, config)
        local icon, hl_group = unpack(config.icon_resolver(match.item:get_kind() or LSP.CompletionItemKind.Text) or {})
        if icon then
          return { {
            col = 0,
            end_col = #icon,
            hl_group = hl_group,
          } }
        end
        return {}
      end,
    },
    {
      padding_left = 0,
      padding_right = 0,
      align = 'left',
      get_text = function(match)
        return strcharpart(match.item:get_label_text(), 0, 48)
      end,
      get_extmarks = function(match)
        return vim.iter(match.match_positions):map(function(position)
          return {
            col = position.start_index - 1,
            end_col = position.end_index,
            hl_group = position.hl_group or 'CmpItemAbbrMatch',
          }
        end):totable()
      end
    },
    {
      padding_left = 0,
      padding_right = 0,
      align = 'right',
      get_text = function(match)
        if not match.item:get_label_details().description then
          return ''
        end
        return strcharpart(match.item:get_label_details().description, 0, 32)
      end,
      get_extmarks = function(match)
        if not match.item:get_label_details().description then
          return {}
        end
        return { {
          col = 0,
          end_col = #match.item:get_label_details().description,
          hl_group = 'Comment',
        } }
      end
    },
  },
  menu_padding_left = 1,
  menu_padding_right = 1,
  menu_gap = 1,
  menu_min_win_height = 10,
  menu_max_win_height = 18,
  docs_min_win_width_ratio = 0.25,
  docs_max_win_width_ratio = 0.55,
  get_menu_position = function(preset)
    return preset.offset
  end,
  icon_resolver = (function()
    local ok, MiniIcons = pcall(require, 'mini.icons')
    local cache = {}
    return function(completion_item_kind)
      if not ok then
        return { '', '' }
      end
      if not cache[completion_item_kind] then
        local kind = CompletionItemKindLookup[completion_item_kind] or 'text'
        cache[completion_item_kind] = { MiniIcons.get('lsp', kind:lower()) }
      end
      return cache[completion_item_kind]
    end
  end)(),
}

---@class cmp-kit.core.DefaultView: cmp-kit.core.View
---@field private _ns integer
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
    _ns = vim.api.nvim_create_namespace(('cmp-kit.core.DefaultView.%s'):format(vim.uv.now())),
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
  ---@type { display_width: integer, byte_width: integer, padding_left: integer, padding_right: integer, align: 'left' | 'right', texts: string[], component: cmp-kit.core.DefaultView.MenuComponent }[]
  local columns = {}
  for _, component in ipairs(self._config.menu_components) do
    table.insert(columns, {
      display_width = 0,
      byte_width = 0,
      padding_left = component.padding_left,
      padding_right = component.padding_right,
      align = component.align,
      texts = {},
      component = component,
    })
  end

  -- compute columns.
  local min_offset = math.huge
  for i, match in ipairs(self._matches) do
    min_offset = math.min(min_offset, match.item:get_offset())
    for j, component in ipairs(self._config.menu_components) do
      local text = component.get_text(match, self._config)
      columns[j].display_width = math.max(columns[j].display_width, get_strwidth(text))
      columns[j].byte_width = math.max(columns[j].byte_width, #text)
      columns[j].texts[i] = text
    end
  end

  -- remove empty columns.
  for i = #columns, 1, -1 do
    if columns[i].display_width == 0 then
      table.remove(columns, i)
    end
  end

  -- set decoration provider.
  vim.api.nvim_set_decoration_provider(self._ns, {
    on_win = function(_, _, buf, toprow, botrow)
      if buf ~= self._menu_window:get_buf() then
        return
      end

      for row = toprow, botrow do
        local off = self._config.menu_padding_left
        for _, column in ipairs(columns) do
          off = off + column.padding_left

          local text = column.texts[row + 1]
          local space_width = column.display_width - get_strwidth(text)
          local right_align_off = column.align == 'right' and space_width or 0
          for _, extmark in ipairs(column.component.get_extmarks(self._matches[row + 1], self._config)) do
            vim.api.nvim_buf_set_extmark(buf, self._ns, row, off + right_align_off + extmark.col, {
              end_row = row,
              end_col = off + right_align_off + extmark.end_col,
              hl_group = extmark.hl_group,
              priority = extmark.priority,
              conceal = extmark.conceal,
              hl_mode = 'combine',
              ephemeral = true,
            })
          end
          off = off + #text + space_width + column.padding_right + self._config.menu_gap
        end
      end
    end,
  })

  -- create formatting (padding and gap is reoslved here).
  local parts = {}
  table.insert(parts, (' '):rep(self._config.menu_padding_left or 1))
  for i, column in ipairs(columns) do
    table.insert(parts, (' '):rep(column.padding_left or 0))
    table.insert(parts, '%s%s')
    if #columns > 1 and i < #columns then
      table.insert(parts, (' '):rep(self._config.menu_gap or 1))
    end
  end
  table.insert(parts, (' '):rep(self._config.menu_padding_right or 1))
  local formatting = table.concat(parts, '')

  -- draw lines.
  local max_content_width = 0
  local lines = {}
  for i in ipairs(self._matches) do
    local args = {}
    for _, column in ipairs(columns) do
      local text = column.texts[i]
      if column.align == 'right' then
        table.insert(args, (' '):rep(column.display_width - get_strwidth(text)))
        table.insert(args, text)
      else
        table.insert(args, text)
        table.insert(args, (' '):rep(column.display_width - get_strwidth(text)))
      end
    end
    local line = formatting:format(unpack(args))
    table.insert(lines, line)
    max_content_width = math.max(max_content_width, get_strwidth(line))
  end
  vim.api.nvim_buf_set_lines(self._menu_window:get_buf(), 0, -1, false, lines)

  local border_size = FloatingWindow.get_border_size(self._config.border)
  local trigger_context = TriggerContext.create()
  local leading_text = trigger_context.text_before:sub(min_offset)

  local pos --[[@as { row: integer, col: integer }]]
  if vim.api.nvim_get_mode().mode ~= 'c' then
    pos = vim.fn.screenpos(0, trigger_context.line + 1, trigger_context.character + 1)
  else
    pos = {}
    pos.row = vim.o.lines
    pos.col = vim.fn.getcmdscreenpos()
  end
  local row = pos.row - 1 -- default row should be below the cursor. so we use 1-origin as-is.
  local col = pos.col - get_strwidth(leading_text)

  -- setup default position offset.
  local row_off = 1
  local col_off = 0
  local anchor = 'NW'

  -- compute outer_height.
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
    width = max_content_width,
    height = outer_height - border_size.v,
    anchor = anchor,
    style = 'minimal',

    border = self._config.border,
  })
  self._menu_window:set_win_option('cursorline', selection.index ~= 0)

  redraw_for_cmdline(self._menu_window:get_win())
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

---Dispose view.
function DefaultView:dispose()
  self._menu_window:hide()
  self._docs_window:hide()
  vim.api.nvim_buf_clear_namespace(self._menu_window:get_buf(), self._ns, 0, -1)
  vim.api.nvim_buf_clear_namespace(self._docs_window:get_buf(), self._ns, 0, -1)
  vim.api.nvim_buf_delete(self._menu_window:get_buf(), { force = true })
  vim.api.nvim_buf_delete(self._docs_window:get_buf(), { force = true })
end

---Update documentation.
---@param item? cmp-kit.core.CompletionItem
function DefaultView:_update_docs(item)
  self._selected_item = item

  Async.run(function()
    if not item then
      self._docs_window:hide()
      return
    end

    item:resolve():await()

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
    Markdown.set(self._docs_window:get_buf(), self._ns, vim.split(documentation.value, '\n', { plain = true }))

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
  end):next(function()
    redraw_for_cmdline(self._docs_window:get_win())
  end)
end

return DefaultView
