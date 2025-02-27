---@alias cmp-kit.core.MatchPosition { start_index: integer, end_index: integer, hl_group?: string }

---@class cmp-kit.core.Match
---@field provider cmp-kit.core.CompletionProvider
---@field item cmp-kit.core.CompletionItem
---@field score integer
---@field index integer
---@field match_positions cmp-kit.core.MatchPosition[]

---@alias cmp-kit.core.Matcher fun(query: string, input: string): integer, cmp-kit.core.MatchPosition[]

---@alias cmp-kit.core.Sorter fun(matches: cmp-kit.core.Match[], context: cmp-kit.core.SorterContext): cmp-kit.core.Match[]
---@class cmp-kit.core.SorterContext
---@field public locality_map table<string, integer>
---@field public trigger_context cmp-kit.core.TriggerContext

---@class cmp-kit.core.CompletionSource.Configuration
---@field public keyword_pattern? string
---@field public trigger_characters? string[]
---@field public position_encoding_kind? cmp-kit.kit.LSP.PositionEncodingKind

---@class cmp-kit.core.CompletionSource
---@field public name string
---@field public get_configuration? fun(self: unknown): cmp-kit.core.CompletionSource.Configuration
---@field public resolve? fun(self: unknown, item: cmp-kit.kit.LSP.CompletionItem): cmp-kit.kit.Async.AsyncTask
---@field public execute? fun(self: unknown, command: cmp-kit.kit.LSP.Command): cmp-kit.kit.Async.AsyncTask
---@field public capable? fun(self: unknown, trigger_context: cmp-kit.core.TriggerContext): boolean
---@field public complete fun(self: unknown, completion_context: cmp-kit.kit.LSP.CompletionContext): cmp-kit.kit.Async.AsyncTask

---@class cmp-kit.core.Selection
---@field public index integer
---@field public preselect boolean
---@field public text_before string

---@class cmp-kit.core.View
---@field public show fun(self: cmp-kit.core.View, matches: cmp-kit.core.Match[], selection: cmp-kit.core.Selection)
---@field public hide fun(self: cmp-kit.core.View, matches: cmp-kit.core.Match[], selection: cmp-kit.core.Selection)
---@field public is_visible fun(): boolean
---@field public select fun(self: cmp-kit.core.View, matches: cmp-kit.core.Match[], selection: cmp-kit.core.Selection)
---@field public dispose fun(self: cmp-kit.core.View)

vim.api.nvim_set_hl(0, 'CmpKitMarkdownAnnotate01', {
  default = true,
  italic = true,
  underline = true,
  undercurl = true,
})
