local status, _ = pcall(require, "lspconfig")
if not status then
	return
end

require("lsp.cmp")
require("lsp.installer")
require("lsp.ui")
require("lsp.null-ls")
