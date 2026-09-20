local t = dofile("tests/helper.lua")
local dlv = vim.fn.exepath("dlv")
if dlv == "" then dlv = vim.fn.stdpath("data") .. "/mason/bin/dlv" end
if vim.fn.executable("go") == 0 or vim.fn.executable(dlv) == 0 then
  print("SKIP - Go remote integration needs go and Delve")
  t.done()
  return
end
local root = vim.fn.tempname() .. " go remote"
vim.fn.mkdir(root, "p")
vim.fn.writefile({ "module fixture", "go 1.22" }, root .. "/go.mod")
vim.fn.writefile({ 'package main', 'import ("os"; "strconv"; "time")',
  'func main() {', ' os.WriteFile("pid", []byte(strconv.Itoa(os.Getpid())), 0600)',
  ' for value := 42; ; value++ {', '  os.WriteFile("heartbeat", []byte(strconv.Itoa(value)), 0600)',
  '  time.Sleep(100 * time.Millisecond)', ' }', '}' }, root .. "/main.go")
local built = vim.system({ "go", "build", "-gcflags=all=-N -l", "-o", root .. "/fixture", "." },
  { cwd = root, text = true }):wait()
t.eq(built.code, 0, "build Go remote fixture")
if built.code ~= 0 then print(built.stderr); vim.fn.delete(root, "rf"); t.done(); return end
local socket = vim.uv.new_tcp()
socket:bind("127.0.0.1", 0)
local port = socket:getsockname().port
socket:close()
local server = vim.system({ dlv, "exec", root .. "/fixture", "--headless", "--listen=127.0.0.1:" .. port,
  "--api-version=2", "--accept-multiclient" }, { cwd = root, text = true })
vim.cmd.edit(vim.fn.fnameescape(root .. "/main.go"))
local dap = require("dap")
require("lazy").load({ plugins = { "nvim-dap-go" } })
vim.api.nvim_win_set_cursor(0, { 6, 0 })
dap.set_breakpoint()
local config
for _, c in ipairs(dap.configurations.go) do if c.type == "go_remote" then config = vim.deepcopy(c) end end
local input = vim.ui.input
vim.ui.input = function(opts, cb) cb(opts.prompt:find("host") and "127.0.0.1" or tostring(port)) end
-- Wait until Delve is listening, without starting a second server.
local ready = false
vim.wait(15000, function()
  if ready then return true end
  local probe = vim.uv.new_tcp()
  probe:connect("127.0.0.1", port, function(err) ready = not err; probe:close() end)
  return false
end, 100)
dap.run(config)
t.ok(vim.wait(20000, function() return dap.session() and dap.session().current_frame ~= nil end, 50), "remote Delve stops at source breakpoint")
vim.ui.input = input
local session = dap.session()
if session and session.current_frame then
  local result
  session:request("evaluate", { expression = "value", frameId = session.current_frame.id, context = "watch" },
    function(err, body) result = err or body end)
  vim.wait(5000, function() return result ~= nil end, 50)
  t.eq(result and result.result, "42", "remote Go variable is readable")
  local bufnr = vim.api.nvim_get_current_buf()
  local breakpoints = vim.deepcopy(require("dap.breakpoints").get(bufnr)[bufnr])
  vim.fn.maparg("<Space>dD", "n", false, true).callback()
  vim.wait(5000, function() return next(dap.sessions()) == nil end, 50)
  t.ok(vim.wait(5000, function()
    if vim.fn.filereadable(root .. "/heartbeat") ~= 1 then return false end
    return (tonumber(vim.fn.readfile(root .. "/heartbeat")[1]) or 0) > 42
  end, 100), "disconnect leaves the remote target running")
  t.eq(require("dap.breakpoints").get(bufnr)[bufnr], breakpoints, "disconnect preserves local breakpoints for reattachment")
end
local cleanup = t.process_cleanup()
for _, active in pairs(dap.sessions()) do active:disconnect({ terminateDebuggee = true }) end
vim.wait(3000, function() return next(dap.sessions()) == nil end, 50)
for _, active in pairs(dap.sessions()) do active:close() end
-- The target was deliberately detached; clean up only this fixture's PID.
if vim.fn.filereadable(root .. "/pid") == 1 then
  local pid = tonumber(vim.fn.readfile(root .. "/pid")[1])
  if pid then vim.uv.kill(pid, "sigterm") end
end
server:kill(15)
server:wait(5000)
for _, c in ipairs(vim.lsp.get_clients({ name = "gopls" })) do c:stop(true) end
cleanup()
vim.fn.delete(root, "rf")
t.done()
