return {
	{
		"nvim-treesitter/nvim-treesitter",
		opts = function(_, opts)
			vim.list_extend(opts.ensure_installed, {
				"go",
				"gowork",
				"gomod",
				"gosum",
			})
		end,
	},
	{
		"williamboman/mason-lspconfig.nvim",
		opts = function(_, opts)
			vim.list_extend(opts.ensure_installed, { "gopls" })
			opts.handlers = opts.handlers or {}
			opts.handlers["gopls"] = function()
				require("lspconfig").gopls.setup({
					-- TODO: more configuration
				})
			end
			return opts
		end,
	},
	{
		"stevearc/conform.nvim",
		optional = true,
		opts = {
			formatters_by_ft = {
				go = { "goimports", "gofumpt" },
			},
		},
	},
}
