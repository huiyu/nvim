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
  local process = vim.system({ vim.v.progpath, "--headless", "-u", "NONE", "-i", "NONE", "-l", plugin .. "/tests/contract.lua" }, {
    text = true, env = { AGENT_PLUGIN_DIR = plugin, AGENT_TEST_PROVIDER = provider, AGENT_TEST_TMP = tmp,
      AGENT_TEST_PYTHON = python, AGENT_SNACKS_DIR = snacks, AGENT_TEST_OUTPUT = output,
      CODEX_WRAP_TMUX = "0", NVIM_AI_PLUGIN_DIR = "", NVIM = false },
  }):wait(15000)
  t.eq(process.code, 0, provider .. ": isolated contract host passes\n" .. (process.stderr or ""))
  if vim.fn.filereadable(output) == 1 then
    local report = vim.json.decode(table.concat(vim.fn.readfile(output), "\n"))
    t.ok(report.checks >= 25, provider .. ": process, view, identity and isolation contracts checked")
  end
  vim.fn.delete(tmp, "rf")
end
t.done()
