-- Real independent hosts and PTYs; no AI CLI or network requests.
local t = dofile("tests/helper.lua")
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local plugin = root .. "/local-plugin/agent-workbench.nvim"
local python = vim.fn.exepath("python3")
t.ok(python ~= "", "Python is available for the offline PTY peer")
local snacks = require("lazy.core.config").plugins["snacks.nvim"].dir
for _, provider in ipairs({ "native", "snacks", "custom" }) do
  local tmp = vim.fn.tempname() .. " provider " .. provider
  vim.fn.mkdir(tmp, "p")
  local output = tmp .. "/result.json"
  local env = vim.fn.environ()
  env.AGENT_PLUGIN_DIR, env.AGENT_TEST_PROVIDER, env.AGENT_TEST_TMP = plugin, provider, tmp
  env.AGENT_TEST_PYTHON, env.AGENT_SNACKS_DIR, env.AGENT_TEST_OUTPUT = python, snacks, output
  env.CODEX_WRAP_TMUX, env.NVIM_AI_PLUGIN_DIR, env.NVIM = "0", "", nil
  local process = vim.system({ vim.v.progpath, "--headless", "-u", "NONE", "-i", "NONE", "-l", plugin .. "/tests/contract.lua" }, {
    text = true, env = env, clear_env = true,
  }):wait(15000)
  t.eq(process.code, 0, provider .. ": isolated contract host passes\n" .. (process.stderr or ""))
  if vim.fn.filereadable(output) == 1 then
    local report = vim.json.decode(table.concat(vim.fn.readfile(output), "\n"))
    t.ok(report.checks >= 25, provider .. ": process, view, identity and isolation contracts checked")
  end
  vim.fn.delete(tmp, "rf")
end
t.done()
