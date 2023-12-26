return {
	"nvim-telescope/telescope.nvim",
	dependencies = {
		{ "nvim-lua/plenary.nvim" },
		{ "nvim-telescope/telescope-file-browser.nvim" },
		{ "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
		{ "nvim-telescope/telescope-ui-select.nvim" },
	},

	opts = function()
		local telescope = require("telescope")
		local actions = require("telescope.actions")
		local fb_actions = require("telescope._extensions.file_browser.actions")

		telescope.load_extension("fzf")
		telescope.load_extension("file_browser")
		telescope.load_extension("ui-select")

		return {
			defaults = {
				prompt_prefix = " ",
				selection_caret = " ",
				path_display = { "smart" },

				file_ignore_patterns = {
					"./node_modules/*",
					"node_modules",
					"^node_modules/*",
					"node_modules/*",
					"./.git/*",
				},

				mappings = {
					i = {
						["<C-n>"] = actions.cycle_history_next,
						["<C-p>"] = actions.cycle_history_prev,
						["<C-j>"] = actions.move_selection_next,
						["<C-k>"] = actions.move_selection_previous,
						["<C-c>"] = actions.close,
						["<Down>"] = actions.move_selection_next,
						["<Up>"] = actions.move_selection_previous,
						["<CR>"] = actions.select_default,
						["<C-s>"] = actions.select_horizontal,
						["<C-v>"] = actions.select_vertical,
						["<C-t>"] = actions.select_tab,
						["<C-u>"] = actions.preview_scrolling_up,
						["<C-d>"] = actions.preview_scrolling_down,
						["<PageUp>"] = actions.results_scrolling_up,
						["<PageDown>"] = actions.results_scrolling_down,
						["<C-q>"] = actions.send_to_qflist + actions.open_qflist,
						["<M-q>"] = actions.send_selected_to_qflist + actions.open_qflist,
						["<C-l>"] = actions.complete_tag,
						["<C-_>"] = actions.which_key, -- keys from pressing <C-/>
					},

					n = {
						["<esc>"] = actions.close,
						["<C-c>"] = actions.close,
						["<CR>"] = actions.select_default,
						["<C-s>"] = actions.select_horizontal,
						["<C-v>"] = actions.select_vertical,
						["<C-t>"] = actions.select_tab,
						["<C-q>"] = actions.send_to_qflist + actions.open_qflist,
						["<M-q>"] = actions.send_selected_to_qflist + actions.open_qflist,

						["j"] = actions.move_selection_next,
						["k"] = actions.move_selection_previous,
						["H"] = actions.move_to_top,
						["M"] = actions.move_to_middle,
						["L"] = actions.move_to_bottom,

						["<Down>"] = actions.move_selection_next,
						["<Up>"] = actions.move_selection_previous,
						["gg"] = actions.move_to_top,
						["G"] = actions.move_to_bottom,
						["<C-u>"] = actions.preview_scrolling_up,
						["<C-d>"] = actions.preview_scrolling_down,
						["<PageUp>"] = actions.results_scrolling_up,
						["<PageDown>"] = actions.results_scrolling_down,
						["?"] = actions.which_key,
					},
				},
			},
			pickers = {
				-- Default configuration for builtin pickers goes here:
				-- picker_name = {
				--   picker_config_key = value,
				--   ...
				-- }
				-- Now the picker_config_key will be applied every time you call this
				-- builtin picker
				live_grep = {
					additional_args = function(_)
						return { "--hidden" }
					end,
				},
			},
			extensions = {
				-- Your extension configuration goes here:
				-- extension_name = {
				--   extension_config_key = value,
				-- }
				-- please take a look at the readme of the extension you want to configure
				fzf = {
					fuzzy = true, -- false will only do exact matching
					override_generic_sorter = true, -- override the generic sorter
					override_file_sorter = true, -- override the file sorter
					case_mode = "smart_case", -- or "ignore_case" or "respect_case"
				},
				file_browser = {
					hijack_netrw = false,
					mappings = {
						["i"] = {
							-- Custom insert mode key mappings
						},
						["n"] = {
							-- Custom normal mode key mappings
							["a"] = fb_actions.create,
							["r"] = fb_actions.rename,
							["m"] = fb_actions.move,
							["y"] = fb_actions.copy,
							["d"] = fb_actions.remove,
							["u"] = fb_actions.goto_parent_dir,
							["U"] = fb_actions.goto_cwd,
							["/"] = function()
								vim.cmd("startinsert")
							end,
						},
					},
				},
				["ui-select"] = {
					require("telescope.themes").get_dropdown({
						-- even more opts
					}),
				},
			},
		}
	end,
}
