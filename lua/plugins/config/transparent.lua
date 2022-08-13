local transparent = require("transparent")

transparent.setup({
	enable = true,
	extra_groups = {
		"BufferLineTabClose",
		"BufferlineBufferSelected",
		"BufferLineFill",
		"BufferLineBackground",
		"BufferLineSeparator",
		"BufferLineIndicatorSelected",
	},
})

vim.api.nvim_command("highlight NormalFloat guibg=none")
