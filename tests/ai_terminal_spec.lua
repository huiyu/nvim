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

  t.ok(vim.wait(2000, function()
    return tmux("display-message", "-p", "-t", "main:", "#{session_name}").code == 0
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
end

-- The Claude wrapper is where mouse reporting is turned on for that provider.
-- Without it the pane's clicks are Nvim's to handle, which is the Normal-mode
-- surprise this spec exists for. Codex has always set it; the two must agree.
if config.is("claude") then
  local spec = require("lazy.core.config").spec.plugins["claudecode.nvim"]
  local cmd = spec and spec.opts and spec.opts.terminal_cmd or ""
  local wraps = cmd:find("tmux", 1, true) ~= nil
  t.ok(not wraps or cmd:find("set-option -g mouse on", 1, true) ~= nil,
    "the Claude tmux wrapper enables the mouse, like the Codex one")
  -- Without these the forwarded PPage reaches Claude instead of tmux, and on
  -- the alternate screen tmux's default wheel handling walks Claude's input
  -- history rather than the transcript.
  t.ok(not wraps or cmd:find("bind-key -T root PPage copy-mode -eu", 1, true) ~= nil,
    "the Claude wrapper routes PPage into copy-mode, like the Codex one")
  t.ok(not wraps or cmd:find("bind-key -T root WheelUpPane copy-mode -eu", 1, true) ~= nil,
    "the Claude wrapper routes the wheel into copy-mode, like the Codex one")
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
if config.is("claude") then
  local spec = require("lazy.core.config").spec.plugins["claudecode.nvim"]
  local cmd = spec and spec.opts and spec.opts.terminal_cmd or ""
  if cmd:find("tmux", 1, true) then
    t.ok(cmd:find(runner, 1, true) ~= nil, "the Claude wrapper runs the pane through agent-run")
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
if config.is("claude") then
  local spec = require("lazy.core.config").spec.plugins["claudecode.nvim"]
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
end

t.done()
