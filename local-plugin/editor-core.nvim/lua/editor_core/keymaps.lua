local M = {}
local defaults = {
  ["indent_left"] = { ["key"] = "<", ["desc"] = "Indent left" },
  ["next_error"] = { ["key"] = "]e", ["desc"] = "Next error" },
  ["next_warning"] = { ["key"] = "]w", ["desc"] = "Next warning" },
  ["indent_right"] = { ["key"] = ">", ["desc"] = "Indent right" },
  ["prev_quickfix"] = { ["key"] = "[q", ["desc"] = "Prev quickfix" },
  ["yank_selection_to_register"] = { ["key"] = "<leader>yy", ["desc"] = "Yank selection to register" },
  ["move_line_s_down"] = { ["key"] = ",j", ["desc"] = "Move line(s) down" },
  ["next_quickfix"] = { ["key"] = "]q", ["desc"] = "Next quickfix" },
  ["yank_selection_to_clipboard"] = { ["key"] = "<leader>yc", ["desc"] = "Yank selection to clipboard" },
  ["run_file"] = { ["key"] = ",x", ["desc"] = "Run file" },
  ["exit_selection_mode_2"] = { ["key"] = "<C-\\>", ["desc"] = "Exit selection mode" },
  ["move_line_s_up"] = { ["key"] = ",k", ["desc"] = "Move line(s) up" },
  ["exit_terminal_mode"] = { ["key"] = "<Esc><Esc>", ["desc"] = "Exit terminal mode" },
  ["escape_and_clear_hlsearch"] = { ["key"] = "<Esc>", ["desc"] = "Escape and clear hlsearch" },
  ["dedent_line_s"] = { ["key"] = ",h", ["desc"] = "Dedent line(s)" },
  ["open_url_local_file"] = { ["key"] = "gx", ["desc"] = "Open URL / local file" },
  ["editor_window_toggle_back_2"] = { ["key"] = "<C-,>", ["desc"] = "Editor window (toggle back)" },
  ["escape_with_normal_input_source"] = { ["key"] = "<C-]>", ["desc"] = "Escape with Normal input source" },
  ["indent_line_s"] = { ["key"] = ",l", ["desc"] = "Indent line(s)" },
  ["fix_terminal_tui_drift"] = { ["key"] = "<leader>md", ["desc"] = "Fix terminal TUI drift" },
  ["escape_with_normal_input_source_2"] = { ["key"] = "<C-\\>", ["desc"] = "Escape with Normal input source" },
  ["editor_window_toggle_back"] = { ["key"] = "<C-,>", ["desc"] = "Editor window (toggle back)" },
  ["prev_diagnostic"] = { ["key"] = "[d", ["desc"] = "Prev diagnostic" },
  ["prev_error"] = { ["key"] = "[e", ["desc"] = "Prev error" },
  ["exit_insert_mode"] = { ["key"] = "jk", ["desc"] = "Exit Insert mode" },
  ["exit_input_mode"] = { ["key"] = "<C-]>", ["desc"] = "Exit input mode" },
  ["send_shift_enter_newline_to_terminal"] = { ["key"] = "<S-CR>", ["desc"] = "Send Shift+Enter (newline) to terminal" },
  ["delete_character_no_yank"] = { ["key"] = "x", ["desc"] = "Delete character (no yank)" },
  ["exit_insert_mode_2"] = { ["key"] = "<C-c>", ["desc"] = "Exit Insert mode" },
  ["redraw_screen"] = { ["key"] = "<leader>ur", ["desc"] = "Redraw screen" },
  ["next_diagnostic"] = { ["key"] = "]d", ["desc"] = "Next diagnostic" },
  ["exit_input_mode_2"] = { ["key"] = "<C-\\>", ["desc"] = "Exit input mode" },
  ["exit_terminal_mode_2"] = { ["key"] = "jk", ["desc"] = "Exit terminal mode" },
  ["exit_selection_mode"] = { ["key"] = "<C-]>", ["desc"] = "Exit selection mode" },
  ["redraw_terminal_tui"] = { ["key"] = "<C-S-l>", ["desc"] = "Redraw terminal TUI" },
  ["exit_input_mode_3"] = { ["key"] = "<C-]>", ["desc"] = "Exit input mode" },
  ["down"] = { ["key"] = "j", ["desc"] = "Down" },
  ["up"] = { ["key"] = "k", ["desc"] = "Up" },
  ["exit_input_mode_4"] = { ["key"] = "<C-\\>", ["desc"] = "Exit input mode" },
  ["prev_warning"] = { ["key"] = "[w", ["desc"] = "Prev warning" },
}
function M.setup(opts)
  local choices = vim.tbl_extend("force", vim.deepcopy(defaults), opts.core or {})
  local function bind(mode, action, rhs, flags)
    local choice = choices[action]
    if choice == false then return end
    assert(type(choice) == "table" and type(choice.key) == "string", "Invalid core key choice: " .. action)
    flags.desc = choice.desc or flags.desc
    vim.keymap.set(mode, choice.key, rhs, flags)
  end
