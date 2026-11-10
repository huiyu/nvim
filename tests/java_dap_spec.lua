-- Real jdtls initialization, project discovery, breakpoint and evaluation.
local t = dofile("tests/helper.lua")
local mason = vim.fn.stdpath("data") .. "/mason/packages/"
if vim.fn.isdirectory(mason .. "jdtls") == 0 or vim.fn.isdirectory(mason .. "java-debug-adapter") == 0
  or vim.fn.isdirectory(mason .. "java-test") == 0
  or vim.fn.executable("java") == 0 then
  print("SKIP - Java integration needs JDK 25+, jdtls, java-debug-adapter and java-test")
  t.done()
  return
end
local root = vim.fn.tempname() .. " java project"
vim.fn.mkdir(root .. "/src", "p")
vim.fn.mkdir(root .. "/.git", "p")
vim.fn.writefile({
  "public class Main {", "  public static void main(String[] args) {",
  "    int value = 42;", "    System.out.println(value);", "  }", "}",
}, root .. "/src/Main.java")
vim.fn.writefile({ "class Other {}" }, root .. "/src/Other.java")
vim.cmd.edit(vim.fn.fnameescape(root .. "/src/Main.java"))
local main = vim.api.nvim_get_current_buf()
local dap = require("dap")
t.ok(vim.wait(45000, function() return dap.adapters.java ~= nil end, 100), "jdtls registers Java adapter after attaching")
-- jdtls's first start on a fresh configuration area (every CI job) can come
-- up without the debug bundle's commands, and then never lists them:
-- lua/lang/java.lua restarts it once. Take the client that has them, a
-- restarted one included; the first may already be stopping.
local first = vim.lsp.get_clients({ name = "jdtls", bufnr = main })[1]
local client
t.ok(vim.wait(120000, function()
  for _, c in ipairs(vim.lsp.get_clients({ name = "jdtls", bufnr = main })) do
    local commands = vim.tbl_get(c.server_capabilities or {}, "executeCommandProvider", "commands") or {}
    if not c:is_stopped() and vim.tbl_contains(commands, "vscode.java.resolveMainClass") then
      client = c
      return true
    end
  end
end, 100), "jdtls offers the debug bundle's commands, after one restart at most")
if client and first and client.id ~= first.id then
  print("NOTE - jdtls was restarted: its first start missed the bundle commands")
end
-- The restart on the real server, forced: show on_init this client as a
-- first start that lost the bundle commands would look. Everything below
-- then runs on the restarted client, so it has to come back complete.
if client then
  local lost = client
  local provider = lost.server_capabilities.executeCommandProvider
  provider.commands = vim.tbl_filter(function(c) return not c:find("^vscode%.java%.") end, provider.commands)
  lost.config.on_init(lost)
  client = nil
  t.ok(vim.wait(120000, function()
    for _, c in ipairs(vim.lsp.get_clients({ name = "jdtls", bufnr = main })) do
      local commands = vim.tbl_get(c.server_capabilities or {}, "executeCommandProvider", "commands") or {}
      if c.id ~= lost.id and not c:is_stopped() and vim.tbl_contains(commands, "vscode.java.resolveMainClass") then
        client = c
        return true
      end
    end
  end, 100), "a jdtls missing the bundle commands is restarted, and comes back with them")
  t.eq(vim.lsp.get_client_by_id(lost.id), nil, "the incomplete client is gone")
  t.ok(vim.wait(10000, function() return dap.adapters.java ~= nil end, 100), "the restarted client sets up debugging again")
