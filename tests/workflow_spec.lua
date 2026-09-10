local t = dofile("tests/helper.lua")
local a = vim.api

vim.api.nvim_exec_autocmds("VimEnter", { modeline = false })
vim.wait(100, function() return false end, 10)

local function press(keys)
  a.nvim_feedkeys(a.nvim_replace_termcodes(keys, true, false, true), "xt", false)
end

-- JS/TS declarations share Dial's ordinary groups; whole words and unrelated
-- filetypes must retain their previous behavior.
for _, ft in ipairs({ "javascript", "javascriptreact", "typescript", "typescriptreact", "lua" }) do
  vim.cmd.enew()
  vim.bo.filetype = ft
  a.nvim_buf_set_lines(0, 0, -1, false, { "let value", "letter", "true", "2026-09-10" })
  a.nvim_win_set_cursor(0, { 1, 0 })
  press("<C-a>")
  t.eq(a.nvim_get_current_line(), ft == "lua" and "let value" or "const value",
    ft .. ": declaration toggle stays language-scoped")
  if ft ~= "lua" then
    press("<C-x>")
    t.eq(a.nvim_get_current_line(), "let value", ft .. ": decrement toggles back")
  end
  a.nvim_win_set_cursor(0, { 2, 0 })
  press("<C-a>")
  t.eq(a.nvim_get_current_line(), "letter", ft .. ": identifiers are not rewritten")
  a.nvim_win_set_cursor(0, { 3, 0 })
  press("<C-a>")
  t.eq(a.nvim_get_current_line(), "false", ft .. ": boolean toggle is retained")
  a.nvim_win_set_cursor(0, { 4, 9 })
  press("<C-a>")
  t.eq(a.nvim_get_current_line(), "2026-09-11", ft .. ": date increment is retained")
  vim.bo.modified = false
end

-- Inspect real highlights so valid color options cannot silently stop working.
vim.cmd("edit " .. vim.fn.fnameescape(vim.fn.tempname() .. ".css"))
a.nvim_buf_set_lines(0, 0, -1, false, {
  ":root {",
  "  --brand: #ff0000;",
  "  color: rgb(0, 255, 0);",
  "  background: hsl(240, 100%, 50%);",
  "  border-color: var(--brand);",
  "}",
})
local colorizer = require("colorizer")
colorizer.attach_to_buffer(0)
local ns = require("colorizer.constants").namespace.default
local function colors()
  local found = {}
  for _, mark in ipairs(a.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })) do
    local hl = mark[4].hl_group
    if hl then found[mark[2]] = a.nvim_get_hl(0, { name = hl, link = false }).bg end
  end
  return found
end
t.ok(vim.wait(1000, function() return colors()[4] ~= nil end, 10), "CSS variable reference receives a color")
t.eq(colors()[1], 0xff0000, "hex preview is preserved")
t.eq(colors()[2], 0x00ff00, "RGB preview renders green")
t.eq(colors()[3], 0x0000ff, "HSL preview renders blue")
t.eq(colors()[4], 0xff0000, "CSS variable preview resolves the local definition")
vim.bo.modified = false
for _, ft in ipairs({ "html", "text" }) do
  vim.cmd.enew()
  vim.bo.filetype = ft
  a.nvim_buf_set_lines(0, 0, -1, false, { '<div class="bg-blue-500">' })
  colorizer.attach_to_buffer(0)
  t.eq(colors()[0] ~= nil, ft == "html", "Tailwind class preview is scoped to frontend files: " .. ft)
  vim.bo.modified = false
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
local plugins = open_picker(";N", "files")
t.eq(plugins.opts.cwd, require("lazy.core.config").options.root,
  ";N searches the configured plugin installation directory")
t.ok(vim.wait(5000, function() return not plugins:is_active() and plugins:count() > 0 end, 10),
  "plugin source search returns files")
plugins:close()
vim.wait(50, function() return false end, 10)
vim.cmd("lcd " .. vim.fn.fnameescape(vim.fn.stdpath("config")))
vim.fn.delete(root, "rf")

-- A zen view shares the edited buffer and leaves ordinary splits, a running
-- terminal and another tab intact when it closes.
vim.cmd.enew()
local file_buf, file_win = a.nvim_get_current_buf(), a.nvim_get_current_win()
a.nvim_buf_set_name(file_buf, vim.fn.tempname() .. ".txt")
a.nvim_buf_set_lines(file_buf, 0, -1, false, { "original" })
vim.cmd.vsplit()
vim.cmd.enew()
local term_win, term_buf = a.nvim_get_current_win(), a.nvim_get_current_buf()
local job = vim.fn.jobstart({ "sh", "-c", "cat" }, { term = true })
vim.cmd.stopinsert()
local tab = a.nvim_get_current_tabpage()
vim.cmd.tabnew()
local other_tab, other_win = a.nvim_get_current_tabpage(), a.nvim_get_current_win()
local other_buf = a.nvim_get_current_buf()
local other_config = a.nvim_win_get_config(other_win)
a.nvim_set_current_tabpage(tab)
a.nvim_set_current_win(file_win)
local layout = vim.fn.winlayout()
press("sz")
local zen = Snacks.zen.win
t.ok(zen and zen:valid(), "sz opens zen for a file")
t.eq(a.nvim_get_current_buf(), file_buf, "zen uses the original file buffer")
a.nvim_buf_set_lines(file_buf, 0, -1, false, { "edited in zen" })
press("sz")
vim.wait(100, function() return false end, 10)
t.eq(vim.fn.winlayout(), layout, "leaving zen restores the split layout")
t.eq(a.nvim_get_current_win(), file_win, "leaving zen returns to the editor window")
t.eq(a.nvim_buf_get_lines(file_buf, 0, -1, false), { "edited in zen" }, "zen preserves unsaved edits")
t.eq(a.nvim_win_get_buf(term_win), term_buf, "zen leaves the terminal buffer in place")
t.eq(vim.fn.jobwait({ job }, 0)[1], -1, "the terminal process is still running")
t.eq(a.nvim_tabpage_list_wins(other_tab), { other_win }, "zen does not create windows in another tab")
t.eq(a.nvim_win_get_buf(other_win), other_buf, "zen leaves the other tab's buffer alone")
t.eq(a.nvim_win_get_config(other_win), other_config, "zen leaves the other tab's geometry alone")
a.nvim_set_current_win(term_win)
press("sz")
t.ok(not Snacks.zen.win, "terminal buffers do not enter zen mode")
vim.fn.jobstop(job)
t.done()
