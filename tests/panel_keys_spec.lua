-- One chord per act across the list views: oil, aerial, the Snacks picker and
-- edgy's panels. A list opens below on <C-s>, beside on <C-v>, previews on
-- <M-p>, toggles hidden files on <M-.> and shows its help on g?; none of them
-- takes window navigation (<C-h/j/k/l>), redo (<C-r>), Insert <C-w> or the
-- global ]w/[w warning jumps. Keys are read off real buffers, so a plugin
-- default that comes back is caught.
local t = dofile("tests/helper.lua")
require("lazy").load({ plugins = { "oil.nvim", "edgy.nvim", "aerial.nvim" } })
vim.o.columns = 200
vim.o.lines = 50

local function settle()
  vim.wait(150, function() return false end, 10)
end

local function press(keys)
  vim.api.nvim_feedkeys(vim.keycode(keys), "xt", false)
  settle()
end

-- The buffer-local mapping of `lhs` in `buf`, or nil when the key falls
-- through to a global one or to the builtin.
local function local_map(buf, lhs, mode)
  local m = vim.api.nvim_buf_call(buf, function() return vim.fn.maparg(lhs, mode, false, true) end)
  return m.buffer == 1 and m or nil
end

local function desc(buf, lhs, mode)
  local m = local_map(buf, lhs, mode)
  return m and m.desc or nil
end

-- Snacks describes a key by its action's name, with or without underscores.
local function action(buf, lhs, mode)
  local d = desc(buf, lhs, mode)
  return d and (d:gsub("_", " ")) or nil
end

local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
root = vim.uv.fs_realpath(root)
vim.fn.writefile({ "alpha" }, root .. "/a.txt")
vim.fn.writefile({ "local function beta() end", "local function gamma() end" }, root .. "/b.lua")

---------------------------------------------------------------------------
-- oil
---------------------------------------------------------------------------
vim.cmd.tabnew()
local oil_tab = vim.api.nvim_get_current_tabpage()
require("oil").open(root)
t.ok(vim.wait(2000, function()
  return vim.bo.filetype == "oil" and require("oil").get_entry_on_line(0, 1) ~= nil
end, 10), "oil lists the fixture directory")
local oil_buf = vim.api.nvim_get_current_buf()
local oil_win = vim.api.nvim_get_current_win()

t.ok((desc(oil_buf, "<C-s>", "n") or ""):find("horizontal = true", 1, true) ~= nil,
  "oil: <C-s> opens the entry below, as in the picker and aerial")
t.ok((desc(oil_buf, "<C-v>", "n") or ""):find("vertical = true", 1, true) ~= nil,
  "oil: <C-v> opens the entry beside")
t.ok(local_map(oil_buf, "<C-v>", "x") == nil, "oil: Visual <C-v> is left to Vim")
t.ok(local_map(oil_buf, "<C-x>", "n") == nil, "oil: <C-x> is no split key (decrement, the pickers' delete)")
t.ok(local_map(oil_buf, "<C-r>", "n") == nil, "oil: <C-r> is redo again")
t.eq(desc(oil_buf, "gR", "n"), "Refresh current directory list", "oil: gR refreshes the listing")
t.ok(local_map(oil_buf, "<C-p>", "n") == nil, "oil: <C-p> no longer previews")
t.ok((desc(oil_buf, "<M-p>", "n") or ""):find("preview window", 1, true) ~= nil,
  "oil: <M-p> toggles the preview, as in the picker")
t.ok(local_map(oil_buf, "<C-h>", "n") == nil and local_map(oil_buf, "<C-l>", "n") == nil,
  "oil: <C-h>/<C-l> stay window navigation")
t.eq(desc(oil_buf, "g?", "n"), "Show default keymaps", "oil: g? shows its help")

-- Blockwise Visual still starts from Visual mode in the editable listing.
_G.__panel_keys_mode = nil
press("gg0v<C-v><Cmd>lua _G.__panel_keys_mode = vim.fn.mode()<CR><Esc>")
t.eq(_G.__panel_keys_mode, "\22", "oil: v<C-v> reaches blockwise Visual")

-- Redo works on a staged edit of the listing.
local before = vim.api.nvim_buf_line_count(oil_buf)
press("ggdd")
local deleted = vim.api.nvim_buf_line_count(oil_buf)
press("u")
press("<C-r>")
t.ok(deleted == before - 1 and vim.api.nvim_buf_line_count(oil_buf) == deleted,
  "oil: u then <C-r> redoes a deleted line")
press("u")
t.eq(vim.api.nvim_buf_line_count(oil_buf), before, "oil: the listing is back as it was")
vim.bo[oil_buf].modified = false

-- The chords really split the way they say.
local function line_of(name)
  for lnum = 1, vim.api.nvim_buf_line_count(oil_buf) do
    local entry = require("oil").get_entry_on_line(oil_buf, lnum)
    if entry and entry.name == name then return lnum end
  end
end
for _, case in ipairs({ { "<C-s>", "col" }, { "<C-v>", "row" } }) do
  vim.api.nvim_set_current_win(oil_win)
  vim.api.nvim_win_set_cursor(oil_win, { assert(line_of("a.txt")), 0 })
  press(case[1])
  local layout = vim.fn.winlayout()
  t.eq(layout[1], case[2], "oil: " .. case[1] .. " splits " .. (case[2] == "col" and "below" or "beside"))
  t.eq(vim.api.nvim_buf_get_name(0), root .. "/a.txt", "oil: " .. case[1] .. " opens the entry")
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(oil_tab)) do
    if win ~= oil_win then vim.api.nvim_win_close(win, true) end
  end
