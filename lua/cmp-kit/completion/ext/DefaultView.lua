local kit = require('cmp-kit.kit')
local LSP = require('cmp-kit.kit.LSP')
local Async = require('cmp-kit.kit.Async')
local FloatingWindow = require('cmp-kit.kit.Vim.FloatingWindow')
local Markdown = require('cmp-kit.core.Markdown')
local TriggerContext = require('cmp-kit.core.TriggerContext')

---NOET: in cmdline, the floating-windows and incsearch-highlight are not redraw automatically.
---The `<Cmd>redraw<CR>` part supports floating-windows.
---The `<C-r>=""<CR>` part supports incsearch-highlight.
local cmdline_redraw_keys = vim.keycode('<Cmd>redraw<CR><Space><BS>')

local tmp_tbls = {
  columns = {},
  parts = {},
  formatting_args = {},
  rendering_lines = {},
}

---Create winhighlight.
---@param map table<string, string>
---@return string
local function winhighlight(map)
  return vim.iter(pairs(map)):map(function(k, v)
    return ('%s:%s'):format(k, v)
  end):join(',')
end
local winhl_bordered = winhighlight({
  NormalFloat = 'Normal',
  Normal = 'Normal',
  FloatBorder = 'Normal',
  CursorLine = 'Visual',
  Search = 'None',
})
local winhl_pum = winhighlight({
  NormalFloat = 'Pmenu',
  Normal = 'Pmenu',
  FloatBorder = 'Pmenu',
  CursorLine = 'PmenuSel',
  Search = 'None',
})

local ensure_color_code_highlight_group
do
  local cache = {}

  ---Ensure color code highlight group.
  ---@param color_code string
  ---@return string
  ensure_color_code_highlight_group = function(color_code)
    color_code = color_code:gsub('^#', ''):sub(1, 6)
    if #color_code == 3 then
      color_code = color_code:sub(1, 1):rep(2) .. color_code:sub(2, 2):rep(2) .. color_code:sub(3, 3):rep(2)
    end
    if not cache[color_code] then
      local name = ('cmp-kit.completion.ext.DefaultView.%s'):format(color_code):gsub('[#_-%.:]', '_')
      vim.api.nvim_set_hl(0, name, {
        fg = '#' .. color_code,
        bg = 'NONE',
        default = true,
      })
      cache[color_code] = name
    end
    return cache[color_code]
  end
end

