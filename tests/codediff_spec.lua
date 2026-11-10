-- CodeDiff as this config wires it (lua/plugin/vcs/codediff.lua and
-- lua/util/codediff.lua), driven through real views on temporary repositories.
--
-- Needs CodeDiff's native library in the plugin directory; tests/run.sh sets
-- VSCODE_DIFF_NO_AUTO_INSTALL so a missing one fails here instead of being
-- downloaded. Every repository lives under tempname() with a space in its
-- path, and git runs with an empty global config.
local t = dofile("tests/helper.lua")
local Config = require("lazy.core.config")

require("lazy").load({ plugins = { "which-key.nvim" } })
vim.api.nvim_exec_autocmds("VimEnter", { modeline = false })
t.ok(vim.wait(1000, function() return require("which-key.config").loaded end), "which-key setup finishes")

local plugin = Config.plugins["codediff.nvim"]
t.ok(plugin ~= nil and plugin._.loaded == nil, "codediff.nvim is declared and waits for its first use")
t.eq(package.loaded["util.codediff"], nil, "util.codediff is not loaded at startup")
local libs = vim.fn.glob(plugin.dir .. "/libvscode_diff*", false, true)
if #libs == 0 then
  t.ok(false, "CodeDiff's native library is installed in " .. plugin.dir .. " (see docs/DIAGNOSTICS.md)")
  t.done()
  return
end

local gitconfig = vim.fn.tempname()
vim.fn.writefile({}, gitconfig)
vim.env.GIT_CONFIG_GLOBAL = gitconfig
vim.env.GIT_CONFIG_NOSYSTEM = "1"

