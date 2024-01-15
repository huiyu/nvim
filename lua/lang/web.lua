return {
	{

		"nvim-treesitter/nvim-treesitter",
		opts = function(_, opts)
			vim.list_extend(opts.ensure_installed, {
				"html",
				"css",
				"javascript",
				"typescript",
				"tsx",
			})
		end,
	},
	{
		"williamboman/mason-lspconfig.nvim",
		opts = function(_, opts)
			local lspconfig = require("lspconfig")
			opts = opts or {}
			opts.ensure_installed = opts.ensure_installed or {}
			vim.list_extend(opts.ensure_installed, {
				"html",
				"cssls",
				"tsserver",
			})
			opts.handlers = opts.handlers or {}
			opts.handlers["cssls"] = function()
				lspconfig.cssls.setup({})
			end
			opts.handlers["html"] = function()
				lspconfig.html.setup({})
			end
			opts.handlers["tsserver"] = function()
				lspconfig.tsserver.setup({})
			end
			return opts
		end,
	},
	{
		"stevearc/conform.nvim",
		optional = true,
		opts = {
			formatters_by_ft = {
				["javascript"] = { "prettier" },
				["javascriptreact"] = { "prettier" },
				["typescript"] = { "prettier" },
				["typescriptreact"] = { "prettier" },
				["vue"] = { "prettier" },
				["css"] = { "prettier" },
				["scss"] = { "prettier" },
				["less"] = { "prettier" },
				["html"] = { "prettier" },
				["json"] = { "prettier" },
				["jsonc"] = { "prettier" },
				["yaml"] = { "prettier" },
				["markdown"] = { "prettier" },
				["markdown.mdx"] = { "prettier" },
				["graphql"] = { "prettier" },
				["handlebars"] = { "prettier" },
			},
		},
	},
}
