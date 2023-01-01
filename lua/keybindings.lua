local opts = { noremap = true, silent = true }
local term_opts = { silent = true }

local map = vim.api.nvim_set_keymap
map("", "<space>", "<Nop>", opts)
map("n", "+", "<C-a>", opts)
map("n", "-", "<C-x>", opts)
map("n", "<C-c", "<ESC>", opts)

vim.g.mapleader = " "
vim.g.maplocalleder = " "

local term_keymap = "<cmd>ToggleTerm<cr>"
map("", "<C-t>", term_keymap, opts)
map("t", "<C-t>", term_keymap, opts)
map("i", "<C-t>", term_keymap, opts)

----------------------------------
-- NORMAL MODE KEYMAP
----------------------------------

----------------------------------
-- INSERT MODE KEYMAP
----------------------------------
map("i", "jk", "<ESC>", opts)
map("i", "<C-c>", "<ESC>", opts)
map("", "<M-CR>", "<cmd>Lspsaga code_action<CR>", opts)

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

local win = require("utils.window")
local M = {}
local wk = {
	["<leader>"] = {
		["b"] = { "<cmd>Telescope buffers cwd_only=true hidden=true path_display={'truncate'}<cr>", "Buffers" },
		["e"] = { "<cmd>Telescope file_browser path=%:p:h<cr>", "Explore current directory" },
		["E"] = { "<cmd>Telescope file_browser<cr>", "Explore working directory" },
		["t"] = { "<cmd>NvimTreeToggle<cr>", "File tree" },
		["T"] = { "<cmd>TodoTelescope<cr>", "Todos" },
		["w"] = { "<cmd>w!<cr>", "Save" },
		["W"] = { "<cmd>wa!<cr>", "Save all" },
		["q"] = { "<cmd>q!<cr>", "Quit" },
		["Q"] = { "<cmd>wqall!<cr>", "Save all & quit" },
		["h"] = { "<cmd>nohlsearch<cr>", "No highlight" },
		["H"] = { "<cmd>Telescope man_pages<cr>", "Man pages" },
		["f"] = { "<cmd>Telescope find_files cwd_only=true path_display={'truncate'}<cr>", "Find files" },
		["F"] = { "<cmd>Telescope live_grep cwd_only=true path_display={'truncate'}<cr>", "Find text" },
		["r"] = { "<cmd>Telescope oldfiles cwd_only=true hidden=true path_display={'truncate'}<cr>", "Recent files" },

		["g"] = {
			name = "Git",
			["g"] = { "<cmd>Gitsign<cr>", "Git actions" },
			["j"] = { "<cmd>Gitsign next_hunk<cr>", "Next hunk" },
			["k"] = { "<cmd>Gitsign prev_hunk<cr>", "Prev hunk" },
			["l"] = { "<cmd>Gitsign blame_line<cr>", "Blame line" },
			["p"] = { "<cmd>Gitsign preview_hunk<cr>", "Preview hunk" },
			["r"] = { "<cmd>Gitsign reset_hunk<cr>", "Reset hunk" },
			["R"] = { "<cmd>Gitsign reset_buffer<cr>", "Reset buffer" },
			["s"] = { "<cmd>Gitsign stage_hunk<cr>", "Stage hunk" },
			["u"] = { "<cmd>Gitsign undo_stage_hunk<cr>", "Undo stage hunk" },
			["o"] = { "<cmd>Telescope git_status<cr>", "Open changed files" },
			["b"] = { "<cmd>Telescope git_branches<cr>", "Checkout branch" },
			["c"] = { "<cmd>Telescope git_commits<cr>", "Checkout commit" },
			["C"] = { "<cmd>Telescope git_bcommits<cr>", "Checkout buffer commit" },
			["d"] = { "<cmd>Gitsign diffthis<cr>", "Diff" },
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
			["c"] = { win.close_current, "Close curent window" },
			["q"] = { "<C-w>q", "Quit current window" },
			["o"] = { win.close_others, "Close other windows" },
			["h"] = { "<C-w>h", "Go to the left window" },
			["j"] = { "<C-w>j", "Go to the down window" },
			["k"] = { "<C-w>k", "Go to the up window" },
			["l"] = { "<C-w>l", "Move right" },
			["w"] = { "<C-w>w", "Switch windows" },
			["x"] = { "<C-w>x", "Swap current with next" },
		},

		[","] = {
			name = "LSP",
			["a"] = { "<cmd>Lspsaga code_action<cr>", "Code action" },
			["f"] = { "<cmd>lua vim.lsp.buf.format()<cr>", "format" },
			["r"] = { "<cmd>Lspsaga rename<cr>", "Rename" },
			["x"] = { "<cmd>Lspsaga lsp_finder<cr>", "Explore associations" },
			["g"] = { "<cmd>Telescope lsp_definitions<cr>", "Goto definitions" },
			["e"] = { "<cmd>Telescope lsp_references<cr>", "Goto references" },
			["t"] = { "<cmd>Telescope lsp_type_definitions<cr>", "Goto type definitions" },
			["i"] = { "<cmd>Telescope lsp_implementations<cr>", "Goto implementations" },
			["s"] = { "<cmd>Telescope lsp_document_symbols<cr>", "Document symbols" },
			["S"] = { "<cmd>Telescope lsp_workspace_symbols<cr>", "Workspace symbols" },
			["d"] = { "<cmd>Telescope diagnostics<cr>", "Workspace diagnostics" },
			["k"] = { "<cmd>Lspsaga diagnostics_jump_prev<cr>", "Prev diagnostic" },
			["j"] = { "<cmd>Lspsaga diagnostics_jump_next<cr>", "Next diagnostic" },
			["q"] = { "<cmd>lua vim.diagnostic.setloclist()<cr>", "Quickfix" },
			["o"] = { "<cmd>Lspsaga outline<cr>", "Quickfix" },
			["h"] = { "<cmd>Lspsaga hover_doc<cr>", "Help" },
		},
	},
	["]"] = {
		["m"] = { "<cmd>TSTextobjectGotoNextStart @function.outer<cr>", "Goto next method start" },
		["M"] = { "<cmd>TSTextobjectGotoNextEnd @function.outer<cr>", "Goto next method end" },
		["c"] = { "<cmd>TSTextobjectGotoNextStart @class.outer<cr>", "Goto next class start" },
		["C"] = { "<cmd>TSTextobjectGotoNextEnd @class.outer<cr>", "Goto next class end" },
	},
	["["] = {
		["m"] = { "<cmd>TSTextobjectGotoPreviousStart @function.outer<cr>", "Goto privous method start" },
		["M"] = { "<cmd>TSTextobjectGotoPreviousEnd @function.outer<cr>", "Goto privous method end" },
		["c"] = { "<cmd>TSTextobjectGotoPreviousStart @class.outer<cr>", "Goto privous class start" },
		["C"] = { "<cmd>TSTextobjectGotoPreviousEnd @class.outer<cr>", "Goto privous class end" },
	},
}

wk["s"] = wk["<leader>"]["s"]
wk[","] = wk["<leader>"][","]

M.whichkey = wk

return M
