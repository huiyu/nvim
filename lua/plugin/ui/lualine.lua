local ai = require("ai.config")

-- The gutter's diagnostic glyphs (vim.diagnostic.config in lua/options.lua),
-- so a count in the statusline and the sign beside the line look alike.
local diagnostic_symbols = {}
do
	local text, severity = vim.diagnostic.config().signs.text, vim.diagnostic.severity
	for name, level in pairs({ error = "ERROR", warn = "WARN", info = "INFO", hint = "HINT" }) do
		diagnostic_symbols[name] = text[severity[level]] .. " "
	end
end

return {
	"nvim-lualine/lualine.nvim",
	-- The statusline is part of the first frame, dashboard included; loading it
	-- on VeryLazy would flash the builtin one first.
	lazy = false,
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
			lualine_b = {
				"branch",
				{
					"diff",
					-- gitsigns already counts the buffer's changed lines against the
					-- index. Without a source lualine would run its own `git diff`
					-- on every BufEnter and write.
					source = function()
						local status = vim.b.gitsigns_status_dict
						if status then
							return { added = status.added, modified = status.changed, removed = status.removed }
						end
					end,
				},
			},
			lualine_c = {
				{
					function()
						local register = vim.fn.reg_recording()
						return register == "" and "" or "● REC @" .. register
					end,
					color = "DiagnosticError",
				},
				{
					"filename",
					file_status = true, -- displays file status (readonly status, modified status)
					-- 1 = path relative to cwd (`%:~:.`), so a monorepo's
					-- packages/db/src/client.ts is distinguishable from its siblings.
					path = 1,
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
				-- Language servers attached to this buffer, with a spinner while
				-- one reports progress (indexing, loading the workspace). Idle
				-- servers show their name only; the default "done" check mark
				-- would stay on screen for good after the first progress report.
				{ "lsp_status", symbols = { done = "" } },
				{
					"diagnostics",
					sources = { "nvim_diagnostic" },
					symbols = diagnostic_symbols,
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
	config = function(_, opts)
		local lualine = require("lualine")
		lualine.setup(opts)
		vim.api.nvim_create_autocmd({ "RecordingEnter", "RecordingLeave" }, {
			group = vim.api.nvim_create_augroup("lualine_recording", { clear = true }),
			callback = function()
				-- Queue the refresh so RecordingLeave finishes clearing reg_recording().
				lualine.refresh({ place = { "statusline" } })
			end,
			desc = "Refresh the macro recording indicator",
		})
	end,
}
