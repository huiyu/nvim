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
vim.keymap.set("n", ",x", function() require("util.run").run_current() end, { desc = "Run current file" })

-- Clear search highlight on Escape
-- Normal mode only: mapping bare <Esc> in insert mode can add latency to / mis-fire
-- on terminal escape sequences (arrows, Alt, F-keys), and there's no hlsearch to clear there.
vim.keymap.set("n", "<Esc>", "<cmd>nohlsearch<cr><Esc>", { desc = "Escape and clear hlsearch" })
-- A repeatable Escape chord for input methods that consume bare Esc. In Normal
-- mode it also captures a manually selected input method and returns to the
-- Normal source without changing modes; InsertEnter restores only a source
-- that Nvim actually switched away. `help` and `man` buffers are the exception
-- -- <C-]> is their primary navigation -- and lua/autocmds.lua gives the
-- builtin back there, buffer-locally.
local function normal_escape()
  vim.cmd.nohlsearch()
  require("util.input_method").ensure_normal_source()
end
vim.keymap.set("n", "<C-]>", normal_escape, { desc = "Escape with Normal input source" })
vim.keymap.set("n", "<C-\\>", normal_escape, { desc = "Escape with Normal input source" })

-- Better up/down on wrapped lines
vim.keymap.set({ "n", "x" }, "j", "v:count == 0 ? 'gj' : 'j'", { expr = true, desc = "Down" })
vim.keymap.set({ "n", "x" }, "k", "v:count == 0 ? 'gk' : 'k'", { expr = true, desc = "Up" })

-- Move lines. Alt belongs to tmux here (see lua/util/move.lua), so this lives
-- under `,` -- the prefix for acting on the code in front of you -- and then
-- repeats on bare j/k. See huiyu/nvim#12.
vim.keymap.set({ "n", "x" }, ",j", function() require("util.move").run("down") end,
  { desc = "Move line(s) down" })
vim.keymap.set({ "n", "x" }, ",k", function() require("util.move").run("up") end,
  { desc = "Move line(s) up" })
vim.keymap.set({ "n", "x" }, ",h", function() require("util.move").run("left") end,
  { desc = "Dedent line(s)" })
vim.keymap.set({ "n", "x" }, ",l", function() require("util.move").run("right") end,
  { desc = "Indent line(s)" })

-- Insert mode
vim.keymap.set("i", "jk", "<ESC>", { desc = "Exit insert mode", noremap = true, silent = true })
vim.keymap.set("i", "<C-c>", "<ESC>", { desc = "Exit insert mode", noremap = true, silent = true })
vim.keymap.set("i", "<C-]>", "<Esc>", { desc = "Exit input mode", noremap = true, silent = true })
vim.keymap.set("i", "<C-\\>", "<Esc>", { desc = "Exit input mode", noremap = true, silent = true })
vim.keymap.set("x", "<C-]>", "<Esc>", { desc = "Exit selection mode", noremap = true, silent = true })
vim.keymap.set("x", "<C-\\>", "<Esc>", { desc = "Exit selection mode", noremap = true, silent = true })

-- Terminal mode
-- The agent panels opt out of this pair: both CLIs read a quick double Esc as
-- their own "go back a message", so lua/ai/terminal.lua maps a buffer-local
-- <Esc> there. <C-]> is the input-method-safe way to stay in the panel and
-- reach terminal-Normal; `jk` remains the unmodified alternative.
vim.keymap.set("t", "<Esc><Esc>", "<C-\\><C-n>", { desc = "Exit terminal mode", noremap = true, silent = true })
vim.keymap.set("t", "jk", "<C-\\><C-n>", { desc = "Exit terminal mode", noremap = true, silent = true })
vim.keymap.set("t", "<C-]>", "<C-\\><C-n>", { desc = "Exit input mode", noremap = true, silent = true })
vim.keymap.set("t", "<C-\\>", "<C-\\><C-n>", { desc = "Exit input mode", noremap = true, silent = true })
-- No "close terminal" key. `exit` in the shell ends the job and the buffer
-- goes with it, <C-/> toggles the panel away, and :bd! covers a wedged one --
-- a dedicated chord only added a way to force-delete the wrong buffer.
-- <C-c> in particular must stay unmapped in Terminal-mode: it is SIGINT, the
-- one key you cannot afford to shadow inside a terminal.
-- Drift fix: shrink/restore terminal windows in one tick to force libvterm to
-- truncate its grid (the only resize op that actually invalidates stale cells).
vim.keymap.set("n", "<leader>md", function()
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
vim.keymap.set("v", "<leader>yy", "y", { desc = "Yank selection to register" })
vim.keymap.set("v", "<leader>yc", '"+y', { desc = "Yank selection to clipboard" })
-- Note: visual paste handled by yanky.nvim (provides yank history cycling)

-- Window navigation works uniformly from editor Normal mode and terminal
-- input mode. Entering a Snacks terminal triggers its auto-insert behavior;
-- leaving one first returns to terminal-Normal mode, then changes windows. At
-- a layout edge, keep terminal input active instead of exiting it for a no-op.
--
-- A floating terminal (lazygit, the float-shaped <C-/> shell) has no layout
-- neighbours at all, but `winnr(direction)` still answers with a window
-- underneath it, so the edge check alone would let <C-h> (a shell's backspace)
-- or <C-l> (clear screen) jump out from under the float and leave it hovering
-- over the editor. Treat a float as all edges.
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
    if vim.api.nvim_win_get_config(0).relative ~= "" then return "" end
    if vim.fn.winnr(direction) == vim.fn.winnr() then return "" end
    return "<C-\\><C-n><C-w>" .. direction
  end, { desc = desc, expr = true, silent = true })
end

-- Ctrl-comma reaches the editor area in one press from Normal or terminal
-- input, and toggles back to the origin window from the editor. Ghostty and
-- Nvim's extended-key protocol keep this distinct from a plain comma, so this
-- pair only exists where that protocol is negotiated. `se` in
-- lua/whichkey_spec.lua is the plain-key fallback for the terminals and tmux
-- configurations that cannot send the chord at all.
vim.keymap.set("n", "<C-,>", "<cmd>WindowFocusEditor<cr>",
  { desc = "Go to editor window", silent = true })
vim.keymap.set("t", "<C-,>", "<C-\\><C-n><cmd>WindowFocusEditor<cr>",
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
