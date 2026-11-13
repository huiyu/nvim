-- Guards the agent panel's input rules (lua/ai/terminal.lua).
--
-- Both were silent losses rather than errors, which is why they survived so
-- long: a click inside the panel left Terminal-mode, so returning to the window
-- manager and clicking back put the panel in Normal mode; and a quick double
-- Esc -- the agents' own "go back a message" -- was eaten by Snacks and by the
-- global <Esc><Esc> before either agent could see it.
local t = dofile("tests/helper.lua")

local config = require("ai.config")
local ai_term = require("ai.terminal")

-- A stand-in for the real CLI: identity is decided by the command's basename,
-- so a script named after the provider is indistinguishable from the agent as
-- far as ai.config.is_native_command is concerned -- and it will not try to
-- reach the network or a real session.
local bin = vim.fn.tempname() .. "/" .. config.agents[config.agent_names()[1]].command
vim.fn.mkdir(vim.fn.fnamemodify(bin, ":h"), "p")
vim.fn.writefile({ "#!/bin/sh", "exec cat" }, bin)
vim.fn.setfperm(bin, "rwx------")

---@param cmd string[]
---@return integer buf
local function open_panel(cmd)
  local term = require("snacks").terminal.open(cmd, {
    auto_insert = true,
    start_insert = true,
    win = { position = "right", width = 0.4, keys = { term_normal = false } },
  })
  vim.wait(2000, function() return vim.bo[term.buf].buftype == "terminal" end)
  return term.buf
end

---tmux leaves its socket file behind when a server exits, so a spec that
---started one removes the file too, or every run adds one to /tmp/tmux-*/.
---@param socket string
local function remove_socket(socket)
  local dir = (vim.env.TMUX_TMPDIR and vim.env.TMUX_TMPDIR ~= "") and vim.env.TMUX_TMPDIR or "/tmp"
  for _, path in ipairs(vim.fn.glob(dir .. "/tmux-*/" .. socket, false, true)) do
    vim.fn.delete(path)
  end
end

---Is `lhs` mapped in Terminal-mode, and is that mapping buffer-local?
local function buffer_local(lhs)
  local m = vim.fn.maparg(lhs, "t", false, true)
  return next(m) ~= nil and m.buffer == 1
end

---The same question for Normal mode, where the scrollback forwarding lives.
local function buffer_local_n(lhs)
  local m = vim.fn.maparg(lhs, "n", false, true)
  return next(m) ~= nil and m.buffer == 1
end

-- Unwrapped panel: Nvim itself sees the click, so it needs the guard.
local plain = open_panel({ bin })
t.ok(ai_term.is_agent_buf(plain), "the fake agent reads as an agent buffer")
t.eq(vim.fn.maparg("<Esc>", "t", false, true).buffer, 1,
  "Esc is buffer-local on the panel, so it reaches the agent instead of <Esc><Esc>")
t.ok(buffer_local("<LeftMouse>"),
  "an unwrapped panel guards the mouse, so a click inside it keeps Terminal-mode")
t.ok(not buffer_local_n("<PageUp>"),
  "an unwrapped panel leaves scrolling to Nvim, which owns the scrollback there")

-- Leaving Terminal-mode still has two documented keys; only the Esc pair moved.
t.eq(vim.fn.maparg("jk", "t", false, true).buffer, 0, "jk still leaves Terminal-mode")
t.eq(vim.fn.maparg("<C-\\>", "t", false, true).buffer, 0, "<C-\\> still leaves Terminal-mode")

