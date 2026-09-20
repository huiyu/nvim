local t = dofile("tests/helper.lua")
local dap = require("dap")
local root = vim.fn.tempname() .. " neotest targets"
vim.fn.mkdir(root, "p")
root = vim.uv.fs_realpath(root)
vim.fn.writefile({ "module example.com/targets", "go 1.23" }, root .. "/go.mod")
vim.fn.writefile({ "package targets", 'import "testing"', "func TestFirst(t *testing.T) {",
  "  t.Log(42)", "}", "func TestSecond(t *testing.T) { t.Log(84) }" }, root .. "/sample_test.go")
vim.fn.writefile({ "[tool.pytest.ini_options]" }, root .. "/pyproject.toml")
vim.fn.writefile({ "import unittest", "class Sample(unittest.TestCase):", "    def test_first(self):",
  "        self.assertEqual(42, 42)", "    def test_second(self):", "        self.assertEqual(84, 84)" }, root .. "/test_sample.py")
local run, captured = dap.run
dap.run = function(config, opts)
  captured = config
  -- Exercise discovery/adapter construction without launching processes here.
  if opts and opts.after then vim.schedule(opts.after) end
end
local function invoke(key)
  captured = nil
  vim.fn.maparg(" " .. key, "n", false, true).callback()
  return vim.wait(15000, function() return captured ~= nil end, 20)
end
for _, case in ipairs({ { "sample_test.go", 4, "TestFirst", "TestSecond" }, { "test_sample.py", 4, "test_first", "test_second" } }) do
  vim.cmd.edit(vim.fn.fnameescape(root .. "/" .. case[1]))
  vim.api.nvim_win_set_cursor(0, { case[2], 0 })
  t.ok(invoke("td"), case[1] .. ": unified nearest key reaches the real neotest adapter")
  local nearest = vim.inspect(captured and captured.args)
  t.ok(nearest:find(case[3], 1, true) and not nearest:find(case[4], 1, true), case[1] .. ": nearest filter excludes sibling test")
  t.ok(invoke("tF"), case[1] .. ": unified file key reaches the real neotest adapter")
  local all = vim.inspect(captured and captured.args)
  if case[1]:match("%.go$") then
    t.ok(all:find(case[3], 1, true) and all:find(case[4], 1, true), "Go file filter includes both tests")
    t.ok(vim.iter(dap.configurations.go):any(function(c) return c.type == "go_remote" end), "neotest's dap-go setup preserves remote attachment")
  else
    t.ok(all:find("test_sample.py", 1, true) and not all:find("::", 1, true), "Python file target has no method selector")
  end
end
dap.run = run
local cleanup = t.process_cleanup()
for _, client in ipairs(vim.lsp.get_clients()) do client:stop(true) end
cleanup()
vim.fn.delete(root, "rf")
t.done()
