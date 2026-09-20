local t = dofile("tests/helper.lua")
t.eq(package.loaded.dap, nil, "target mappings keep DAP lazy at startup")
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
key("td")
t.eq(launched and launched.args, { "run", "--no-file-parallelism", path .. ":2" }, "nearest Vitest uses the containing declaration")
vim.api.nvim_win_set_cursor(0, { 6, 0 })
key("td")
t.eq(launched and launched.args[3], path .. ":5", "parameterized Vitest selects the outer test.each call")
vim.api.nvim_win_set_cursor(0, { 1, 0 })
key("td")
t.eq(launched, nil, "Vitest suite scope does not widen nearest-test debugging")
key("tF")
t.eq(launched and launched.args[3], path, "test-file entry selects only this Vitest file")
key("df")
t.eq(launched and launched.program, path, "file entry runs the current Node script")
vim.fn.writefile({ '{"version":"2.0.0"}' }, root .. "/node_modules/vitest/package.json")
vim.api.nvim_win_set_cursor(0, { 3, 0 })
key("td")
t.eq(launched, nil, "old Vitest cannot silently ignore a line filter")

vim.fn.writefile({ "name: fixture" }, root .. "/pubspec.yaml")
edit("scope_test.dart", {
  "void main() {", "  group('outer', () {", "    test('same name', () {",
  "      expect(42, 42);", "    });", "  });", "}",
})
path = vim.api.nvim_buf_get_name(0)
vim.api.nvim_win_set_cursor(0, { 4, 0 })
key("td")
t.eq(launched and { launched.type, launched.program }, { "dart_test", path .. "?line=3" }, "Dart uses native line selection in nested groups")
key("tF")
t.eq(launched and launched.program, path, "Dart file debugging omits the line filter")
vim.fn.writefile({ "name: fixture", "dependencies:", "  flutter:", "    sdk: flutter" }, root .. "/pubspec.yaml")
key("td")
t.eq(launched and launched.type, "flutter_test", "Flutter SDK dependency selects the Flutter test adapter")
key("df")
t.eq(launched and { launched.type, launched.program }, { "flutter", path }, "Flutter file entry keeps the selected file")
vim.api.nvim_win_set_cursor(0, { 2, 0 })
key("td")
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
key("td")
t.eq(launched, nil, "unsupported language does not fall back to another adapter")
dap.run = run
local cleanup = t.process_cleanup()
for _, client in ipairs(vim.lsp.get_clients()) do client:stop(true) end
cleanup()
vim.fn.delete(root, "rf")
t.done()