end
vim.cmd.tabclose()

---------------------------------------------------------------------------
-- aerial
---------------------------------------------------------------------------
vim.cmd.tabnew()
vim.cmd.edit(vim.fn.fnameescape(root .. "/b.lua"))
vim.cmd("AerialOpen")
local aerial_buf
t.ok(vim.wait(3000, function()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype == "aerial" then aerial_buf = buf return true end
  end
  return false
end, 10), "aerial opens its outline")
if aerial_buf then
  t.ok(local_map(aerial_buf, "<C-j>", "n") == nil and local_map(aerial_buf, "<C-k>", "n") == nil,
    "aerial: <C-j>/<C-k> stay window navigation")
  t.eq(vim.api.nvim_buf_call(aerial_buf, function() return vim.fn.maparg("<C-j>", "n", false, true).desc end),
    "Go to lower window", "aerial: <C-j> reaches the global window key")
  t.ok((desc(aerial_buf, "<C-s>", "n") or ""):find("horizontal", 1, true) ~= nil
    and (desc(aerial_buf, "<C-v>", "n") or ""):find("vertical", 1, true) ~= nil,
    "aerial: <C-s>/<C-v> open below/beside, as in oil")
  t.ok(local_map(aerial_buf, "g?", "n") ~= nil, "aerial: g? shows its help")
end
vim.cmd("AerialClose")
vim.cmd.tabclose()

---------------------------------------------------------------------------
-- edgy panels
---------------------------------------------------------------------------
local edgy_keys = require("edgy.config").keys
for _, lhs in ipairs({ "<c-q>", "Q", "]w", "[w", "]W", "[W" }) do
  t.eq(edgy_keys[lhs], false, "edgy: " .. lhs .. " is off in its config")
end
t.eq(type(edgy_keys.q), "function", "edgy: q still closes a panel")
t.eq(type(edgy_keys["<c-w>>"]), "function", "edgy: the <C-w> resizers stay")

vim.cmd.tabnew()
vim.fn.setqflist({ { filename = root .. "/a.txt", lnum = 1, text = "alpha" } })
vim.cmd("copen")
local qf_buf = vim.api.nvim_get_current_buf()
t.ok(vim.wait(2000, function() return vim.b[qf_buf].edgy_keys == true end, 10),
  "edgy arms the quickfix panel")
