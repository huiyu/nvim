-- DAP adapter and configuration registration, asserted against the real config.
--
-- mason-nvim-dap only installs packages for the handlers it is given; it ships
-- no adapter definition for js-debug (`mappings/adapters/` has bash, chrome,
-- codelldb, node2, python … but no `js.lua`). A `handlers = { ["js"] = {} }`
-- entry therefore downloads the binary and registers nothing, which is silent:
-- `<leader>dc` simply offers no configuration on a TypeScript buffer. These
-- assertions are what makes that failure loud.
local t = dofile("tests/helper.lua")

-- `require` is what pulls a lazy-loaded plugin in, so the adapters below are
-- whatever the shipped config actually registers -- not a stripped-down setup.
local dap = require("dap")

-- UC-2: one js-debug binary serves both runtimes; the launch config picks which.
for _, name in ipairs({ "pwa-node", "pwa-chrome" }) do
  t.ok(dap.adapters[name] ~= nil, "js-debug adapter registered: " .. name)
end

-- UC-2: without configurations `<leader>dc` has nothing to offer. Every
-- filetype vtsls attaches to needs an entry, not just the two base languages.
for _, ft in ipairs({ "javascript", "javascriptreact", "typescript", "typescriptreact" }) do
  local configs = dap.configurations[ft]
  t.ok(configs ~= nil and #configs > 0, "debug configurations present for " .. ft)
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
  t.ok(command ~= nil and (vim.fn.executable(command) == 1 or vim.uv.fs_stat(command) ~= nil),
    "the adapter command is startable: " .. tostring(command))
  -- Whatever runs it, the bundle it is pointed at has to be on disk.
  for _, arg in ipairs(chrome.executable.args or {}) do
    if arg:match("%.js$") then
      t.ok(vim.uv.fs_stat(arg) ~= nil, "the adapter bundle exists: " .. arg)
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
  t.ok(extension.extensionPath ~= nil, "the extension configuration carries extensionPath")
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
for _, name in ipairs({ "delve", "python", "codelldb" }) do
  t.ok(dap.adapters[name] ~= nil, "pre-existing adapter still registered: " .. name)
end

t.done()
