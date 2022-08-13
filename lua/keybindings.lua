local opts = { noremap = true, silent = true }
local term_opts = { silent = true }

local map = vim.api.nvim_set_keymap

map("", "<space>", "<Nop>", opts)
map("n", "+", "<C-a>", opts)
map("n", "-", "<C-x>", opts)

vim.g.mapleader = " "
vim.g.maplocalleder = " "

local whichkey = require("which-key")

----------------------------------
-- Which Key Configuration
----------------------------------
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

local term_keymap = "<cmd>lua require('actions').toggle_terminal()<cr>"
map("", "<M-t>", term_keymap, opts)
map("t", "<M-t>", term_keymap, opts)
map("i", "<M-t>", term_keymap, opts)

local actions = require("actions")
local mapping = {
	["b"] = { actions.find_buffers, "Buffers" },
	["B"] = { actions.find_all_buffers, "All Buffers" },
	["t"] = { actions.toggle_explorer, "Explorer" },
	["T"] = { actions.toggle_todos, "Todos" },
	["w"] = { "<cmd>w!<CR>", "Save" },
	["W"] = { "<cmd>wa!<CR>", "Save All" },
	["q"] = { "<cmd>q!<CR>", "Quit" },
	["Q"] = { "<cmd>wqall!<CR>", "Save All & Quit" },
	["h"] = { "<cmd>nohlsearch<CR>", "No Highlight" },
	["H"] = { "<cmd>Telescope man_pages<cr>", "Man Pages" },
	["f"] = { actions.find_files, "Find Files" },
	["F"] = { actions.find_text, "Find Text" },
	["/"] = { actions.file_browser, "File Browser" },
	["r"] = { actions.recent_files, "Recent File" },
	["R"] = { actions.all_recent_files, "All Recent File" },
	["p"] = { actions.find_projects, "Projects" },

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
		["c"] = { "<cmd>lua require('actions').close_current_window()<cr>", "Close Curent Window" },
		["q"] = { "<C-w>q", "Quit current window" },
		["o"] = { "<cmd>lua require('actions').close_other_windows()<cr>", "Close Other Windows" },
		["h"] = { "<C-w>h", "Go to the left window" },
		["j"] = { "<C-w>j", "Go to the down window" },
		["k"] = { "<C-w>k", "Go to the up window" },
		["l"] = { "<C-w>l", "Move Right" },
		["w"] = { "<C-w>w", "Switch windows" },
		["x"] = { "<C-w>x", "Swap current with next" },
	},

	[","] = {
		name = "LSP",
		["a"] = { actions.lsp_code_action, "Code Action" },
		["A"] = { actions.lsp_range_code_action, "Range Code Action" },
		["f"] = { actions.lsp_formatting, "Format" },
		["r"] = { actions.lsp_rename, "Rename" },
		["g"] = { actions.lsp_definitions, "Goto Definitions" },
		["G"] = { actions.lsp_type_definitions, "Goto Type Definitions" },
		["i"] = { actions.lsp_implementations, "Goto Implementations" },
		["e"] = { actions.lsp_references, "Goto References" },
		["s"] = { actions.lsp_document_symbols, "Document Symbols" },
		["S"] = { actions.lsp_workspace_symbols, "Workspace Symbols" },
		["d"] = { actions.lsp_diagnostics, "Workspace Diagnostics" },
		["k"] = { "<cmd>lua vim.diagnostic.goto_prev()<cr>", "Prev Diagnostic" },
		["j"] = { "<cmd>lua vim.diagnostic.goto_next()<cr>", "Next Diagnostic" },
		["q"] = { "<cmd>lua vim.diagnostic.setloclist()<cr>", "Quickfix" },

		-- Hover
		["h"] = { "<cmd>Lspsaga hover_doc<cr>", "Help" },
	},
}

whichkey.register(mapping, { prefix = "<leader>", mode = "n" })
whichkey.register(mapping["s"], { prefix = "s", mode = "n" })
whichkey.register(mapping[","], { prefix = ",", mode = "n" })

----------------------------------
-- NORMAL MODE KEYMAP
----------------------------------

----------------------------------
-- INSERT MODE KEYMAP
----------------------------------
map("i", "jk", "<ESC>", opts)

----------------------------------
-- VISUAL MODE KEYMAP
----------------------------------

-- Stay in indent mode
map("v", "<", "<gv", opts)
map("v", ">", ">gv", opts)

-- Move text up and down
map("v", "<A-j>", ":m .+1<CR>==", opts)
map("v", "<A-k>", ":m .-2<CR>==", opts)
map("v", "p", '"_dP', opts)

----------------------------------
-- VISUAL BLOCK MODE KEYMAP
----------------------------------

-- Move text up and down
map("x", "J", ":move '>+1<CR>gv-gv", opts)
map("x", "K", ":move '<-2<CR>gv-gv", opts)
map("x", "<A-j>", ":move '>+1<CR>gv-gv", opts)
map("x", "<A-k>", ":move '<-2<CR>gv-gv", opts)

----------------------------------
-- TERMINAL MODE KEYMAP
----------------------------------

-- Better terminal navigation
map("t", "<C-h>", "<C-\\><C-N><C-w>h", term_opts)
map("t", "<C-j>", "<C-\\><C-N><C-w>j", term_opts)
map("t", "<C-k>", "<C-\\><C-N><C-w>k", term_opts)
map("t", "<C-l>", "<C-\\><C-N><C-w>l", term_opts)

map("c", "<C-j>", "<C-n>", {})
map("c", "<C-k>", "<C-p>", {})
