local status_ok, _ = pcall(require, "lspconfig")
if not status_ok then
  return
end

require("lsp.cmp")
require("lsp.installer")
require("lsp.ui")
require("lsp.null-ls")
