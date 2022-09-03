local status, _ = pcall(require, "lspconfig")
if not status then
	return
end

require("modules.lsp.cmp")
require("modules.lsp.installer")
require("modules.lsp.ui")
require("modules.lsp.null-ls")
