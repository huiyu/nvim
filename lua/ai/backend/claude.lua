local M = {}
local launch = require("ai.backend.launch")

-- Whether to wrap claude in a dedicated tmux server when launching the
-- terminal. Precedence: env var > vim.g > default.
--   CLAUDE_WRAP_TMUX=1 nvim    -> force on
--   CLAUDE_WRAP_TMUX=0 nvim    -> force off (one-off A/B testing)
--   vim.g.claude_wrap_tmux = false in init.lua -> persistent opt-out
-- Default is ON: claude's Ink TUI emits DEC mode 2026 (Synchronized Output)
-- sequences, which nvim's :terminal buffer does not understand. Without the
-- wrapper you get visible mid-frame tearing (status bar double-render, lines
-- bleeding into the next). tmux absorbs the 2026 protocol and emits already-
-- composed plain ANSI to nvim :terminal. Trade-off: minor CJK width
-- misalignment in box-bordered UI inside the wrapped tmux — acceptable
-- vs. the tearing without it.
local function should_wrap_tmux()
  return launch.enabled("CLAUDE_WRAP_TMUX", "claude_wrap_tmux")
end

-- Whether to launch claude with the Claude in Chrome integration enabled.
-- Same precedence as should_wrap_tmux: env var > vim.g > default (ON).
--   CLAUDE_CHROME=0 nvim               -> force off (one-off)
--   vim.g.claude_chrome = false        -> persistent opt-out
local function should_use_chrome()
  return launch.enabled("CLAUDE_CHROME", "claude_chrome")
end

