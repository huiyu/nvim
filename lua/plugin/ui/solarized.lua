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

		-- Strengthen Visual selection: transparent bg makes the default too faint
		vim.api.nvim_set_hl(0, "Visual", { bg = "#264F78", fg = "NONE" })

		-- The tabline is the one area `transparent` misses: Normal loses its
		-- background but TabLineFill keeps an opaque teal, and the tabline is
		-- permanent here (always_show_bufferline), so an empty one drew a solid
		-- band across the top of the editor. bufferline asks for a transparent
		-- fill already, but an unset background there means "inherit the
		-- tabline's own default", which is this group -- so the request only
		-- lands once this is cleared too.
		vim.api.nvim_set_hl(0, "TabLineFill", { bg = "NONE" })

		-- Match the fold column to the line numbers beside it. The theme gives
		-- FoldColumn the ordinary foreground (#9eabac), so the `-` and `|` fold
		-- markers were the brightest thing in the gutter while the line numbers
		-- they sit next to are deliberately dimmed -- decoration reading louder
		-- than the numbers it decorates. CursorLineFold too, or the cursor row
		-- keeps the one remaining bright marker; CursorLineNr already carries
		-- the accent that marks that row.
		local gutter = vim.api.nvim_get_hl(0, { name = "LineNr", link = false }).fg
		vim.api.nvim_set_hl(0, "FoldColumn", { fg = gutter })
		vim.api.nvim_set_hl(0, "CursorLineFold", { fg = gutter })

		-- Fix built-in terminal colors so tools like Claude Code have distinguishable highlighting
		vim.g.terminal_color_0 = "#073642" -- black (base02, standard Solarized)
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
