local t = dofile("tests/helper.lua")
local dap = require("dap")
local build, test
for _, config in ipairs(dap.configurations.rust or {}) do
  if config.name == "rust: cargo build" then build = config end
  if config.name == "rust: cargo test" then test = config end
end
t.ok(build and test, "Rust offers Cargo binary and test debugging")
if vim.fn.executable("cargo") == 0 then
  print("SKIP - Cargo integration needs the Rust toolchain")
  t.done()
  return
end
local root = vim.fn.tempname() .. " rust project"
vim.fn.mkdir(root .. "/src", "p")
vim.fn.mkdir(root .. "/.cargo", "p")
vim.fn.mkdir(root .. "/dependency/src", "p")
vim.fn.writefile({ '[package]', 'name = "dependency"', 'version = "0.1.0"' }, root .. "/dependency/Cargo.toml")
vim.fn.writefile({ "pub fn answer() -> i32 { 42 }" }, root .. "/dependency/src/lib.rs")
vim.fn.writefile({ '[package]', 'name = "dap_fixture"', 'version = "0.1.0"', 'edition = "2021"',
  '[dependencies]', 'dependency = { path = "dependency" }' }, root .. "/Cargo.toml")
vim.fn.writefile({ '[build]', 'target-dir = "custom target"' }, root .. "/.cargo/config.toml")
vim.fn.writefile({ 'fn main() {', '  let value = 42;', '  println!("{}", value);', '}',
  '#[test] fn works() { assert_eq!(2 + 2, 4); }' }, root .. "/src/main.rs")
vim.cmd.edit(vim.fn.fnameescape(root .. "/src/main.rs"))

-- Cargo answers in 0.1-2 s here. On CI the first `cargo test` of a runner
-- once took 30.4 s, past the old 30 s bound, while Nvim's loop ran normally
-- throughout: the build itself stalled, most likely on I/O. The bound only
-- catches a wedged build now, and a slow one prints what it was doing.
local function descendants(pid, out)
  out = out or {}
  for _, child in ipairs(vim.api.nvim_get_proc_children(pid)) do
    out[#out + 1] = child
    descendants(child, out)
  end
  return out
end
local function await(done, what)
  local started = vim.uv.now()
  if vim.wait(10000, done, 50) then return true end
  local pids = descendants(vim.fn.getpid())
  local ps = #pids == 0 and "(none)\n" or vim.system({ "ps", "-o", "pid,ppid,stat,etime,command", "-p",
    table.concat(pids, ",") }, { text = true }):wait().stdout
  print(("NOTE - %s: still waiting after 10 s; child processes:\n%s"):format(what, ps))
  local ok = vim.wait(110000, done, 50)
  print(("NOTE - %s: %s after %.1f s"):format(what, ok and "done" or "gave up", (vim.uv.now() - started) / 1000))
  return ok
end

local function resolve(config)
  local path
  local co = coroutine.create(function() path = coroutine.yield() end)
  coroutine.resume(co)
  local started, err = coroutine.resume(config.program(), co)
  if not started then print(("NOTE - %s did not start: %s"):format(config.name, tostring(err))) end
  t.ok(await(function() return path ~= nil end, config.name), config.name .. " finishes")
  t.ok(type(path) == "string" and vim.fn.executable(path) == 1, config.name .. " resolves an actual executable")
  t.ok(type(path) == "string" and path:find("custom target", 1, true), "Cargo custom target-dir and spaces are respected")
  return path
end
local binary = resolve(build)
local test_binary = resolve(test)
if type(binary) == "string" then
  t.eq(vim.system({ binary }, { text = true }):wait().stdout, "42\n", "selected binary runs")
end
if type(test_binary) == "string" then
  local result = vim.system({ test_binary, "--list" }, { text = true }):wait()
  t.ok(result.stdout:find("works: test", 1, true), "selected executable is the test harness")
