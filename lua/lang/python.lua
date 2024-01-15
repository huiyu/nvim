return {
	{
		"nvim-treesitter/nvim-treesitter",
		opts = function(_, opts)
			vim.list_extend(opts.ensure_installed, { "python" })
			return opts
		end,
	},
	{
		"williamboman/mason-lspconfig.nvim",
		opts = function(_, opts)
			opts = opts or {}
			opts.ensure_installed = opts.ensure_installed or {}
			vim.list_extend(opts.ensure_installed, { "pylsp" })
			opts.handlers = opts.handlers or {}
			opts.handlers["pylsp"] = function()
				require("lspconfig").pylsp.setup({
          -- TODO: more configuration
        })
			end
			return opts
		end,
	},
}
