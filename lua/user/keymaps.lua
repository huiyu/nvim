local opts = { noremap = true, silent = true }
local term_opts = { silent = true }

local map = vim.api.nvim_set_keymap

map("", "<space>", "<Nop>", opts)
vim.g.mapleader = " "
vim.g.maplocalleder = " "

----------------------------------
-- NORMAL MODE KEYMAP
----------------------------------
-- window navigation
map("n", "<A-h>", "<C-w>h", opts)
map("n", "<A-j>", "<C-w>j", opts)
map("n", "<A-k>", "<C-w>k", opts)
map("n", "<A-l>", "<C-w>l", opts)

-- window split
map("n", "sv", ":vsp<CR>", opts)
map("n", "sh", ":sp<CR>", opts)
map("n", "sc", "<C-w>c", opts)
map("n", "so", "<C-w>o", opts)

-- lsp
map("n", ",a", "<cmd>Lspsaga code_action<cr>", opts)
map("n", ",A", "<cmd>Lspsaga range_code_action<cr>", opts)
map("n", ",r", "<cmd>Lspsaga rename<cr>", opts)
map("n", ",g", "<cmd>Telescope lsp_definitions<cr>", opts)
map("n", ",G", "<cmd>Telescope lsp_type_definitions<cr>", opts)

map("n", ",e", "<cmd>Telescope lsp_references<cr>", opts)
map("n", ",i", "<cmd>Telescope lsp_implementations<cr>", opts)
map("n", ",s", "<cmd>Telescope lsp_document_symbols<cr>", opts)
map("n", ",S", "<cmd>Telescope lsp_dynamic_workspace_symbols<cr>", opts)
map("n", ",d", "<cmd>Telescope diagnostics<cr>", opts)

map("n", ",k", "<cmd>Lspsaga diagnostic_jump_prev<cr>", opts)
map("n", ",j", "<cmd>Lspsaga diagnostic_jump_next<cr>", opts)
map("n", ",q", "<cmd>Telescope quickfix<cr>", opts)
map("n", ",h", "<cmd>Lspsaga hover_doc<cr>", opts)

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
