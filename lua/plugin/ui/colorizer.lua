-- Using catgoose fork because the original norcalli/nvim-colorizer.lua is
-- unmaintained and still calls the deprecated vim.tbl_flatten (Neovim 0.10+).
-- Tracked in repo issue; switch back if upstream resumes maintenance.
return {
	"catgoose/nvim-colorizer.lua",
	event = "BufReadPre",
	opts = {
		filetypes = { "*" },
		user_default_options = {
			names = false,
			tailwind = false,
		},
	},
}