--- Keybindings
--- see https://neovim.io/doc/user/intro.html#vim-modes-intro

-- Filetype/view actions share the comma menu with general editing actions.


-- No <C-s> save mapping: C-s is the tmux prefix on this setup, so tmux consumes
-- it and the mapping never fired. `:w` is the working path.

-- Open URLs externally and referenced files in Nvim, including wrapped terminal links.
bind("n", "open_url_local_file", function()
  require("editor_core.url").open()
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
  -- The gr popup's group says "Nvim default" already (lua/config/whichkey_spec.lua).
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
bind("n", "run_file", function() require("editor_core.run").run_current() end, { desc = "Run file" })

-- Clear search highlight on Escape
-- Normal mode only: mapping bare <Esc> in insert mode can add latency to / mis-fire
-- on terminal escape sequences (arrows, Alt, F-keys), and there's no hlsearch to clear there.
bind("n", "escape_and_clear_hlsearch", "<cmd>nohlsearch<cr><Esc>", { desc = "Escape and clear hlsearch" })
-- A repeatable Escape chord for input methods that consume bare Esc. In Normal
-- mode it also captures a manually selected input method and returns to the
-- Normal source without changing modes; InsertEnter restores only a source
-- that Nvim actually switched away. `help` and `man` buffers are the exception
-- -- <C-]> is their primary navigation -- and local-plugin/editor-core.nvim/lua/editor_core/autocmds.lua gives the
-- builtin back there, buffer-locally.
local function normal_escape()
  vim.cmd.nohlsearch()
  require("editor_core.input_method").ensure_normal_source()
end
bind("n", "escape_with_normal_input_source", normal_escape, { desc = "Escape with Normal input source" })
bind("n", "escape_with_normal_input_source_2", normal_escape, { desc = "Escape with Normal input source" })

-- Better up/down on wrapped lines
bind({ "n", "x" }, "down", "v:count == 0 ? 'gj' : 'j'", { expr = true, desc = "Down" })
bind({ "n", "x" }, "up", "v:count == 0 ? 'gk' : 'k'", { expr = true, desc = "Up" })

