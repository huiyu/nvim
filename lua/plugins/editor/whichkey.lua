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

local cwd = require("utils.cwd")
local win = require("utils.window")
local git = require("utils.git")
local lsp = require("utils.lsp")

local mapping = {
	["b"] = { cwd.find_buffers, "Buffers" },
	["e"] = { "<cmd>Telescope file_browser path=%:p:h<cr>", "Explore Current Directory" },
	["E"] = { "<cmd>Telescope file_browser<cr>", "Explore Working Directory" },
	["t"] = { "<cmd>NvimTreeToggle<cr>", "File Tree" },
	["T"] = { "<cmd>TodoTelescope<cr>", "Todos" },
	["w"] = { "<cmd>w!<cr>", "Save" },
	["W"] = { "<cmd>wa!<cr>", "Save All" },
	["q"] = { "<cmd>q!<cr>", "Quit" },
	["Q"] = { "<cmd>wqall!<cr>", "Save All & Quit" },
	["h"] = { "<cmd>nohlsearch<cr>", "No Highlight" },
	["H"] = { "<cmd>Telescope man_pages<cr>", "Man Pages" },
	["f"] = { cwd.find_files, "Find Files" },
	["F"] = { cwd.find_text, "Find Text" },
	["r"] = { cwd.recent_files, "Recent File" },

	["g"] = {
		name = "Git",
		["j"] = { git.next_hunk, "Next Hunk" },
		["k"] = { git.prev_hunk, "Prev Hunk" },
		["l"] = { git.blame_line, "Blame" },
		["p"] = { git.preview_hunk, "Preview Hunk" },
		["r"] = { git.reset_hunk, "Reset Hunk" },
		["R"] = { git.reset_buffer, "Reset Buffer" },
		["s"] = { git.stage_hunk, "Stage Hunk" },
		["u"] = { git.undo_stage_hunk, "Undo Stage Hunk" },
		["o"] = { git.status, "Open Changed Files" },
		["b"] = { git.branches, "Checkout Branch" },
		["c"] = { git.commits, "Checkout Commit" },
		["C"] = { git.buffer_commits, "Checkout Buffer Commit" },
		["d"] = { git.diffthis, "Diff" },
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
		["c"] = { win.close_current, "Close Curent Window" },
		["q"] = { "<C-w>q", "Quit current window" },
		["o"] = { win.close_others, "Close Other Windows" },
		["h"] = { "<C-w>h", "Go to the left window" },
		["j"] = { "<C-w>j", "Go to the down window" },
		["k"] = { "<C-w>k", "Go to the up window" },
		["l"] = { "<C-w>l", "Move Right" },
		["w"] = { "<C-w>w", "Switch windows" },
		["x"] = { "<C-w>x", "Swap current with next" },
	},

	[","] = {
		name = "LSP",
		["a"] = { lsp.code_action, "Code Action" },
		["f"] = { lsp.formatting, "Format" },
		["r"] = { lsp.rename, "Rename" },
		["g"] = { lsp.definitions, "Goto Definitions" },
		["G"] = { lsp.references, "Goto References" },
		["t"] = { lsp.type_definitions, "Goto Type Definitions" },
		["i"] = { lsp.implementations, "Goto Implementations" },
		["s"] = { lsp.document_symbols, "Document Symbols" },
		["S"] = { lsp.workspace_symbols, "Workspace Symbols" },
		["d"] = { lsp.diagnostics, "Workspace Diagnostics" },
		["k"] = { lsp.prev_diagnostics, "Prev Diagnostic" },
		["j"] = { lsp.next_disgnostics, "Next Diagnostic" },
		["q"] = { lsp.quickfix, "Quickfix" },

		-- Hover
		["h"] = { lsp.show_doc, "Help" },
	},
}

whichkey.register(mapping, { prefix = "<leader>", mode = "n" })
whichkey.register(mapping["s"], { prefix = "s", mode = "n" })
whichkey.register(mapping[","], { prefix = ",", mode = "n" })
