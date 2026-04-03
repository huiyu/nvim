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

		-- 修正内置终端颜色，使 Claude Code 等工具的高亮和语法着色可区分
		vim.g.terminal_color_0 = "#073642" -- black (base02, 标准 Solarized)
		vim.g.terminal_color_8 = "#657b83" -- bright black (base00)
		vim.g.terminal_color_9 = "#cb4b16" -- bright red (orange)
		vim.g.terminal_color_10 = "#586e75" -- bright green (base01)
		vim.g.terminal_color_11 = "#657b83" -- bright yellow (base00)
		vim.g.terminal_color_12 = "#839496" -- bright blue (base0)
		vim.g.terminal_color_13 = "#6c71c4" -- bright magenta (violet)
		vim.g.terminal_color_14 = "#93a1a1" -- bright cyan (base1)
		vim.g.terminal_color_15 = "#fdf6e3" -- bright white (base3)
	end,
}
