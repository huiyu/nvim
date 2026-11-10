-- Guards the agent panel's input rules (lua/ai/terminal.lua).
--
-- Both were silent losses rather than errors, which is why they survived so
-- long: a click inside the panel left Terminal-mode, so returning to the window
-- manager and clicking back put the panel in Normal mode; and a quick double
-- Esc -- the agents' own "go back a message" -- was eaten by Snacks and by the
-- global <Esc><Esc> before either agent could see it.
local t = dofile("tests/helper.lua")

local config = require("ai.config")
local util_term = require("util.terminal")

-- A stand-in for the real CLI: identity is decided by the command's basename,
-- so a script named after the provider is indistinguishable from the agent as
-- far as ai.config.is_native_command is concerned -- and it will not try to
-- reach the network or a real session.
local bin = vim.fn.tempname() .. "/" .. config.native.command
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
t.ok(util_term.is_agent_buf(plain), "the fake agent reads as an agent buffer")
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

-- The Claude wrapper is where mouse reporting is turned on for that provider.
-- Without it the pane's clicks are Nvim's to handle, which is the Normal-mode
-- surprise this spec exists for. Codex has always set it; the two must agree.
-- claudecode.nvim is declared under both providers, with `opts` a table built
-- at startup, so its wrapper command is checked whichever one this runs under.
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
if config.is("codex") and vim.fn.executable("tmux") == 1 then
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
if config.is("codex") and vim.fn.executable("tmux") == 1 then
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

