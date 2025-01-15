local kit = require('cmp-kit.kit')
local LSP = require('cmp-kit.kit.LSP')
local Async = require('cmp-kit.kit.Async')
local Client = require('cmp-kit.kit.LSP.Client')
local Position = require('cmp-kit.kit.LSP.Position')

---@class cmp-kit.ext.source.lsp_signature_help.Option
---@field public client vim.lsp.Client
---@param option cmp-kit.ext.source.lsp_signature_help.Option
return function(option)
  local client = Client.new(assert(option.client, '`option.client` is required.'))

  ---Extract triggerCharacters.
  ---@return string[]
  local function get_trigger_characters()
    local chars = {}
    if option.client.server_capabilities.signatureHelpProvider then
      for _, char in ipairs(option.client.server_capabilities.signatureHelpProvider.triggerCharacters or {}) do
        table.insert(chars, char)
      end
    end
    return chars
  end

  ---Extract retriggerCharacteres.
  ---@return string[]
  local function get_retrigger_characters()
    local chars = {}
    if option.client.server_capabilities.signatureHelpProvider then
      for _, char in ipairs(option.client.server_capabilities.signatureHelpProvider.retriggerCharacters or {}) do
        table.insert(chars, char)
      end
    end
    return chars
  end

  ---Get parameter label.
  ---@param signature_label string
  ---@param parameter_label string|{ [1]: integer, [2]: integer }
  ---@return string
  local function get_parameter_label(signature_label, parameter_label)
    if type(parameter_label) == 'table' then
      return signature_label:sub(parameter_label[1] + 1, parameter_label[2])
    end
    return parameter_label
  end

  ---Create MarkupContent from signature and parameter.
  ---@param signature cmp-kit.kit.LSP.SignatureInformation
  ---@param parameter cmp-kit.kit.LSP.ParameterInformation
  local function create_documentation(signature, parameter)
    local contents = { ('```%s'):format(vim.bo.filetype), signature.label, '```' }

    if signature.documentation then
      if type(signature.documentation) == 'string' then
        table.insert(contents, signature.documentation)
      else
        table.insert(contents, signature.documentation.value)
      end
    end

    if parameter.documentation then
      table.insert(contents, '# ' .. get_parameter_label(signature.label, parameter.label))
      if type(parameter.documentation) == 'string' then
        table.insert(contents, parameter.documentation)
      else
        table.insert(contents, parameter.documentation.value)
      end
    end

    return {
      kind = LSP.MarkupKind.Markdown,
      value = table.concat(contents, '\n')
    }
  end

  ---Create LSP.CompletionItem from LSP.SignatureInformation
  ---@param signature cmp-kit.kit.LSP.SignatureInformation
  ---@param preselect boolean
  ---@return cmp-kit.kit.LSP.CompletionItem?
  local function create_completion_item(signature, preselect)
    local parameter = signature.parameters and signature.parameters[(math.max(0, signature.activeParameter or -1)) + 1] or
        {}
    if not parameter then
      return
    end

    ---@type cmp-kit.kit.LSP.CompletionItem
    return {
      label = get_parameter_label(signature.label, parameter.label) or '',
      labelDetails = {
        description = signature.label,
      },
      insertText = '',
      documentation = create_documentation(signature, parameter),
      preselect = preselect
    }
  end

  ---@type cmp-kit.core.CompletionSource
  return {
    name = ('%s.signature_help'):format(option.client.name),
    get_configuration = function()
      local trigger_characters = kit.concat(get_trigger_characters(), get_retrigger_characters())
      local keyword_pattern = ([[\%%(%s\)\zs\s*]]):format(vim.iter(trigger_characters):map(function(c)
        return '\\V' .. c .. '\\m'
      end):join(''))
      ---@type cmp-kit.core.CompletionSource.Configuration
      return {
        completion_options = {
          triggerCharacters = kit.concat(get_trigger_characters(), get_retrigger_characters()),
          resolveProvider = true,
        },
        keyword_pattern = keyword_pattern,
      }
    end,
    capable = function()
      return not not option.client.server_capabilities.signatureHelpProvider
    end,
    complete = function(_, completion_context)
      local cursor_position = Position.cursor(option.client.offset_encoding or LSP.PositionEncodingKind.UTF16)
      return Async.run(function()
        if not completion_context.triggerCharacter then
          return {}
        end

        ---@type cmp-kit.kit.LSP.TextDocumentSignatureHelpResponse
        local response = client:textDocument_signatureHelp({
          position = cursor_position,
          textDocument = { uri = vim.uri_from_bufnr(0) },
          context = {
            triggerKind = LSP.SignatureHelpTriggerKind.TriggerCharacter,
            triggerCharacter = completion_context.triggerCharacter,
            isRetrigger = vim.tbl_contains(get_retrigger_characters(), completion_context.triggerCharacter or ''),
          }
        }):await()

        if not response then
          return {}
        end

        -- move to top if activeSignature is exists.
        local active_signature --[[@as cmp-kit.kit.LSP.SignatureInformation]]
        if response.activeSignature then
          local active_signature_index = response.activeSignature
          if 0 <= active_signature_index and active_signature_index < #response.signatures then
            table.insert(response.signatures, 1, table.remove(response.signatures, active_signature_index + 1))
            active_signature = response.signatures[1]
          end
        end

        local items = {}
        for _, signature in ipairs(response.signatures) do
          local item = create_completion_item(signature, signature == active_signature)
          if item then
            table.insert(items, item)
          end
        end
        return items
      end)
    end
  }
end
