---@alias cmp-kit.completion.MatchPosition { start_index: integer, end_index: integer, hl_group?: string }

---@class cmp-kit.completion.Match
---@field provider cmp-kit.completion.CompletionProvider
---@field item cmp-kit.completion.CompletionItem
---@field score integer
---@field index integer
---@field match_positions cmp-kit.completion.MatchPosition[]

---@alias cmp-kit.completion.Matcher fun(query: string, input: string): integer, cmp-kit.completion.MatchPosition[]

---@alias cmp-kit.completion.Sorter fun(matches: cmp-kit.completion.Match[], context: cmp-kit.completion.SorterContext): cmp-kit.completion.Match[]

---@class cmp-kit.completion.SorterContext
---@field public locality_map table<string, integer>
---@field public trigger_context cmp-kit.core.TriggerContext

---@class cmp-kit.completion.CompletionSource.Configuration
---@field public keyword_pattern? string
---@field public trigger_characters? string[]
---@field public position_encoding_kind? cmp-kit.kit.LSP.PositionEncodingKind

---@class cmp-kit.completion.CompletionSource
---@field public name string
---@field public get_configuration? fun(self: unknown): cmp-kit.completion.CompletionSource.Configuration
---@field public resolve? fun(self: unknown, item: cmp-kit.kit.LSP.CompletionItem): cmp-kit.kit.Async.AsyncTask
---@field public execute? fun(self: unknown, command: cmp-kit.kit.LSP.Command): cmp-kit.kit.Async.AsyncTask
---@field public capable? fun(self: unknown, trigger_context: cmp-kit.core.TriggerContext): boolean
---@field public complete fun(self: unknown, completion_context: cmp-kit.kit.LSP.CompletionContext): cmp-kit.kit.Async.AsyncTask

---@class cmp-kit.completion.Selection
---@field public index integer
---@field public preselect boolean
---@field public text_before string

---@class cmp-kit.completion.CompletionView
---@field public show fun(self: cmp-kit.completion.CompletionView, matches: cmp-kit.completion.Match[], selection: cmp-kit.completion.Selection)
---@field public hide fun(self: cmp-kit.completion.CompletionView, matches: cmp-kit.completion.Match[], selection: cmp-kit.completion.Selection)
---@field public is_menu_visible fun(): boolean
---@field public is_docs_visible fun(): boolean
---@field public select fun(self: cmp-kit.completion.CompletionView, matches: cmp-kit.completion.Match[], selection: cmp-kit.completion.Selection)
---@field public scroll_docs fun(self: cmp-kit.completion.CompletionView, delta: integer)
---@field public dispose fun(self: cmp-kit.completion.CompletionView)
