-- LSP rename with a live preview: every occurrence updates in the buffer while
-- the new name is still being typed on the cmdline, and <Esc> leaves the code
-- untouched. Same interaction model as `inccommand = "split"` in
-- lua/options.lua, applied to rename instead of :substitute.
--
-- Reached through `,r` on an LSP buffer (lua/plugin/lsp/lsp.lua). It is an
-- `expr` map that leaves `:IncRename <cword>` on the cmdline for editing
-- rather than running it.
--
-- Nvim's own `grn` (plain `vim.lsp.buf.rename()`) is not remapped, but the
-- nowait `gr` (References) shadows it in an LSP buffer, so `,r` is the rename
-- key there.
return {
  "smjonas/inc-rename.nvim",
  cmd = "IncRename",
  opts = {},
}
