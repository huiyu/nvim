return {
	{
		"williamboman/mason.nvim",
		dependencies = {
			"neovim/nvim-lspconfig",
		},
		opts = {},
		config = function(_, opts)
			require("mason").setup(opts)
		end,
	},
	{
		"williamboman/mason-lspconfig.nvim",
		dependencies = {
			"mason.nvim",
		},
		opts = function()
			local lsp_util = require("util.lsp-util")
			return {
				ensure_installed = lsp_util.server_names(),
			}
		end,
		config = function(_, opts)
			local lspconfig = require("lspconfig")
			local mason_lspconfig = require("mason-lspconfig")
			local lsp_util = require("util.lsp-util")
			mason_lspconfig.setup_handlers({
				function(server_name)
					local server_opts = lsp_util.get_server_opts(server_name)
					lspconfig[server_name].setup(server_opts)
				end,
			})
			mason_lspconfig.setup(opts)
		end,
	},
}
