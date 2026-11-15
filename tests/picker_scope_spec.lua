local t = dofile("tests/helper.lua")
local a = vim.api

vim.api.nvim_exec_autocmds("VimEnter", { modeline = false })
vim.wait(100, function() return false end, 10)

local function press(keys)
  a.nvim_feedkeys(a.nvim_replace_termcodes(keys, true, false, true), "xt", false)
end

-- Real files verify the difference between the two search scopes, including
-- tracked source under a directory excluded by the broad search.
local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/build", "p")
local function git(args)
  local cmd = { "git", "-C", root }
  vim.list_extend(cmd, args)
  t.eq(vim.system(cmd, { text = true }):wait().code, 0, "fixture git " .. args[1])
end
git({ "init", "-q" })
vim.fn.writefile({ "ignored.txt" }, root .. "/.gitignore")
for _, name in ipairs({ "source.txt", "ignored.txt", ".hidden.txt", "build/source.txt" }) do
  vim.fn.writefile({ "workflow_fixture" }, root .. "/" .. name)
end
git({ "add", ".gitignore", "source.txt", ".hidden.txt", "build/source.txt" })
vim.cmd("lcd " .. vim.fn.fnameescape(root))

local function open_picker(key, source)
  press(key)
  local picker
  t.ok(vim.wait(1500, function()
    picker = Snacks.picker.get({ source = source })[1]
    return picker ~= nil
  end, 10), key .. " opens a picker")
  return assert(picker)
end

for _, case in ipairs({ { ";f", true, false }, { ";i", false, true }, { ";?", false, true } }) do
  local picker = open_picker(case[1], case[1] == ";?" and "grep" or "files")
  if case[1] == ";?" then
    picker.input:set("", "workflow_fixture")
    picker:find()
  end
  vim.wait(100, function() return false end, 10)
  t.ok(vim.wait(3000, function() return not picker:is_active() and picker:count() > 0 end, 10),
    case[1] .. " finishes searching")
  local found = {}
  for _, item in ipairs(picker:items()) do
    local name = item.file:gsub("^" .. vim.pesc(root) .. "/", ""):gsub("^%./", "")
    found[name] = true
  end
  t.eq(found["ignored.txt"] == true, case[2], case[1] .. ": ignored file scope")
  t.eq(found["build/source.txt"] == true, case[3], case[1] .. ": tracked build source scope")
  t.ok(found[".hidden.txt"], case[1] .. ": hidden files stay visible")
  picker:close()
  vim.wait(50, function() return false end, 10)
end
local config_files = open_picker("<leader>mf", "files")
t.eq(config_files.opts.cwd, vim.fn.stdpath("config"),
  "<leader>mf searches the Nvim configuration from another project")
config_files:close()
vim.wait(50, function() return false end, 10)
local plugins = open_picker("<leader>mF", "files")
t.eq(plugins.opts.cwd, require("lazy.core.config").options.root,
  "<leader>mF searches the configured plugin installation directory")
t.ok(vim.wait(5000, function() return not plugins:is_active() and plugins:count() > 0 end, 10),
  "plugin source search returns files")
plugins:close()
vim.wait(50, function() return false end, 10)
vim.cmd("lcd " .. vim.fn.fnameescape(vim.fn.stdpath("config")))
vim.fn.delete(root, "rf")

t.done()