-- x deletes into the black hole register. Under clipboard=unnamedplus a plain x
-- replaced the system clipboard and pushed a one-character entry onto the
-- yanky ring. The price is the `xp` swap, which is `dlp` here. Normal mode
-- only: a Visual x is a deliberate cut. A named register ("ax) still applies;
-- '"', '+' and '*' are redirected, since v:register cannot tell a typed "+
-- from the default that 'clipboard' supplies.
bind("n", "delete_character_no_yank", function()
  return vim.v.register:match('^["+*]$') and '"_x' or "x"
end, { expr = true, desc = "Delete character (no yank)" })

-- Move lines. Alt belongs to tmux here (see local-plugin/editor-core.nvim/lua/editor_core/move.lua), so this lives
-- under `,` -- the current file/view action prefix -- and then
-- repeats on bare j/k. See huiyu/nvim#12.
bind({ "n", "x" }, "move_line_s_down", function() require("editor_core.move").run("down") end,
  { desc = "Move line(s) down" })
bind({ "n", "x" }, "move_line_s_up", function() require("editor_core.move").run("up") end,
  { desc = "Move line(s) up" })
bind({ "n", "x" }, "dedent_line_s", function() require("editor_core.move").run("left") end,
  { desc = "Dedent line(s)" })
bind({ "n", "x" }, "indent_line_s", function() require("editor_core.move").run("right") end,
  { desc = "Indent line(s)" })

-- Insert mode
bind("i", "exit_insert_mode", "<ESC>", { desc = "Exit Insert mode", noremap = true, silent = true })
bind("i", "exit_insert_mode_2", "<ESC>", { desc = "Exit Insert mode", noremap = true, silent = true })
bind("i", "exit_input_mode", "<Esc>", { desc = "Exit input mode", noremap = true, silent = true })
bind("i", "exit_input_mode_2", "<Esc>", { desc = "Exit input mode", noremap = true, silent = true })
bind("x", "exit_selection_mode", "<Esc>", { desc = "Exit selection mode", noremap = true, silent = true })
bind("x", "exit_selection_mode_2", "<Esc>", { desc = "Exit selection mode", noremap = true, silent = true })

-- Terminal mode
-- The agent panels opt out of this pair: both CLIs read a quick double Esc as
-- their own "go back a message", so local-plugin/agent-workbench.nvim/lua/agent_workbench/terminal.lua maps a buffer-local
-- <Esc> there. <C-]> is the input-method-safe way to stay in the panel and
-- reach terminal-Normal; `jk` remains the unmodified alternative except in
-- lazygit, whose buffer-local j must navigate immediately (snacks.lua).
bind("t", "exit_terminal_mode", "<C-\\><C-n>", { desc = "Exit terminal mode", noremap = true, silent = true })
bind("t", "exit_terminal_mode_2", "<C-\\><C-n>", { desc = "Exit terminal mode", noremap = true, silent = true })
bind("t", "exit_input_mode_3", "<C-\\><C-n>", { desc = "Exit input mode", noremap = true, silent = true })
bind("t", "exit_input_mode_4", "<C-\\><C-n>", { desc = "Exit input mode", noremap = true, silent = true })
-- No "close terminal" key. `exit` in the shell ends the job and the buffer
-- goes with it, <C-/> toggles the panel away, and :bd! covers a wedged one --
-- a dedicated chord only added a way to force-delete the wrong buffer.
-- <C-c> in particular must stay unmapped in Terminal-mode: it is SIGINT, the
-- one key you cannot afford to shadow inside a terminal.
-- Drift fix: shrink/restore terminal windows in one tick to force libvterm to
-- truncate its grid (the only resize op that actually invalidates stale cells).
bind("n", "fix_terminal_tui_drift", function()
  require("editor_core.terminal").fix_drift()
end, { desc = "Fix terminal TUI drift" })
-- Shift+Enter as CSI 13;2u: Claude and Codex read it as a newline, not a submit.
bind("t", "send_shift_enter_newline_to_terminal", function()
  vim.fn.chansend(vim.b.terminal_job_id, "\x1b[13;2u")
end, { desc = "Send Shift+Enter (newline) to terminal", noremap = true, silent = true })
-- Ctrl+hjkl belong to Nvim window navigation in Terminal-mode. Preserve the
-- TUI's useful Ctrl+L redraw action on a shifted chord by forwarding the
-- original form-feed byte to the terminal job.
bind("t", "redraw_terminal_tui", function()
  vim.fn.chansend(vim.b.terminal_job_id, "\x0c")
end, { desc = "Redraw terminal TUI", noremap = true, silent = true })
-- <C-l> is window navigation here, so Nvim's own clear-and-repaint needs a
-- home. It clears every cell of the host terminal, which wipes text the host
-- drew where Nvim's grid did not expect it: Ghostty renders Devanagari wider
-- than Nvim's one-cell-per-cluster model, so an agent panel showing it can
-- overflow the right edge and wrap onto the window at the left.
-- `:mode`, not `:redraw!`: the latter only invalidates and re-sends cells
-- that changed, so cells Nvim believes are unchanged are never rewritten.
bind("n", "redraw_screen", "<cmd>mode<cr>", { desc = "Redraw screen" })