end
if client then
  t.ok(dap.providers.configs.jdtls ~= nil, "main class discovery stays dynamic per project")
  local bundles = client.config.init_options.bundles
  t.ok(vim.iter(bundles):any(function(path) return path:find("junit-platform-commons", 1, true) end), "JUnit extension dependencies are loaded")
  t.ok(not vim.iter(bundles):any(function(path) return path:find("jacocoagent.jar", 1, true) end), "non-OSGi agent is excluded")
  vim.cmd.edit(vim.fn.fnameescape(root .. "/src/Other.java"))
  t.ok(vim.wait(5000, function() return vim.lsp.buf_is_attached(0, client.id) end, 50), "second Java buffer attaches to the same server")
  t.ok(vim.fn.maparg(",dt", "n", false, true).buffer == 1, "Java test debug key is buffer-local")
  vim.api.nvim_set_current_buf(main)
  local configs
  require("jdtls.dap").fetch_main_configs({}, function(value) configs = value end)
  t.ok(vim.wait(30000, function() return configs ~= nil end, 100), "jdtls discovers main classes")
  t.ok(configs and #configs > 0, "project offers an executable main class")
  if configs and configs[1] then
    vim.api.nvim_win_set_cursor(0, { 4, 0 })
    dap.set_breakpoint()
    -- Internal console makes the integration test independent of terminal UI.
    local run = dap.run
    dap.run = function(config, opts)
      config.console = "internalConsole"
      return run(config, opts)
    end
    vim.fn.maparg(" df", "n", false, true).callback()
    t.ok(vim.wait(30000, function() return dap.session() and dap.session().current_frame ~= nil end, 100), "Java stops on the source breakpoint")
    local session = dap.session()
    if session and session.current_frame then
      local result
      session:request("evaluate", { expression = "value", frameId = session.current_frame.id, context = "watch" },
        function(err, body) result = err or body end)
      vim.wait(5000, function() return result ~= nil end, 50)
      t.eq(result and result.result, "42", "Java evaluates a stopped local variable")
    end
  end
end
for _, session in pairs(dap.sessions()) do session:disconnect({ terminateDebuggee = true }) end
vim.wait(5000, function() return next(dap.sessions()) == nil end, 50)
if client then
  dap.clear_breakpoints()
  local java = client.config.cmd[1]
  local javac = vim.fs.dirname(java) .. "/javac"
  local built = vim.system({ javac, "-g", "-d", root .. "/out", root .. "/src/Main.java" }, { text = true }):wait()
  t.eq(built.code, 0, "standalone Java attach target compiles")
  if built.code == 0 then
    local socket = vim.uv.new_tcp()
    socket:bind("127.0.0.1", 0)
    local port = socket:getsockname().port
    socket:close()
    local output = ""
    local process = vim.system({ java,
      "-agentlib:jdwp=transport=dt_socket,server=y,suspend=y,address=127.0.0.1:" .. port,
      "-cp", root .. "/out", "Main" }, { stdout = function(_, data) output = output .. (data or "") end })
    t.ok(vim.wait(5000, function() return output:find("Listening for transport", 1, true) ~= nil end, 50), "JDWP target waits for attachment")
    vim.api.nvim_set_current_buf(main)
    vim.api.nvim_win_set_cursor(0, { 4, 0 })
    dap.set_breakpoint()
    -- Attaching from a class without main must not invoke launch enrichment.
    vim.cmd.edit(vim.fn.fnameescape(root .. "/src/Other.java"))
    local input, select = vim.fn.input, vim.ui.select
    vim.fn.input = function(opts) return opts.prompt:find("port") and tostring(port) or "127.0.0.1" end
    vim.ui.select = function(items, _, cb)
      cb(vim.iter(items):find(function(c) return c.name == "java: attach to JDWP" end))
    end
    vim.cmd.DapAttach()
    t.ok(vim.wait(20000, function() return dap.session() and dap.session().current_frame ~= nil end, 50), "JDWP attach from a non-main source hits the breakpoint")
    vim.fn.input, vim.ui.select = input, select
    local session = dap.session()
    if session and session.current_frame then
      local result
      session:request("evaluate", { expression = "value", frameId = session.current_frame.id, context = "watch" },
        function(err, body) result = err or body end)
      vim.wait(5000, function() return result ~= nil end, 50)
      t.eq(result and result.result, "42", "JDWP attach evaluates the target's local variable")
      require("util.dap").disconnect()
      t.ok(vim.wait(5000, function() return output:find("42", 1, true) ~= nil end, 50), "JDWP disconnect resumes the standalone application")
    end
    local cleanup = t.process_cleanup()
    for _, active in pairs(dap.sessions()) do active:disconnect({ terminateDebuggee = true }) end
    vim.wait(3000, function() return next(dap.sessions()) == nil end, 50)
    for _, active in pairs(dap.sessions()) do active:close() end
    process:kill(15)
    process:wait(3000)
    cleanup()
  end
end
-- The restart, driven with stand-ins for a client whose initialize response
-- lacked the bundle commands, so it is pinned without waiting for the race.
local on_init = client and client.config.on_init
t.ok(type(on_init) == "function", "the jdtls config checks the commands it came up with")
if type(on_init) == "function" then
  local notes, stops = {}, 0
  local notify = vim.notify
  -- Only the restart's own words: the JDWP cleanup above stopped the real
  -- jdtls, and Nvim reports that exit whenever it gets to it.
  vim.notify = function(msg, level)
    msg = tostring(msg)
    if msg:find("^jdtls came up") or msg:find("^jdtls started again") then
      notes[#notes + 1] = { msg = msg, level = level }
    end
  end
  local function stand_in(commands)
    return {
      id = -1, attached_buffers = {}, config = client.config,
      server_capabilities = { executeCommandProvider = { commands = commands } },
      stop = function() stops = stops + 1 end,
    }
  end
  local complete = { "vscode.java.startDebugSession", "vscode.java.test.findJavaProjects" }
  on_init(stand_in({ "java.edit.organizeImports" }))
  vim.wait(1000, function() return stops == 1 end, 10)
  t.eq(stops, 1, "a jdtls that came up without the bundle commands is restarted")
  t.ok(notes[1] and notes[1].level == vim.log.levels.INFO and notes[1].msg:find("restarting it", 1, true) ~= nil,
    "with a word")
  on_init(stand_in({ "vscode.java.startDebugSession" }))
  vim.wait(300, function() return stops > 1 end, 10)
  t.eq(stops, 1, "a second miss for that root is not restarted again")
  t.ok(notes[2] and notes[2].level == vim.log.levels.WARN and notes[2].msg:find("vscode.java.test.findJavaProjects", 1, true)
    and notes[2].msg:find(":JdtRestart", 1, true), "it names what is missing and what to do")
  on_init(stand_in(complete))
  t.eq(#notes, 2, "a complete start says nothing")
  on_init(stand_in({}))
  vim.wait(1000, function() return stops == 2 end, 10)
  t.eq(stops, 2, "and lets a later miss restart again")
  vim.notify = notify
end
for _, c in ipairs(vim.lsp.get_clients({ name = "jdtls" })) do c:stop(true) end
vim.fn.delete(root, "rf")
t.done()
