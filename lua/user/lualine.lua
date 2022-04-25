local status_ok, lualine = pcall(require, "lualine")
if not status_ok then
	vim.notify("lualine not found!")
	return
end

lualine.setup({
	options = {
		theme = "sonokai",
		component_separators = { left = "|", right = "|" },
		section_separators = { left = " ", right = "" },
	},

	extensions = { "nvim-tree", "toggleterm" },

	sections = {
		lualine_c = {
			"filename",
			{
				"lsp_progress",
				spinner_symbols = { " ", " ", " ", " ", " ", " " },
			},
		},
		lualine_x = {
			"filesize",
			{
				"fileformat",
				symbols = {
					unix = "LF",
					dos = "CRLF",
					mac = "CR",
				},
			},

			"encoding",
			"filetype",
		},
	},
})