---Ensure coloring extmarks.
---@param item cmp-kit.completion.CompletionItem
---@return string?
local function get_coloring(item)
  local cache_key = 'cmp-kit.completion.ext.DefaultView.coloring'
  if not item.cache[cache_key] then
    if item:get_kind() == LSP.CompletionItemKind.Color then
      local details = item:get_label_details()
      local match = nil

      -- detail.
      if not match and details.detail then
        match = details.detail:match('#([a-fA-F0-9]+)')
        if match and (#match == 3 or #match == 6) then
          item.cache[cache_key] = ensure_color_code_highlight_group(match)
        end
      end

      -- docs.
      local docs = item:get_documentation()
      if not match and docs then
        match = docs.value:match('#([a-fA-F0-9]+)')
        if match and (#match == 3 or #match == 6) then
          item.cache[cache_key] = ensure_color_code_highlight_group(match)
        end
      end

      -- label.
      if not match then
        match = item:get_label_text():match('#([a-fA-F0-9]+)')
        if match and (#match == 3 or #match == 6) then
          item.cache[cache_key] = ensure_color_code_highlight_group(match)
        end
      end
    end
  end
  return item.cache[cache_key]
end

---@class cmp-kit.completion.ext.DefaultView.WindowPosition
---@field public row integer
---@field public col integer
---@field public anchor 'NW' | 'NE' | 'SW' | 'SE'

---@class cmp-kit.completion.ext.DefaultView.Extmark
---@field public col integer
---@field public end_col integer
---@field public hl_group? string
---@field public priority? integer
---@field public conceal? string

---@class cmp-kit.completion.ext.DefaultView.MenuComponent
---@field padding_left integer
---@field padding_right integer
---@field align 'left' | 'right'
---@field get_text fun(match: cmp-kit.completion.Match, config: cmp-kit.completion.ext.DefaultView.Config): string
---@field get_extmarks fun(text: string, match: cmp-kit.completion.Match, config: cmp-kit.completion.ext.DefaultView.Config): cmp-kit.completion.ext.DefaultView.Extmark[]

---@class cmp-kit.completion.ext.DefaultView.Config
---@field menu_components cmp-kit.completion.ext.DefaultView.MenuComponent[]
---@field menu_padding_left integer
---@field menu_padding_right integer
---@field menu_gap integer
---@field menu_min_win_height integer
---@field menu_max_win_height integer
---@field docs_min_win_width_ratio number
---@field docs_max_win_width_ratio number
---@field get_menu_position fun(preset: { offset: cmp-kit.completion.ext.DefaultView.WindowPosition, cursor: cmp-kit.completion.ext.DefaultView.WindowPosition }): cmp-kit.completion.ext.DefaultView.WindowPosition
---@field icon_resolver fun(kind: cmp-kit.kit.LSP.CompletionItemKind): { [1]: string, [2]?: string }?

---Lookup table for CompletionItemKind.
local CompletionItemKindLookup = {}
for k, v in pairs(LSP.CompletionItemKind) do
  CompletionItemKindLookup[v] = k
end

---Redraw for cmdline.
---@param win integer?
local function redraw_for_cmdline(win)
  if vim.fn.mode(1):sub(1, 1) == 'c' then
    if vim.tbl_contains({ '/', '?' }, vim.fn.getcmdtype()) and vim.o.incsearch then
      vim.api.nvim_feedkeys(cmdline_redraw_keys, 'n', true)
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
      cache = kit.clear(cache)
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

---@type cmp-kit.completion.ext.DefaultView.Config
local default_config = {
  menu_components = {
    -- kind icon.
    {
      padding_left = 0,
      padding_right = 0,
      align = 'right',
      get_text = function(match, config)
        return config.icon_resolver(match.item:get_kind() or LSP.CompletionItemKind.Text)[1]
      end,
      get_extmarks = function(_, match, config)
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
    -- label.
    {
      padding_left = 0,
      padding_right = 0,
      align = 'left',
      get_text = function(match)
        return strcharpart(match.item:get_label_text(), 0, 48)
      end,
      get_extmarks = function(text, match)
        local extmarks = {}
        for _, position in ipairs(match.match_positions) do
          table.insert(extmarks, {
            col = position.start_index - 1,
            end_col = position.end_index,
            hl_group = position.hl_group or 'PmenuMatch',
          })
        end
        if match.item:get_tags()[LSP.CompletionItemTag.Deprecated] then
          table.insert(extmarks, {
            col = 0,
            end_col = #text,
            hl_group = 'CmpKitDeprecated',
          })
        end
        return extmarks
      end
    },
    -- description.
    {
      padding_left = 0,
      padding_right = 0,
      align = 'right',
      get_text = function(match)
        local details = match.item:get_label_details()
        if details.description then
          return strcharpart(match.item:get_label_details().description, 0, 32)
        end

        -- coloring.
        local coloring = get_coloring(match.item)
        if coloring then
          return '●'
        end

        return ''
      end,
      get_extmarks = function(text, match)
        local details = match.item:get_label_details()
        if details.description then
          return { {
            col = 0,
            end_col = #text,
            hl_group = 'Comment',
          } }
        end

        -- coloring.
        local coloring = get_coloring(match.item)
        if coloring then
          return { {
            col = 0,
            end_col = #text,
            hl_group = coloring,
          } }
        end

        return {}
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

---@class cmp-kit.completion.ext.DefaultView: cmp-kit.completion.CompletionView
---@field private _ns integer
---@field private _config cmp-kit.completion.ext.DefaultView.Config
---@field private _service cmp-kit.completion.CompletionService
---@field private _menu_window cmp-kit.kit.Vim.FloatingWindow
---@field private _docs_window cmp-kit.kit.Vim.FloatingWindow
---@field private _matches cmp-kit.completion.Match[]
---@field private _columns { display_width: integer, byte_width: integer, padding_left: integer, padding_right: integer, align: 'left' | 'right', texts: string[], component: cmp-kit.completion.ext.DefaultView.MenuComponent }[]
---@field private _selected_item? cmp-kit.completion.CompletionItem
---@field private _resolving cmp-kit.kit.Async.AsyncTask
local DefaultView = {}
DefaultView.__index = DefaultView

---Create DefaultView
---@param config? cmp-kit.completion.ext.DefaultView.Config|{}
---@return cmp-kit.completion.ext.DefaultView
function DefaultView.new(config)
  config = kit.merge(config or {}, default_config) --[[@as cmp-kit.completion.ext.DefaultView.Config]]
  local self = setmetatable({
    _ns = vim.api.nvim_create_namespace(('cmp-kit.completion.ext.DefaultView.%s'):format(vim.uv.now())),
    _config = config,
    _menu_window = FloatingWindow.new(),
    _docs_window = FloatingWindow.new(),
    _matches = {},
    _columns = vim.iter(config.menu_components):map(function(component)
      return {
        display_width = 0,
        byte_width = 0,
        padding_left = component.padding_left,
        padding_right = component.padding_right,
        align = component.align,
        texts = {},
        component = component,
      }
    end):totable(),
    _selected_item = nil,
    _resolving = Async.resolve(),
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
function DefaultView:is_menu_visible()
  return self._menu_window:is_visible()
end

---Return true if window is visible.
---@return boolean
function DefaultView:is_docs_visible()
  return self._docs_window:is_visible()
end

---Show completion menu.
---@param matches cmp-kit.completion.Match[]
---@param selection cmp-kit.completion.Selection
function DefaultView:show(matches, selection)
  -- hide window if no matches.
  self._matches = matches
  if #self._matches == 0 then
    self:hide()
    return
  end

  -- reset columns.
  for _, column in ipairs(self._columns) do
    column.display_width = 0
    column.byte_width = 0
    column.texts = kit.clear(column.texts)
  end
  local columns = kit.clear(tmp_tbls.columns)
  for i, column in ipairs(self._columns) do
    columns[i] = column
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
          for _, extmark in ipairs(column.component.get_extmarks(text, self._matches[row + 1], self._config)) do
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
  local parts = kit.clear(tmp_tbls.parts)
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
  local rendering_lines = kit.clear(tmp_tbls.rendering_lines)
  for i in ipairs(self._matches) do
    local formatting_args = kit.clear(tmp_tbls.formatting_args)
    for _, column in ipairs(columns) do
      local text = column.texts[i]
      if column.align == 'right' then
        table.insert(formatting_args, (' '):rep(column.display_width - get_strwidth(text)))
        table.insert(formatting_args, text)
      else
        table.insert(formatting_args, text)
        table.insert(formatting_args, (' '):rep(column.display_width - get_strwidth(text)))
      end
    end
    local line = formatting:format(unpack(formatting_args))
    table.insert(rendering_lines, line)
    max_content_width = math.max(max_content_width, get_strwidth(line))
  end
  vim.api.nvim_buf_set_lines(self._menu_window:get_buf(), 0, -1, false, rendering_lines)

  local border_size = FloatingWindow.get_border_size(vim.o.winborder)
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

  if (vim.o.winborder ~= '' and vim.o.winborder ~= 'none') then
    self._menu_window:set_win_option('winhighlight', winhl_bordered)
  else
    self._menu_window:set_win_option('winhighlight', winhl_pum)
  end
  self._menu_window:set_win_option('winblend', vim.o.pumblend)
  self._menu_window:set_win_option('cursorline', selection.index ~= 0)
  self._menu_window:show({
    row = row + row_off,
    col = col + col_off,
    width = max_content_width,
    height = outer_height - border_size.v,
    anchor = anchor,
    style = 'minimal',
    border = vim.o.winborder,
  })

  redraw_for_cmdline(self._menu_window:get_win())
end

---Hide window.
function DefaultView:hide()
  get_strwidth.clear_cache()
  self._menu_window:hide()
  self._docs_window:hide()
end

---Apply selection.
---@param matches cmp-kit.completion.Match[]
---@param selection cmp-kit.completion.Selection
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
end

---Update documentation.
---@param item? cmp-kit.completion.CompletionItem
function DefaultView:_update_docs(item)
  self._selected_item = item

  self._resolving = self._resolving:next(function()
    return Async.run(function()
      if not item then
        self._docs_window:hide()
        return
      end

      if item ~= self._selected_item then
        return
      end
      if not self._menu_window:is_visible() then
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
      local docs_border = (vim.o.winborder ~= '' and vim.o.winborder ~= 'none') and vim.o.winborder or
          border_padding_side
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

      if (vim.o.winborder ~= '' and vim.o.winborder ~= 'none') then
        self._docs_window:set_win_option('winhighlight', winhl_bordered)
      else
        self._docs_window:set_win_option('winhighlight', winhl_pum)
      end
      self._docs_window:set_win_option('winblend', vim.o.pumblend)

      self._docs_window:show({
        row = row, --[[@as integer]]
        col = col,
        width = restricted_size.inner_width,
        height = restricted_size.inner_height,
        border = docs_border,
        style = 'minimal',
      })
      vim.api.nvim_win_set_cursor(self._docs_window:get_win() --[[@as integer]], { 1, 0 })
    end):next(function()
      redraw_for_cmdline(self._docs_window:get_win())
    end)
  end)
end

---Scroll documentation if possible.
---@param delta integer
function DefaultView:scroll_docs(delta)
  if not self._docs_window:is_visible() then
    return
  end
  self._docs_window:scroll(delta)
end

return DefaultView
