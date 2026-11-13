local t = dofile("tests/helper.lua")
t.eq(package.loaded.dap, nil, "attach command and key keep DAP lazy")
t.eq(vim.fn.exists(":DapAttach"), 2, "attach command is discoverable before loading DAP")
local select, offered, callback = vim.ui.select
vim.ui.select = function(items, _, cb) offered, callback = items, cb end
vim.cmd.DapAttach()
local dap = require("dap")
require("lazy").load({ plugins = { "nvim-dap-python", "nvim-dap-go" } })
for _, ft in ipairs({ "c", "cpp", "rust", "java", "python", "go", "dart", "javascript", "javascriptreact", "typescript", "typescriptreact" }) do
  local configs = vim.tbl_filter(function(c) return c.request == "attach" end, dap.configurations[ft] or {})
  t.ok(#configs > 0, ft .. " has a preconfigured attach target")
end

-- Go remote attachment, Dart/FVM adapters and the Electron renderer listener.
-- nvim-dap-go is already loaded above.
local dart_root = vim.fn.tempname() .. " dart project"
do
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

  local root = dart_root
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
end

-- DAP adapter and configuration registration, asserted against the real
-- config.
--
-- mason-nvim-dap only installs packages for the handlers it is given; it ships
-- no adapter definition for js-debug (`mappings/adapters/` has bash, chrome,
-- codelldb, node2, python … but no `js.lua`). A `handlers = { ["js"] = {} }`
-- entry therefore downloads the binary and registers nothing, which is silent:
-- `<leader>dc` simply offers no configuration on a TypeScript buffer. These
-- assertions are what makes that failure loud; the attach loop above already
-- requires a configuration for every filetype vtsls attaches to.
do
  -- An adapter that runs a Mason package is only registered, and only
  -- startable, once Mason has installed that package. A fresh machine (CI)
  -- installs them in the background while the specs run, so there the checks
  -- that need one say SKIP instead, as native_attach_spec does.
  local registry = require("mason-registry")
  local function skip_without(pkg, what)
    if registry.is_installed(pkg) then return false end
    print(("SKIP - %s needs Mason's %s, not installed yet"):format(what, pkg))
    return true
  end

  -- UC-2: one js-debug binary serves both runtimes; the launch config picks which.
  for _, name in ipairs({ "pwa-node", "pwa-chrome" }) do
    t.ok(dap.adapters[name] ~= nil, "js-debug adapter registered: " .. name)
  end

  -- The vitest entry is the one that has to resolve a binary inside the project,
  -- so assert its shape rather than only its presence.
  local vitest
  for _, config in ipairs(dap.configurations.typescript or {}) do
    if config.name:lower():find("vitest", 1, true) then vitest = config end
  end
  t.ok(vitest ~= nil, "typescript offers a vitest configuration")
  if vitest then
    t.eq(vitest.type, "pwa-node", "vitest runs on the node runtime, not the browser one")
    -- Vitest isolates test files in worker threads by default; a breakpoint set in
    -- the editor never binds there, so the flag is part of the contract.
    local args = type(vitest.args) == "table" and table.concat(vitest.args, " ") or ""
    t.ok(args:find("--no-file-parallelism", 1, true) ~= nil,
      "vitest configuration disables file parallelism so breakpoints bind")
  end

  -- A missing install must report one line and abort. Raising instead would
  -- surface as an E5108 block with a stack traceback for what is really
  -- "install your dependencies" -- the same refusal-reporting rule the rest of
  -- this config follows.
  if vitest and type(vitest.program) == "function" then
    local warned
    local real_notify = vim.notify
    vim.notify = function(msg, level) warned = { msg = msg, level = level } end
    local previous = vim.api.nvim_get_current_buf()
    -- A path with no node_modules anywhere above it.
    vim.cmd("edit " .. vim.fn.tempname() .. "/no-vitest-here/file.ts")
    local ok, result = pcall(vitest.program)
    vim.cmd("buffer " .. previous)
    vim.notify = real_notify

    t.ok(ok, "a missing vitest does not raise")
    t.eq(result, dap.ABORT, "a missing vitest aborts the session")
    t.ok(warned ~= nil and warned.msg:find("vitest", 1, true) ~= nil,
      "a missing vitest is reported to the user")
    t.ok(warned == nil or warned.msg:find("stack traceback") == nil,
      "the report is one line, not a traceback")
  end

  -- Chrome extension debugging needs vscode-js-debug#2361, which upstream closed
  -- as out-of-scope, so mason's build cannot do it. A locally installed fork build
  -- takes precedence when present; either way the adapter must point at a file
  -- that exists, or sessions fail with an opaque spawn error.
  local chrome = dap.adapters["pwa-chrome"]
  t.ok(type(chrome) == "table" and type(chrome.executable) == "table",
    "pwa-chrome adapter declares an executable")
  if chrome and chrome.executable then
    -- Either an absolute path (mason's binary) or a PATH lookup (`node` running
    -- the fork's bundle). Both must be startable, or a session dies on spawn with
    -- nothing useful to read.
    local command = chrome.executable.command
    local from_mason = type(command) == "string" and command:find("/mason/", 1, true) ~= nil
    if not (from_mason and skip_without("js-debug-adapter", "starting the pwa-chrome adapter")) then
      t.ok(command ~= nil and (vim.fn.executable(command) == 1 or vim.uv.fs_stat(command) ~= nil),
        "the adapter command is startable: " .. tostring(command))
      -- Whatever runs it, the bundle it is pointed at has to be on disk.
      for _, arg in ipairs(chrome.executable.args or {}) do
        if arg:match("%.js$") then
          t.ok(vim.uv.fs_stat(arg) ~= nil, "the adapter bundle exists: " .. arg)
        end
      end
    end
  end

  -- The extension configuration carries extensionPath and nothing else about
  -- paths: the fork derives the extension id, target filter and sourcemap mapping
  -- from it, so a hand-set webRoot here would be noise at best.
  local extension
  for _, config in ipairs(dap.configurations.typescript or {}) do
    if config.name:lower():find("extension", 1, true) then extension = config end
  end
  t.ok(extension ~= nil, "typescript offers a Chrome extension configuration")
  if extension then
    t.eq(extension.type, "pwa-chrome", "extension debugging runs on the browser runtime")
    -- A function, not a literal: ${workspaceFolder} is the editor's cwd, which in
    -- a monorepo is the repository root, not the package holding the extension.
    t.eq(type(extension.extensionPath), "function",
      "extensionPath is resolved from the buffer, not relative to the cwd")
    t.ok(extension.webRoot == nil, "it does not hand-set webRoot -- the fork derives paths")
  end

  -- Both directions are offered: launch for the one-key loop, attach for a browser
  -- that is already running (a real session, a specific profile).
  local requests = {}
  for _, config in ipairs(dap.configurations.typescript or {}) do
    if config.name:lower():find("extension", 1, true) then requests[config.request] = config end
  end
  t.ok(requests.launch ~= nil, "extension debugging offers a launch configuration")
  t.ok(requests.attach ~= nil, "extension debugging offers an attach configuration")
  if requests.launch then
    -- Launch starts a browser, so it must own the profile it starts it with:
    -- sharing one across concurrent sessions corrupts browser storage.
    t.ok(requests.launch.userDataDir ~= nil, "the launch configuration pins its own user data dir")
  end

  -- UC-R1: Go, Python and C register their adapters through their own plugins.
  -- Adding the js entries must not disturb them.
  for _, adapter in ipairs({ { "delve", "delve" }, { "python", "debugpy" }, { "codelldb", "codelldb" } }) do
    local name, pkg = adapter[1], adapter[2]
    if not skip_without(pkg, "the " .. name .. " adapter") then
      t.ok(dap.adapters[name] ~= nil, "pre-existing adapter still registered: " .. name)
    end
  end
end

local root = vim.fn.tempname() .. " attach project"
vim.fn.mkdir(root .. "/.vscode", "p")
vim.fn.writefile({ '{ "version": "0.2.0", "configurations": [',
  '// project attach must participate in the same picker',
  '{"name":"project attach","type":"pwa-node","request":"attach","port":12345},',
  '{"name":"project launch","type":"pwa-node","request":"launch","program":"app.js"}', ']}',
}, root .. "/.vscode/launch.json")
vim.cmd.edit(vim.fn.fnameescape(root .. "/app.js"))
vim.cmd.lcd(vim.fn.fnameescape(root))
local run, launched, options = dap.run
dap.run = function(config, opts) launched, options = config, opts end
vim.cmd.DapAttach()
t.ok(offered and #offered > 1, "command offers built-in and project attach choices")
t.ok(vim.iter(offered):all(function(c) return c.request == "attach" end), "attach picker excludes every launch target")
local project = vim.iter(offered):find(function(c) return c.name == "project attach" end)
t.ok(project and project.port == 12345, "JSONC project attach configuration is usable")
callback(project)
t.eq(launched and launched.port, 12345, "selected project connection reaches DAP")
t.eq(options, { new = true, filetype = "javascript" }, "attach always starts a new session without continuing another one")
launched = nil
vim.fn.maparg(" dA", "n", false, true).callback()
callback(nil)
t.eq(launched, nil, "cancelling attach makes no connection")
vim.cmd.DapAttach()
vim.cmd.enew()
callback(project)
t.eq(launched, nil, "a source-buffer switch cannot attach with the wrong context")

local input = vim.fn.input
local util = require("util.dap")
for _, value in ipairs({ "0", "65536", "42.5", "not a port", "" }) do
  vim.fn.input = function() return value end
  t.eq(util.port(5005), dap.ABORT, "invalid/empty attach port aborts: " .. value)
end
vim.fn.input = function() error("cancelled") end
t.eq(util.input("Host: ", "127.0.0.1"), dap.ABORT, "cancelled attach prompt aborts")
vim.fn.input = function() return " 5005 " end
t.eq(util.port(5005), 5005, "port parser returns a validated number")
local dart = vim.iter(dap.configurations.dart):find(function(c) return c.name == "dart: attach to VM service" end)
vim.fn.input = function() return "http://127.0.0.1:8181/secret=/" end
t.eq(dart.vmServiceUri(), "http://127.0.0.1:8181/secret=/", "Dart attach preserves the service URI token")
vim.fn.input = function() return "8181" end
t.eq(dart.vmServiceUri(), dap.ABORT, "Dart refuses a port in place of a service URI")
vim.fn.input = function() return "" end
t.eq(dart.vmServiceUri(), dap.ABORT, "Dart attach requires a URI")
vim.fn.input, vim.ui.select, dap.run = input, select, run
vim.cmd.lcd(vim.fn.fnameescape(vim.fn.stdpath("config")))
vim.fn.delete(root, "rf")
vim.fn.delete(dart_root, "rf")
t.done()