-- The review hooks ride in the agent's own argv (lua/ai/review/hook.lua). They
-- must not move the agent word, which is how every panel rule identifies the
-- agent, nor the point where claudecode appends --resume / --continue.
-- tests/agent_hook_spec.lua runs both commands and checks the argv byte for
-- byte; this checks the shape of what is declared.
do
  local hook = require("ai.review.hook")
  local cmd = claude_spec and claude_spec.opts and claude_spec.opts.terminal_cmd or ""
  local settings = "--settings " .. vim.fn.shellescape(hook.claude_settings())
  t.eq(config.provider_of_command(cmd), "claude", "the Claude command with its hooks still reads as Claude")
  if cmd:find("tmux", 1, true) then
    -- Inside the wrapper's own `sh -c '...'`, so every quote is re-quoted.
    local inner = settings:gsub("'", "'\\''")
    local at = cmd:find(inner .. ' "$@"', 1, true)
    t.ok(at ~= nil and cmd:find(" claude ", 1, true) < at,
      "under tmux, --settings follows `claude` and precedes the appended \"$@\"")
  else
    t.ok(vim.endswith(cmd, " " .. settings), "unwrapped, --settings ends the command, so appended arguments follow it")
  end

  local codex_backend = require("ai.backend.codex")
  local codex_cmd = codex_backend._codex_command({ "resume" })
  t.eq(vim.list_slice(codex_cmd, 1, 5), { "codex", "--no-alt-screen", "--yolo", "-c", hook.codex_override() },
    "Codex keeps its flags and gets the hook override before its arguments")
  t.eq(codex_cmd[6], "resume", "and resume / resume --last still follow")
  if config.is("codex") and vim.fn.executable("tmux") == 1 then
    local saved_wrap = vim.env.CODEX_WRAP_TMUX
    vim.env.CODEX_WRAP_TMUX = "1"
    local wrapped = codex_backend._terminal_command(codex_cmd)
    vim.env.CODEX_WRAP_TMUX = saved_wrap
    local at = vim.fn.index(wrapped, runner)
    t.eq(vim.list_slice(wrapped, at + 2, at + 1 + #codex_cmd), codex_cmd,
      "the Codex wrapper hands the whole command to agent-run")
    t.eq(config.provider_of_command(wrapped), "codex", "and the wrapped command still reads as Codex")
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
-- back to claudecode, which then uses Nvim's working directory as before.
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
    t.eq(provider({ file = file, cwd = "/" }), nil, "claude_cwd = \"cwd\": no answer, so Nvim's directory as before")
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

if config.is("codex") and vim.fn.executable("tmux") == 1 then
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

-- Two agents at once. After :AI provider both CLIs can be running in one Nvim,
-- and every per-buffer rule follows the buffer's own agent, not the active
-- provider. Stand-ins named after each CLI, so identity is decided exactly as
-- for the real ones, and nothing reaches the network or a real session.
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
t.eq(util_term.agent_of(claude_term.buf), "claude", "a Claude terminal is Claude's")
t.eq(util_term.agent_of(codex_probe.buf), "codex", "a Codex terminal is Codex's")
t.ok(util_term.is_agent_buf(claude_term.buf) and util_term.is_agent_buf(codex_probe.buf),
  "both are agent buffers, whichever provider is active")
t.eq(vim.fn.maparg("<Esc>", "t", false, true).buffer, 1, "and both get the panel input rules")
vim.fn.jobstop(vim.bo[codex_probe.buf].channel)
pcall(vim.api.nvim_buf_delete, codex_probe.buf, { force = true })

-- One panel per tabpage. The real backends drive this: Codex through its own
-- Snacks terminal (unwrapped, from the stand-in on PATH), Claude through the
-- one claudecode.nvim would manage -- looked up from a stand-in of its module,
-- so the plugin itself, its WebSocket server and lockfile stay out of it.
local saved = { path = vim.env.PATH, wrap = vim.env.CODEX_WRAP_TMUX, provider = config.provider,
  cc = package.loaded["claudecode"], cc_terminal = package.loaded["claudecode.terminal"] }
vim.env.PATH = agents_dir .. ":" .. vim.env.PATH
vim.env.CODEX_WRAP_TMUX = "0"
package.loaded["claudecode"] = saved.cc or {}
package.loaded["claudecode.terminal"] = { get_active_terminal_bufnr = function() return claude_term.buf end }
local real_notify = vim.notify
vim.notify = function() end

local ai = require("ai")
local claude, codex = require("ai.backend.claude"), require("ai.backend.codex")
local function alive(term) return vim.fn.jobwait({ vim.bo[term.buf].channel }, 0)[1] == -1 end
local function shown_here(buf)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_buf(win) == buf then return true end
  end
  return false
end

if vim.fn.exepath("codex") ~= agents_dir .. "/codex" then
  t.ok(false, "codex resolves to the stand-in, so the single-slot checks never start the real CLI")
else
  require("ai.switch").provider("codex")
  t.ok(claude.visible() and not codex.running(), "start: the Claude panel is shown, Codex is not running")

  -- Revealing the active panel hides the other one in this tabpage.
  ai.toggle()
  local codex_buf = codex.window() and vim.api.nvim_win_get_buf(codex.window())
  t.ok(codex.visible(), "<leader>ac opens the Codex panel")
  t.ok(not shown_here(claude_term.buf), "and the Claude panel in this tabpage made room for it")
  t.ok(alive(claude_term), "hidden, not stopped: Claude's job is still running")

  -- The keys that feed the agent run for real here, into the stand-in. What
  -- they write to Codex's channel is recorded on the way through rather than
  -- read off its screen: the panels stacked by now leave that terminal a row
  -- or two, which keeps only the tail of a long line.
  local sample = vim.fn.tempname() .. "_feed.txt"
  vim.fn.writefile({ "fed to the agent" }, sample)
  local function edit_sample()
    local editor_win
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if vim.bo[vim.api.nvim_win_get_buf(win)].buftype == "" and vim.api.nvim_win_get_config(win).relative == "" then
        editor_win = win
        break
      end
    end
    if editor_win then vim.api.nvim_set_current_win(editor_win) else vim.cmd("topleft vnew") end
    vim.cmd("edit " .. vim.fn.fnameescape(sample))
  end
  local sent = {}
  local real_chan_send = vim.api.nvim_chan_send
  vim.api.nvim_chan_send = function(chan, data)
    if codex_buf and chan == vim.bo[codex_buf].channel then sent[#sent + 1] = data end
    return real_chan_send(chan, data)
  end
  local function delivered(text)
    return #vim.tbl_filter(function(data) return data:find(text, 1, true) ~= nil end, sent)
  end
  local function arrives(text, before)
    return vim.wait(2000, function() return delivered(text) > before end, 20)
  end

  -- Placed side by side by hand, neither hides the other -- not for a key that
  -- shows the active panel, nor for one that feeds it.
  claude_term:show()
  vim.cmd("stopinsert")
  ai.focus()
  t.ok(claude.visible() and codex.visible(), "with the active panel already shown, nothing yields")
  vim.cmd("stopinsert")
  edit_sample()
  local before = delivered(vim.fs.basename(sample))
  ai.add_buffer()
  t.ok(arrives(vim.fs.basename(sample), before), "<leader>ab writes the buffer to the shown panel")
  t.ok(claude.visible() and codex.visible(), "and rearranges nothing")

  -- A key that feeds the agent opens its panel to deliver, so it makes room
  -- like any other key that reveals it.
  for _, case in ipairs({
    { "<leader>ab", ai.add_buffer, vim.fs.basename(sample) },
    { "<leader>am", ai.select_model, "/model" },
  }) do
    codex.hide()
    claude_term:show()
    vim.cmd("stopinsert")
    edit_sample()
    t.ok(claude.visible() and not codex.visible(), case[1] .. ": only the Claude panel is shown")
    before = delivered(case[3])
    case[2]()
    t.ok(vim.wait(2000, codex.visible, 20), case[1] .. " opens the Codex panel to deliver")
    t.ok(not shown_here(claude_term.buf), case[1] .. ": the Claude panel in this tabpage made room for it")
    t.ok(alive(claude_term), case[1] .. ": hidden, not stopped")
    t.ok(arrives(case[3], before), case[1] .. ": and wrote to Codex")
    vim.cmd("stopinsert")
  end
  vim.api.nvim_chan_send = real_chan_send
  codex.hide()
  claude_term:show()
  vim.cmd("stopinsert")
  vim.fn.delete(sample)

  -- Another tabpage is left alone.
  local first_tab = vim.api.nvim_get_current_tabpage()
  vim.cmd("tabnew")
  ai.toggle()
  t.ok(codex.visible(), "<leader>ac opens Codex in a second tabpage")
  t.ok(claude.window() ~= nil and vim.api.nvim_win_get_tabpage(claude.window()) == first_tab,
    "while Claude stays shown in the first one")

  -- And the other way round: Claude active, Codex hidden here for it.
  require("ai.switch").provider("claude")
  vim.api.nvim_set_current_tabpage(first_tab)
  claude.hide()
  vim.cmd("tabnext")
  local real_toggle = claude.toggle
  -- claudecode's own toggle would start the real CLI; showing the stand-in's
  -- window is the part under test.
  claude.toggle = function() claude_term:show() end
  ai.toggle()
  claude.toggle = real_toggle
  t.ok(claude.visible() and not codex.visible(), "revealing Claude hides Codex in this tabpage")
  t.ok(codex_buf and vim.fn.jobwait({ vim.bo[codex_buf].channel }, 0)[1] == -1, "and Codex keeps running")

  -- Claude is shown in the second tabpage; Codex comes up in the first. A
  -- toggle there acts on Claude's window where it is and opens nothing in the
  -- first tabpage, so Codex has no reason to yield.
  vim.api.nvim_set_current_tabpage(first_tab)
  codex.focus()
  vim.cmd("stopinsert")
  claude.toggle = function() end
  ai.toggle()
  claude.toggle = real_toggle
  t.ok(codex.visible(), "a panel shown in another tabpage takes no room from this one")

  if codex_buf and vim.api.nvim_buf_is_valid(codex_buf) then
    vim.fn.jobstop(vim.bo[codex_buf].channel)
    pcall(vim.api.nvim_buf_delete, codex_buf, { force = true })
  end
  vim.cmd("silent! tabonly")
end

vim.fn.jobstop(vim.bo[claude_term.buf].channel)
pcall(vim.api.nvim_buf_delete, claude_term.buf, { force = true })
package.loaded["claudecode"], package.loaded["claudecode.terminal"] = saved.cc, saved.cc_terminal
vim.env.PATH, vim.env.CODEX_WRAP_TMUX = saved.path, saved.wrap
config.use_provider(saved.provider)
ai.apply_keymaps()
vim.notify = real_notify
vim.fn.delete(agents_dir, "rf")

t.done()
