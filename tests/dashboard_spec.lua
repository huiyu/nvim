local t = dofile("tests/helper.lua")

-- Exercise the actual dashboard commands under a PTY, as Snacks runs them.
-- The fake gh makes network failures deterministic and checks that the inner
-- process cannot probe the dashboard terminal or prompt for authentication.
local fixture = vim.fn.tempname() .. " gh's bin"
vim.fn.mkdir(fixture, "p")
vim.fn.writefile({
  "#!/bin/sh",
  'if [ -t 0 ] || [ -t 1 ] || [ -n "$GH_FORCE_TTY" ] || [ "$GH_PROMPT_DISABLED" != 1 ]; then',
  '  printf "unexpected interactive gh\\n"; exit 8',
  "fi",
  'if [ "$NVIM_DASHBOARD_GH_TEST" = fail ]; then',
  '  printf "Get https://api.github.com/: EOF\\n" >&2; exit 1',
  "fi",
  'printf "GitHub fixture rows\\n"',
  'printf "%s\\n" "$@"',
}, fixture .. "/gh")
vim.fn.setfperm(fixture .. "/gh", "rwx------")

local commands = {}
for _, section in ipairs(Snacks.config.get("dashboard", {}).sections) do
  if type(section) == "function" then
    for _, item in ipairs(section() or {}) do
      if type(item.cmd) == "table" and item.cmd[4] == "dashboard-gh" then
        commands[#commands + 1] = item
      end
    end
  end
end
t.eq(#commands, 3, "all three GitHub dashboard sections use the guarded command")

local errors = {}
local original_debug_cmd = Snacks.debug.cmd
Snacks.debug.cmd = function(opts) errors[#errors + 1] = opts end
for _, item in ipairs(commands) do
  for _, outcome in ipairs({ "success", "fail" }) do
    local buf = vim.api.nvim_create_buf(false, true)
    local exit_code
    local job = require("snacks.util.job").new(buf, item.cmd, {
      term = true,
      env = {
        PATH = fixture .. ":" .. vim.env.PATH,
        GH_FORCE_TTY = "1",
        NVIM_DASHBOARD_GH_TEST = outcome,
      },
      on_exit = function(_, code) exit_code = code end,
    })
    t.ok(vim.wait(3000, function() return exit_code ~= nil end, 10),
      item.title .. " finishes on " .. outcome)
    t.eq(exit_code, 0, item.title .. " renders " .. outcome .. " without a job failure")
    local output = table.concat(job.lines, "\n")
    t.ok(not output:find("unexpected interactive gh", 1, true),
      item.title .. " runs gh without terminal detection or prompts")
    if outcome == "fail" then
      t.ok(output:find("GitHub unavailable", 1, true) and output:find("EOF", 1, true),
        item.title .. " displays both the unavailable state and the original error")
    else
      t.ok(output:find("GitHub fixture rows", 1, true) ~= nil,
        item.title .. " preserves successful output")
    end
    job:stop()
    vim.api.nvim_buf_delete(buf, { force = true })
  end
end
Snacks.debug.cmd = original_debug_cmd
t.eq(#errors, 0, "dashboard GitHub failures never emit a Snacks job-error popup")
vim.fn.delete(fixture, "rf")
t.done()
