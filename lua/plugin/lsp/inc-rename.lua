-- LSP rename with a live preview: every occurrence updates in the buffer while
-- the new name is still being typed on the cmdline, and <Esc> leaves the code
-- untouched. Same interaction model as `inccommand = "split"` in
-- lua/options.lua, applied to rename instead of :substitute.
--
-- The keys stay where they were -- `grn` globally and `,r` on an LSP
-- buffer (lua/plugin/lsp/lsp.lua) -- so this changes how rename feels, not
-- where it lives. Both are `expr` maps that leave `:IncRename <cword>` on the
-- cmdline for editing rather than running it.
return {
  "smjonas/inc-rename.nvim",
  cmd = "IncRename",
  opts = {},
}
