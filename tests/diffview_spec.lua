local t = dofile("tests/helper.lua")
require("lazy").load({ plugins = { "which-key.nvim" } })
vim.api.nvim_exec_autocmds("VimEnter", { modeline = false })
t.ok(vim.wait(1000, function() return require("which-key.config").loaded end), "which-key setup finishes")

vim.cmd("Lazy! load diffview.nvim")
local keymaps = require("diffview.config").get_config().keymaps.file_panel
local stage
local blocked_semicolon
for _, map in ipairs(keymaps) do
  if map[1] == "n" and map[2] == "s" then stage = map end
  if map[1] == "n" and map[2] == ";" then blocked_semicolon = map end
end

t.ok(stage ~= nil, "Diffview file panel keeps an exact s mapping")
t.ok(stage and stage[4] and (stage[4].desc or ""):find("Stage / unstage", 1, true) ~= nil,
  "Diffview file-panel s still stages and unstages")
t.ok(blocked_semicolon and blocked_semicolon[4]
  and blocked_semicolon[4].desc == "Disabled in Diffview",
  "Diffview file panel still blocks the global file-picker prefix")

-- Drive real mouse events through real Diffview windows, including hovering
-- a pane that does not have focus (native Nvim ignores scrollbind there).
local cwd = vim.fn.getcwd()
local root = vim.fn.tempname() .. " diff mouse"
vim.fn.mkdir(root, "p")
root = vim.uv.fs_realpath(root)
local function git(...)
  local command = { "git", "-C", root }
  vim.list_extend(command, { ... })
  local result = vim.system(command, { text = true }):wait()
  assert(result.code == 0, result.stderr)
end
git("init", "-q")
local lines = {}
for i = 1, 200 do lines[i] = ("row %03d "):format(i) .. string.rep("x", 160) end
vim.fn.writefile(lines, root .. "/sample.md")
-- Enough real files to scroll the file panel independently.
for i = 1, 50 do vim.fn.writefile({ "before" }, root .. ("/z%02d.txt"):format(i)) end
git("add", ".")
git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-qm", "baseline")
for i = 40, 61 do table.insert(lines, i, "inserted " .. i) end
vim.fn.writefile(lines, root .. "/sample.md")
for i = 1, 50 do vim.fn.writefile({ "after" }, root .. ("/z%02d.txt"):format(i)) end

