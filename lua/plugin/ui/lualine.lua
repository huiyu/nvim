local ai = require("ai.config")

return {
	"nvim-lualine/lualine.nvim",
	opts = {
		options = {
			icons_enabled = true,
			-- "auto" resolves to lualine.themes.<colors_name>, which
			-- solarized-osaka ships. lualine's built-in "solarized_dark" is the
			-- classic palette instead, so its section backgrounds and foregrounds
			-- (#002b36 / #073642) sit a shade off this colorscheme's own
			-- (#001419 / #002c38) and the statusline never quite matches the
			-- editor behind it.
			theme = "auto",
			section_separators = { left = "", right = "" },
			component_separators = { left = "", right = "" },
			disabled_filetypes = {},
		},
		sections = {
			lualine_a = { "mode" },
			lualine_b = { "branch" },
			lualine_c = {
				{
					"filename",
					file_status = true, -- displays file status (readonly status, modified status)
					path = 0, -- 0 = just filename, 1 = relative path, 2 = absolute path
					fmt = function(name)
						if vim.bo.buftype ~= "terminal" then
							return name
						end
						-- Agent terminal commands can be very long (Claude is tmux-
						-- wrapped). Collapse the selected provider to a clean label.
						local info = vim.b.snacks_terminal
						if info and ai.is_native_command(info.cmd) then
							return " " .. ai.label
						end
						return " " .. (vim.b.term_title or "terminal")
					end,
				},
			},
			lualine_x = {
				{
					"diagnostics",
					sources = { "nvim_diagnostic" },
					symbols = { error = " ", warn = " ", info = " ", hint = " " },
				},
				"encoding",
				"filetype",
			},
			lualine_y = { "progress" },
			lualine_z = { "location" },
		},
		inactive_sections = {
			lualine_a = {},
			lualine_b = {},
			lualine_c = {
				{
					"filename",
					file_status = true, -- displays file status (readonly status, modified status)
					path = 1, -- 0 = just filename, 1 = relative path, 2 = absolute path
				},
			},
			lualine_x = { "location" },
			lualine_y = {},
			lualine_z = {},
		},
		tabline = {},
		extensions = {},
	},
}
