-- Guards the exit status run.sh reads: a spec whose assertions all passed must
-- exit 0, even when Nvim's teardown still writes to a pipe nobody reads.
--
-- Nvim resets SIGPIPE to its default action before the event loop's last
-- iteration, and some writes made during teardown are attempted only then.
-- One addressed to a process that has gone -- an LSP server a spec has just
-- stopped -- kills the spec's Nvim with SIGPIPE (status 141). sh prints
-- nothing for SIGPIPE, which is how run.sh came to report SPEC FAILURES while
-- every spec showed "assertions passed". helper.done() keeps the signal caught.
local t = dofile("tests/helper.lua")

-- Each probe runs in a child Nvim of its own: the exit status is the subject.
-- The peer closes its stdin and stays alive, so every write to it fails with
-- EPIPE. The check callback runs in the loop iterations of Nvim's teardown,
-- like the read that delivers a server's last message, and what it schedules
-- writes twice: the first failure is still queued when the second is made, so
-- that one is left for the loop's last iteration.
local PROBE = [[
local t = dofile("tests/helper.lua")
local ready = false
local peer = vim.system({ "sh", "-c", "exec 0<&-; echo ready; exec sleep 30" }, {
  stdin = true,
  stdout = function(_, data) if data and data:find("ready", 1, true) then ready = true end end,
})
io.stdout:write("peer=" .. peer.pid .. "\n")
vim.wait(5000, function() return ready end, 10)
local leaving = false
vim.api.nvim_create_autocmd("VimLeave", { callback = function() leaving = true end })
local check = vim.uv.new_check()
check:start(function()
  if not leaving then return end
  check:stop()
  vim.schedule(function()
    pcall(peer.write, peer, "first\n")
    pcall(peer.write, peer, "second\n")
  end)
end)
t.ok(ready, "the peer closed its stdin")
t.ok(%s, "the probe's own assertion")
%s
]]

local function run(passing, exit)
  local path = vim.fn.tempname() .. ".lua"
  vim.fn.writefile(vim.split(PROBE:format(tostring(passing), exit), "\n"), path)
  local result = vim.system({ vim.v.progpath, "--headless", "-u", "NONE", "-i", "NONE",
    "-c", "luafile " .. vim.fn.fnameescape(path) }, { text = true }):wait(20000)
  local pid = tonumber((result.stdout or ""):match("peer=(%d+)"))
  if pid then vim.uv.kill(pid, "sigkill") end
  vim.fn.delete(path)
  return result
end

-- Control: the same teardown without helper.done(). If Nvim stops resetting
-- SIGPIPE early this exits cleanly, and the guard in helper.done() can go.
local control = run(true, 'vim.cmd("cquit 0")')
t.eq(control.signal, 13, "control: a bare cquit 0 dies of SIGPIPE in this teardown")

local passed = run(true, "t.done()")
t.eq({ passed.code, passed.signal }, { 0, 0 }, "all assertions passed: the probe exits 0")
-- Headless print() goes to stderr.
t.ok((passed.stderr or ""):find("2 assertions passed", 1, true) ~= nil, "and says so")

local failed = run(false, "t.done()")
t.eq({ failed.code, failed.signal }, { 1, 0 }, "a failed assertion still exits 1, not 141")
t.ok((failed.stderr or ""):find("1 of 2 assertions failed", 1, true) ~= nil, "and says so")

t.done()