function M.terminal_command()
  local claude_args = { "claude" }
  for _, arg in ipairs(require("ai.plugins").claude_args()) do
    claude_args[#claude_args + 1] = vim.fn.shellescape(arg)
  end
  if should_use_chrome() then claude_args[#claude_args + 1] = "--chrome" end
  -- The review baseline's prompt hooks (lua/ai/review/hook.lua). Claude merges
  -- --settings hooks with the user's own instead of replacing them, so nothing
  -- is written to ~/.claude. One shell word after `claude`: agent_of_command
  -- still finds the agent in front of it, and claudecode's appended --resume /
  -- --continue still land after it, through "$@" under tmux.
  if require("ai.review.settings").get().sources.claude then
    claude_args[#claude_args + 1] = "--settings"
    claude_args[#claude_args + 1] = vim.fn.shellescape(require("ai.review.hook").claude_settings())
  end
  local claude_cmd = table.concat(claude_args, " ")

  -- nvim defaults TERM=xterm-256color for :terminal children, but xterm-256color
  -- claims more capabilities than nvim's libvterm actually implements. Ink emits
  -- ANSI sequences for those claimed-but-unsupported features → libvterm renders
  -- incomplete frames → drift, residue, cumulative degradation (huiyu/nvim#2).
  -- Forcing TERM to whatever nvim's own terminal advertises (e.g. xterm-ghostty
  -- in Ghostty) gives Ink a conservative terminfo that matches libvterm's actual
  -- capabilities. nvim's own vim.env.TERM is the original host-terminal TERM —
  -- nvim only overrides it for :terminal children, not its own env.
  local term = vim.env.TERM or "xterm-256color"

  -- ctrl+g in the TUI edits the input box in $EDITOR. Pointing it at the wrapper
  -- sends that back to this nvim rather than nesting a second one inside the
  -- :terminal -- see lua/ai/editor.lua.
  local env = launch.editor_env()
  local editor_env = "EDITOR=" .. vim.fn.shellescape(env.EDITOR) .. " VISUAL=" .. vim.fn.shellescape(env.VISUAL)
  -- Launcher that keeps a failed claude's error on screen; see scripts/agent-run
  -- and the note on the pane command below.
  local runner = vim.fn.shellescape(launch.runner())

  -- Skip the wrapper unless tmux is available AND wrapping is explicitly enabled.
  if vim.fn.executable("tmux") ~= 1 or not should_wrap_tmux() then
    return "env TERM=" .. vim.fn.shellescape(term) .. " " .. editor_env .. " " .. claude_cmd
  end

  -- Rationale for the wrapper lives in should_wrap_tmux above. Implementation
  -- notes below.
  --
  -- Dedicated tmux server (-L <socket>) isolates our hooks and sessions from
  -- the user's regular tmux. When the nvim client goes away -- panel closed,
  -- nvim quit, host terminal gone -- the client-detached hook runs
  -- scripts/agent-teardown, which kills this server and then whatever claude
  -- left running in process groups of its own; a bare kill-server only ever
  -- reached the pane's own process. See ai.backend.launch.teardown_hook.
  --
  -- Wrap in `sh -c '...' _` so that cmd args appended by claudecode.nvim
  -- (e.g. --resume, --continue) land inside the claude invocation via "$@"
  -- rather than after the trailing tmux set-hook.
  local socket = "claude-nvim-" .. vim.fn.getpid()
  local inner = table.concat({
    -- `-f /dev/null`: don't load the host ~/.config/tmux/tmux.conf into this
    -- wrapper server. The host conf binds prefix-free Alt keys (window/pane
    -- navigation) that would otherwise be swallowed here instead of reaching
    -- claude. This server sets every option it needs explicitly below.
    "tmux -f /dev/null -L " .. socket,
    -- Set default-terminal BEFORE new-session so claude inside the pane sees
    -- the conservative TERM directly. tmux otherwise injects its own default
    -- (tmux-256color) into the pane env regardless of the outer TERM we set
    -- via env(1), which puts us right back into the "terminfo claims more
    -- than libvterm implements" trap that caused huiyu/nvim#2.
    "set-option -g default-terminal " .. vim.fn.shellescape(term),
    "\\;",
    -- Claude's classic renderer (`/tui default`) never asks for mouse
    -- reporting (the fullscreen one does), and nvim only forwards
    -- a click to a job that did. Without this the pane's clicks are handled by
    -- nvim instead -- which drops out of Terminal-mode, so clicking back into
    -- the window after an app switch left the panel in Normal mode. tmux does
    -- ask, so the click reaches the pane and Terminal-mode survives. Codex
    -- already had this; the two wrappers now agree.
    "set-option -g mouse on",
    "\\;",
    -- Keep mouse scrolling, but suppress tmux's pane menu on right-click.
    "unbind-key -T root MouseDown3Pane",
    "\\;",
    "unbind-key -T root M-MouseDown3Pane",
    "\\;",
    -- Keep modified Enter chords intact on their way into the pane, as the
    -- Codex wrapper does: tmux's default `extended-keys off` turns the CSI u
    -- ESC[13;2u that lua/config/keymaps.lua sends for <S-CR> into a bare CR, which
    -- submits instead of inserting a newline (measured on tmux 3.6b). Claude
    -- Code parses ESC[13;2u -- it is what its /terminal-setup teaches iTerm2 --
    -- and claudecode.nvim's own buffer-local <S-CR> (backslash + Enter) keeps
    -- working regardless, so this is about the two wrappers agreeing on what a
    -- chord means, not a fix Claude needs on its own.
    "set-option -g extended-keys always",
    "\\;",
    "set-option -g extended-keys-format csi-u",
    "\\;",
    -- With the mouse on, the wheel reaches tmux and opens copy-mode over the
    -- real transcript, so the default 2000-line history becomes the limit
    -- worth raising. Same value as the Codex wrapper.
    "set-option -g history-limit 50000",
    "\\;",
    -- Force copy-mode rather than leaving tmux's default root bindings to
    -- decide. Claude Code can be put on the alternate screen (`/tui
    -- fullscreen`), and there, with its mouse reporting off, tmux's default
    -- translates the wheel into arrow keys -- which Claude reads as "walk the
    -- input history", so scrolling would replace whatever is typed in the box.
    -- An empty copy-mode you leave with `q` is the better failure. With mouse
    -- reporting on, fullscreen's default, these bindings still take the wheel
    -- and PageUp away from Claude's own scrolling: the wrapper is tuned for the
    -- classic renderer. PPage is what lua/ai/terminal.lua sends
    -- when the scroll starts from terminal-Normal mode.
    --
    -- The wheel enters copy-mode without `-u`, which PPage keeps: `-u` scrolls
    -- a full page on entry, so the first notch used to jump a whole screen. A
    -- page is what PageUp means; it is not what one notch means.
    "bind-key -T root WheelUpPane copy-mode -e",
    "\\;",
    "bind-key -T root PPage copy-mode -eu",
    "\\;",
    -- Once in copy-mode, 2 lines per wheel event rather than tmux's default 5:
    -- Ghostty sends 3 events per discrete notch (mouse-scroll-multiplier), so
    -- the default made one notch ~15 lines. Both tables are bound because
    -- which one is live depends on mode-keys, which tmux derives from
    -- $EDITOR/$VISUAL in the server's own environment -- emacs as measured
    -- here, but not something this wrapper controls.
    "bind-key -T copy-mode WheelUpPane send-keys -X -N 2 scroll-up",
    "\\;",
    "bind-key -T copy-mode WheelDownPane send-keys -X -N 2 scroll-down",
    "\\;",
    "bind-key -T copy-mode-vi WheelUpPane send-keys -X -N 2 scroll-up",
    "\\;",
    "bind-key -T copy-mode-vi WheelDownPane send-keys -X -N 2 scroll-down",
    "\\;",
    "new-session -A -s main",
    "-e CLAUDE_CODE_SSE_PORT=$CLAUDE_CODE_SSE_PORT",
    "-e ENABLE_IDE_INTEGRATION=$ENABLE_IDE_INTEGRATION",
    "-e FORCE_CODE_TERMINAL=$FORCE_CODE_TERMINAL",
    "-e no_proxy=localhost,127.0.0.1",
    -- CLAUDE_CODE_NO_FLICKER=1 used to be forced here for the alt-screen
    -- renderer. Claude Code has since made that a first-class user preference:
    -- `/tui fullscreen` / `/tui default`, stored as "tui" in
    -- ~/.claude/settings.json, with the env var documented as the override.
    -- Forcing the override here would silently ignore whatever the user chose,
    -- so it is left unset and the preference wins.
    --
    -- Note this is NOT the lever for "the pane goes blank while the ctrl+g
    -- prompt editor is open", and neither is `/tui`. Measured: the pane goes
    -- blank with the env var set, with it unset, and on the `default`
    -- (main-screen) renderer alike. Claude Code simply clears the terminal
    -- before handing it to $EDITOR, and our editor draws in a float instead of
    -- on that canvas. It is its own choice, not something every CLI does --
    -- Codex held its TUI at 18 non-blank lines across the same edit while
    -- Claude went 17 -> 0 -> 17. scripts/agent-editor prints into the cleared
    -- pane so it explains itself rather than looking hung.
    -- tmux only puts into the pane what is whitelisted with -e, so the ctrl+g
    -- editor handoff has to be forwarded explicitly. $NVIM is already in this
    -- sh's environment because nvim sets it for every :terminal child, and it
    -- is what lets the wrapper find its way back here.
    "-e EDITOR=$EDITOR",
    "-e VISUAL=$VISUAL",
    "-e NVIM=$NVIM",
    -- Run claude through the launcher rather than directly. The trailing
    -- `exit-empty` / client-detached teardown below makes the
    -- tmux client exit 0 however the pane's command ended, so nvim's :terminal
    -- job reports success and Snacks' auto_close silently closes the panel --
    -- taking claude's own startup error with it. See scripts/agent-run.
    runner .. " " .. claude_cmd .. ' "$@"',
    -- Off, deliberately: the client-detached hook below is what ends this
    -- server, and with destroy-unattached on the session -- and the pane's
    -- process tree the hook has to record -- was gone before the hook ran
    -- (measured). exit-empty still ends the server when claude itself exits.
    "\\; set-option -g destroy-unattached off",
    "\\; set-option -g exit-empty on",
    -- Hide status bar in wrapper tmux: avoids periodic status redraws
    -- and stale-frame artifacts on resize (host's tmux.conf still loads,
    -- but status is overridden here per-server).
    "\\; set-option -g status off",
    "\\; set-hook -g client-detached " .. vim.fn.shellescape(launch.teardown_hook(socket)),
  }, " ")
  return "env TERM=" .. vim.fn.shellescape(term) .. " " .. editor_env
    .. " sh -c " .. vim.fn.shellescape(inner) .. " _"
end

-- Where Claude starts. "git_root" (the default) is the rule Codex uses: the
-- current file's Git root (util.cwd.project_root), so both agents' sessions --
-- and the review rounds their prompts open -- belong to the same project.
-- "cwd" answers nil, which leaves claudecode's own default: Nvim's working
-- directory. Read on every launch.
function M.cwd(ctx)
  if require("ai.review.settings").get().claude_cwd ~= "git_root" then return nil end
  return require("util.cwd").project_root(ctx.file)
end

-- Called when claudecode.nvim first loads. The watchdog and its stale-server
-- sweep start here, while building its lazy spec never starts a process.
function M.configure(opts)
  if vim.fn.executable("tmux") == 1 and should_wrap_tmux() then
    launch.ensure_watchdog("claude")
  end
  -- Build again now so vim.g.ai_review set later in init.lua still reaches
  -- the first launch. The command is fixed after setup; disabling the source
  -- later still drops its events in ai.review.hook.
  opts.terminal_cmd = M.terminal_command()
  require("claudecode").setup(opts)
end

local INFO, WARN = vim.log.levels.INFO, vim.log.levels.WARN

local function command(cmd)
  vim.cmd(cmd)
end

function M.send_selection() command("ClaudeCodeSend") end
function M.accept_diff() command("ClaudeCodeDiffAccept") end
function M.deny_diff() command("ClaudeCodeDiffDeny") end
function M.tree_add() command("ClaudeCodeTreeAdd") end

-- The Snacks terminal claudecode.nvim manages. Answering never loads the
-- plugin: with it unloaded there is no Claude panel to find.
local function panel()
  if not package.loaded["claudecode"] then return nil end
  local buf = require("claudecode.terminal").get_active_terminal_bufnr()
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then return nil end
  for _, term in ipairs(require("snacks").terminal.list()) do
    if term.buf == buf then return term end
  end
end

---Is a Claude session running in this Nvim, shown or not?
---@return boolean
function M.running()
  return panel() ~= nil
end

---The session's terminal buffer, while one runs.
---@return integer|nil
function M.buf()
  local term = panel()
  return term and term.buf or nil
end

---A window of the current tabpage that shows the session: its own, else
---the copy claudecode puts beside a proposed diff in a tabpage of its own.
---@return integer|nil
function M.window_here()
  local buf = M.buf()
  if not buf then return nil end
  if M.visible() then return M.window() end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_config(win).relative == "" and vim.api.nvim_win_get_buf(win) == buf then return win end
  end
end

---Show the session here and focus it, starting it when none runs. Shown here
---already -- in its own window, or in the copy of a diff tabpage -- it is
---focused where it is. Else this is claudecode's open, not its toggles: it
---reuses the one terminal (cc_show) and never hides it, and it judges "shown"
---by the terminal's own window, so it would open a second one beside a copy.
---Through the command until the plugin has loaded -- the command is what
---loads it -- and the module function after, which is also what a spec
---stands in for.
---@param args string? CLI arguments for a session it starts; a running one ignores them
function M.reveal(args)
  local here = M.window_here()
  if here then
    vim.api.nvim_set_current_win(here)
    vim.cmd("startinsert")
    return
  end
  if package.loaded["claudecode"] then
    require("claudecode.terminal").open({}, args)
  else
    command("ClaudeCodeOpen" .. (args and (" " .. args) or ""))
  end
end

local function already(what)
  vim.notify("Claude Code is already running: " .. what, INFO, { title = "AI" })
end

-- These start a session with their arguments. One that is running already is
-- shown and left as it is: claudecode keeps one terminal, and its toggles
-- would drop the arguments and hide a shown panel instead.
function M.resume()
  if M.running() then
    M.reveal()
    return already("use /resume in it, or exit it first")
  end
  M.reveal("--resume")
end
function M.continue()
  if M.running() then
    M.reveal()
    return already("this is its session")
  end
  M.reveal("--continue")
end
-- What a cold start asks before it shows anything: claudecode's model
-- question, which can be cancelled. The slot hides nothing for it until the
-- terminal does show (lua/ai/init.lua, native_key).
M.asks_first = { select_model = true }

function M.select_model()
  if M.running() then
    M.reveal()
    -- Nothing is typed for it: "/model" would land after a half-typed prompt
    -- -- no command there -- and its Enter would submit that prompt, or answer
    -- a permission dialog the TUI is showing.
    return already("use /model in it")
  end
  command("ClaudeCodeSelectModel")
end

---Mention a file, as <leader>ab does for the current buffer: claudecode's
---public send_at_mention, which queues the mention while the TUI connects.
---Not :ClaudeCodeAdd, which splits its argument on whitespace and keeps the
---backslashes fnameescape adds, so "a repo/x.lua", "[id]/page.tsx" or
---"$post.tsx" never arrived. Warns when `modified`: Claude reads the saved
---file, as Codex does.
---@param path string
---@param modified boolean?
function M.add_path(path, modified)
  if vim.fn.filereadable(path) == 0 and vim.fn.isdirectory(path) == 0 then
    return vim.notify("Claude Code reads files from disk, and this one is not saved: " .. path, WARN, { title = "AI" })
  end
  if modified then
    vim.notify("Claude Code reads the saved file; this buffer has unsaved changes", WARN, { title = "AI" })
  end
  local ok, err = require("claudecode").send_at_mention(path, nil, nil, "ClaudeCodeAdd")
  if not ok then
    vim.notify("Claude Code did not take the file: " .. tostring(err), WARN, { title = "AI" })
  end
end

---Mention lines `l1`..`l2` (1-based) of `path`: what :ClaudeCodeSend makes of
---a selection, without needing that selection to be live -- the facade has
---captured it before asking where it goes (lua/ai/init.lua). claudecode's
---public send_at_mention, which queues the mention while the TUI is still
---connecting.
---@param path string
---@param l1 integer
---@param l2 integer
function M.send_range(path, l1, l2)
  local ok, err = require("claudecode").send_at_mention(path, l1 - 1, l2 - 1, "ClaudeCodeSend")
  if not ok then
    vim.notify("Claude Code did not take the selection: " .. tostring(err), vim.log.levels.WARN, { title = "AI" })
  end
end

---The panel's window, in whichever tabpage shows it; nil while hidden.
---@return integer|nil
function M.window()
  local term = panel()
  local win = term and term.win
  if not (win and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == term.buf) then return nil end
  -- claudecode parks a hidden float with `hide = true` instead of closing it.
  if vim.api.nvim_win_get_config(win).hide then return nil end
  return win
end

---Is the panel on screen in the current tabpage?
---@return boolean
function M.visible()
  local win = M.window()
  return win ~= nil and vim.api.nvim_win_get_tabpage(win) == vim.api.nvim_get_current_tabpage()
end

---Hide the panel in the current tabpage only. The job and its tmux client stay:
---claudecode patches the terminal's hide (terminal/snacks.lua `cc_hide`) to
---close the split and keep the buffer, the same path its own toggle takes.
function M.hide()
  local term = M.visible() and panel()
  if term then term:hide() end
end

---Feed staged images to the TUI through its own ctrl+v. Backs <C-v> in the
---prompt editor.
---@param paths string[]
function M.attach_images(paths)
  local terminal = require("claudecode.terminal")
  local bufnr = terminal.get_active_terminal_bufnr()
  local channel = bufnr
    and vim.api.nvim_buf_is_valid(bufnr)
    and vim.bo[bufnr].channel

  local function discard()
    for _, png in ipairs(paths) do vim.fn.delete(png) end
  end

  if not channel or channel <= 0 then
    vim.notify("Claude terminal is gone; images were not attached", vim.log.levels.WARN)
    discard()
    return
  end

  require("ai.clipboard").attach(channel, paths, discard)
end

---Ask the TUI to open its own prompt editor, seeding the input box first when
---`opts.seed` is given. Backs `<leader>ai`, and review feedback (ai.feed),
---which hears through the callbacks whether the seed reached a prompt.
---@param opts { seed?: string, on_consumed?: fun(), on_expired?: fun(), ttl_ms?: integer }?
function M.edit_prompt(opts)
  opts = opts or {}
  local terminal = require("claudecode.terminal")
  local editor = require("ai.editor")

  local function channel_of(bufnr)
    if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return nil end
    local channel = vim.bo[bufnr].channel
    return channel and channel > 0 and channel or nil
  end

  -- Sampled BEFORE ensure_visible, which starts the terminal when none exists.
  -- A freshly started job has a channel immediately, so checking afterwards
  -- would look "already running" and fire the key into a booting TUI.
  local running = channel_of(terminal.get_active_terminal_bufnr())

  editor.stage_seed(opts.seed, { agent = "claude", on_consumed = opts.on_consumed, on_expired = opts.on_expired, ttl_ms = opts.ttl_ms })

  -- Shown here already, in its own window or the copy of a diff tabpage: it
  -- stays as it is -- open() would put a second window beside a copy. A
  -- hidden session is shown through open(): ensure_visible counts any window
  -- on the terminal as shown, a copy in another tabpage too, and would open
  -- nothing here, where the slot just made room for it (lua/ai/slot.lua).
  if not M.window_here() then
    if M.running() and not M.window() then terminal.open() else terminal.ensure_visible() end
  end

  if running then
    vim.api.nvim_chan_send(running, editor.EDIT_KEY)
    return
  end

  -- Nothing was running, so the CLI is booting. Wait for its input box instead
  -- of firing a 0x07 it would swallow with nothing on screen to show for it.
  editor.when_ready(
    terminal.get_active_terminal_bufnr,
    function(buf)
      local ready = channel_of(buf)
      if ready then vim.api.nvim_chan_send(ready, editor.EDIT_KEY) end
    end,
    function()
      vim.notify(
        "Claude Code did not reach its prompt — press <leader>ai again",
        vim.log.levels.WARN
      )
    end
  )
end

return M
