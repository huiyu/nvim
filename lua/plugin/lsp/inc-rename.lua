-- LSP rename with a live preview: every occurrence updates in the buffer while
-- the new name is still being typed on the cmdline, and <Esc> leaves the code
-- untouched. Same interaction model as `inccommand = "split"` in
-- lua/options.lua, applied to rename instead of :substitute.
--
-- Reached through `,r` on an LSP buffer (lua/plugin/lsp/lsp.lua). It is an
-- `expr` map that leaves `:IncRename <cword>` on the cmdline for editing
-- rather than running it.
--
-- Nvim's own `grn` is left alone and keeps plain `vim.lsp.buf.rename()`, so
-- the live preview is what `,r` adds over the default rather than a
-- replacement for it.
return {
  "smjonas/inc-rename.nvim",
  cmd = "IncRename",
  opts = {},
}