-- Wrapped panel: tmux turns mouse reporting on, Nvim forwards the click and
-- never leaves Terminal-mode on its own. Mapping there would take the click
-- away from tmux's copy-mode instead of fixing anything.
if vim.fn.executable("tmux") == 1 then
  local wrapped = open_panel({
    "tmux", "-f", "/dev/null", "-L", "nvim-spec-" .. vim.fn.getpid(),
    "set-option", "-g", "mouse", "on", ";",
    "new-session", "-A", "-s", "main", bin,
  })
  t.eq(vim.fn.maparg("<Esc>", "t", false, true).buffer, 1,
    "a wrapped panel still passes Esc through to the agent")
  t.ok(not buffer_local("<LeftMouse>"), "a wrapped panel leaves the mouse to tmux")
  -- Nvim's scrollback is one composed screenful when tmux owns the history, so
  -- a scroll from terminal-Normal mode has to go into the pane instead.
  for _, lhs in ipairs({ "<PageUp>", "<PageDown>", "<ScrollWheelUp>", "<C-u>", "<C-d>" }) do
    t.ok(buffer_local_n(lhs), "a wrapped panel forwards " .. lhs .. " into tmux history")
  end

  local socket = "nvim-spec-" .. vim.fn.getpid()
  local tmux = function(...)
    local command = { "tmux", "-L", socket }
    vim.list_extend(command, { ... })
    return vim.system(command, { text = true }):wait()
  end
  local pane_in_mode = function()
    return vim.trim(tmux("display-message", "-p", "-t", "main:", "#{pane_in_mode}").stdout or "")
  end

  -- The session answers before its pane does: on tmux 3.4 (CI) copy-mode
  -- failed and #{pane_in_mode} was empty for ~25 ms after #{session_name}
  -- was there. Wait for the pane, and the client, the next steps use.
  t.ok(vim.wait(2000, function()
    return pane_in_mode() == "0" and vim.trim(tmux("list-clients", "-t", "main").stdout or "") ~= ""
  end, 10), "the wrapped tmux server is ready")
  t.eq(tmux("copy-mode", "-u", "-t", "main:").code, 0,
    "the wrapped panel can enter tmux copy-mode")
  t.eq(pane_in_mode(), "1", "tmux reports that scrollback is active")
  vim.b[wrapped].ai_preserve_scrollback_once = true
  vim.api.nvim_exec_autocmds("TermEnter", { buffer = wrapped, modeline = false })
  t.eq(pane_in_mode(), "1", "the scroll-forwarding TermEnter preserves copy-mode once")
  vim.api.nvim_exec_autocmds("TermEnter", { buffer = wrapped, modeline = false })
  t.ok(vim.wait(1000, function() return pane_in_mode() == "0" end, 10),
    "manually resuming terminal input returns tmux to the live bottom")
  vim.fn.jobstop(vim.bo[wrapped].channel)
  -- jobstop only detaches the client; the server and its cat pane would
  -- outlive the run otherwise (39 of them had piled up under /tmp/tmux-*/).
  tmux("kill-server")
  remove_socket(socket)
end

-- The Claude wrapper is where mouse reporting is turned on for Claude.
-- Without it the pane's clicks are Nvim's to handle, which is the Normal-mode
-- surprise this spec exists for. Codex has always set it; the two must agree.
-- claudecode.nvim is declared whatever lua/ai/config.lua lists, with `opts` a
-- table built at startup, so its wrapper command is always checked here.
local claude_spec = require("lazy.core.config").spec.plugins["claudecode.nvim"]
t.ok(claude_spec ~= nil and type(claude_spec.opts) == "table" and type(claude_spec.opts.terminal_cmd) == "string",
  "claudecode.nvim is declared with a static opts.terminal_cmd")
