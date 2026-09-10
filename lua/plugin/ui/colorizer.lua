-- Using catgoose fork because the original norcalli/nvim-colorizer.lua is
-- unmaintained and still calls the deprecated vim.tbl_flatten (Neovim 0.10+).
-- Tracked in repo issue; switch back if upstream resumes maintenance.
return {
	"catgoose/nvim-colorizer.lua",
	event = { "BufReadPre", "BufNewFile" },
	opts = {
		filetypes = { "*" },
		options = {
			parsers = {
				names = { enable = false },
				rgb = { enable = true },
				hsl = { enable = true },
				css_var = { enable = true },
				-- Tailwind belongs to the frontend filetypes in lang/frontend.lua.
				tailwind = { enable = false },
			},
		},
	},
}