local notices = {}
local real_notify = vim.notify
vim.notify = function(msg, level) notices[#notices + 1] = { msg = tostring(msg), level = level } end
local function said(text)
  for _, n in ipairs(notices) do
    if n.msg:find(text, 1, true) then return n end
  end
end

local function key(lhs)
  for _, spec in ipairs(plugin.keys) do
    if spec[1] == lhs then return spec end
  end
end
local function press(lhs) key(lhs)[2]() end
local function map(buf, lhs, mode)
  return vim.api.nvim_buf_call(buf, function() return vim.fn.maparg(lhs, mode or "n", false, true) end)
end
local function settle(ms) vim.wait(ms or 100, function() return false end, 10) end

local function repo(name)
  local root = vim.fn.tempname() .. " " .. name
  vim.fn.mkdir(root, "p")
  root = vim.uv.fs_realpath(root)
  local function git(...)
    local command = { "git", "-C", root, "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid" }
    local result = vim.system(vim.list_extend(command, { ... }), { text = true }):wait()
    return result.code == 0, result.stderr
  end
  assert(git("init", "-q", "-b", "main"))
  return root, git
end

-- The main fixture: a Markdown file with 22 lines inserted at 40, fifty small
-- files so the explorer scrolls, a non-ASCII name and three commits.
local root, git = repo("codediff spec")
local lines = {}
for i = 1, 200 do lines[i] = ("row %03d "):format(i) .. string.rep("x", 160) end
vim.fn.writefile(lines, root .. "/sample.md")
for i = 1, 50 do vim.fn.writefile({ "before" }, root .. ("/z%02d.txt"):format(i)) end
vim.fn.writefile({ "one" }, root .. "/中文.txt")
vim.fn.writefile({ "first" }, root .. "/notes.txt")
assert(git("add", "."))
assert(git("commit", "-qm", "baseline"))
vim.fn.writefile({ "second" }, root .. "/notes.txt")
assert(git("commit", "-qam", "second"))
vim.fn.writefile({ "third" }, root .. "/notes.txt")
assert(git("commit", "-qam", "third"))
for i = 40, 61 do table.insert(lines, i, "inserted " .. i) end
vim.fn.writefile(lines, root .. "/sample.md")
for i = 1, 50 do vim.fn.writefile({ "after" }, root .. ("/z%02d.txt"):format(i)) end
vim.fn.writefile({ "two" }, root .. "/中文.txt")

local cwd = vim.fn.getcwd()
vim.o.lines, vim.o.columns = 45, 180
local editor_tab = vim.api.nvim_get_current_tabpage()

---------------------------------------------------------------------------
-- Before the first view
---------------------------------------------------------------------------

-- A clean tree is refused with our own words (#582) and loads nothing.
local clean = repo("codediff clean")
vim.fn.writefile({ "x" }, clean .. "/a.txt")
vim.system({ "git", "-C", clean, "add", "." }):wait()
vim.system({ "git", "-C", clean, "-c", "user.name=F", "-c", "user.email=f@x.invalid", "commit", "-qm", "a" }):wait()
vim.cmd.cd(vim.fn.fnameescape(clean))
vim.cmd.enew()
press("<leader>gv")
t.ok(said("working tree is clean") ~= nil, "<leader>gv on a clean tree says so")
t.eq(#vim.api.nvim_list_tabpages(), 1, "and opens no view")
t.ok(plugin._.loaded == nil, "refusing a clean tree does not load CodeDiff")

-- Not a file: <leader>gV refuses before git or CodeDiff.
press("<leader>gV")
t.ok(said("File history: the current buffer is not a file") ~= nil, "<leader>gV refuses a buffer without a file")

t.eq(key("<leader>gV").desc, "File history (recent 100, no merges)", "<leader>gV says how much history it lists")
t.eq(key("<leader>gH").desc, "Repo history (recent 100, no merges)", "and so does <leader>gH")

---------------------------------------------------------------------------
-- The status view (<leader>gv)
---------------------------------------------------------------------------

vim.cmd.cd(vim.fn.fnameescape(root))
vim.cmd.edit(vim.fn.fnameescape(root .. "/sample.md"))
local sample = vim.api.nvim_get_current_buf()
local ordinary = vim.api.nvim_get_current_win()
local function state(win) return vim.api.nvim_win_call(win, vim.fn.winsaveview) end
local ordinary_state = state(ordinary)
press("<leader>gv")
local cd = require("util.codediff")

--- A view in the current tabpage that has loaded its first file (`file`, if
--- given, in the right pane) and carries this config's keys. A view opens on
--- empty placeholder panes and loads that file asynchronously; leaving its
--- tabpage before then interrupts the load.
local function ready(file)
  return function()
    local s = cd.session(0)
    if not s or not s.modified_bufnr or not vim.api.nvim_buf_is_valid(s.modified_bufnr) then return false end
    local name = vim.api.nvim_buf_get_name(s.modified_bufnr)
    if name == "" or (file and not name:find(file, 1, true)) then return false end
    if s.panel == "explorer" and not s.selection then return false end
    local refresh = require("codediff.ui.lifecycle").get_session(s.tabpage).refresh
    return refresh ~= nil and refresh.loading == false and map(s.modified_bufnr, ";").desc == "Disabled in CodeDiff"
  end
end
--- A history view showing a commit: one of its panes is a revision buffer
--- (only the right one for the commit that added the file).
local function history_ready()
  local h = cd.session(0)
  if not h or h.mode ~= "history" or not h.panel_bufnr then return false end
  local shown = false
  for _, buf in ipairs({ h.original_bufnr, h.modified_bufnr }) do
    shown = shown or vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_name(buf):match("^codediff://") ~= nil
  end
  return shown and map(h.panel_bufnr, ";").desc == "Disabled in CodeDiff"
end
t.ok(vim.wait(15000, ready("sample.md"), 20), "<leader>gv opens the status view on the current file")
t.ok(plugin._.loaded ~= nil, "the first view loaded CodeDiff")
t.ok(not cd.degraded(), "the installed CodeDiff is the version util.codediff was written against")

-- The internals util.codediff reads (its header lists them).
local lifecycle = require("codediff.ui.lifecycle")
for _, name in ipairs({ "get_session", "set_buf_keymap", "set_tab_keymap", "begin_keymap_scope",
  "end_keymap_scope", "close", "update_buffers" }) do
  t.eq(type(lifecycle[name]), "function", "codediff.ui.lifecycle." .. name .. " exists")
end
t.ok(lifecycle.nvim_config_patched == true, "pane buffer swaps are hooked")
local actions = require("codediff.ui.explorer.actions")
for _, name in ipairs({ "toggle_stage_entry", "stage_all", "unstage_all", "restore_entry" }) do
  t.eq(type(actions[name]), "function", "codediff.ui.explorer.actions." .. name .. " exists")
end
t.eq(type(require("codediff.ui.view.actions.hunk").unstage_hunk), "function", "hunk.unstage_hunk exists")
t.eq(type(require("codediff.core.diff").compute_diff), "function", "core.diff.compute_diff exists")
t.eq(type(require("codediff.ui.view.render").diff_options), "function", "view.render.diff_options exists")
t.eq(type(require("codediff.ui.layout").arrange), "function", "ui.layout.arrange exists")
t.eq(type(require("codediff.core.git.changes").get_diff_revision), "function", "changes.get_diff_revision exists")
t.ok(require("codediff.core.git.runner").nvim_config_patched == true, "the git runner is patched")
t.ok(require("codediff.core.git").nvim_config_patched == true, "the history listing is patched")
t.eq(require("codediff.version").VERSION, cd.VERSION, "codediff.version.VERSION matches")

local view_tab = vim.api.nvim_get_current_tabpage()
local s = cd.session(0)
local raw = lifecycle.get_session(view_tab)
t.eq(s.mode, "status", "session() reports the status view")
t.eq(type(raw.stored_diff_result.changes), "table", "the session stores the displayed hunks")
t.ok(vim.t.blocks_global_prefixes == true, "the view's tabpage blocks the global prefixes")
t.eq(vim.t.codediff_label, "index/HEAD ↔ working tree", "and says what it compares")
t.ok(said("Comparing index/HEAD ↔ working tree") ~= nil, "opening the view says it once")
t.ok(vim.api.nvim_buf_get_name(s.original_bufnr):match("^codediff://") ~= nil, "the left pane is a revision buffer")
t.eq(vim.bo[s.original_bufnr].buflisted, false, "which stays out of the buffer list")

local left, right, panel_win = s.original_win, s.modified_win, s.panel_win
local panel_buf = s.panel_bufnr
vim.api.nvim_set_current_win(right)
t.eq(map(sample, ",p").desc, "Toggle Markdown Preview", "Markdown preview survives inside CodeDiff")
t.eq(map(sample, ",m").desc, "Toggle Markdown render", "Markdown rendering survives inside CodeDiff")
t.eq(map(sample, ",P").desc, "Focus explorer panel", "CodeDiff focuses its explorer on ,P")
for _, lhs in ipairs({ ",B", ",z", ",I" }) do
  t.ok(map(sample, lhs).buffer == 1, "CodeDiff's " .. lhs .. " is on the comma menu")
end
t.eq(map(sample, ",co"), {}, "CodeDiff adds no longer ,c candidate")

-- Defaults that would have shadowed this config's keys stay off.
t.ok(map(sample, "gc").buffer ~= 1, "gc is still the comment operator in a diff pane")
t.ok(map(sample, "gS").buffer ~= 1, "gS is still splitjoin")
t.eq(map(sample, "-").desc, "Oil: parent directory", "- is still oil's parent directory")
t.ok(map(sample, "t").buffer ~= 1, "t keeps its builtin meaning")
t.ok(map(sample, "gm").buffer ~= 1, "gm keeps its builtin meaning")
t.ok(map(sample, "q").buffer ~= 1, "q in a diff pane is macro recording again")
for _, lhs in ipairs({ "<leader>b", "<leader>e", "<leader>hs", "<leader>hu", "<leader>hr", "<leader>co" }) do
  t.eq(map(sample, lhs), {}, lhs .. " is not mapped by CodeDiff")
end
t.eq(map(sample, "<leader>bd").desc, "Delete buffer", "<leader>bd still deletes the buffer")

-- ; and s: blocked in every window of the view, with a visible hint.
for _, buf in ipairs({ s.original_bufnr, sample, panel_buf }) do
  for _, lhs in ipairs({ ";", "s" }) do
    local m = map(buf, lhs)
    t.ok(m.desc == "Disabled in CodeDiff" and m.nowait == 1 and m.buffer == 1,
      ("%s is blocked with nowait in %s"):format(lhs, vim.bo[buf].filetype ~= "" and vim.bo[buf].filetype or vim.api.nvim_buf_get_name(buf)))
  end
end
local wins_before, cursor_before = vim.api.nvim_tabpage_list_wins(0), vim.api.nvim_win_get_cursor(right)
for _, prefix in ipairs({ ";", "s" }) do
  notices = {}
  vim.api.nvim_feedkeys(prefix, "xt", false)
  t.ok(said(prefix .. " is disabled in CodeDiff") ~= nil, prefix .. " in a pane explains itself")
end
-- The key after the prefix is swallowed too, so `so` does not open a line and
-- `;f` does not start a jump. A headless feed cannot type it a moment later
-- (feedkeys "x" ends typeahead with an <Esc>, as :normal does, and keys fed
-- together go to the longer global mapping, :help map-nowait), so queue it
-- and run the block the way the mapping would.
for _, keys in ipairs({ ";f", "so", "sd", "ss", "sv", "s=", "sm", "sz" }) do
  vim.api.nvim_feedkeys(keys:sub(2), "t", false)
  map(sample, keys:sub(1, 1)).callback()
  t.eq(vim.fn.getchar(1), 0, keys .. ": the key after the prefix is swallowed")
end
t.eq(vim.fn.mode(), "n", "no command is left pending")
t.eq(vim.api.nvim_tabpage_list_wins(0), wins_before, "none of them touched the layout")
t.eq(vim.api.nvim_get_current_win(), right, "or moved the cursor out of the pane")
t.eq(vim.api.nvim_win_get_cursor(right), cursor_before, "or within it")
t.ok(not vim.bo[sample].modified, "and the file is untouched")

-- The status view's explorer keeps its file-level index keys and q.
for lhs, desc in pairs({ ["-"] = "Stage / unstage", S = "Stage all files", U = "Unstage all files",
  X = "Restore / discard changes", q = "Close the CodeDiff view" }) do
  t.eq(map(panel_buf, lhs).desc, desc, "the status explorer has " .. lhs)
end

-- which-key: the view's actions and the language's share the comma menu.
local wk_mode = require("which-key.buf").get({ mode = "n", update = true })
local node = wk_mode.tree:find(",")
local View, rows = require("which-key.view"), {}
for _, child in ipairs(node:children()) do rows[#rows + 1] = View.item(child, { parent = node }) end
View.sort(rows)
local title, owners = nil, {}
for _, row in ipairs(rows) do
  if row.key == "" then title = row.desc:sub(#"── " + 1) else owners[row.keys] = title end
end
t.eq(owners[",p"], "Markdown · preview", "a CodeDiff pane keeps its language section")
t.eq(owners[",P"], "CodeDiff · panels / layout / conflicts", "and shows the view's own section")
t.eq(owners[",z"], "CodeDiff · panels / layout / conflicts", "compact is in the view's section")

-- <leader>gv from inside the view: a bare :CodeDiff there would close it.
notices = {}
press("<leader>gv")
t.ok(said("already shows a CodeDiff view") ~= nil, "<leader>gv inside a view says it already is one")
t.ok(vim.api.nvim_tabpage_is_valid(view_tab) and #vim.api.nvim_list_tabpages() == 2, "and neither closes it nor opens another")

-- The comma panel keys work.
vim.api.nvim_feedkeys(",P", "xt", false)
t.eq(vim.api.nvim_get_current_win(), panel_win, ",P focuses the explorer")
vim.api.nvim_set_current_win(right)
vim.api.nvim_feedkeys(",B", "xt", false)
settle()
t.ok(not vim.api.nvim_win_is_valid(panel_win), ",B hides the explorer")
vim.api.nvim_feedkeys(",B", "xt", false)
settle()
panel_win = cd.session(0).panel_win
t.ok(panel_win and vim.api.nvim_win_is_valid(panel_win), ",B shows it again")
vim.api.nvim_set_current_win(right)

-- The hunk under the cursor, and whether it is still what the buffers hold.
vim.api.nvim_win_set_cursor(right, { 45, 0 })
local hunk = cd.hunk_at_cursor(0, right)
t.eq(hunk and { hunk.side, hunk.original, hunk.modified },
  { "modified", { start_line = 40, end_line = 40 }, { start_line = 40, end_line = 62 } },
  "hunk_at_cursor finds the inserted block")
t.eq(cd.fresh_hunk(0, right), hunk, "fresh_hunk confirms it against the buffers")
vim.api.nvim_buf_set_lines(sample, 44, 44, false, { "an edit the view has not seen" })
local stale, reason = cd.fresh_hunk(0, right)
t.ok(stale == nil and reason ~= nil, "fresh_hunk refuses once the text moved under it")
vim.cmd("silent undo")
t.ok(not vim.bo[sample].modified, "the edit is undone")
vim.api.nvim_win_set_cursor(right, { 10, 0 })
t.eq(cd.hunk_at_cursor(0, right), nil, "no hunk outside a change")

-- set_keys with a scope: a claim the next pass does not repeat goes away.
t.eq(map(sample, ",Q"), {}, ",Q starts unmapped")
t.ok(cd.set_keys(0, { { "n", "<localleader>Q", function() end, desc = "spec key", on = "modified" } }, "spec"),
  "set_keys installs on a view")
t.eq(map(sample, ",Q").desc, "spec key", "on the requested pane")
t.eq(map(s.original_bufnr, ",Q").desc, nil, "and only there")
cd.set_keys(0, {}, "spec")
t.eq(map(sample, ",Q"), {}, "a later pass of the same scope releases it")

---------------------------------------------------------------------------
-- Wheel scrolling keeps the panes together
---------------------------------------------------------------------------

-- Real mouse events through real windows, including hovering a pane that
-- does not have focus. No :syncbind here: it leaves scrollbind's reference
-- point stale in non-diff windows, and the next scroll then lags by one step.
for _, win in ipairs({ left, right }) do vim.wo[win].foldenable = false end
vim.cmd("normal! gg")

local function wheel(win, direction)
  vim.cmd.redraw()
  local pos = vim.api.nvim_win_get_position(win)
  vim.api.nvim_input_mouse("wheel", direction, "", 0, pos[1] + 5, pos[2] + 8)
  -- getcharstr decodes the mouse coordinates; feedkeys executes that same
  -- event through mappings synchronously inside the headless test.
  vim.api.nvim_feedkeys(vim.fn.getcharstr(), "mx", false)
  vim.cmd.redraw()
  settle(150)
end
--- The left pane draws CodeDiff's filler for the 22 inserted lines as
--- virtual lines above its line 40, which winsaveview reports as topfill.
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
vim.cmd("normal! 60Gzt") -- scrolloff: the top line lands in the inserted block
for _, direction in ipairs({ "down", "down", "up" }) do
  wheel(left, direction)
  aligned("scrolling across added-line filler keeps corresponding source lines aligned")
end
t.ok(state(left).topfill > 0, "the fixture exercises filler, not just equal line numbers")

vim.api.nvim_set_current_win(panel_win)
wheel(left, "down")
aligned("diff panes stay synchronized when the explorer has focus")
t.eq(vim.api.nvim_get_current_win(), panel_win, "hover scrolling preserves explorer focus")
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

-- CodeDiff's own folds: compact mode folds the unchanged runs in both panes.
for _, win in ipairs({ left, right }) do vim.wo[win].foldenable = true end
vim.cmd("normal! gg")
vim.api.nvim_feedkeys(",z", "xt", false)
t.ok(vim.wait(2000, function()
  return vim.api.nvim_win_call(right, function() return vim.fn.foldclosed(1) end) == 1
end, 20), ",z folds the unchanged lines")
for _, hover in ipairs({ right, left }) do
  wheel(hover, "down")
  aligned("folded diff panes also remain aligned")
end
vim.api.nvim_feedkeys(",z", "xt", false)
t.eq(state(ordinary), ordinary_state, "scrolling CodeDiff does not change another tab's viewport")
t.eq(map(sample, "<ScrollWheelDown>").desc, "Scroll down (sync diff panes)", "the wheel keys are the view's")

---------------------------------------------------------------------------
-- A window opened beside the view (the agent panel, say) evens out the panes
---------------------------------------------------------------------------

-- WinResized fires from the main loop, which a headless spec never reaches,
-- so each step announces it the way a redraw would.
local function widths() return { vim.api.nvim_win_get_width(left), vim.api.nvim_win_get_width(right) } end
local function even(w) return math.abs(w[1] - w[2]) <= 1 end
local function resized() vim.api.nvim_exec_autocmds("WinResized", { modeline = false }) settle(100) end
vim.cmd("botright 60vnew")
local side = vim.api.nvim_get_current_win()
t.ok(not even(widths()), "a window opened beside the view takes its width from one pane")
resized()
t.ok(even(widths()), ("then the panes are evened out (%s)"):format(table.concat(widths(), "/")))
vim.api.nvim_set_current_win(right)
vim.cmd("vertical resize +10")
local by_hand = widths()
resized()
t.eq(widths(), by_hand, "a pane resized by hand keeps its size")
vim.api.nvim_win_close(side, true)
resized()
t.ok(even(widths()), "closing the window evens them out again")
vim.api.nvim_set_current_win(right)

---------------------------------------------------------------------------
-- <leader>gq closes this view and hands every key back
---------------------------------------------------------------------------

notices = {}
press("<leader>gq")
t.ok(vim.wait(2000, function() return not vim.api.nvim_tabpage_is_valid(view_tab) end, 20), "<leader>gq closes the view's tabpage")
t.eq(vim.api.nvim_get_current_tabpage(), editor_tab, "back on the editing page")
settle()
t.eq(map(sample, ",P"), {}, "CodeDiff removes its panel mappings when it closes")
t.eq(map(sample, ",p").desc, "Toggle Markdown Preview", "closing CodeDiff preserves the filetype mapping")
-- Back to the global prefix, or to which-key's buffer-local trigger for it.
t.ok(map(sample, ";").desc ~= "Disabled in CodeDiff", "; is no longer blocked")
t.ok(map(sample, "s").desc ~= "Disabled in CodeDiff", "and neither is s")
t.eq(map(sample, "<ScrollWheelDown>"), {}, "the wheel overrides are gone")
local leftovers = vim.tbl_filter(function(b) return vim.api.nvim_buf_get_name(b):match("^codediff://") ~= nil end,
  vim.api.nvim_list_bufs())
t.eq(leftovers, {}, "no codediff:// buffer survives the view")
wk_mode = require("which-key.buf").get({ mode = "n", update = true })
t.eq(wk_mode.tree:find(",g"), nil, "closing CodeDiff leaves no empty conflict group in the menu")

notices = {}
press("<leader>gq")
t.ok(said("No diff view in this tab") ~= nil, "<leader>gq without a view says so")
t.eq(#vim.api.nvim_list_tabpages(), 1, "and does not open one, the way a bare :CodeDiff would")

---------------------------------------------------------------------------
-- <leader>gm, <leader>gV, <leader>gH, and <leader>gq per tabpage
---------------------------------------------------------------------------

press("<leader>gm")
t.ok(vim.wait(15000, ready(), 20), "<leader>gm opens a view")
local rev_tab = vim.api.nvim_get_current_tabpage()
s = cd.session(0)
t.eq(s.mode, "revision", "against the working tree, not the merge base")
t.eq(vim.t.codediff_label, "main → working tree", "labelled with the branch it picked")
local listed = {}
for _, entry in ipairs(lifecycle.get_session(rev_tab).panel.data.status_result.unstaged) do
  listed[#listed + 1] = entry.path
end
t.ok(vim.list_contains(listed, "中文.txt"), "a non-ASCII path is listed intact (" .. table.concat(listed, ", "):sub(1, 60) .. ")")
for _, lhs in ipairs({ "-", "S", "U", "X" }) do
  t.ok(map(s.panel_bufnr, lhs).buffer ~= 1, "a revision view's explorer has no " .. lhs)
end
t.eq(map(s.panel_bufnr, "q").desc, "Close the CodeDiff view", "but closes on q")

vim.cmd.tabnext(1)
vim.cmd.edit(vim.fn.fnameescape(root .. "/sample.md"))
press("<leader>gV")
t.ok(vim.wait(15000, history_ready, 20), "<leader>gV opens the file's history")
local file_tab = vim.api.nvim_get_current_tabpage()
t.eq(vim.t.codediff_label, "history · sample.md", "labelled with the file")
t.eq(map(cd.session(0).panel_bufnr, "q").desc, "Close the CodeDiff view", "the history panel closes on q")
t.eq(#lifecycle.get_session(file_tab).panel.data.commits, 1, "sample.md has one commit")

-- From inside a view: the left pane is not a file.
vim.api.nvim_set_current_win(cd.session(0).panel_win)
notices = {}
press("<leader>gV")
t.ok(said("not a file") ~= nil, "<leader>gV refuses CodeDiff's own buffers")

-- <leader>gq closes the current tabpage's view and leaves the other alone.
local tabs = #vim.api.nvim_list_tabpages()
press("<leader>gq")
t.ok(vim.wait(2000, function() return not vim.api.nvim_tabpage_is_valid(file_tab) end, 20), "<leader>gq closes the history view")
t.eq(#vim.api.nvim_list_tabpages(), tabs - 1, "and only that tabpage")
t.ok(cd.session(rev_tab) ~= nil, "the revision view in the other tabpage is untouched")
vim.api.nvim_set_current_tabpage(rev_tab)
press("<leader>gq")
t.ok(vim.wait(2000, function() return not vim.api.nvim_tabpage_is_valid(rev_tab) end, 20), "and closes there too")

--- Open <leader>gH under `limit` and return how many commits it lists,
--- first and after a refresh (R).
local function repo_history(limit)
  vim.g.ai_review = limit ~= nil and { history_limit = limit } or nil
  vim.api.nvim_set_current_tabpage(editor_tab)
  press("<leader>gH")
  if not vim.wait(15000, history_ready, 20) then return nil end
  local tab = vim.api.nvim_get_current_tabpage()
  local data = lifecycle.get_session(tab).panel.data
  local first = #data.commits
  vim.api.nvim_set_current_win(cd.session(0).panel_win)
  vim.api.nvim_feedkeys("R", "xt", false)
  settle(1500)
  local refreshed = #lifecycle.get_session(tab).panel.data.commits
  t.ok(vim.t.codediff_label:match("^history · ") ~= nil, "<leader>gH is labelled with the repository")
  press("<leader>gq")
  vim.wait(2000, function() return not vim.api.nvim_tabpage_is_valid(tab) end, 20)
  return { first, refreshed }
end
t.eq(repo_history(nil), { 3, 3 }, "<leader>gH lists the repository's commits")
t.eq(repo_history(2), { 2, 2 }, "history_limit caps the listing, refreshes included")
t.eq(repo_history(false), { 3, 3 }, "history_limit = false lifts the cap")
vim.g.ai_review = nil

---------------------------------------------------------------------------
-- The panel internals util.codediff.panel_item reads
---------------------------------------------------------------------------

-- session.panel.view.tree:get_node(line) and the node.data of each kind of
-- entry, on a fixture with a committed and a staged rename so that old_path
-- has something to say.
local panel_root, pgit = repo("codediff panel")
vim.fn.writefile({ "one" }, panel_root .. "/a.txt")
vim.fn.writefile({ "moved" }, panel_root .. "/old.txt")
vim.fn.writefile({ "staged move" }, panel_root .. "/b.txt")
vim.fn.mkdir(panel_root .. "/sub", "p")
vim.fn.writefile({ "deep" }, panel_root .. "/sub/d.txt")
assert(pgit("add", "."))
assert(pgit("commit", "-qm", "base"))
assert(pgit("mv", "old.txt", "new.txt"))
assert(pgit("commit", "-qm", "rename"))
assert(pgit("mv", "b.txt", "c.txt"))
vim.fn.writefile({ "two" }, panel_root .. "/a.txt")
vim.fn.writefile({ "deeper" }, panel_root .. "/sub/d.txt")

do
  --- The panel of the current tabpage's view: its raw session, its view, and the
  --- node.data of every line get_node finds an entry on.
  local function panel_entries()
    local raw_s = lifecycle.get_session(vim.api.nvim_get_current_tabpage())
    local view = raw_s and type(raw_s.panel) == "table" and raw_s.panel.view or {}
    local tree = view.tree
    local found = {}
    if type(tree) == "table" and type(tree.get_node) == "function" and view.bufnr then
      for line = 1, vim.api.nvim_buf_line_count(view.bufnr) do
        local ok, node = pcall(tree.get_node, tree, line)
        if ok and type(node) == "table" and type(node.data) == "table" then
          found[#found + 1] = { line = line, data = node.data }
        end
      end
    end
    return raw_s, view, found
  end
  --- The first entry whose node.data has every field of `fields`.
  local function entry_with(found, fields)
    for _, e in ipairs(found) do
      local hit = true
      for k, v in pairs(fields) do hit = hit and e.data[k] == v end
      if hit then return e end
    end
  end
  local function shape(e, fields)
    local out = {}
    for _, f in ipairs(fields) do out[f] = e and e.data[f] end
    return out
  end
  --- panel_item on `e`'s line of the panel window.
  local function item_at(view, e)
    if not e then return nil end
    vim.api.nvim_win_set_cursor(view.winid, { e.line, 0 })
    return cd.panel_item(0, view.winid)
  end
  local function close_view()
    local tab = vim.api.nvim_get_current_tabpage()
    press("<leader>gq")
    vim.wait(2000, function() return not vim.api.nvim_tabpage_is_valid(tab) end, 20)
    vim.api.nvim_set_current_tabpage(editor_tab)
  end

  vim.api.nvim_set_current_tabpage(editor_tab)
  vim.cmd.cd(vim.fn.fnameescape(panel_root))
  vim.cmd.edit(vim.fn.fnameescape(panel_root .. "/a.txt"))
  press("<leader>gv")
  t.ok(vim.wait(15000, ready("a.txt"), 20), "<leader>gv opens on the panel fixture")
  local praw, pview, found = panel_entries()
  t.eq(praw and praw.panel.name, "explorer", "session.panel.name is explorer")
  t.ok(type(pview.tree) == "table" and type(pview.tree.get_node) == "function" and pview.winid ~= nil,
    "session.panel.view has tree:get_node(line), bufnr and winid")
  t.ok(entry_with(found, { type = "group" }) ~= nil, "a status group's node.data.type is group")
  local changed = entry_with(found, { path = "a.txt" })
  t.eq(shape(changed, { "type", "status", "group" }), { status = "M", group = "unstaged" },
    "an explorer file's node.data: path, status, group, and no type")
  local staged_move = entry_with(found, { path = "c.txt" })
  t.eq(shape(staged_move, { "old_path", "status", "group" }), { old_path = "b.txt", status = "R", group = "staged" },
    "a staged rename's node.data: old_path, status R, group staged")
  local item = item_at(pview, staged_move)
  t.eq(item and { item.panel, item.type, item.path, item.old_path, item.status, item.group },
    { "explorer", "file", "c.txt", "b.txt", "R", "staged" }, "panel_item reads the explorer entry from them")
  -- Files show as a directory tree by default (lua/plugin/vcs/codediff.lua);
  -- `i` toggles a flat list.
  local options = require("codediff.config").options
  t.eq({ options.explorer.view_mode, options.history.view_mode }, { "tree", "tree" },
    "the explorer and history panels default to a directory tree")
  local dir = entry_with(found, { type = "directory" })
  t.ok(dir ~= nil and entry_with(found, { path = "sub/d.txt" }) ~= nil,
    "a file in a subdirectory sits under a directory node")
  item = item_at(pview, dir)
  t.eq(item and item.type, "directory", "panel_item reports a directory node as such, so ,C asks for a file")
  close_view()

  vim.cmd.edit(vim.fn.fnameescape(panel_root .. "/a.txt"))
  press("<leader>gH")
  t.ok(vim.wait(15000, history_ready, 20), "<leader>gH opens on the panel fixture")
  praw, pview, found = panel_entries()
  t.eq(praw and praw.panel.name, "history", "session.panel.name is history")
  t.ok(entry_with(found, { type = "title" }) ~= nil, "the history's title line has node.data.type title")
  local rename = entry_with(found, { type = "commit", subject = "rename" })
  local hash = rename and rename.data.hash
  t.ok(type(hash) == "string" and #hash == 40 and type(rename.data.short_hash) == "string"
    and hash:sub(1, #rename.data.short_hash) == rename.data.short_hash,
    "a commit's node.data: type commit, hash, short_hash and subject " .. vim.inspect(shape(rename, { "hash", "short_hash" })))
  local moved = entry_with(found, { type = "file", path = "new.txt" })
  t.eq(shape(moved, { "old_path", "status", "commit_hash" }), { old_path = "old.txt", status = "R", commit_hash = hash },
    "a commit's file: node.data type file, path, old_path, status and commit_hash")
  item = item_at(pview, moved)
  t.eq(item and { item.panel, item.type, item.path, item.old_path, item.status, item.commit },
    { "history", "file", "new.txt", "old.txt", "R", hash }, "panel_item reads a history file from them")
  item = item_at(pview, rename)
  t.eq(item and { item.type, item.commit, item.short_hash, item.subject }, { "commit", hash, rename.data.short_hash, "rename" },
    "and a commit")
  close_view()

  vim.cmd.edit(vim.fn.fnameescape(panel_root .. "/a.txt"))
  press("<leader>gV")
  t.ok(vim.wait(15000, history_ready, 20), "<leader>gV opens a.txt's history")
  praw, pview, found = panel_entries()
  t.eq(type(praw.panel.data) == "table" and type(praw.panel.data.opts) == "table" and praw.panel.data.opts.file_path, "a.txt",
    "a single file's history names it in session.panel.data.opts.file_path")
  local base = entry_with(found, { type = "commit", subject = "base" })
  t.eq(base and base.data.file_path, "a.txt", "and each commit's node.data.file_path is the file in that commit")
  item = item_at(pview, base)
  t.eq(item and { item.type, item.path }, { "commit", "a.txt" }, "panel_item gives such a commit the file's path")
  close_view()

  -- A single file's history across a rename. CodeDiff keeps each commit's
  -- path from `git log --follow --numstat` (core/git/history.lua): the plain
  -- name, and for the renaming commit either `old => new` verbatim, where
  -- git prints no braces, or the old name alone, where it prints
  -- `dir/{old => new}`; a brace, a `=>` or a blank at the edge of a
  -- component is misread outright. Those listings are pinned as they come,
  -- so a CodeDiff that changes them shows up here. panel_item reads none of
  -- them: every commit row is the followed file as the working tree names
  -- it, which a digest can hash, and no row claims a rename.
  local follow_root, fgit = repo("codediff follow")
  local function rows(prefix, n)
    local out = {}
    for i = 1, n do out[i] = prefix .. " " .. i end
    return out
  end
  local follows = {
    { old = "old.txt", file = "new.txt", listed = "old.txt => new.txt", form = "without braces" },
    { old = "dir/before.txt", file = "dir/after.txt", listed = "dir/before.txt", form = "with braces" },
    { old = "x => y.txt", file = "z.txt", listed = "x => y.txt => z.txt", form = "of a name holding =>" },
    { old = "braces/{a}.txt", file = "braces/{b}.txt", listed = "braces/{a}.txt.txt}", form = "of a name holding braces" },
    { old = "a /f.txt", file = "b/f.txt", listed = "a/f.txt", form = "of a directory ending in a blank" },
  }
  for i, case in ipairs(follows) do
    for _, name in ipairs({ case.old, case.file }) do
      vim.fn.mkdir(vim.fs.dirname(follow_root .. "/" .. name), "p")
    end
    -- Distinct contents, so that git pairs each rename with its own source.
    case.tag = "file" .. i
    vim.fn.writefile(rows(case.tag, 8), follow_root .. "/" .. case.old)
  end
  assert(fgit("add", "."))
  assert(fgit("commit", "-qm", "create"))
  for _, case in ipairs(follows) do vim.fn.writefile(rows(case.tag, 9), follow_root .. "/" .. case.old) end
  assert(fgit("commit", "-qam", "edit before"))
  for _, case in ipairs(follows) do assert(fgit("mv", case.old, case.file)) end
  assert(fgit("commit", "-qm", "rename"))
  for _, case in ipairs(follows) do vim.fn.writefile(rows(case.tag, 10), follow_root .. "/" .. case.file) end
  assert(fgit("commit", "-qam", "edit after"))
  vim.cmd.cd(vim.fn.fnameescape(follow_root))
  for _, case in ipairs(follows) do
    vim.cmd.edit(vim.fn.fnameescape(follow_root .. "/" .. case.file))
    press("<leader>gV")
    t.ok(vim.wait(15000, history_ready, 20), "<leader>gV opens " .. case.file .. "'s history")
    praw, pview, found = panel_entries()
    local listing = vim.tbl_map(function(c) return { c.subject, c.file_path } end, praw.panel.data.commits or {})
    t.eq(listing, { { "edit after", case.file }, { "rename", case.listed }, { "edit before", case.old }, { "create", case.old } },
      "session.panel.data.commits lists the commits newest first, a rename " .. case.form .. " as " .. case.listed)
    for _, subject in ipairs({ "edit after", "rename", "edit before", "create" }) do
      item = item_at(pview, entry_with(found, { type = "commit", subject = subject }))
      t.eq(item and { path = item.path, old_path = item.old_path, status = item.status }, { path = case.file },
        ("panel_item on %q in %s's history"):format(subject, case.file))
    end
    close_view()
  end
  vim.fn.delete(follow_root, "rf")
end
vim.cmd.cd(vim.fn.fnameescape(root))

---------------------------------------------------------------------------
-- A view CodeDiff tears down under its tabpage
---------------------------------------------------------------------------

vim.api.nvim_set_current_tabpage(editor_tab)
vim.cmd.edit(vim.fn.fnameescape(root .. "/sample.md"))
press("<leader>gv")
t.ok(vim.wait(15000, ready("sample.md"), 20), "a second status view opens")
local orphan_tab = vim.api.nvim_get_current_tabpage()
vim.api.nvim_set_current_win(cd.session(0).original_win)
notices = {}
-- :e in the revision pane wipes its buffer, and CodeDiff drops the session
-- but leaves the tabpage with a dead explorer behind.
vim.cmd.edit(vim.fn.fnameescape(root .. "/notes.txt"))
t.ok(vim.wait(3000, function() return not vim.api.nvim_tabpage_is_valid(orphan_tab) end, 20),
  "the abandoned tabpage is closed")
t.ok(said("lost a pane") ~= nil, "with a word about why")
t.eq(#vim.api.nvim_list_tabpages(), 1, "only the editing page is left")
t.ok(vim.fn.bufloaded(root .. "/notes.txt") == 1, "the file asked for is still loaded")

-- The other teardown: a pane's buffer wiped while its tabpage is hidden.
-- CodeDiff drops that session on the way back in, without CodeDiffClose.
press("<leader>gv")
t.ok(vim.wait(15000, ready(), 20), "a third status view opens")
local hidden_tab = vim.api.nvim_get_current_tabpage()
local revision_buf = cd.session(0).original_bufnr
vim.api.nvim_set_current_tabpage(editor_tab)
vim.api.nvim_buf_delete(revision_buf, { force = true })
notices = {}
vim.api.nvim_set_current_tabpage(hidden_tab)
t.ok(vim.wait(3000, function() return not vim.api.nvim_tabpage_is_valid(hidden_tab) end, 20),
  "a view dropped while hidden is closed when its tabpage comes back")
t.eq(#vim.api.nvim_list_tabpages(), 1, "leaving the editing page alone again")

---------------------------------------------------------------------------
-- A merge conflict
---------------------------------------------------------------------------

local conflicted, cgit = repo("codediff conflict")
vim.fn.writefile({ "base" }, conflicted .. "/conflict.txt")
assert(cgit("add", "."))
assert(cgit("commit", "-qm", "base"))
assert(cgit("checkout", "-qb", "other"))
vim.fn.writefile({ "theirs" }, conflicted .. "/conflict.txt")
assert(cgit("commit", "-qam", "theirs"))
assert(cgit("checkout", "-q", "main"))
vim.fn.writefile({ "ours" }, conflicted .. "/conflict.txt")
assert(cgit("commit", "-qam", "ours"))
cgit("merge", "-q", "other")
vim.cmd.edit(vim.fn.fnameescape(conflicted .. "/conflict.txt"))
press("<leader>gv")
t.ok(vim.wait(15000, function()
  local c = cd.session(0)
  return c and c.conflict and c.result_bufnr and vim.api.nvim_buf_is_valid(c.result_bufnr)
    and map(c.result_bufnr, ",go").desc ~= nil and map(c.result_bufnr, ";").desc == "Disabled in CodeDiff"
end, 20), "a conflicted file opens CodeDiff's merge view")
local merge = cd.session(0)
for _, lhs in ipairs({ ",go", ",gt", ",gb", ",ga", ",gO", ",gT", ",gB", ",gA" }) do
  t.ok(map(merge.result_bufnr, lhs).desc ~= nil, "conflict action " .. lhs .. " is on the comma menu")
end
for _, lhs in ipairs({ ",co", "<leader>co", "<leader>ct", "<leader>cO" }) do
  t.eq(map(merge.result_bufnr, lhs), {}, lhs .. " is not mapped")
end
vim.api.nvim_set_current_win(merge.result_win)
local conflict_node = require("which-key.buf").get({ mode = "n", update = true }).tree:find(",g")
t.eq(conflict_node and conflict_node.desc, "Conflict", "the ,g prefix is labelled Conflict where it exists")
local merge_tab = vim.api.nvim_get_current_tabpage()
-- CodeDiff resets the result to the merge base, which leaves it modified and
-- makes close ask first; nothing here is worth keeping.
vim.bo[merge.result_bufnr].modified = false
press("<leader>gq")
t.ok(vim.wait(2000, function() return not vim.api.nvim_tabpage_is_valid(merge_tab) end, 20), "the merge view closes")

vim.notify = real_notify
local cleanup = t.process_cleanup()
cleanup()
vim.cmd.cd(vim.fn.fnameescape(cwd))
for _, dir in ipairs({ root, clean, panel_root, conflicted }) do vim.fn.delete(dir, "rf") end
vim.fn.delete(gitconfig)

t.done()
