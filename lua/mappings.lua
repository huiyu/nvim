--- Keybindings
--- see https://neovim.io/doc/user/intro.html#vim-modes-intro
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- Save file
vim.keymap.set({ "i", "x", "n", "s" }, "<C-s>", "<cmd>w<cr><esc>", { desc = "Save file" })

-- Open URL under cursor or on current line with system default app
vim.keymap.set("n", "gx", function()
  -- First try <cfile> (works when cursor is directly on a URL/path)
  local cfile = vim.fn.expand("<cfile>")
  if cfile:match("^https?://") then
    vim.ui.open(cfile)
    return
  end
  -- Search the current line for a URL (find the nearest one to cursor)
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1 -- 1-indexed
  local best_url, best_dist = nil, math.huge
  for url, s, e in line:gmatch("()(https?://[%w%-%._~:/?#%[%]@!$&'()*+,;%%=]+)()") do
    ---@diagnostic disable-next-line: param-type-mismatch
    local dist = (col < url) and (url - col) or (col > e - 1) and (col - e + 1) or 0
    if dist < best_dist then
      best_url, best_dist = s, dist
    end
  end
  if best_url then
    vim.ui.open(best_url)
  else
    -- Fallback: open current file with system app
    local file = vim.fn.expand("%:p")
    if file ~= "" then
      vim.ui.open(file)
    end
  end
end, { desc = "Open URL or file with system app" })

