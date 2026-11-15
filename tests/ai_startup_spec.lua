-- Startup knobs resolve without starting a CLI or loading optional integrations.
local t = dofile("tests/helper.lua")
local tmp = vim.fn.tempname() .. " startup knobs"
vim.fn.mkdir(tmp, "p")
local script = tmp .. "/probe.lua"
local output = tmp .. "/report.json"
vim.fn.writefile({
  "vim.wait(120, function() return false end)",
  "local s = require('agent_workbench.state')",
  "local report = { key = s.key_setting(), auto = s.key.auto, agents = s.agent_names(), notes = _G.notes, sessions = require('agent_workbench').sessions(), companion = package.loaded.codecompanion ~= nil, claude = package.loaded.claudecode ~= nil }",
  "vim.fn.writefile({vim.json.encode(report)}, " .. string.format("%q", output) .. ")",
  "vim.cmd('cquit 0')",
}, script)
for _, case in ipairs({
  { name = "environment overrides global", env = "openai", global = "auto", expected = "openai" },
  { name = "global overrides configured auto", global = "openai", expected = "openai" },
  { name = "environment auto overrides global pin", env = "auto", global = "openai", expected = "auto" },
  { name = "empty environment behaves as unset", env = "", global = "openai", expected = "openai" },
  { name = "invalid profile falls back", env = "unknown-profile", expected = "auto", warning = true },
  { name = "deprecated default backend is ignored", provider = "claude", expected = "auto", warning = true },
}) do
  vim.fn.delete(output)
  local pre = "_G.notes = {}; vim.notify = function(message) table.insert(_G.notes, tostring(message)) end"
  if case.global then pre = pre .. "; vim.g.ai_key_profile = " .. string.format("%q", case.global) end
  local env = vim.fn.environ()
  env.NVIM_AI_KEY_PROFILE, env.NVIM_AI_PROVIDER, env.NVIM = case.env, case.provider, nil
  env.NVIM_AI_PLUGIN_DIR = ""
  local result = vim.system({ vim.v.progpath, "--headless", "-u", t.root .. "/init.lua", "-i", "NONE",
    "--cmd", "lua " .. pre, "-c", "luafile " .. vim.fn.fnameescape(script),
  }, { text = true, env = env, clear_env = true, cwd = t.root }):wait(10000)
  t.eq(result.code, 0, case.name .. ": startup succeeds " .. (result.stderr or ""))
  if vim.fn.filereadable(output) == 1 then
    local report = vim.json.decode(table.concat(vim.fn.readfile(output), "\n"))
    t.eq(report.key, case.expected, case.name .. ": profile precedence")
    t.eq(report.agents, { "codex" }, case.name .. ": native backend stays Codex only")
    t.ok(#report.sessions == 0 and not report.companion and not report.claude, case.name .. ": nothing starts")
    if case.warning then t.ok(#report.notes >= 1, case.name .. ": one actionable warning is available") end
  end
end
vim.fn.delete(tmp, "rf")
t.done()