t.ok(local_map(qf_buf, "<C-w>>", "n") ~= nil, "edgy: the panel has its resizer")
for _, lhs in ipairs({ "<C-q>", "Q", "]W", "[W" }) do
  t.ok(local_map(qf_buf, lhs, "n") == nil, "edgy: the panel has no " .. lhs)
end
for _, case in ipairs({ { "]w", "Next warning" }, { "[w", "Prev warning" } }) do
  t.eq(vim.api.nvim_buf_call(qf_buf, function() return vim.fn.maparg(case[1], "n", false, true).desc end),
    case[2], "edgy: " .. case[1] .. " in a panel is the global warning jump")
end
vim.cmd("cclose")
vim.cmd.tabclose()

---------------------------------------------------------------------------
-- Snacks picker
---------------------------------------------------------------------------
local resolved = require("snacks.picker.config").get({ source = "files" })
local input_keys, list_keys = resolved.win.input.keys, resolved.win.list.keys
t.ok(not input_keys["<M-h>"] and not list_keys["<M-h>"], "picker: <M-h> (tmux's pane key) is off")
t.eq(input_keys["<M-.>"], { "toggle_hidden", mode = { "i", "n" } }, "picker: <M-.> toggles hidden in the input")
t.eq(list_keys["<M-.>"], "toggle_hidden", "picker: <M-.> toggles hidden in the list")
t.eq({ list_keys["g?"], list_keys["?"] }, { "toggle_help_list", "toggle_help_list" },
  "picker: the list's help is on g? and ?")
t.eq({ input_keys["g?"], input_keys["?"] }, { "toggle_help_input", "toggle_help_input" },
  "picker: the input's help is on g? and ?")

local files = Snacks.picker.files({ cwd = root })
t.ok(vim.wait(2000, function() return files.input and files.input.win:buf_valid() and files.list.win:buf_valid() end, 10),
  "picker: the files picker opens")
local input_buf, list_buf = files.input.win.buf, files.list.win.buf
t.eq(action(input_buf, "<M-.>", "i"), "toggle hidden", "picker: Insert <M-.> is mapped on the input")
t.ok(local_map(input_buf, "<M-h>", "i") == nil and local_map(list_buf, "<M-h>", "n") == nil,
  "picker: no window maps <M-h>")
t.eq(action(list_buf, "g?", "n"), "toggle help list", "picker: g? is mapped on the list")
t.eq(action(input_buf, "g?", "n"), "toggle help input", "picker: g? is mapped on the input (Normal mode)")
t.eq(action(list_buf, "<M-.>", "n"), "toggle hidden", "picker: <M-.> is mapped on the list")
files:close()
settle()

-- ;p: Insert <C-w> deletes a word; Normal <C-w> still cds to the project.
local project_keys = require("snacks.picker.config").get({ source = "projects" }).win.input.keys
t.eq(project_keys["<C-W>"], { { "tcd" }, mode = { "n" } }, "projects: <C-w> is tcd in Normal mode only")
t.eq(project_keys.i_ctrl_w, { "<c-w>", "<c-s-w>", mode = { "i" }, expr = true, desc = "delete word" },
  "projects: Insert <C-w> is the picker's delete-word")

local projects = Snacks.picker.projects({ projects = { root }, recent = false, dev = { root } })
t.ok(vim.wait(2000, function() return projects.input and projects.input.win:buf_valid() end, 10),
  "projects: the picker opens")
local p_buf = projects.input.win.buf
t.eq(desc(p_buf, "<C-w>", "i"), "delete word", "projects: Insert <C-w> on the input deletes a word")
t.eq(action(p_buf, "<C-w>", "n"), "tcd", "projects: Normal <C-w> on the input is tcd")
vim.api.nvim_set_current_win(projects.input.win.win)
projects.input:set("foo bar")
settle()
press("A<C-w><Esc>")
t.eq(projects.input:get(), "foo ", "projects: typing <C-w> deletes the last word of the query")
t.ok(projects.input.win:valid(), "projects: and the picker stays open")

