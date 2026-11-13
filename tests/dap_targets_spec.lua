local t = dofile("tests/helper.lua")
local dap = require("dap")
local util = require("util.dap")
local root = vim.fn.tempname() .. " debug targets"
vim.fn.mkdir(root .. "/node_modules/vitest", "p")
vim.fn.writefile({ '{"version":"4.0.0"}' }, root .. "/node_modules/vitest/package.json")
vim.fn.writefile({}, root .. "/node_modules/vitest/vitest.mjs")
vim.fn.writefile({ '{}' }, root .. "/package.json")
local run, launched = dap.run
dap.run = function(config) launched = config end
local function edit(name, lines)
  vim.fn.writefile(lines, root .. "/" .. name)
  vim.cmd.edit(vim.fn.fnameescape(root .. "/" .. name))
  -- Mapping-triggered writes should run the real save hooks, but avoid an
  -- unrelated formatter changing the fixture's deliberately fixed positions.
  vim.b.autoformat = false
end
local function key(suffix)
  launched = nil
  vim.fn.maparg(" " .. suffix, "n", false, true).callback()
end
edit("scope.test.ts", {
  "describe('outer', () => {",
  "  test('same name', () => {",
  "    expect(42).toBe(42);",
  "  });",
  "  test.each([1, 2])('other %s', (n) => {",
  "    expect(n).toBeGreaterThan(0);",
  "  });",
  "});",
})
local path = vim.api.nvim_buf_get_name(0)
vim.api.nvim_win_set_cursor(0, { 3, 0 })
key("tM")
t.eq(launched and launched.args, { "run", "--no-file-parallelism", path .. ":2" }, "nearest Vitest uses the containing declaration")
vim.api.nvim_win_set_cursor(0, { 6, 0 })
key("tM")
t.eq(launched and launched.args[3], path .. ":5", "parameterized Vitest selects the outer test.each call")
vim.api.nvim_win_set_cursor(0, { 1, 0 })
key("tM")
t.eq(launched, nil, "Vitest suite scope does not widen nearest-test debugging")
key("tF")
t.eq(launched and launched.args[3], path, "test-file entry selects only this Vitest file")
key("df")
t.eq(launched and launched.program, path, "file entry runs the current Node script")
vim.fn.writefile({ '{"version":"2.0.0"}' }, root .. "/node_modules/vitest/package.json")
vim.api.nvim_win_set_cursor(0, { 3, 0 })
key("tM")
t.eq(launched, nil, "old Vitest cannot silently ignore a line filter")

vim.fn.writefile({ "name: fixture" }, root .. "/pubspec.yaml")
edit("scope_test.dart", {
  "void main() {", "  group('outer', () {", "    test('same name', () {",
  "      expect(42, 42);", "    });", "  });", "}",
})
path = vim.api.nvim_buf_get_name(0)
vim.api.nvim_win_set_cursor(0, { 4, 0 })
key("tM")
t.eq(launched and { launched.type, launched.program }, { "dart_test", path .. "?line=3" }, "Dart uses native line selection in nested groups")
key("tF")
t.eq(launched and launched.program, path, "Dart file debugging omits the line filter")
vim.fn.writefile({ "name: fixture", "dependencies:", "  flutter:", "    sdk: flutter" }, root .. "/pubspec.yaml")
key("tM")
t.eq(launched and launched.type, "flutter_test", "Flutter SDK dependency selects the Flutter test adapter")
key("df")
t.eq(launched and { launched.type, launched.program }, { "flutter", path }, "Flutter file entry keeps the selected file")
vim.api.nvim_win_set_cursor(0, { 2, 0 })
key("tM")
t.eq(launched, nil, "Dart group scope does not run the entire suite")

-- Save failures must not launch stale source, and unknown/special buffers must
-- not accidentally fall through to the previous language's target.
local called, context
util.targets.dart.file = function(ctx) called = true; context = ctx end
vim.api.nvim_buf_set_lines(0, 3, 4, false, { "      expect(43, 43);" })
key("df")
t.ok(called and vim.fn.readfile(path)[4]:find("43", 1, true), "entry saves edits before dispatch")
t.eq(context.path, path, "context carries an absolute buffer path")
called = false
vim.bo.readonly = true
vim.api.nvim_buf_set_lines(0, 3, 4, false, { "      expect(44, 44);" })
key("df")
t.eq(called, false, "failed save aborts dispatch")
vim.bo.readonly = false
vim.bo.modified = false
vim.cmd.enew()
vim.bo.filetype = "dart"
key("df")
t.eq(called, false, "unnamed buffer cannot launch the previous file")
vim.bo.filetype = "text"
key("tM")
t.eq(launched, nil, "unsupported language does not fall back to another adapter")

-- The same unified keys reach the real neotest Go and Python adapters, in a
-- project of their own. This
-- dap.run stub also runs neotest's `after`, or its dap strategy would still be
-- waiting on tM's session when tF starts; the final `dap.run = run` restores
-- the real one.
local neotest_root = vim.fn.tempname() .. " neotest targets"
vim.fn.mkdir(neotest_root, "p")
neotest_root = vim.uv.fs_realpath(neotest_root)
vim.fn.writefile({ "module example.com/targets", "go 1.23" }, neotest_root .. "/go.mod")
vim.fn.writefile({ "package targets", 'import "testing"', "func TestFirst(t *testing.T) {",
  "  t.Log(42)", "}", "func TestSecond(t *testing.T) { t.Log(84) }" }, neotest_root .. "/sample_test.go")
vim.fn.writefile({ "[tool.pytest.ini_options]" }, neotest_root .. "/pyproject.toml")
vim.fn.writefile({ "import unittest", "class Sample(unittest.TestCase):", "    def test_first(self):",
  "        self.assertEqual(42, 42)", "    def test_second(self):", "        self.assertEqual(84, 84)" }, neotest_root .. "/test_sample.py")
local captured
dap.run = function(config, opts)
  captured = config
  -- Exercise discovery/adapter construction without launching processes here.
  if opts and opts.after then vim.schedule(opts.after) end
end
local function invoke(suffix)
  captured = nil
  vim.fn.maparg(" " .. suffix, "n", false, true).callback()
  return vim.wait(15000, function() return captured ~= nil end, 20)
end
for _, case in ipairs({ { "sample_test.go", 4, "TestFirst", "TestSecond" }, { "test_sample.py", 4, "test_first", "test_second" } }) do
  vim.cmd.edit(vim.fn.fnameescape(neotest_root .. "/" .. case[1]))
  vim.api.nvim_win_set_cursor(0, { case[2], 0 })
  t.ok(invoke("tM"), case[1] .. ": unified nearest key reaches the real neotest adapter")
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
vim.fn.delete(neotest_root, "rf")
t.done()
