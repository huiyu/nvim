local t = dofile("tests/helper.lua")
local dap = require("dap")
require("lazy").load({ plugins = { "nvim-dap-go" } })
local remote
for _, config in ipairs(dap.configurations.go or {}) do
  if config.type == "go_remote" then remote = config end
end
t.ok(remote ~= nil, "Go offers remote attachment alongside local debugging")
local input = vim.ui.input
local responses = { "127.0.0.1", "38697" }
vim.ui.input = function(_, cb) cb(table.remove(responses, 1)) end
local adapter
dap.adapters.go_remote(function(value) adapter = value end)
t.eq({ type = adapter.type, host = adapter.host, port = adapter.port, executable = adapter.executable },
  { type = "server", host = "127.0.0.1", port = 38697 }, "remote attach connects without spawning Delve")
dap.adapters.go_remote(function(value) adapter = value end, { host = "localhost", port = 45678 })
t.eq({ adapter.host, adapter.port }, { "localhost", 45678 }, "Go launch.json endpoint overrides do not prompt or get ignored")
local prepared = false
adapter.options.before_disconnect({
  stopped_thread_id = 1,
  request_with_timeout = function(_, _, _, _, cb) cb("cannot resume") end,
}, function() prepared = true end)
t.eq(prepared, false, "failed remote preparation keeps the debug connection open")
adapter = nil
responses = { "127.0.0.1", "not a port" }
dap.adapters.go_remote(function(value) adapter = value end)
t.eq(adapter, nil, "invalid remote port does not connect")
vim.ui.input = function(_, cb) cb(nil) end
dap.adapters.go_remote(function(value) adapter = value end)
t.eq(adapter, nil, "cancelled remote attach does not connect")
vim.ui.input = input

local root = vim.fn.tempname() .. " dart project"
vim.fn.mkdir(root .. "/.fvm/flutter_sdk/bin", "p")
vim.fn.writefile({ "name: fixture" }, root .. "/pubspec.yaml")
for _, tool in ipairs({ "dart", "flutter" }) do
  local path = root .. "/.fvm/flutter_sdk/bin/" .. tool
  vim.fn.writefile({ "#!/bin/sh", "exit 0" }, path)
  vim.fn.setfperm(path, "rwx------")
end
vim.cmd.edit(vim.fn.fnameescape(root .. "/main.dart"))
for _, kind in ipairs({ "dart", "dart_test", "flutter", "flutter_test" }) do
  local resolved
  dap.adapters[kind](function(value) resolved = value end, { cwd = root })
  t.ok(resolved and resolved.command:find(".fvm/flutter_sdk/bin/", 1, true), kind .. " prefers project FVM SDK")
  t.eq(resolved.args, kind:find("test") and { "debug_adapter", "--test" } or { "debug_adapter" }, kind .. " invokes official SDK adapter")
end
t.eq(#dap.configurations.dart, 6, "Dart/Flutter provide CLI/app attach alongside launch and tests")
t.eq(dap.configurations.dart[1].program(), vim.api.nvim_buf_get_name(0), "Dart launch uses the same canonical path as breakpoints")
local session, request = dap.session
dap.session = function() return {
  config = { type = "flutter" },
  request = function(_, method, _, callback) request = method; callback(nil) end,
} end
vim.fn.maparg(",dr", "n", false, true).callback()
t.eq(request, "hotReload", "Dart buffer's reload mapping calls the SDK request")
vim.fn.maparg(",dR", "n", false, true).callback()
t.eq(request, "hotRestart", "Dart buffer's restart mapping calls the SDK request")
dap.session = session

local main, renderer
for _, config in ipairs(dap.configurations.typescript) do
  if config.name == "electron: main + renderer" then main = config end
  if config.name == "electron: attach renderer (port 9222)" then renderer = config end
end
t.ok(main and renderer, "Electron offers combined launch and standalone renderer attach")
local run, launched = dap.run
dap.run = function(config) launched = config end
dap.listeners.after.launch.electron_renderer({ config = { __electron_renderer = true, cwd = root } })
t.eq(launched and launched.type, "pwa-chrome", "successful Electron main launch starts renderer attach")
t.eq(launched and launched.webRoot, root, "renderer retains main project's root after buffer focus changes")
launched = nil
dap.listeners.after.launch.electron_renderer({ config = { __electron_renderer = true, cwd = root } }, "failed")
t.eq(launched, nil, "failed main launch does not start a renderer")
dap.run = run
vim.fn.delete(root, "rf")
t.done()
