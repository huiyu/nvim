local whichkey = require("which-key")

whichkey.setup({
	-- the presets plugin, adds help for a bunch of default keybindings in Neovim
	-- No actual key bindings are created
	presets = {
		operators = true, -- adds help for operators like d, y, ... and registers them for motion / text object completion
		motions = true, -- adds help for motions
		text_objects = true, -- help for text objects triggered after entering an operator
		windows = true, -- default bindings on <c-w>
		nav = true, -- misc bindings to work with windows
		z = true, -- bindings for folds, spelling and others prefixed with z
		g = true, -- bindings for prefixed with g
	},
	window = {
		border = "single", -- none, single, double, shadow
		position = "bottom", -- bottom, top
		margin = { 1, 0, 1, 0 }, -- extra window margin [top, right, bottom, left]
		padding = { 2, 2, 2, 2 }, -- extra window padding [top, right, bottom, left]
		winblend = 0,
	},
	layout = {
		height = { min = 4, max = 25 }, -- min and max height of the columns
		width = { min = 20, max = 50 }, -- min and max width of the columns
		spacing = 3, -- spacing between columns
		align = "left", -- align columns left, center or right
	},
})

local cwd_actions = require("actions.cwd")
local win_actions = require("actions.window")
local lsp_actions = require("actions.lsp")

local mapping = {
	["b"] = { cwd_actions.find_buffers, "Buffers" },
	["t"] = { "<cmd>NvimTreeToggle<CR>", "Explorer" },
	["T"] = { "<cmd>TodoTelescope theme=ivy", "Todos" },
	["w"] = { "<cmd>w!<CR>", "Save" },
	["W"] = { "<cmd>wa!<CR>", "Save All" },
	["q"] = { "<cmd>q!<CR>", "Quit" },
	["Q"] = { "<cmd>wqall!<CR>", "Save All & Quit" },
	["h"] = { "<cmd>nohlsearch<CR>", "No Highlight" },
	["H"] = { "<cmd>Telescope man_pages<cr>", "Man Pages" },
	["f"] = { cwd_actions.find_files, "Find Files" },
	["F"] = { cwd_actions.find_text, "Find Text" },
	["r"] = { cwd_actions.recent_files, "Recent File" },

	["g"] = {
		name = "Git",
		["j"] = { "<cmd>lua require 'gitsigns'.next_hunk()<cr>", "Next Hunk" },
		["k"] = { "<cmd>lua require 'gitsigns'.prev_hunk()<cr>", "Prev Hunk" },
		["l"] = { "<cmd>lua require 'gitsigns'.blame_line()<cr>", "Blame" },
		["p"] = { "<cmd>lua require 'gitsigns'.preview_hunk()<cr>", "Preview Hunk" },
		["r"] = { "<cmd>lua require 'gitsigns'.reset_hunk()<cr>", "Reset Hunk" },
		["R"] = { "<cmd>lua require 'gitsigns'.reset_buffer()<cr>", "Reset Buffer" },
		["s"] = { "<cmd>lua require 'gitsigns'.stage_hunk()<cr>", "Stage Hunk" },
		["u"] = { "<cmd>lua require 'gitsigns'.undo_stage_hunk()<cr>", "Undo Stage Hunk" },
		["o"] = { "<cmd>lua require('actions').git_status()<cr>", "Open Changed Files" },
		["b"] = { "<cmd>lua require('actions').git_branches()<cr>", "Checkout Branch" },
		["c"] = { "<cmd>lua require('actions').git_commits()<cr>", "Checkout commit" },
		["d"] = { "<cmd>Gitsigns diffthis HEAD<cr>", "Diff" },
	},

	["s"] = {
		name = "Window",
		["+"] = { "<C-w>+", "Increase height" },
		["-"] = { "<C-w>-", "Descrease height" },
		["="] = { "<C-w>=", "Equally high and wide" },
		["<"] = { "<C-w>,", "Descrease width" },
		[">"] = { "<C-w>.", "Increase width" },
		["|"] = { "<C-w>|", "Max out the width" },
		["v"] = { "<cmd>vsplit<cr>", "Split window vertically " },
		["s"] = { "<cmd>split<cr>", "Split window horizontally" },
		["c"] = { win_actions.close_current, "Close Curent Window" },
		["q"] = { "<C-w>q", "Quit current window" },
		["o"] = { win_actions.close_others, "Close Other Windows" },
		["h"] = { "<C-w>h", "Go to the left window" },
		["j"] = { "<C-w>j", "Go to the down window" },
		["k"] = { "<C-w>k", "Go to the up window" },
		["l"] = { "<C-w>l", "Move Right" },
		["w"] = { "<C-w>w", "Switch windows" },
		["x"] = { "<C-w>x", "Swap current with next" },
	},

	[","] = {
		name = "LSP",
		["a"] = { lsp_actions.code_action, "Code Action" },
		["f"] = { lsp_actions.formatting, "Format" },
		["r"] = { lsp_actions.rename, "Rename" },
		["g"] = { lsp_actions.definitions, "Goto Definitions" },
		["G"] = { lsp_actions.references, "Goto References" },
		["t"] = { lsp_actions.type_definitions, "Goto Type Definitions" },
		["i"] = { lsp_actions.implementations, "Goto Implementations" },
		["s"] = { lsp_actions.document_symbols, "Document Symbols" },
		["S"] = { lsp_actions.workspace_symbols, "Workspace Symbols" },
		["d"] = { lsp_actions.diagnostics, "Workspace Diagnostics" },
		["k"] = { lsp_actions.prev_diagnostics, "Prev Diagnostic" },
		["j"] = { lsp_actions.next_disgnostics, "Next Diagnostic" },
		["q"] = { lsp_actions.quickfix, "Quickfix" },

		-- Hover
		["h"] = { lsp_actions.show_doc, "Help" },
	},
}

whichkey.register(mapping, { prefix = "<leader>", mode = "n" })
whichkey.register(mapping["s"], { prefix = "s", mode = "n" })
whichkey.register(mapping[","], { prefix = ",", mode = "n" })
