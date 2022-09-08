local opts = { noremap = true, silent = true }
local term_opts = { silent = true }

local map = vim.api.nvim_set_keymap

map("", "<space>", "<Nop>", opts)
map("n", "+", "<C-a>", opts)
map("n", "-", "<C-x>", opts)

vim.g.mapleader = " "
vim.g.maplocalleder = " "

local term_keymap = "<cmd>lua require('actions').toggle_terminal()<cr>"
map("", "<M-t>", term_keymap, opts)
map("t", "<M-t>", term_keymap, opts)
map("i", "<M-t>", term_keymap, opts)

----------------------------------
-- NORMAL MODE KEYMAP
----------------------------------

----------------------------------
-- INSERT MODE KEYMAP
----------------------------------
map("i", "jk", "<ESC>", opts)
map("", "<M-CR>", "<cmd>lua require('actions.lsp').code_action()<CR>", opts)

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