-- Run the current file (dispatched by filetype; runners registered in lang/*.lua)
vim.keymap.set("n", "<leader>cx", function() require("util.run").run_current() end, { desc = "Run current file" })

-- Clear search highlight on Escape
-- Normal mode only: mapping bare <Esc> in insert mode can add latency to / mis-fire
-- on terminal escape sequences (arrows, Alt, F-keys), and there's no hlsearch to clear there.
vim.keymap.set("n", "<Esc>", "<cmd>nohlsearch<cr><Esc>", { desc = "Escape and clear hlsearch" })

-- Better up/down on wrapped lines
vim.keymap.set({ "n", "x" }, "j", "v:count == 0 ? 'gj' : 'j'", { expr = true, desc = "Down" })
vim.keymap.set({ "n", "x" }, "k", "v:count == 0 ? 'gk' : 'k'", { expr = true, desc = "Up" })

-- Move lines
vim.keymap.set("n", "<A-j>", "<cmd>execute 'move .+' . v:count1<cr>==", { desc = "Move down" })
vim.keymap.set("n", "<A-k>", "<cmd>execute 'move .-' . (v:count1 + 1)<cr>==", { desc = "Move up" })
vim.keymap.set("i", "<A-j>", "<esc><cmd>m .+1<cr>==gi", { desc = "Move down" })
vim.keymap.set("i", "<A-k>", "<esc><cmd>m .-2<cr>==gi", { desc = "Move up" })
vim.keymap.set("v", "<A-j>", ":m '>+1<cr>gv=gv", { desc = "Move down", silent = true })
vim.keymap.set("v", "<A-k>", ":m '<-2<cr>gv=gv", { desc = "Move up", silent = true })

-- Insert mode
vim.keymap.set("i", "jk", "<ESC>", { desc = "Exit insert mode", noremap = true, silent = true })
vim.keymap.set("i", "<C-c>", "<ESC>", { desc = "Exit insert mode", noremap = true, silent = true })

-- Terminal mode
vim.keymap.set("t", "<Esc><Esc>", "<C-\\><C-n>", { desc = "Exit terminal mode", noremap = true, silent = true })
vim.keymap.set("t", "jk", "<C-\\><C-n>", { desc = "Exit terminal mode", noremap = true, silent = true })
vim.keymap.set("t", "<C-q>", function()
  vim.cmd("bdelete!")
end, { desc = "Close terminal", noremap = true, silent = true })
vim.keymap.set("n", "<leader>Tx", "<cmd>bdelete!<cr>", { desc = "Close terminal" })
-- Drift fix: shrink/restore terminal windows in one tick to force libvterm to
-- truncate its grid (the only resize op that actually invalidates stale cells).
vim.keymap.set("n", "<leader>Td", function()
  require("util.terminal").fix_drift()
end, { desc = "Fix terminal TUI drift" })
vim.keymap.set("t", "<S-CR>", function()
  vim.fn.chansend(vim.b.terminal_job_id, "\x1b[13;2u")
end, { noremap = true, silent = true })

-- Visual & Select mode
vim.keymap.set("v", "<", "<gv", { desc = "Indent left", noremap = true, silent = true })
vim.keymap.set("v", ">", ">gv", { desc = "Indent right", noremap = true, silent = true })
vim.keymap.set("v", "<leader>y", "y", { desc = "Yank to register" })
vim.keymap.set("v", "<leader>Y", '"+y', { desc = "Yank to clipboard" })
-- Note: visual paste handled by yanky.nvim (provides yank history cycling)

-- Window navigation (Ctrl+hjkl) — skip terminal windows so navigation stays
-- within editor splits. Use <C-/> to jump to the terminal explicitly.
local function nav_skip_terminal(direction)
  return function()
    local start = vim.api.nvim_get_current_win()
    vim.cmd("wincmd " .. direction)
    local cur = vim.api.nvim_get_current_win()
    -- If we landed on a terminal, keep stepping; bail out if we loop back.
    while cur ~= start and vim.bo[vim.api.nvim_win_get_buf(cur)].buftype == "terminal" do
      vim.cmd("wincmd " .. direction)
      local next_win = vim.api.nvim_get_current_win()
      if next_win == cur then break end
      cur = next_win
    end
  end
end

vim.keymap.set("n", "<C-h>", nav_skip_terminal("h"), { desc = "Go to left window" })
vim.keymap.set("n", "<C-j>", nav_skip_terminal("j"), { desc = "Go to lower window" })
vim.keymap.set("n", "<C-k>", nav_skip_terminal("k"), { desc = "Go to upper window" })
vim.keymap.set("n", "<C-l>", nav_skip_terminal("l"), { desc = "Go to right window" })

-- Window resize (Ctrl+arrows)
vim.keymap.set("n", "<C-Up>", "<cmd>resize +2<cr>", { desc = "Increase window height" })
vim.keymap.set("n", "<C-Down>", "<cmd>resize -2<cr>", { desc = "Decrease window height" })
vim.keymap.set("n", "<C-Left>", "<cmd>vertical resize -2<cr>", { desc = "Decrease window width" })
vim.keymap.set("n", "<C-Right>", "<cmd>vertical resize +2<cr>", { desc = "Increase window width" })

-- Buffer navigation
vim.keymap.set("n", "[b", "<cmd>bprev<cr>", { desc = "Prev buffer" })
vim.keymap.set("n", "]b", "<cmd>bnext<cr>", { desc = "Next buffer" })

-- Diagnostic navigation
vim.keymap.set("n", "[d", function() vim.diagnostic.jump({ count = -1, float = true }) end, { desc = "Prev diagnostic" })
vim.keymap.set("n", "]d", function() vim.diagnostic.jump({ count = 1, float = true }) end, { desc = "Next diagnostic" })
vim.keymap.set("n", "[e", function() vim.diagnostic.jump({ count = -1, severity = vim.diagnostic.severity.ERROR, float = true }) end, { desc = "Prev error" })
vim.keymap.set("n", "]e", function() vim.diagnostic.jump({ count = 1, severity = vim.diagnostic.severity.ERROR, float = true }) end, { desc = "Next error" })
vim.keymap.set("n", "[w", function() vim.diagnostic.jump({ count = -1, severity = vim.diagnostic.severity.WARN, float = true }) end, { desc = "Prev warning" })
vim.keymap.set("n", "]w", function() vim.diagnostic.jump({ count = 1, severity = vim.diagnostic.severity.WARN, float = true }) end, { desc = "Next warning" })

-- Quickfix navigation
vim.keymap.set("n", "[q", "<cmd>cprev<cr>zz", { desc = "Prev quickfix" })
vim.keymap.set("n", "]q", "<cmd>cnext<cr>zz", { desc = "Next quickfix" })
