local ai = require("ai.config")

-- The gutter's diagnostic glyphs (vim.diagnostic.config in lua/config/options.lua),
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
				-- What a CodeDiff tabpage compares (`main → working tree`): the
				-- panes' own names are a codediff:// URI on one side and the
				-- file on the other, and neither says which revision it is.
				-- util.codediff sets the variable while the view is open.
				{
					function() return "󰓡 " .. vim.t.codediff_label end,
					cond = function() return type(vim.t.codediff_label) == "string" end,
					color = "DiagnosticInfo",
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
						-- wrapped). Collapse them to the label of the agent the
						-- terminal runs.
						local info = vim.b.snacks_terminal
						local agent = info and ai.agent_of_command(info.cmd)
						if agent then
							return " " .. ai.agents[agent].label
						end
						return " " .. (vim.b.term_title or "terminal")
					end,
				},
			},
			lualine_x = {
				-- 'showcmd' (lua/config/options.lua puts it here, 'showcmdloc'): a
				-- pending count, operator or register (`2d`, `"a`) and the
				-- Visual selection size (`3x12`). Nvim fills %S on every redraw.
				"%S",
				-- The API key profile, only while one is pinned (:AI key <name>,
				-- NVIM_AI_KEY_PROFILE): `auto` is the first provider whose key is
				-- set, so it needs no reminder. A click reopens the key picker.
				{
					function()
						return ("󰌆 %s"):format(ai.key.label)
					end,
					cond = function() return not ai.key.auto end,
					on_click = function() vim.cmd("AI key") end,
				},
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
		vim.api.nvim_create_autocmd("User", {
			group = vim.api.nvim_create_augroup("lualine_ai_state", { clear = true }),
			pattern = "AIStateChanged",
			callback = function() lualine.refresh({ place = { "statusline" } }) end,
			desc = "Show or update the pinned API key profile in the statusline",
		})
	end,
}
