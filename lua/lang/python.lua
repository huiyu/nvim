return {
	{
		"nvim-treesitter/nvim-treesitter",
		opts = function(_, opts)
			vim.list_extend(opts.ensure_installed, { "python" })
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
				require("lspconfig").pylsp.setup({})
			end
			return opts
		end,
	},
	{
		"jay-babu/mason-nvim-dap.nvim",
		opts = function(_, opts)
			opts = opts or {}
			opts.ensure_installed = opts.ensure_installed or {}
			vim.list_extend(opts.ensure_installed, { "python" })
			return opts
		end,
	},
	{
		"mfussenegger/nvim-dap-python",
		config = function()
			local path = require("mason-registry").get_package("debugpy"):get_install_path()
			require("dap-python").setup(path .. "/venv/bin/python")
		end,
	},
}
