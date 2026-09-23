-- Real jdtls initialization, project discovery, breakpoint and evaluation.
local t = dofile("tests/helper.lua")
local mason = vim.fn.stdpath("data") .. "/mason/packages/"
if vim.fn.isdirectory(mason .. "jdtls") == 0 or vim.fn.isdirectory(mason .. "java-debug-adapter") == 0
  or vim.fn.isdirectory(mason .. "java-test") == 0
  or vim.fn.executable("java") == 0 then
  print("SKIP - Java integration needs JDK 21+, jdtls, java-debug-adapter and java-test")
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
local client = vim.lsp.get_clients({ name = "jdtls", bufnr = main })[1]
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
for _, c in ipairs(vim.lsp.get_clients({ name = "jdtls" })) do c:stop(true) end
vim.fn.delete(root, "rf")
t.done()
