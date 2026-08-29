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

t.done()
