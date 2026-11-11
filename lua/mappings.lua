--- Keybindings
--- see https://neovim.io/doc/user/intro.html#vim-modes-intro
vim.g.mapleader = " "
-- Filetype/view actions share the comma menu with general editing actions.
vim.g.maplocalleader = ","

-- No <C-s> save mapping: C-s is the tmux prefix on this setup, so tmux consumes
-- it and the mapping never fired. `:w` is the working path.

-- Open URLs externally and referenced files in Nvim, including wrapped terminal links.
vim.keymap.set("n", "gx", function()
  require("util.url").open()
end, { desc = "Open URL / local file" })

-- Nvim's own LSP defaults keep their behaviour; only the desc is rewritten.
-- Theirs is the code ("vim.lsp.buf.references()"), which is what the popup
-- showed. mapset() re-creates each from what maparg() returned -- the same
-- callback and flags -- so ":help lsp-defaults" still describes them. gO needs
-- a real desc rather than a which-key label: markdown, help, checkhealth and
-- man map their own gO (the outline), and a global which-key label outranked
-- theirs. A default someone has already replaced is left alone.
for _, d in ipairs({
  { "n", "gO",  "[LSP] Document symbols (Nvim default)" },
  -- The gr popup's group says "Nvim default" already (lua/whichkey_spec.lua).
  { "n", "grr", "[LSP] References" },
  { "n", "gri", "[LSP] Implementation" },
  { "n", "grt", "[LSP] Type definition" },
  -- "…": both ask first (the new name, which action), as ,r and ,a do.
  { "n", "grn", "[LSP] Rename…" },
  { "n", "gra", "[LSP] Code action…" },
  { "x", "gra", "[LSP] Code action…" },
  { "n", "grx", "[LSP] Run codelens" },
}) do
  local m = vim.fn.maparg(d[2], d[1], false, true)
  if m.buffer == 0 and (m.desc or ""):find("^vim%.lsp%.") then
    m.desc = d[3]
    vim.fn.mapset(m)
  end
end

-- Run the current file (dispatched by filetype; runners registered in lang/*.lua)
vim.keymap.set("n", ",x", function() require("util.run").run_current() end, { desc = "Run file" })

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

-- x deletes into the black hole register. Under clipboard=unnamedplus a plain x
-- replaced the system clipboard and pushed a one-character entry onto the
-- yanky ring. The price is the `xp` swap, which is `dlp` here. Normal mode
-- only: a Visual x is a deliberate cut. A named register ("ax) still applies;
-- '"', '+' and '*' are redirected, since v:register cannot tell a typed "+
-- from the default that 'clipboard' supplies.
vim.keymap.set("n", "x", function()
  return vim.v.register:match('^["+*]$') and '"_x' or "x"
end, { expr = true, desc = "Delete character (no yank)" })

-- Move lines. Alt belongs to tmux here (see lua/util/move.lua), so this lives
-- under `,` -- the current file/view action prefix -- and then
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
vim.keymap.set("i", "jk", "<ESC>", { desc = "Exit Insert mode", noremap = true, silent = true })
vim.keymap.set("i", "<C-c>", "<ESC>", { desc = "Exit Insert mode", noremap = true, silent = true })
vim.keymap.set("i", "<C-]>", "<Esc>", { desc = "Exit input mode", noremap = true, silent = true })
vim.keymap.set("i", "<C-\\>", "<Esc>", { desc = "Exit input mode", noremap = true, silent = true })
vim.keymap.set("x", "<C-]>", "<Esc>", { desc = "Exit selection mode", noremap = true, silent = true })
vim.keymap.set("x", "<C-\\>", "<Esc>", { desc = "Exit selection mode", noremap = true, silent = true })

-- Terminal mode
-- The agent panels opt out of this pair: both CLIs read a quick double Esc as
-- their own "go back a message", so lua/ai/terminal.lua maps a buffer-local
-- <Esc> there. <C-]> is the input-method-safe way to stay in the panel and
-- reach terminal-Normal; `jk` remains the unmodified alternative except in
-- lazygit, whose buffer-local j must navigate immediately (snacks.lua).
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
-- Shift+Enter as CSI 13;2u: Claude and Codex read it as a newline, not a submit.
vim.keymap.set("t", "<S-CR>", function()
  vim.fn.chansend(vim.b.terminal_job_id, "\x1b[13;2u")
end, { desc = "Send Shift+Enter (newline) to terminal", noremap = true, silent = true })
-- Ctrl+hjkl belong to Nvim window navigation in Terminal-mode. Preserve the
-- TUI's useful Ctrl+L redraw action on a shifted chord by forwarding the
-- original form-feed byte to the terminal job.
vim.keymap.set("t", "<C-S-l>", function()
  vim.fn.chansend(vim.b.terminal_job_id, "\x0c")
end, { desc = "Redraw terminal TUI", noremap = true, silent = true })
-- <C-l> is window navigation here, so Nvim's own clear-and-repaint needs a
-- home. It clears every cell of the host terminal, which wipes text the host
-- drew where Nvim's grid did not expect it: Ghostty renders Devanagari wider
-- than Nvim's one-cell-per-cluster model, so an agent panel showing it can
-- overflow the right edge and wrap onto the window at the left.
-- `:mode`, not `:redraw!`: the latter only invalidates and re-sends cells
-- that changed, so cells Nvim believes are unchanged are never rewritten.
vim.keymap.set("n", "<leader>ur", "<cmd>mode<cr>", { desc = "Redraw screen" })

-- Visual mode. "x", never "v": "v" also maps Select mode, where a snippet
-- placeholder sits and the first printable key typed must replace it -- with
-- "v", `<`/`>` indented the line and `,`/<Space> started a mapping instead
-- (`:h mapmode-x`). tests/select_mode_spec.lua holds every config key to it.
vim.keymap.set("x", "<", "<gv", { desc = "Indent left", noremap = true, silent = true })
vim.keymap.set("x", ">", ">gv", { desc = "Indent right", noremap = true, silent = true })
vim.keymap.set("x", "<leader>yy", "y", { desc = "Yank selection to register" })
vim.keymap.set("x", "<leader>yc", '"+y', { desc = "Yank selection to clipboard" })
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
  { desc = "Editor window (toggle back)", silent = true })
vim.keymap.set("t", "<C-,>", "<C-\\><C-n><cmd>WindowFocusEditor<cr>",
  { desc = "Editor window (toggle back)", silent = true })

-- Window resize (Ctrl+arrows). Routed through util.window rather than straight
-- to `:resize`: once edgy owns a panel in the tabpage, a bare `:resize` is a
-- no-op on an editor window and is reverted on a panel. See `window.resize`.
for _, spec in ipairs({
  { key = "<C-Up>",    dim = "height", delta = 2,  desc = "Increase window height" },
  { key = "<C-Down>",  dim = "height", delta = -2, desc = "Decrease window height" },
  { key = "<C-Left>",  dim = "width",  delta = -2, desc = "Decrease window width" },
  { key = "<C-Right>", dim = "width",  delta = 2,  desc = "Increase window width" },
}) do
  vim.keymap.set("n", spec.key, function()
    require("util.window").resize(spec.dim, spec.delta)
  end, { desc = spec.desc })
end

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