-- ;p: <C-r> (tcd, then recent files) is Normal only; Insert <C-r> inserts a
-- register, as in every other picker's input.
t.eq(project_keys["<C-R>"], { { "tcd", "picker_recent" }, mode = { "n" } },
  "projects: <C-r> is tcd + recent in Normal mode only")
t.ok(local_map(p_buf, "<C-r>", "n") ~= nil, "projects: Normal <C-r> on the input is mapped")
t.ok(local_map(p_buf, "<C-r>", "i") == nil, "projects: Insert <C-r> on the input is not taken")
vim.fn.setreg("a", "reg")
projects.input:set("")
settle()
press("A<C-r>a<Esc>")
t.eq(projects.input:get(), "reg", "projects: Insert <C-r>a inserts register a into the query")
t.ok(projects.input.win:valid(), "projects: and the picker stays open")
projects:close()
settle()

-- <leader>gs / ;c: restoring a file or hunk is <C-x>, the pickers' "remove
-- an item" chord, behind Snacks' own confirmation; <C-r> is the input's
-- register insert (Insert) and redo (Normal) again.
local gitroot = vim.fn.tempname()
vim.fn.mkdir(gitroot, "p")
gitroot = vim.uv.fs_realpath(gitroot)
local function git(...)
  return vim.system({ "git", "-C", gitroot, "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
    "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null", ... }):wait()
end
git("init", "-q")
vim.fn.writefile({ "one" }, gitroot .. "/hunk.txt")
git("add", "hunk.txt")
git("commit", "-qm", "fixture")
vim.fn.writefile({ "two" }, gitroot .. "/hunk.txt")

for _, source in ipairs({ "git_status", "git_diff" }) do
  local keys = require("snacks.picker.config").get({ source = source }).win.input.keys
  t.eq(keys["<C-R>"], false, source .. ": upstream's <C-r> restore is off")
  t.eq(keys["<C-X>"], { "git_restore", mode = { "n", "i" } }, source .. ": <C-x> restores")

  local picker = Snacks.picker[source]({ cwd = gitroot })
  t.ok(vim.wait(2000, function()
    return picker.input and picker.input.win:buf_valid() and picker:count() > 0
  end, 10), source .. ": the picker opens and lists the change")
  local buf = picker.input.win.buf
  for _, mode in ipairs({ "i", "n" }) do
    t.eq(action(buf, "<C-x>", mode), "git restore", source .. ": " .. mode .. " <C-x> on the input restores")
    t.ok(local_map(buf, "<C-r>", mode) == nil, source .. ": " .. mode .. " <C-r> on the input is not taken")
  end
  t.eq(action(buf, "<C-r><C-w>", "i"), "insert cword", source .. ": Insert <C-r><C-w> inserts the cword")

  vim.api.nvim_set_current_win(picker.input.win.win)
  press("A<C-r>a<Esc>")
  t.eq(picker.input:get(), "reg", source .. ": Insert <C-r>a inserts register a into the query")
  t.ok(Snacks.picker.get({ source = "select" })[1] == nil, source .. ": and asks nothing")
  picker.input:set("")
  settle()

  press("<C-x>")
  local confirm
  t.ok(vim.wait(2000, function()
    confirm = Snacks.picker.get({ source = "select" })[1]
    return confirm ~= nil
  end, 10), source .. ": <C-x> asks before discarding")
  if confirm then confirm:close() end
  settle()
  t.eq(vim.fn.readfile(gitroot .. "/hunk.txt"), { "two" }, source .. ": declining keeps the change")
  if not picker.closed then picker:close() end
  settle()
end

vim.fn.delete(gitroot, "rf")
vim.fn.delete(root, "rf")
t.done()
