local Character = require('cmp-kit.kit.App.Character')

local Hack = {}

Hack.clangd = {}

---The clangd does not respect VSCode implementation.
---In VSCode, the `vscode-clangd` fixes it, in `clangd` itself does not support VSCode compatible editors.
---@param item cmp-kit.completion.CompletionItem
---@param trigger_context cmp-kit.core.TriggerContext
---@param filter_text string
---@return string
function Hack.clangd.get_filter_text(
    item,
    trigger_context,
    provider,
    filter_text
)
  if item:has_text_edit() then
    local offset = item:get_offset() -- NOTE: get_filter_text and get_offset reference each other, but calling get_offset here does NOT cause an infinite loop.
    if Character.is_symbol(trigger_context.text:byte(offset)) then
      local keyword_offset = provider:get_keyword_offset() or trigger_context.character + 1
      local delta = keyword_offset - offset
      if delta > 0 then
        local prefix = trigger_context:substr(offset, keyword_offset - 1)
        if not vim.startswith(filter_text, prefix) then
          filter_text = prefix .. filter_text
        end
      end
    end
  end
  return filter_text
end

return Hack
