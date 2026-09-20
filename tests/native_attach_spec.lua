local t = dofile("tests/helper.lua")
local dap = require("dap")
local root = vim.fn.tempname() .. " native attach"
vim.fn.mkdir(root, "p")
root = vim.uv.fs_realpath(root)
local native = { '#include <stdio.h>', '#include <unistd.h>', 'int main(void) {', '  int value = 42;',
  '  for (;;) {', '    printf("%d\\n", value);', '    fflush(stdout);', '    usleep(100000);', '  }', '}' }
local cases = {
  { ft = "c", file = "main.c", compiler = "cc", source = native, line = 6 },
  { ft = "cpp", file = "main.cpp", compiler = "c++", source = native, line = 6 },
  { ft = "rust", file = "main.rs", compiler = "rustc", line = 4, source = {
    'fn main() {', '  let value = 42;', '  loop {', '    println!("{}", value);',
    '    std::thread::sleep(std::time::Duration::from_millis(100));', '  }', '}',
  } },
}
local select, pick = vim.ui.select, require("dap.utils").pick_process
for _, case in ipairs(cases) do
  if vim.fn.executable(case.compiler) == 0 or vim.fn.executable(vim.fn.stdpath("data") .. "/mason/bin/codelldb") == 0 then
    print("SKIP - native attach needs " .. case.compiler .. " and codelldb")
  else
    local source, binary = root .. "/" .. case.file, root .. "/" .. case.ft .. "-app"
    vim.fn.writefile(case.source, source)
    local command = case.ft == "rust" and { "rustc", "-g", "-C", "opt-level=0", source, "-o", binary }
      or { case.compiler, "-g", "-O0", source, "-o", binary }
    local compiled = vim.system(command, { text = true }):wait()
    t.eq(compiled.code, 0, case.ft .. ": fixture compiles with debug symbols")
    if compiled.code == 0 then
      local output = ""
      local process = vim.system({ binary }, { stdout = function(_, data) output = output .. (data or "") end })
      vim.cmd.edit(vim.fn.fnameescape(source))
      vim.api.nvim_win_set_cursor(0, { case.line, 0 })
      dap.set_breakpoint()
      require("dap.utils").pick_process = function() return process.pid end
      vim.ui.select = function(items, _, cb)
        cb(vim.iter(items):find(function(c) return c.name == case.ft .. ": attach to process" end))
      end
      vim.cmd.DapAttach()
      t.ok(vim.wait(20000, function()
        local frame = dap.session() and dap.session().current_frame
        return frame and frame.line == case.line and (frame.source or {}).path == source
      end, 50), case.ft .. ": attach command hits a source breakpoint")
      local session = dap.session()
      if session and session.current_frame then
        local result
        session:request("evaluate", { expression = "value", frameId = session.current_frame.id, context = "watch" },
          function(err, body) result = err or body end)
        vim.wait(5000, function() return result ~= nil end, 50)
        t.eq(result and result.result, "42", case.ft .. ": attached process exposes local variables")
        local before = #output
        require("util.dap").disconnect()
        t.ok(vim.wait(5000, function() return next(dap.sessions()) == nil and #output > before end, 50), case.ft .. ": detach resumes the externally started process")
      end
      local cleanup = t.process_cleanup()
      for _, active in pairs(dap.sessions()) do active:disconnect({ terminateDebuggee = true }) end
      vim.wait(3000, function() return next(dap.sessions()) == nil end, 50)
      for _, active in pairs(dap.sessions()) do active:close() end
      process:kill(15)
      process:wait(3000)
      cleanup()
      dap.clear_breakpoints()
    end
  end
end
vim.ui.select, require("dap.utils").pick_process = select, pick
for _, client in ipairs(vim.lsp.get_clients()) do client:stop(true) end
vim.fn.delete(root, "rf")
t.done()