do
  local spec = claude_spec
  local cmd = spec and spec.opts and spec.opts.terminal_cmd or ""
  local wraps = cmd:find("tmux", 1, true) ~= nil
  t.ok(not wraps or cmd:find("set-option -g mouse on", 1, true) ~= nil,
    "the Claude tmux wrapper enables the mouse, like the Codex one")
  -- Without these the forwarded PPage reaches Claude instead of tmux, and on
  -- the alternate screen tmux's default wheel handling walks Claude's input
  -- history rather than the transcript.
  t.ok(not wraps or cmd:find("bind-key -T root PPage copy-mode -eu", 1, true) ~= nil,
    "the Claude wrapper routes PPage into copy-mode, like the Codex one")
  t.ok(not wraps or cmd:find("bind-key -T root WheelUpPane copy-mode -e", 1, true) ~= nil,
    "the Claude wrapper routes the wheel into copy-mode, like the Codex one")
  -- `-e` without `-u`: entering copy-mode must not also jump a page, and the
  -- wheel steps 2 lines per event because Ghostty sends 3 per notch.
  t.ok(not wraps or cmd:find("bind-key -T root WheelUpPane copy-mode -eu", 1, true) == nil,
    "and does not page-jump on the first notch")
  t.ok(not wraps or cmd:find("bind-key -T copy-mode WheelUpPane send-keys -X -N 2 scroll-up", 1, true) ~= nil,
    "and slows the wheel to 2 lines per event")
  -- <S-CR> arrives as ESC[13;2u. tmux's default `extended-keys off` turns that
  -- into a bare CR, which submits the message instead of adding a newline.
  t.ok(not wraps or cmd:find("set-option -g extended-keys always", 1, true) ~= nil,
    "the Claude wrapper keeps modified Enter chords (extended-keys always)")
  t.ok(not wraps or cmd:find("set-option -g extended-keys-format csi-u", 1, true) ~= nil,
    "and emits them as CSI u, the form both TUIs parse")
end
if vim.fn.executable("tmux") == 1 then
  local joined = table.concat(require("ai.backend.codex")._terminal_command({ "codex" }), " ")
  t.ok(joined:find("set-option -g extended-keys always", 1, true) ~= nil,
    "the Codex wrapper keeps modified Enter chords (extended-keys always)")
  t.ok(joined:find("set-option -g extended-keys-format csi-u", 1, true) ~= nil,
    "and emits them as CSI u, which Codex parses (it ignores the xterm form)")
end

-- A failing agent must not take its own error message down with it. The tmux
-- wrapper's teardown reports success to nvim whatever the pane's command did,
-- so without the launcher a startup failure is indistinguishable from a clean
-- exit and Snacks just closes the panel.
local runner = require("ai.editor").runner()
t.eq(vim.fn.executable(runner), 1, "scripts/agent-run is present and executable")

-- The script itself: a clean exit passes straight through, a failure reports
-- the status and says why the panel is still there.
t.eq(vim.fn.system({ runner, "sh", "-c", "exit 0" }) == "" and vim.v.shell_error, 0,
  "a clean exit passes through untouched")
local failed = vim.fn.system({ runner, "sh", "-c", "echo boom; exit 7" })
t.eq(vim.v.shell_error, 7, "a failure keeps the agent's own exit status")
t.ok(failed:find("boom", 1, true) ~= nil, "and keeps the agent's own output")
t.ok(failed:find("exited with status 7", 1, true) ~= nil, "and names the status")

-- Both wrappers have to route the pane through it.
if vim.fn.executable("tmux") == 1 then
  local cmd = require("ai.backend.codex")._terminal_command({ "codex" })
  local at = vim.fn.index(cmd, runner)
  t.ok(at >= 0, "the Codex wrapper runs the pane through agent-run")
  t.eq(cmd[at + 2], "codex", "with the agent command right after it")
end
do
  local spec = claude_spec
  local cmd = spec and spec.opts and spec.opts.terminal_cmd or ""
  if cmd:find("tmux", 1, true) then
    t.ok(cmd:find(runner, 1, true) ~= nil, "the Claude wrapper runs the pane through agent-run")
  end
end

-- D7: a proposed Claude edit opens in a tabpage of its own, because CodeDiff's
-- panes never set 'diff' and claudecode would otherwise take one for the main
-- editor window. The Claude panel still comes along, for comparison.
do
  local diff_opts = claude_spec and claude_spec.opts and claude_spec.opts.diff_opts or {}
  t.eq(diff_opts.open_in_new_tab, true, "claudecode opens a proposed diff in a new tabpage")
  t.ok(diff_opts.hide_terminal_in_new_tab ~= true, "and keeps the Claude panel in that tabpage")
end

-- Claude starts where Codex does: the current file's Git root, the session
-- root every review round is filed under. claude_cwd = "cwd" hands the choice
-- back to claudecode, which then uses Nvim's working directory.
do
  local provider = claude_spec and claude_spec.opts and claude_spec.opts.terminal
    and claude_spec.opts.terminal.cwd_provider
  t.eq(type(provider), "function", "claudecode is given a cwd_provider")
  if type(provider) == "function" then
    local repo = vim.fn.tempname() .. "/repo"
    vim.fn.mkdir(repo .. "/.git", "p")
    vim.fn.mkdir(repo .. "/src", "p")
    local file = repo .. "/src/main.lua"
    t.eq(provider({ file = file, cwd = "/" }), config.project_root(file),
      "git_root (the default): the current file's Git root, by the same rule as Codex")
    t.eq(provider({ file = file, cwd = "/" }), repo, "which is the repository, not Nvim's directory")
    t.eq(provider({ cwd = "/" }), config.project_root(nil), "with no file, the working directory's root")
    local saved_review = vim.g.ai_review
    vim.g.ai_review = { claude_cwd = "cwd" }
    t.eq(provider({ file = file, cwd = "/" }), nil, "claude_cwd = \"cwd\": no answer, so Nvim's directory")
    vim.g.ai_review = saved_review
    vim.fn.delete(vim.fs.dirname(repo), "rf")
  end
end

-- Teardown. Quitting Nvim used to leave behind whatever the agent had spawned
-- into its own process group -- tmux only signals the pane's own process, and
-- the kernel's hangup only its session leader -- so a Codex exec_command dev
-- server outlived its Nvim by three days with ppid 1. The wrapper's
-- client-detached hook now runs scripts/agent-teardown, which records the
-- pane's process tree before the server goes and sweeps the survivors after.
-- destroy-unattached has to be off for that hook to run at all: with it on, the
-- server was gone before the hook fired (measured).
local editor = require("ai.editor")
local teardown = editor.teardown and editor.teardown() or ""
t.eq(vim.fn.executable(teardown), 1, "scripts/agent-teardown is present and executable")

if vim.fn.executable("tmux") == 1 then
  local cmd = require("ai.backend.codex")._terminal_command({ "codex" })
  local joined = table.concat(cmd, " ")
  t.ok(joined:find("destroy-unattached off", 1, true) ~= nil,
    "the Codex wrapper keeps the session until its client-detached hook has run")
  t.eq(cmd[#cmd - 1], "client-detached", "the Codex wrapper ends with the client-detached hook")
  t.ok(teardown ~= "" and cmd[#cmd]:find(teardown, 1, true) ~= nil
    and cmd[#cmd]:find("kill-server", 1, true) ~= nil,
    "and that hook runs agent-teardown, falling back to kill-server")
end
do
  local spec = claude_spec
  local cmd = spec and spec.opts and spec.opts.terminal_cmd or ""
  if cmd:find("tmux", 1, true) then
    t.ok(cmd:find("destroy-unattached off", 1, true) ~= nil,
      "the Claude wrapper keeps the session until its client-detached hook has run")
    local hook = cmd:match("client%-detached (.*)$") or ""
    t.ok(teardown ~= "" and hook:find(teardown, 1, true) ~= nil
      and hook:find("kill-server", 1, true) ~= nil,
      "and its client-detached hook runs agent-teardown, falling back to kill-server")
  end
end

-- The script itself, against a throwaway server shaped like a real pane: the
-- real launcher (agent-run) -> an agent stand-in -> the agent's children, two
-- of them in process groups of their own. One child is the leak shape (UC-1);
-- the other names an ignore-listed daemon and must be left alone (UC-R3). The
-- agent's argv -- and so the launcher's -- carries ignore-listed words too, as
-- a plugin path can, and that must not exempt the tree: the ignore list only
-- starts at the agent's children. The stand-in keeps its `&` list so no shell
-- exec-optimises a level away; agent-run never does, it checks the status.
if teardown ~= "" and vim.fn.executable("tmux") == 1 and vim.fn.executable("perl") == 1 then
  local sock = "nvim-spec-teardown-" .. vim.fn.getpid()
  local orphan = "nvim-spec-orphan-" .. vim.fn.getpid()
  local keep = "nvim-spec-crashpad_handler-" .. vim.fn.getpid()
  local children = table.concat({
    "perl -e 'setpgrp(0,0); sleep 300' " .. orphan .. " &",
    "perl -e 'setpgrp(0,0); sleep 300' " .. keep .. " &",
    "sleep 300",
  }, " ")
  local function alive(tag) return vim.fn.system({ "pgrep", "-f", tag }) ~= "" end
  vim.fn.system({ "tmux", "-f", "/dev/null", "-L", sock, "new-session", "-d", "-s", "main",
    runner, "sh", "-c", children, "--plugin-dir", "/x/gradle/emulator/" })
  vim.wait(2000, function() return alive(orphan) and alive(keep) end, 100)
  t.ok(alive(orphan) and alive(keep), "the stand-in tree is up before teardown")

  -- The default form returns at once and does the work detached (a hook's job
  -- dies with the server); --wait is the watchdog's synchronous form.
  vim.fn.system({ teardown, "--wait", sock })
  t.eq(vim.v.shell_error, 0, "agent-teardown --wait exits 0")
  vim.fn.system({ "tmux", "-L", sock, "list-sessions" })
  t.ok(vim.v.shell_error ~= 0, "the tmux server is gone")
  t.ok(not alive(orphan), "the own-process-group child went with it (UC-1)")
  t.ok(alive(keep), "an ignore-listed process under the pane was left alone (UC-R3)")
  vim.fn.system({ "pkill", "-f", keep })

  -- A server that is already gone is a no-op, not an error (UC-3).
  vim.fn.system({ teardown, sock })
  t.eq(vim.v.shell_error, 0, "agent-teardown on a dead server is a quiet no-op")
  remove_socket(sock)
end

-- Two agents at once. Both CLIs can be running in one Nvim, and every
-- per-buffer rule follows the buffer's own agent. Stand-ins are named after
-- each CLI, so identity is decided exactly as for the real ones, and nothing
-- reaches the network or a real session.
local agents_dir = vim.fn.tempname()
vim.fn.mkdir(agents_dir, "p")
for _, name in ipairs({ "claude", "codex" }) do
  vim.fn.writefile({ "#!/bin/sh", "exec cat" }, agents_dir .. "/" .. name)
  vim.fn.setfperm(agents_dir .. "/" .. name, "rwx------")
end
local Snacks = require("snacks")
local function panel(cmd)
  local term = Snacks.terminal.open(cmd, { win = { position = "right", width = 40, keys = { term_normal = false } } })
  vim.wait(2000, function() return vim.bo[term.buf].buftype == "terminal" end)
  vim.cmd("stopinsert")
  return term
end
local claude_term = panel({ agents_dir .. "/claude" })
local codex_probe = panel({ agents_dir .. "/codex" })
t.eq(ai_term.agent_of(claude_term.buf), "claude", "a Claude terminal is Claude's")
t.eq(ai_term.agent_of(codex_probe.buf), "codex", "a Codex terminal is Codex's")
t.ok(ai_term.is_agent_buf(claude_term.buf) and ai_term.is_agent_buf(codex_probe.buf),
  "both are agent buffers")
t.eq(vim.fn.maparg("<Esc>", "t", false, true).buffer, 1, "and both get the panel input rules")
vim.fn.jobstop(vim.bo[codex_probe.buf].channel)
pcall(vim.api.nvim_buf_delete, codex_probe.buf, { force = true })

-- One AI window per tabpage -- which panel yields to which, and when -- is
-- the AI slot's rule now, and tests/ai_slot_spec.lua drives it with these
-- same stand-ins through the real backends.

-- Neither agent panel carries Snacks' "<n>: <term title>" winbar: Claude's
-- through claudecode's snacks_win_opts, Codex's through its terminal opts,
-- opened here as a real Snacks terminal running `cat`.
t.eq(vim.tbl_get(claude_spec, "opts", "terminal", "snacks_win_opts", "wo", "winbar"), "",
  "the Claude panel has no winbar")
do
  local opts = require("ai.backend.codex")._terminal_opts(vim.fn.getcwd())
  t.eq(opts.win.wo.winbar, "", "the Codex panel asks for no winbar")
  local term = Snacks.terminal.open({ "cat" }, opts)
  t.ok(term and term:win_valid() and vim.wo[term.win].winbar == "",
    "and a split terminal opened with its options has none (" .. tostring(term and vim.wo[term.win].winbar) .. ")")
  local plain = Snacks.terminal.open({ "cat" }, { win = { position = "right" } })
  t.ok(plain and plain:win_valid() and vim.wo[plain.win].winbar ~= "",
    "while Snacks gives one to a split terminal by default (" .. tostring(plain and vim.wo[plain.win].winbar) .. ")")
  for _, tm in ipairs({ term, plain }) do
    if tm then
      pcall(vim.fn.jobstop, vim.bo[tm.buf].channel)
      pcall(function() tm:close() end)
    end
  end
end

-- lua/ai/backend/claude.lua drives claudecode through a few of its module
-- functions (AGENTS.md lists them with the other internals readers), which
-- tests/ai_slot_spec.lua stands in for so the plugin never loads. Pin them
-- against the pinned plugin's source -- read, not required: a require would
-- load claudecode.nvim, its WebSocket server and lockfile.
do
  local dir = require("lazy.core.config").plugins["claudecode.nvim"].dir
  local function source(rel)
    local ok, lines = pcall(vim.fn.readfile, dir .. "/lua/claudecode/" .. rel)
    return ok and table.concat(lines, "\n") or ""
  end
  local terminal, init = source("terminal.lua"), source("init.lua")
  for _, want in ipairs({
    { terminal, "function M.open(opts_override, cmd_args)" },
    { terminal, "function M.ensure_visible(" },
    { terminal, "function M.get_active_terminal_bufnr()" },
    { init, "function M.send_at_mention(file_path, start_line, end_line, context)" },
    { init, '"ClaudeCodeOpen"' },
  }) do
    t.ok(want[1]:find(want[2], 1, true) ~= nil, "claudecode still has " .. want[2])
  end
  t.ok(not require("lazy.core.config").plugins["claudecode.nvim"]._.loaded, "and reading it loaded nothing")
end

vim.fn.jobstop(vim.bo[claude_term.buf].channel)
pcall(vim.api.nvim_buf_delete, claude_term.buf, { force = true })
vim.fn.delete(agents_dir, "rf")

t.done()