-- Visual mode. "x", never "v": "v" also maps Select mode, where a snippet
-- placeholder sits and the first printable key typed must replace it -- with
-- "v", `<`/`>` indented the line and `,`/<Space> started a mapping instead
-- (`:h mapmode-x`). tests/select_mode_spec.lua holds every config key to it.
bind("x", "indent_left", "<gv", { desc = "Indent left", noremap = true, silent = true })
bind("x", "indent_right", ">gv", { desc = "Indent right", noremap = true, silent = true })
bind("x", "yank_selection_to_register", "y", { desc = "Yank selection to register" })
bind("x", "yank_selection_to_clipboard", '"+y', { desc = "Yank selection to clipboard" })
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
-- lua/config/whichkey_spec.lua is the plain-key fallback for the terminals and tmux
-- configurations that cannot send the chord at all.
bind("n", "editor_window_toggle_back", "<cmd>WindowFocusEditor<cr>",
  { desc = "Editor window (toggle back)", silent = true })
bind("t", "editor_window_toggle_back_2", "<C-\\><C-n><cmd>WindowFocusEditor<cr>",
  { desc = "Editor window (toggle back)", silent = true })

-- Window resize (Ctrl+arrows). Routed through editor_core.window rather than straight
-- to `:resize`: once edgy owns a panel in the tabpage, a bare `:resize` is a
-- no-op on an editor window and is reverted on a panel. See `window.resize`.
for _, spec in ipairs({
  { key = "<C-Up>",    dim = "height", delta = 2,  desc = "Increase window height" },
  { key = "<C-Down>",  dim = "height", delta = -2, desc = "Decrease window height" },
  { key = "<C-Left>",  dim = "width",  delta = -2, desc = "Decrease window width" },
  { key = "<C-Right>", dim = "width",  delta = 2,  desc = "Increase window width" },
}) do
  vim.keymap.set("n", spec.key, function()
    require("editor_core.window").resize(spec.dim, spec.delta)
  end, { desc = spec.desc })
end

-- Buffer navigation ([b / ]b) lives in plugins/ui/bufferline.lua next to
-- <S-h>/<S-l>, so both pairs follow the visual bufferline order (pins/sorting)
-- instead of :bprev/:bnext buffer-number order.

-- Diagnostic navigation. Each jump shows the diagnostic it lands on in a
-- float; `on_jump` replaces jump()'s `float` option, deprecated in 0.12.
local function show_jumped(_, bufnr)
  vim.diagnostic.open_float({ bufnr = bufnr, scope = "cursor", focus = false })
end
bind("n", "prev_diagnostic", function() vim.diagnostic.jump({ count = -1, on_jump = show_jumped }) end, { desc = "Prev diagnostic" })
bind("n", "next_diagnostic", function() vim.diagnostic.jump({ count = 1, on_jump = show_jumped }) end, { desc = "Next diagnostic" })
bind("n", "prev_error", function() vim.diagnostic.jump({ count = -1, severity = vim.diagnostic.severity.ERROR, on_jump = show_jumped }) end, { desc = "Prev error" })
bind("n", "next_error", function() vim.diagnostic.jump({ count = 1, severity = vim.diagnostic.severity.ERROR, on_jump = show_jumped }) end, { desc = "Next error" })
bind("n", "prev_warning", function() vim.diagnostic.jump({ count = -1, severity = vim.diagnostic.severity.WARN, on_jump = show_jumped }) end, { desc = "Prev warning" })
bind("n", "next_warning", function() vim.diagnostic.jump({ count = 1, severity = vim.diagnostic.severity.WARN, on_jump = show_jumped }) end, { desc = "Next warning" })

-- Quickfix navigation
bind("n", "prev_quickfix", "<cmd>cprev<cr>zz", { desc = "Prev quickfix" })
bind("n", "next_quickfix", "<cmd>cnext<cr>zz", { desc = "Next quickfix" })

end
return M
