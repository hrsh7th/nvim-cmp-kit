# nvim-cmp-kit

nvim's completion core module.

## Custom Extension

`nvim-cmp-kit` implements some custom extensions that are not defined in LSP.

- `LSP.CompletionItem.nvim_previewText` (string)
    - This value will be inserted as a preview text when the completion item is selected.

## Highlighting

- markdown related highlights
    - CmpKitMarkdownAnnotateUnderlined
    - CmpKitMarkdownAnnotateBold
    - CmpKitMarkdownAnnotateEm
    - CmpKitMarkdownAnnotateStrong
    - CmpKitMarkdownAnnotateCode
    - CmpKitMarkdownAnnotateCodeBlock
    - CmpKitMarkdownAnnotateHeading{1,2,3,4,5,6}

- completion related highlights
    - CmpKitDeprecated

- default completion menu highlights
    - CmpKitCompletionItemLabel
    - CmpKitCompletionItemDescription
    - CmpKitCompletionItemMatch
    - CmpKitCompletionItemExtra

## TODO

- [ ] Rename repository

