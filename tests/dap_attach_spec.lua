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
t.done()