vim.o.lines, vim.o.columns = 45, 180
vim.cmd.cd(vim.fn.fnameescape(root))
vim.cmd.edit(vim.fn.fnameescape(root .. "/sample.md"))
local ordinary = vim.api.nvim_get_current_win()
local function state(win) return vim.api.nvim_win_call(win, vim.fn.winsaveview) end
local ordinary_state = state(ordinary)
vim.cmd.DiffviewOpen()
local view = require("diffview.lib").get_current_view()
assert(vim.wait(15000, function()
  local layout = view.cur_layout
  return view.cur_entry and layout.a.file.bufnr and layout.b.file.bufnr
    and vim.wo[layout.a.id].diff and vim.wo[layout.b.id].diff
end, 20), "Diffview fixture did not open")
local left, right, panel_win = view.cur_layout.a.id, view.cur_layout.b.id, view.panel.winid
for _, win in ipairs({ left, right }) do vim.wo[win].foldenable = false end
vim.api.nvim_set_current_win(right)
local function mapping(lhs) return vim.fn.maparg(lhs, "n", false, true) end
t.eq(mapping(",p").desc, "Toggle Markdown Preview", "Markdown preview survives inside Diffview")
t.eq(mapping(",m").desc, "Toggle Markdown render", "Markdown rendering survives inside Diffview")
t.eq(mapping(",P").desc, "Focus the file panel", "Diffview has a separate panel focus key")
t.ok(mapping(",go").callback ~= nil, "Diffview conflicts use ,g without extending codelens")
t.eq(mapping(",co"), {}, "Diffview adds no longer ,c candidate")
vim.api.nvim_feedkeys(",P", "xt", false)
t.eq(vim.api.nvim_get_current_win(), panel_win, ",P focuses the real file panel")
vim.api.nvim_feedkeys(",B", "xt", false)
t.ok(not view.panel:is_open(), ",B closes the file panel")
vim.api.nvim_set_current_win(right)
vim.api.nvim_feedkeys(",B", "xt", false)
t.ok(view.panel:is_open(), ",B reopens the file panel")
panel_win = view.panel.winid
vim.api.nvim_set_current_win(right)
local mode = require("which-key.buf").get({ mode = "n", update = true })
local node = mode.tree:find(",")
local View, rows = require("which-key.view"), {}
for _, child in ipairs(node:children()) do rows[#rows + 1] = View.item(child, { parent = node }) end
View.sort(rows)
local title, owners = nil, {}
for _, row in ipairs(rows) do
  if row.key == "" then title = row.desc:sub(#"── " + 1) else owners[row.keys] = title end
end
t.eq(owners[",p"], "Markdown · preview", "Diffview source keeps its language section")
t.eq(owners[",P"], "Diffview · panels / conflicts", "Diffview source also shows its view section")
vim.cmd("normal! gg")
vim.cmd.syncbind()

local function wheel(win, direction)
  vim.cmd.redraw()
  local pos = vim.api.nvim_win_get_position(win)
  vim.api.nvim_input_mouse("wheel", direction, "", 0, pos[1] + 5, pos[2] + 8)
  -- getcharstr decodes the mouse coordinates; feedkeys executes that same
  -- event through mappings synchronously inside the headless test.
  vim.api.nvim_feedkeys(vim.fn.getcharstr(), "mx", false)
  vim.cmd.redraw()
  vim.wait(250, function() return false end, 10)
end
local function aligned(label)
  local a, b = state(left), state(right)
  local expected_line = b.topline < 40 and b.topline or math.max(40, b.topline - 22)
  local expected_fill = b.topline >= 40 and math.max(0, 62 - b.topline) or 0
  t.eq({ a.topline, a.topfill }, { expected_line, expected_fill }, label)
end

for _, hover in ipairs({ left, right }) do
  local before = state(right).topline
  wheel(hover, "down")
  t.ok(state(right).topline > before, "wheel over either pane advances the diff")
  aligned("both diff panes stay aligned")
  t.eq(vim.api.nvim_get_current_win(), right, "mouse scrolling preserves editing focus")
end
vim.cmd("normal! 42Gzt")
for _, direction in ipairs({ "down", "down", "up" }) do
  wheel(left, direction)
  aligned("scrolling across added-line filler keeps corresponding source lines aligned")
end
t.ok(state(left).topfill > 0, "the fixture exercises diff filler, not just equal line numbers")

vim.api.nvim_set_current_win(panel_win)
wheel(left, "down")
aligned("diff panes stay synchronized when the file panel has focus")
t.eq(vim.api.nvim_get_current_win(), panel_win, "hover scrolling preserves file-panel focus")
local before_left, before_right, before_panel = state(left), state(right), state(panel_win)
wheel(panel_win, "down")
t.ok(state(panel_win).topline > before_panel.topline, "the file list itself still scrolls")
t.eq(state(left), before_left, "scrolling the file list leaves the left diff pane alone")
t.eq(state(right), before_right, "scrolling the file list leaves the right diff pane alone")

vim.api.nvim_set_current_win(right)
before_left, before_right = state(left), state(right)
wheel(panel_win, "down")
t.eq({ state(left), state(right) }, { before_left, before_right }, "hovering the file list from a diff pane still scrolls only the list")
t.eq(vim.api.nvim_get_current_win(), right, "scrolling an unfocused file list preserves editing focus")
vim.api.nvim_feedkeys("v", "nx", false)
wheel(left, "down")
aligned("mouse scrolling also stays synchronized in Visual mode")
t.eq(vim.fn.mode(), "v", "mouse scrolling preserves Visual mode")
vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
for _, win in ipairs({ left, right }) do vim.wo[win].foldenable = true end
vim.cmd("normal! gg")
wheel(left, "down")
aligned("folded diff panes also remain aligned")
t.eq(state(ordinary), ordinary_state, "scrolling Diffview does not change another tab's viewport")
vim.cmd.DiffviewClose()
vim.wait(100, function() return false end, 10)
t.eq(mapping(",P"), {}, "Diffview removes panel mappings when it closes")
t.eq(mapping(",p").desc, "Toggle Markdown Preview", "closing Diffview preserves the filetype mapping")
mode = require("which-key.buf").get({ mode = "n", update = true })
t.eq(mode.tree:find(",g"), nil, "closing Diffview leaves no empty conflict group in the menu")
t.eq(vim.fn.maparg("<ScrollWheelDown>", "n", false, true), {}, "Diffview removes wheel overrides when it closes")
vim.cmd.cd(vim.fn.fnameescape(cwd))
vim.fn.delete(root, "rf")

t.done()
