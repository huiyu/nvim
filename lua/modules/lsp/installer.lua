local lspconfig = require("lspconfig")
local protocol = require("vim.lsp.protocol")
local mason = require("mason")
local mason_lspconfig = require("mason-lspconfig")

local servers = { "sumneko_lua", "tailwindcss", "tsserver", "gopls" }

-- get server opts from `lsp.config` folders
local get_server_opts = function(server_name)
	return require("modules.lsp.config." .. server_name)
end

-- after the language server attaches to the current buffer
local on_attach =
	function(client, bufnr)
		-- formatting
		if client.server_capabilities.documentFormattingProvider then
			vim.api.nvim_create_autocmd("BufWritePre", {
				group = vim.api.nvim_create_augroup("Format", { clear = true }),
				buffer = bufnr,
				callback = function()
					vim.lsp.buf.formatting_seq_sync()
				end,
			})
		end
	end,
	
mason.setup({})
mason_lspconfig.setup({
	ensure_installed = servers,
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
		-- default opts
		local opts = {
			on_attach = on_attach,
		}
		local custom_opts = get_server_opts(server_name)

		-- extend default options
		if custom_opts ~= nil then
			opts = vim.tbl_deep_extend("force", custom_opts, opts)
		end

		lspconfig[server_name].setup(opts)
	end,
})
