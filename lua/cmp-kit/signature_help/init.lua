---@class cmp-kit.signature_help.SignatureHelpSource.Configuration
---@field public trigger_characters? string[]
---@field public retrigger_characters? string[]
---@field public position_encoding_kind? cmp-kit.kit.LSP.PositionEncodingKind

---@class cmp-kit.signature_help.SignatureHelpSource
---@field public name string
---@field public get_configuration? fun(self: unknown): cmp-kit.signature_help.SignatureHelpSource.Configuration
---@field public fetch fun(self: unknown, context: cmp-kit.kit.LSP.SignatureHelpContext, callback: fun(err?: unknown, response?: cmp-kit.kit.LSP.TextDocumentSignatureHelpResponse)): nil
---@field public capable? fun(self: unknown): boolean

---@class cmp-kit.signature_help.SignatureHelpView
---@field public show fun(self: cmp-kit.signature_help.SignatureHelpView, data: cmp-kit.signature_help.ActiveSignatureData)
---@field public hide fun(self: cmp-kit.signature_help.SignatureHelpView)
---@field public is_visible fun(): boolean
---@field public select fun(self: cmp-kit.signature_help.SignatureHelpView)
---@field public scroll fun(self: cmp-kit.signature_help.SignatureHelpView, delta: integer)
---@field public dispose fun(self: cmp-kit.signature_help.SignatureHelpView)

---@class cmp-kit.signature_help.ActiveSignatureData
---@field public signature cmp-kit.kit.LSP.SignatureInformation
---@field public parameter_index integer 1-origin index
---@field public signature_index integer 1-origin index
---@field public signature_count integer
