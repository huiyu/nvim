local lspconfig = require("lspconfig")
local protocol = require("vim.lsp.protocol")
local mason = require("mason")
local mason_lspconfig = require("mason-lspconfig")

local lang_servers = require("plugins.lsp.lang-servers")

mason.setup({})

mason_lspconfig.setup({
	ensure_installed = lang_servers.server_names(),
})

protocol.CompletionItemKind = {
	"", -- Text
	"", -- Method
	"", -- Function
	"", -- Constructor
	"", -- Field
	"", -- Variable
	"", -- Class
	"ﰮ", -- Interface
	"", -- Module
	"", -- Property
	"", -- Unit
	"", -- Value
	"", -- Enum
	"", -- Keyword
	"﬌", -- Snippet
	"", -- Color
	"", -- File
	"", -- Reference
	"", -- Folder
	"", -- EnumMember
	"", -- Constant
	"", -- Struct
	"", -- Event
	"ﬦ", -- Operator
	"", -- TypeParameter
}

mason_lspconfig.setup_handlers({
	function(server_name)
		local opts = lang_servers.get_server_opts(server_name)
		lspconfig[server_name].setup(opts)
	end,
})
