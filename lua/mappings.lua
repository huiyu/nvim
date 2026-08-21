--- Keybindings
--- see https://neovim.io/doc/user/intro.html#vim-modes-intro
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- No <C-s> save mapping: C-s is the tmux prefix on this setup, so tmux consumes
-- it and the mapping never fired. `:w` is the working path.

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

-- Move lines. Alt belongs to tmux here (see lua/util/move.lua), so this lives on
-- <leader>m and then repeats on bare j/k -- see huiyu/nvim#12.
vim.keymap.set({ "n", "x" }, "<leader>mj", function() require("util.move").run("down") end,
  { desc = "Move line(s) down" })
vim.keymap.set({ "n", "x" }, "<leader>mk", function() require("util.move").run("up") end,
  { desc = "Move line(s) up" })

-- Insert mode
vim.keymap.set("i", "jk", "<ESC>", { desc = "Exit insert mode", noremap = true, silent = true })
vim.keymap.set("i", "<C-c>", "<ESC>", { desc = "Exit insert mode", noremap = true, silent = true })

-- Terminal mode
vim.keymap.set("t", "<Esc><Esc>", "<C-\\><C-n>", { desc = "Exit terminal mode", noremap = true, silent = true })
vim.keymap.set("t", "jk", "<C-\\><C-n>", { desc = "Exit terminal mode", noremap = true, silent = true })
vim.keymap.set("t", "<C-q>", function()
  vim.cmd("bdelete!")
end, { desc = "Close terminal", noremap = true, silent = true })
vim.keymap.set("n", "<leader>tx", function()
  if vim.bo.buftype ~= "terminal" then
    vim.notify("Current buffer is not a terminal", vim.log.levels.WARN)
    return
  end
  vim.cmd("bdelete!")
end, { desc = "Close terminal" })
-- Drift fix: shrink/restore terminal windows in one tick to force libvterm to
-- truncate its grid (the only resize op that actually invalidates stale cells).
vim.keymap.set("n", "<leader>td", function()
  require("util.terminal").fix_drift()
end, { desc = "Fix terminal TUI drift" })
vim.keymap.set("t", "<S-CR>", function()
  vim.fn.chansend(vim.b.terminal_job_id, "\x1b[13;2u")
end, { noremap = true, silent = true })
-- Ctrl+hjkl belong to Nvim window navigation in Terminal-mode. Preserve the
-- TUI's useful Ctrl+L redraw action on a shifted chord by forwarding the
-- original form-feed byte to the terminal job.
vim.keymap.set("t", "<C-S-l>", function()
  vim.fn.chansend(vim.b.terminal_job_id, "\x0c")
end, { desc = "Redraw terminal TUI", noremap = true, silent = true })

-- Visual & Select mode
vim.keymap.set("v", "<", "<gv", { desc = "Indent left", noremap = true, silent = true })
vim.keymap.set("v", ">", ">gv", { desc = "Indent right", noremap = true, silent = true })
vim.keymap.set("v", "<leader>y", "y", { desc = "Yank to register" })
vim.keymap.set("v", "<leader>Y", '"+y', { desc = "Yank to clipboard" })
-- Note: visual paste handled by yanky.nvim (provides yank history cycling)

-- Window navigation works uniformly from editor Normal mode and terminal
-- input mode. Entering a Snacks terminal triggers its auto-insert behavior;
-- leaving one first returns to terminal-Normal mode, then changes windows. At
-- a layout edge, keep terminal input active instead of exiting it for a no-op.
for _, nav in ipairs({
  { key = "h", label = "left" },
  { key = "j", label = "lower" },
  { key = "k", label = "upper" },
  { key = "l", label = "right" },
}) do
  local direction = nav.key
  local lhs = "<C-" .. direction .. ">"
  local desc = "Go to " .. nav.label .. " window"
  vim.keymap.set("n", lhs, "<C-w>" .. direction, { desc = desc, silent = true })
  vim.keymap.set("t", lhs, function()
    if vim.fn.winnr(direction) == vim.fn.winnr() then return "" end
    return "<C-\\><C-n><C-w>" .. direction
  end, { desc = desc, expr = true, silent = true })
end

-- <C-\> reaches the editor area in one press. With a file tree on one side and
-- a terminal or agent panel on the other, <C-h>/<C-l> need up to three hops to
-- cross back to the middle. Pressing it inside the editor returns to the window
-- it came from, so one key travels both ways.
-- Mapping <C-\> in Terminal-mode shadows the built-in <C-\><C-n>; `jk` and
-- <Esc><Esc> above already cover leaving terminal input mode.
vim.keymap.set("n", "<C-\\>", "<cmd>WindowFocusEditor<cr>",
  { desc = "Go to editor window", silent = true })
vim.keymap.set("t", "<C-\\>", "<C-\\><C-n><cmd>WindowFocusEditor<cr>",
  { desc = "Go to editor window", silent = true })

-- Window resize (Ctrl+arrows)
vim.keymap.set("n", "<C-Up>", "<cmd>resize +2<cr>", { desc = "Increase window height" })
vim.keymap.set("n", "<C-Down>", "<cmd>resize -2<cr>", { desc = "Decrease window height" })
vim.keymap.set("n", "<C-Left>", "<cmd>vertical resize -2<cr>", { desc = "Decrease window width" })
vim.keymap.set("n", "<C-Right>", "<cmd>vertical resize +2<cr>", { desc = "Increase window width" })

-- Buffer navigation ([b / ]b) lives in plugin/ui/bufferline.lua next to
-- <S-h>/<S-l>, so both pairs follow the visual bufferline order (pins/sorting)
-- instead of :bprev/:bnext buffer-number order.

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
