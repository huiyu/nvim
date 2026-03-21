--- Keybindings
--- see https://neovim.io/doc/user/intro.html#vim-modes-intro
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- Normal mode
vim.keymap.set("n", "j", "v:count == 0 ? 'gj' : 'j'", { expr = true, desc = "Move cursor down" })
vim.keymap.set("n", "k", "v:count == 0 ? 'gk' : 'k'", { expr = true, desc = "Move cursor up" })

-- Insert mode mapping
vim.keymap.set("i", "jk", "<ESC>", { desc = "Exit insert mode", noremap = true, silent = true })
vim.keymap.set("i", "<C-c>", "<ESC>", { desc = "Exit insert mode", noremap = true, silent = true })

-- Terminal mode: escape to normal mode (enables <leader> in terminal buffers)
vim.keymap.set("t", "<Esc><Esc>", "<C-\\><C-n>", { desc = "Exit terminal mode", noremap = true, silent = true })
vim.keymap.set("t", "jk", "<C-\\><C-n>", { desc = "Exit terminal mode", noremap = true, silent = true })
-- Pass Shift+Enter to terminal apps (e.g. Claude Code uses it for newline)
-- Neovim's terminal cannot distinguish Shift+Enter from Enter by default.
-- iTerm2 setup required: Settings → Profiles → Keys → Key Mappings →
--   Shortcut: Shift+Return, Action: Send Escape Sequence, Value: [13;2u
vim.keymap.set("t", "<S-CR>", function()
  vim.fn.chansend(vim.b.terminal_job_id, "\x1b[13;2u")
end, { noremap = true, silent = true })

-- Visual & Select mode mappings
vim.keymap.set("v", "<", "<gv", { desc = "Indent left", noremap = true, silent = true })
vim.keymap.set("v", ">", ">gv", { desc = "Indent right", noremap = true, silent = true })
vim.keymap.set({ "v", "x" }, "<A-j>", ":m .+1<CR>==", { desc = "Move text down", noremap = true, silent = true })
vim.keymap.set({ "v", "x" }, "<A-k>", ":m .-2<CR>==", { desc = "Move text up", noremap = true, silent = true })
vim.keymap.set("v", "p", '"_dP', { desc = "Paste without yanking", noremap = true, silent = true })

return {
  -- Which-key group labels
  { "<leader>s",  group = "Search",       mode = { "n", "v" } },
  { "<leader>c",  group = "Code",         mode = { "n", "v" } },
  { "<leader>d",  group = "Debug",        mode = { "n", "v" } },
  { "<leader>g",  group = "Git",          mode = { "n", "v" } },
  { "<leader>t",  group = "Test" },
  { "<leader>h",  group = "Help",         mode = { "n", "v" } },
  { "<leader>x",  group = "Diagnostics",  mode = "n" },
  { "<leader>a",  group = "AI/Claude Code" },
  { "<leader>q",  group = "Quit/Session", mode = "n" },
  { "<leader>w",  group = "Window",       mode = "n" },

  -- Help (no plugin dependency)
  { "<leader>hn", "<cmd>nohlsearch<cr>",  desc = "No highlight" },

  -- Quit/Session (no plugin dependency)
  { "<leader>qu", "<cmd>Lazy update<cr>", desc = "Update plugins",  mode = "n" },
  { "<leader>qw", "<cmd>w<cr>",           desc = "Save",            mode = "n" },
  { "<leader>qW", "<cmd>wall<cr>",        desc = "Save all",        mode = "n" },
  { "<leader>qq", "<cmd>qall<cr>",        desc = "Quit",            mode = "n" },
  { "<leader>qQ", "<cmd>qa!<cr>",         desc = "Force quit all",  mode = "n" },

  -- Window management (native vim)
  { "<leader>w+", "<C-w>+",                      desc = "Increase height",          mode = "n" },
  { "<leader>w-", "<C-w>-",                      desc = "Decrease height",           mode = "n" },
  { "<leader>w=", "<C-w>=",                      desc = "Equalize windows",          mode = "n" },
  { "<leader>w<", "<C-w><",                      desc = "Decrease width",            mode = "n" },
  { "<leader>w>", "<C-w>>",                      desc = "Increase width",            mode = "n" },
  { "<leader>w|", "<C-w>|",                      desc = "Max out the width",         mode = "n" },
  { "<leader>wv", "<cmd>vsplit<cr>",             desc = "Split window vertically",   mode = "n" },
  { "<leader>ws", "<cmd>split<cr>",              desc = "Split window horizontally", mode = "n" },
  { "<leader>wc", "<cmd>WindowCloseCurrent<cr>", desc = "Close current window",      mode = "n" },
  { "<leader>wo", "<cmd>WindowCloseOthers<cr>",  desc = "Close other windows",       mode = "n" },
  { "<leader>wh", "<C-w>h",                      desc = "Go to left window",         mode = "n" },
  { "<leader>wj", "<C-w>j",                      desc = "Go to lower window",        mode = "n" },
  { "<leader>wk", "<C-w>k",                      desc = "Go to upper window",        mode = "n" },
  { "<leader>wl", "<C-w>l",                      desc = "Go to right window",        mode = "n" },
  { "<leader>ww", "<C-w>w",                      desc = "Switch window",             mode = "n" },

  -- Window navigation (Ctrl+hjkl)
  { "<C-h>", "<C-w>h", desc = "Go to left window",  mode = { "n", "t" } },
  { "<C-j>", "<C-w>j", desc = "Go to lower window", mode = { "n", "t" } },
  { "<C-k>", "<C-w>k", desc = "Go to upper window", mode = { "n", "t" } },
  { "<C-l>", "<C-w>l", desc = "Go to right window", mode = { "n", "t" } },

  -- Buffer/diagnostic navigation (built-in)
  { "[b", "<cmd>bprev<cr>",                              desc = "Previous buffer",  mode = "n" },
  { "]b", "<cmd>bnext<cr>",                              desc = "Next buffer",      mode = "n" },
  { "[d", function() vim.diagnostic.goto_prev() end,     desc = "Prev diagnostic",  mode = "n" },
  { "]d", function() vim.diagnostic.goto_next() end,     desc = "Next diagnostic",  mode = "n" },
}
