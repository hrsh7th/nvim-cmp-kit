local cmp_kit = {}

---Return completion related capabilities.
---@return table
function cmp_kit.get_completion_capabilities()
  return {
    textDocument = {
      completion = {
        dynamicRegistration = true,
        completionItem = {
          snippetSupport = true,
          commitCharactersSupport = true,
          deprecatedSupport = true,
          preselectSupport = true,
          tagSupport = {
            valueSet = { 1 }
          },
          insertReplaceSupport = true,
          resolveSupport = {
            properties = {
              "documentation",
              "additionalTextEdits",
              "insertTextFormat",
              "insertTextMode",
              "command",
            },
          },
          insertTextModeSupport = {
            valueSet = { 1, 2 }
          },
          labelDetailsSupport = true,
        },
        contextSupport = true,
        insertTextMode = 1,
        completionList = {
          itemDefaults = {
            'commitCharacters',
            'editRange',
            'insertTextFormat',
            'insertTextMode',
            'data',
          }
        }
      },
    },
  }
end

---Return completion related capabilities.
---@return table
function cmp_kit.get_signature_help_capabilities()
  return {
    textDocument = {
      signatureHelp = {
        dynamicRegistration = true,
        signatureInformation = {
          documentationFormat = { 'markdown', 'plaintext' },
          parameterInformation = {
            labelOffsetSupport = true,
          },
          activeParameterSupport = true,
        },
        contextSupport = true,
      }
    },
  }
end

return cmp_kit
