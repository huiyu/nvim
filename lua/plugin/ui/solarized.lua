return {
	"craftzdog/solarized-osaka.nvim",
	lazy = false,
	priority = 1000,
	opts = {
		transparent = true,
	},
	config = function(_, opts)
		require("solarized-osaka").setup(opts)
		vim.cmd([[colorscheme solarized-osaka]])
	end,
}