end
local original_adapter, prepared = dap.adapters.codelldb
dap.adapters.codelldb = function(_, config) prepared = config end
local buffer = vim.api.nvim_get_current_buf()
dap.run(build)
vim.cmd.enew()
await(function() return prepared ~= nil end, "cargo build for dap.run")
t.eq(prepared and prepared.cwd, vim.uv.fs_realpath(root), "switching buffers during Cargo build preserves project cwd")
t.eq(prepared and prepared.program, binary, "buffer switch does not change the executable")
vim.api.nvim_set_current_buf(buffer)
dap.adapters.codelldb = original_adapter
-- Unified entries resolve module-qualified names and never run sibling files.
vim.fn.writefile({ 'fn main() { println!("42"); }', 'mod math;',
  '#[test] fn works() { assert_eq!(2 + 2, 4); }' }, root .. "/src/main.rs")
vim.fn.writefile({ '#[test]', 'fn same() {', '  let value = 42;', '  assert_eq!(value, 42);', '}',
  'mod nested { #[test] fn same() { assert!(true); } }', 'fn helper() {}' }, root .. "/src/math.rs")
vim.cmd.edit(vim.fn.fnameescape(root .. "/src/math.rs"))
local math_buffer = vim.api.nvim_get_current_buf()
vim.api.nvim_win_set_cursor(0, { 4, 0 })
local run, selected = dap.run
dap.run = function(config) selected = config end
vim.fn.maparg(" tM", "n", false, true).callback()
vim.cmd.enew()
t.ok(await(function() return selected ~= nil end, "nearest Rust test"), "nearest Rust test resolves after a buffer switch")
t.eq(selected and selected.args, { "--exact", "--nocapture", "math::same" }, "nearest Rust test uses its full module path")
t.eq(selected and selected.cwd, vim.uv.fs_realpath(root), "nearest test preserves project cwd")
if selected then
  local result = vim.system(vim.list_extend({ selected.program }, selected.args), { text = true }):wait()
  t.ok(result.stdout:find("1 passed; 0 failed; 0 ignored; 0 measured; 2 filtered out", 1, true), "real Rust harness runs exactly one test")
end
vim.api.nvim_set_current_buf(math_buffer)
selected = nil
vim.fn.maparg(" tF", "n", false, true).callback()
t.ok(await(function() return selected ~= nil end, "Rust test-file target"), "Rust test-file target resolves")
t.eq(selected and selected.args, { "--exact", "--nocapture", "math::nested::same", "math::same" }, "file target includes nested tests without the sibling file")
if selected then
  local result = vim.system(vim.list_extend({ selected.program }, selected.args), { text = true }):wait()
  t.ok(result.stdout:find("2 passed; 0 failed; 0 ignored; 0 measured; 1 filtered out", 1, true), "real Rust harness runs only tests in the selected file")
end
dap.run = run
if vim.fn.executable(vim.fn.stdpath("data") .. "/mason/bin/codelldb") == 1 then
  vim.api.nvim_win_set_cursor(0, { 4, 0 })
  dap.set_breakpoint()
  vim.fn.maparg(" tM", "n", false, true).callback()
  t.ok(vim.wait(20000, function() return dap.session() and dap.session().current_frame ~= nil end, 50), "unified nearest-test key stops inside the selected Rust test")
  local session = dap.session()
  if session and session.current_frame then
    local result
    session:request("evaluate", { expression = "value", frameId = session.current_frame.id, context = "watch" },
      function(err, body) result = err or body end)
    vim.wait(5000, function() return result ~= nil end, 50)
    t.eq(result and result.result, "42", "selected Rust test exposes its locals")
  end
  local cleanup = t.process_cleanup()
  for _, active in pairs(dap.sessions()) do active:disconnect({ terminateDebuggee = true }) end
  vim.wait(5000, function() return next(dap.sessions()) == nil end, 50)
  for _, active in pairs(dap.sessions()) do active:close() end
  cleanup()
end
vim.fn.writefile({ "not valid rust" }, root .. "/src/main.rs")
local failed
local co = coroutine.create(function() failed = coroutine.yield() end)
coroutine.resume(co)
coroutine.resume(build.program(), co)
await(function() return failed ~= nil end, "failing cargo build")
t.eq(failed, dap.ABORT, "build errors abort instead of launching a stale binary")
vim.fn.delete(root, "rf")
t.done()
