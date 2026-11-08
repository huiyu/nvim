-- refactoring.nvim broke twice without a startup error: an update removed the
-- refactor() entry point every mapping called, and on Nvim 0.12 its fallback
-- `require("async")` resolved to promise-async, which nvim-ufo loads on the
-- first file read (lua/plugin/editor/refactoring.lua). So this spec reads a
-- real file first, the order a session has, and drives each refactor through
-- its mapped key, asserting the text that comes out.
local t = dofile("tests/helper.lua")
local Config = require("lazy.core.config")

local function loaded(name)
  local plugin = Config.plugins[name]
  return plugin ~= nil and plugin._.loaded ~= nil
end

if vim.fn.has("nvim-0.12.5") == 0 then
  t.eq(vim.fn.maparg(",ex", "x"), "", "below Nvim 0.12.5 the refactor keys are absent, not broken")
  t.done()
  return
end

require("lazy").load({ plugins = { "which-key.nvim" } })
vim.api.nvim_exec_autocmds("VimEnter", { modeline = false })
t.ok(vim.wait(1000, function() return require("which-key.config").loaded end), "which-key owns the comma trigger, as in a session")

local source = {
  "local function f(a, b)",
  "  local total = a + b",
  "  print(total * 3)",
  "  return a * 2 + b",
  "end",
  "return f",
}
local dir = vim.fn.tempname()
vim.fn.mkdir(dir, "p")
local file = dir .. "/refactor.lua"
vim.fn.writefile(source, file)
vim.cmd.edit(file)
t.ok(vim.wait(1000, function() return package.loaded.async ~= nil end), "the file read loads nvim-ufo and its async module")
local ufo_async = package.loaded.async
t.eq(ufo_async._id, { "promise-async" }, "the module named async is promise-async's")
t.ok(not loaded("refactoring.nvim"), "refactoring.nvim waits for its first key")

-- Name prompts and errors are the observable side channels: answer the one,
-- collect the other.
local answers, errors = {}, {}
vim.ui.input = function(_, on_confirm) on_confirm(table.remove(answers, 1)) end
vim.notify = function(msg, level)
  if level == vim.log.levels.ERROR then errors[#errors + 1] = msg end
end

local function lines() return vim.api.nvim_buf_get_lines(0, 0, -1, false) end
local function reset(cursor)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, source)
  vim.api.nvim_win_set_cursor(0, cursor)
end
---Feed `keys` through the real mappings and wait for the async task's edit.
local function run(keys, name)
  answers = { name }
  local before = lines()
  vim.api.nvim_feedkeys(vim.keycode(keys), "mx", false)
  vim.wait(3000, function() return not vim.deep_equal(lines(), before) end, 20)
end

-- Normal mode first: the lazy stub must hand the operator its text object.
reset({ 3, 9 })
run(",exi(", "scaled")
t.eq(lines(), {
  "local function f(a, b)",
  "  local total = a + b",
  "  local scaled = total * 3",
  "  print(scaled)",
  "  return a * 2 + b",
  "end",
  "return f",
}, "Normal ,ex takes a text object and extracts it into a variable")
t.ok(vim.async ~= nil and vim.async ~= ufo_async, "refactoring.nvim runs on async.nvim through vim.async")
t.eq(package.loaded.async, ufo_async, "nvim-ufo keeps its own async module")

reset({ 4, 9 })
run("v4l,ex", "double")
t.eq(lines(), {
  "local function f(a, b)",
  "  local total = a + b",
  "  print(total * 3)",
  "  local double = a * 2",
  "  return double + b",
  "end",
  "return f",
}, "Visual ,ex extracts the selection into a variable")
t.eq(vim.fn.mode(), "n", "the refactor leaves Visual mode")

reset({ 2, 0 })
run("Vj,ef", "helper")
t.eq(lines(), {
  "local function helper(a, b)",
  "  local total = a + b",
  "  print(total * 3)",
  "end",
  "",
  "local function f(a, b)",
  "  helper(a, b)",
  "  return a * 2 + b",
  "end",
  "return f",
}, "Visual ,ef extracts the lines into a function with their inputs as parameters")

for _, mode in ipairs({ "n", "x" }) do
  t.eq(vim.fn.maparg(",R", mode, false, true).desc, "Select refactor", ",R offers every refactor in mode " .. mode)
end

-- Inline variable resolves references through the language server.
if vim.fn.executable("lua-language-server") == 1 then
  reset({ 2, 8 })
  t.ok(vim.wait(20000, function() return #vim.lsp.get_clients({ bufnr = 0, name = "lua_ls" }) > 0 end, 50),
    "lua_ls attaches to the file")
  -- A fresh server answers references only once it has indexed the file.
  t.ok(vim.wait(20000, function()
    local params = vim.lsp.util.make_position_params(0, "utf-16")
    params.context = { includeDeclaration = false }
    for _, r in pairs(vim.lsp.buf_request_sync(0, "textDocument/references", params, 2000) or {}) do
      if r.result and #r.result > 0 then return true end
    end
    return false
  end, 200), "lua_ls answers references")
  run(",i")
  t.eq(lines(), {
    "local function f(a, b)",
    "  print((a + b) * 3)",
    "  return a * 2 + b",
    "end",
    "return f",
  }, ",i inlines the variable under the cursor into its references")
  for _, client in ipairs(vim.lsp.get_clients()) do client:stop(true) end
else
  print("skip - lua-language-server is not installed")
end

t.eq(errors, {}, "no refactor reported an error")
t.done()
