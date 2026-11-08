-- Review feedback (lua/ai/review/feedback.lua): the entries ,C writes from a
-- real CodeDiff view, the draft and its float, the staleness check, and
-- delivery to a native agent (its prompt editor's seed) and to a chat.
--
-- Every repository is a scratch one under tempname(), with a space in its
-- path, under an empty global git config. Drafts go to a scratch directory
-- (rounds.draft_path is redirected). No agent is started: the "Claude panel"
-- is a terminal running `cat` with the Snacks record an agent panel carries,
-- claudecode.terminal is a stand-in, and the agent's prompt editor is opened
-- the way scripts/agent-editor opens it (editor.open on a temp file). The chat
-- is a stub object; CodeCompanion is never loaded and nothing is sent.
-- vim.ui.select and vim.ui.input are stubbed throughout: a prompt nobody
-- answers would hang the spec.
local t = dofile("tests/helper.lua")
local Config = require("lazy.core.config")
local api, uv = vim.api, vim.uv
local INFO, WARN = vim.log.levels.INFO, vim.log.levels.WARN

t.eq(package.loaded["ai.review.feedback"], nil, "ai.review.feedback is not loaded at startup")
local plugin = Config.plugins["codediff.nvim"]
local libs = vim.fn.glob(plugin.dir .. "/libvscode_diff*", false, true)
if #libs == 0 then
  t.ok(false, "CodeDiff's native library is installed in " .. plugin.dir .. " (see docs/DIAGNOSTICS.md)")
  t.done()
  return
end

local scratch = vim.fn.tempname() .. " review feedback"
vim.fn.mkdir(scratch, "p")
scratch = uv.fs_realpath(scratch)
local saved_env = { GIT_CONFIG_NOSYSTEM = vim.env.GIT_CONFIG_NOSYSTEM, GIT_CONFIG_GLOBAL = vim.env.GIT_CONFIG_GLOBAL }
vim.env.GIT_CONFIG_NOSYSTEM = "1"
vim.env.GIT_CONFIG_GLOBAL = scratch .. "/gitconfig"
vim.fn.writefile({}, vim.env.GIT_CONFIG_GLOBAL)
local saved_review = vim.g.ai_review
vim.g.ai_review = nil
local spec_cwd = vim.fn.getcwd()

local notes = {}
local real_notify = vim.notify
vim.notify = function(msg, level, opts)
  notes[#notes + 1] = { msg = tostring(msg), level = level or INFO, title = opts and opts.title }
end
local function noted(text)
  for _, n in ipairs(notes) do
    if n.msg:find(text, 1, true) then return n end
  end
end

local real_select, real_input = vim.ui.select, vim.ui.input
local selects, answers = {}, {}
vim.ui.select = function(items, opts, on_choice)
  selects[#selects + 1] = { items = items, prompt = opts.prompt, kind = opts.kind }
  local answer = table.remove(answers, 1)
  on_choice(answer and answer(items) or nil)
end
vim.ui.input = function(_, on_confirm) on_confirm(nil) end
local function choose(want)
  return function(items)
    for _, item in ipairs(items) do
      local text = type(item) == "table" and item.label or item
      if text:find(want, 1, true) then return item end
    end
  end
end
local function kinds() return vim.tbl_map(function(s) return s.kind end, selects) end

local function settle(ms) vim.wait(ms or 100, function() return false end, 10) end
local function map(buf, lhs, mode)
  return api.nvim_buf_call(buf, function() return vim.fn.maparg(lhs, mode or "n", false, true) end)
end

local rounds = require("ai.review.rounds")
local editor = require("ai.editor")
local cd = require("util.codediff")
local config = require("ai.config")

-- Drafts in the scratch directory, laid out as the real ones are.
local real_draft_path = rounds.draft_path
rounds.draft_path = function(root, id)
  return ("%s/drafts/%s/%s.md"):format(scratch, vim.fn.sha256(uv.fs_realpath(root) or root):sub(1, 12), id)
end

---------------------------------------------------------------------------
-- A round in a scratch repository, and its view
---------------------------------------------------------------------------

local root = scratch .. "/proj one"
vim.fn.mkdir(root, "p")
local function git(...)
  local r = vim.system(vim.list_extend({ "git", "-C", root, "-c", "user.name=Fixture",
    "-c", "user.email=fixture@example.invalid", "-c", "commit.gpgsign=false" }, { ... }), { text = true }):wait()
  return r.code == 0 and r.stdout or nil, r.stderr
end
assert(git("init", "-q", "-b", "main"))
local rows = {}
for i = 1, 20 do rows[i] = "f line " .. i end
vim.fn.writefile(rows, root .. "/f.txt")
vim.fn.writefile({ "gone 1", "gone 2" }, root .. "/gone.txt")
vim.fn.writefile({ "old a", "old b", "old c" }, root .. "/old.txt")
assert(git("add", "."))
assert(git("commit", "-qm", "fixture"))

local function save_round(conversation, source)
  local entry
  require("util.baseline").save(root, "round", {
    subject = "spec round", Source = source, Conversation = conversation, Root = root,
  }, function(e, info)
    entry = e or false
    if not e then print("baseline: " .. tostring(info)) end
  end)
  vim.wait(10000, function() return entry ~= nil end, 20)
  return entry
end
local entry = save_round("claude:s1", "claude")
t.ok(entry, "a round baseline is taken")
local vars = rounds.review_vars(entry)
local sha = vars.sha

-- What the agent did since: a changed line, an inserted one, a deletion, a
-- rename (a plain mv) and a new file.
local working = vim.deepcopy(rows)
working[5] = "f line 5 CHANGED"
table.insert(working, 10, "INSERTED")
vim.fn.writefile(working, root .. "/f.txt")
os.remove(root .. "/gone.txt")
os.rename(root .. "/old.txt", root .. "/new.txt")
vim.fn.writefile({ "added" }, root .. "/added.txt")

local editor_tab = api.nvim_get_current_tabpage()
vim.o.lines, vim.o.columns = 50, 200

--- The view shows `rel` and carries this config's keys.
local function shows(rel)
  return function()
    local s = cd.session(0)
    if not s then return false end
    local raw = require("codediff.ui.lifecycle").get_session(s.tabpage)
    if not raw or not raw.refresh or raw.refresh.loading ~= false then return false end
    for _, b in ipairs({ s.modified_bufnr, s.original_bufnr }) do
      if type(b) == "number" and api.nvim_buf_is_valid(b) then
        local name = api.nvim_buf_get_name(b)
        if name:sub(-#rel - 1) == "/" .. rel and map(b, ";").desc == "Disabled in CodeDiff" then return true end
      end
    end
    return false
  end
end

api.nvim_set_current_tabpage(editor_tab)
vim.cmd.cd(vim.fn.fnameescape(root))
vim.cmd.edit(vim.fn.fnameescape(root .. "/f.txt"))
cd.open({ args = { sha }, label = "spec view", tab_vars = { ai_review = vars, codediff_baseline = { sha = sha, kind = "round" } } })
t.ok(vim.wait(15000, shows("f.txt"), 20), "a round view of f.txt opens")
local tab = api.nvim_get_current_tabpage()
local s = cd.session(tab)
t.eq(vim.t[tab].ai_review and vim.t[tab].ai_review.id, vars.id, "the view carries its round")

local feedback = require("ai.review.feedback")
local draft = rounds.draft_path(root, vars.id)

local function draft_lines(path) return vim.fn.filereadable(path or draft) == 1 and vim.fn.readfile(path or draft) or nil end
local function index_of(lines, line, from)
  for i = from or 1, #(lines or {}) do
    if lines[i] == line then return i end
  end
end
local function find(lines, pattern)
  for i, line in ipairs(lines or {}) do
    if line:find(pattern, 1, true) then return i end
  end
end
local function count(lines, pattern)
  local n = 0
  for _, line in ipairs(lines or {}) do
    if line:find(pattern, 1, true) then n = n + 1 end
  end
  return n
end
--- The draft floats in a tabpage (default: this one). Other floats, such as
--- incline's labels, are not the spec's business.
local function floats_here(tp)
  local out = {}
  for _, win in ipairs(api.nvim_tabpage_list_wins(tp or 0)) do
    local name = api.nvim_buf_get_name(api.nvim_win_get_buf(win))
    if api.nvim_win_get_config(win).relative ~= "" and name:match("/drafts/") then out[#out + 1] = win end
  end
  return out
end
local function item(path, side, digest)
  return ("<!-- review-item path=%s side=%s digest=%s -->"):format(vim.json.encode(path), vim.json.encode(side),
    vim.json.encode(digest))
end
local function digest(path)
  local f = io.open(root .. "/" .. path, "rb")
  if not f then return "none" end
  local text = f:read("*a")
  f:close()
  return "sha256:" .. vim.fn.sha256(text)
end

--- Press ,C as attach() would: in `win`, Normal mode or a line range.
local function comment(win, range)
  api.nvim_set_current_tabpage(tab)
  api.nvim_set_current_win(win)
  feedback.comment({
    tab = tab, win = win, buf = api.nvim_win_get_buf(win),
    mode = range and "v" or "n", range = range and { first = range[1], last = range[2] } or nil,
  })
  -- comment() ends in startinsert!, which would otherwise take effect on the
  -- spec's next command.
  vim.cmd("stopinsert")
end

local function hide_float()
  local buf = feedback._buf(draft)
  if buf then feedback.hide(buf) end
end

---------------------------------------------------------------------------
-- Entries
---------------------------------------------------------------------------

-- Normal mode in the right pane: the hunk under the cursor, both sides.
api.nvim_win_set_cursor(s.modified_win, { 5, 0 })
comment(s.modified_win)
local lines = draft_lines()
t.eq(lines and lines[1], ("<!-- nvim-review round=%s sha=%s conversation=claude:s1 root=%s -->")
  :format(vars.id, sha, vim.json.encode(root)), "the draft starts with its header: round, sha, conversation, root")
t.ok(lines and lines[2]:match("^Review of changes since baseline %d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d %(Claude round%) in .+:$") ~= nil,
  "then the intro names the baseline's time and source: " .. tostring(lines and lines[2]))
local at = index_of(lines, "## f.txt:5 (working tree) · was 5 at the baseline")
t.ok(at ~= nil, "the hunk's heading gives both sides' lines, the left as the baseline's")
t.eq(lines and at and vim.list_slice(lines, at + 1, at + 12), {
  "```diff", "@@ -2,7 +2,7 @@",
  " f line 2", " f line 3", " f line 4", "-f line 5", "+f line 5 CHANGED", " f line 6", " f line 7", " f line 8",
  "```", "> ",
}, "the hunk is quoted as a diff of both sides with three lines of context, then the comment line")
t.eq(lines and at and lines[at + 13], item("f.txt", "new", digest("f.txt")),
  "the review-item names the real path and the file's digest")

local win = api.nvim_get_current_win()
local fbuf = api.nvim_win_get_buf(win)
t.eq(api.nvim_win_get_config(win).relative, "editor", "the draft opens in an editor-relative float")
t.eq(fbuf, feedback._buf(draft), "showing the draft")
t.eq(api.nvim_win_get_cursor(win)[1], at + 12, "the cursor is on the new entry's \"> \" line")
t.eq({ vim.b[fbuf].ai_prompt, vim.b[fbuf].autoformat, vim.bo[fbuf].swapfile, vim.bo[fbuf].filetype },
  { true, false, false, "markdown" }, "@file completion on, no autoformat, no swap, markdown")
t.ok(map(fbuf, "<C-d>").callback ~= nil and map(fbuf, "<C-d>", "i").callback ~= nil and map(fbuf, "q").callback ~= nil,
  "<C-d> (Normal and Insert) and q are mapped in the draft")
local own = {}
for _, mode in ipairs({ "n", "i" }) do
  for _, lhs in ipairs({ "<C-c>", "<C-o>", "<C-y>" }) do
    if map(fbuf, lhs, mode).buffer == 1 then own[#own + 1] = mode .. lhs end
  end
end
t.eq(own, {}, "<C-c>, <C-o> and <C-y> stay what they were (no buffer-local mapping)")
t.ok(cd.session(tab) ~= nil and api.nvim_win_is_valid(s.modified_win) and api.nvim_win_is_valid(s.original_win),
  "the view survives the float opening")

-- What is typed reaches the file when the float is hidden; the view stays.
local cursor = api.nvim_win_get_cursor(win)[1]
api.nvim_buf_set_lines(fbuf, cursor - 1, cursor, false, { "> the change drops the eof check" })
map(fbuf, "q").callback()
t.eq(#floats_here(), 0, "q hides the float")
t.ok(cd.session(tab) ~= nil and api.nvim_win_is_valid(s.modified_win), "and the view is intact")
t.ok(index_of(draft_lines(), "> the change drops the eof check") ~= nil, "what was typed is in the draft file")

-- An inserted line: the left side has none.
api.nvim_win_set_cursor(s.modified_win, { 10, 0 })
comment(s.modified_win)
lines = draft_lines()
at = index_of(lines, "## f.txt:10 (working tree) · new since the baseline")
t.ok(at ~= nil and lines[at + 2] == "@@ -7,6 +7,7 @@" and lines[at + 6] == "+INSERTED",
  "an insertion is quoted with its context; the baseline side is empty")
t.eq(count(lines, "Review of changes since baseline"), 1, "the intro is written once per draft")
hide_float()

-- Visual in the right pane: those lines of the working tree.
comment(s.modified_win, { 9, 10 })
lines = draft_lines()
at = index_of(lines, "## f.txt:9-10 (working tree)")
t.ok(at ~= nil, "a right-side selection is headed by its working-tree lines")
t.eq(lines and at and vim.list_slice(lines, at + 1, at + 5), { "```text", "f line 9", "INSERTED", "```", "> " },
  "and quotes them")
hide_float()

-- An unsaved change in that pane is said so.
local rbuf = s.modified_bufnr
api.nvim_buf_set_lines(rbuf, 0, 1, false, { "f line 1 UNSAVED" })
comment(s.modified_win, { 1, 1 })
t.ok(index_of(draft_lines(), "## f.txt:1 (working tree, unsaved buffer)") ~= nil, "a modified buffer is marked unsaved")
hide_float()
api.nvim_buf_set_lines(rbuf, 0, 1, false, { "f line 1" })
vim.bo[rbuf].modified = false

-- Visual in the left pane: the baseline's text, which no file holds.
comment(s.original_win, { 4, 5 })
lines = draft_lines()
at = index_of(lines, "## f.txt:4-5 (baseline side, not on disk)")
t.ok(at ~= nil, "a left-side selection is marked as the baseline side, not on disk")
t.eq(lines and at and vim.list_slice(lines, at + 1, at + 6),
  { "```text", "f line 4", "f line 5", "```", "> ", item("f.txt", "old", digest("f.txt")) },
  "it quotes the baseline's lines, under the working tree's path")
hide_float()

-- Explorer items: the file's name and status only.
local function on_item(path)
  local pwin = s.panel_win
  api.nvim_set_current_tabpage(tab)
  for line = 1, api.nvim_buf_line_count(s.panel_bufnr) do
    api.nvim_win_set_cursor(pwin, { line, 0 })
    local it = cd.panel_item(tab, pwin)
    if it and it.path == path then return pwin, it end
  end
end
local pwin, it = on_item("gone.txt")
t.eq(it and { it.type, it.status }, { "file", "D" }, "panel_item reads the explorer entry under the cursor")
comment(pwin)
lines = draft_lines()
at = index_of(lines, "## gone.txt (D)")
t.ok(at ~= nil and lines[at + 1] == "> " and lines[at + 2] == item("gone.txt", "file", "none"),
  "a deleted file in the explorer: name, D, the comment line; nothing on disk to digest")
hide_float()
pwin = on_item("new.txt")
comment(pwin)
t.ok(index_of(draft_lines(), "## new.txt (R old.txt→new.txt)") ~= nil, "a rename: R old→new")
hide_float()
pwin = on_item("added.txt")
comment(pwin)
t.ok(index_of(draft_lines(), "## added.txt (A)") ~= nil, "a new file: A")
hide_float()
api.nvim_win_set_cursor(pwin, { 1, 0 })
notes = {}
local before = draft_lines()
comment(pwin)
t.ok(noted("Put the cursor on a file") ~= nil and vim.deep_equal(draft_lines(), before),
  "a group line adds nothing, and says why")

-- A deleted file's own view: the baseline side under its real path.
local function select_file(path)
  local w = on_item(path)
  -- CodeDiff's <CR> reads the node under the current window's cursor.
  api.nvim_set_current_win(w)
  map(s.panel_bufnr, "<CR>").callback()
  local ok = vim.wait(10000, function()
    local now = cd.session(tab)
    if not now then return false end
    local raw = require("codediff.ui.lifecycle").get_session(tab)
    return raw and raw.refresh and raw.refresh.loading == false
      and ((now.modified and now.modified.relative == path) or (now.original and now.original.relative == path))
  end, 20)
  settle(300)
  s = cd.session(tab)
  return ok, w
end
t.ok(select_file("gone.txt"), "the explorer selects the deleted file")
t.eq(s.single_side, "original", "a deletion is a one-sided view")
comment(s.original_win, { 1, 2 })
lines = draft_lines()
at = index_of(lines, "## gone.txt:1-2 (baseline side, not on disk)")
t.ok(at ~= nil and lines[at + 2] == "gone 1" and lines[at + 6] == item("gone.txt", "old", "none"),
  "a deleted file's lines: the baseline's real path (original.absolute), never codediff://")
hide_float()
api.nvim_win_set_cursor(s.original_win, { 1, 0 })
comment(s.original_win)
t.ok(find(draft_lines(), "## gone.txt") ~= nil, "Normal mode there quotes it too")
hide_float()

-- A renamed file's view: the working tree's path, the baseline's old one.
t.ok(select_file("new.txt"), "the explorer selects the renamed file")
comment(s.original_win, { 2, 2 })
t.ok(index_of(draft_lines(), "## new.txt:2 (baseline side, as old.txt, not on disk)") ~= nil,
  "the baseline side of a rename names both paths")
hide_float()
comment(s.modified_win, { 1, 1 })
t.ok(index_of(draft_lines(), "## new.txt:1 (working tree)") ~= nil, "its working-tree side, the new path")
hide_float()

local all = table.concat(draft_lines(), "\n")
t.ok(not all:find("codediff://", 1, true), "no entry names a codediff:// buffer")
t.ok(not all:find(scratch, 1, true) or all:find(vim.json.encode(root), 1, true) ~= nil,
  "paths are relative to the root (only the header names it)")
t.eq(count(draft_lines(), "Review of changes since baseline"), 1, "still one intro")

-- Back to f.txt for what follows.
t.ok(select_file("f.txt"), "the explorer selects f.txt again")

---------------------------------------------------------------------------
-- The draft's file is the truth: typing, closing, another Nvim
---------------------------------------------------------------------------

api.nvim_win_set_cursor(s.modified_win, { 5, 0 })
comment(s.modified_win)
win = api.nvim_get_current_win()
fbuf = api.nvim_win_get_buf(win)
cursor = api.nvim_win_get_cursor(win)[1]
api.nvim_buf_set_lines(fbuf, cursor - 1, cursor, false, { "> typed, then the window closed" })
api.nvim_win_close(win, true)
t.ok(index_of(draft_lines(), "> typed, then the window closed") ~= nil, "closing the float any other way still saves")
t.ok(cd.session(tab) ~= nil and api.nvim_win_is_valid(s.modified_win), "and leaves the view intact")

comment(s.modified_win, { 3, 3 })
win = api.nvim_get_current_win()
fbuf = api.nvim_win_get_buf(win)
cursor = api.nvim_win_get_cursor(win)[1]
api.nvim_buf_set_lines(fbuf, cursor - 1, cursor, false, { "> typed while another Nvim wrote" })
-- Another Nvim's ,C lands in the file meanwhile.
local disk = table.concat(draft_lines(), "\n") .. "\n"
local f = assert(io.open(draft, "wb"))
f:write(disk .. "\n## elsewhere.txt (M)\n> from the other Nvim\n")
f:close()
api.nvim_set_current_win(s.modified_win)
lines = draft_lines()
t.ok(index_of(lines, "> typed while another Nvim wrote") ~= nil and index_of(lines, "> from the other Nvim") ~= nil,
  "leaving the float saves; what another Nvim appended meanwhile is kept after it")
hide_float()

---------------------------------------------------------------------------
-- Staleness
---------------------------------------------------------------------------

local real_resolve = rounds.resolve_sink
local resolved = {}
rounds.resolve_sink = function(conversation, roots, cb)
  resolved[#resolved + 1] = { conversation = conversation, roots = roots }
  return real_resolve(conversation, roots, cb)
end

-- added.txt is deleted after its comment, f.txt changes on disk.
vim.fn.writefile(vim.list_extend(vim.deepcopy(working), { "agent wrote more" }), root .. "/f.txt")
os.remove(root .. "/added.txt")
-- Commented before the pane has caught up: the entry quotes what the view
-- shows, which the disk no longer holds (§9, the agent writing meanwhile).
comment(s.modified_win, { 11, 11 })
hide_float()
-- The pane catches up with the write (autoread, as on any focus or :checktime):
-- entries made from here on quote what the disk holds.
api.nvim_buf_call(s.modified_bufnr, function() vim.cmd("silent checktime") end)
vim.wait(5000, function()
  return api.nvim_buf_get_lines(s.modified_bufnr, -2, -1, false)[1] == "agent wrote more"
end, 20)
settle(300)
selects, answers, notes = {}, { choose("Edit first") }, {}
comment(s.modified_win, { 2, 2 })
fbuf = feedback._buf(draft)
feedback.deliver(fbuf)
t.eq(kinds(), { "ai_review_stale" }, "a changed file asks before delivering")
t.ok(selects[1] and vim.deep_equal(selects[1].items, { "Deliver anyway", "Edit first" }), "deliver anyway, or edit first")
t.ok(selects[1] and selects[1].prompt:find("f.txt", 1, true) and selects[1].prompt:find("added.txt", 1, true),
  "naming the files, a deleted one included")
t.eq(#resolved, 0, "Edit first delivers nothing")
lines = draft_lines()
t.ok(index_of(lines, "## ⚠ changed since this comment · f.txt:5 (working tree) · was 5 at the baseline") ~= nil,
  "a stale entry's heading is marked")
t.ok(index_of(lines, "## ⚠ changed since this comment · added.txt (A)") ~= nil, "so is a deleted file's")
t.ok(index_of(lines, "## gone.txt (D)") ~= nil and index_of(lines, "## new.txt (R old.txt→new.txt)") ~= nil,
  "unchanged files are not")
t.ok(index_of(lines, "## ⚠ changed since this comment · f.txt:11 (working tree)") ~= nil,
  "an entry made while the view was behind the disk is marked too")
t.ok(index_of(lines, "## f.txt:2 (working tree)") ~= nil, "but not one made once it caught up")
t.eq(api.nvim_win_get_buf(api.nvim_get_current_win()), fbuf, "the draft is back in focus to edit")
-- Asking again marks nothing twice.
selects, answers = {}, { choose("Edit first") }
feedback.deliver(fbuf)
t.eq(count(draft_lines(), "⚠ changed since this comment"), count(lines, "⚠ changed since this comment"),
  "asking again marks nothing twice")
hide_float()

---------------------------------------------------------------------------
-- Native delivery: the round's Claude, through its prompt editor
---------------------------------------------------------------------------

-- The Claude panel, beside the file in the editor tab.
api.nvim_set_current_tabpage(editor_tab)
vim.cmd("vsplit")
vim.cmd.enew()
local claude_buf = api.nvim_get_current_buf()
local claude_job = vim.fn.jobstart({ "cat" }, { term = true, cwd = root })
vim.b[claude_buf].snacks_terminal = { cmd = { "claude", "--settings", "{}" }, cwd = root }
local native = rounds._state().native
t.ok(vim.wait(2000, function() return native.claude and native.claude.buf == claude_buf end, 10),
  "the stand-in Claude panel is registered")
native.claude.session, native.claude.dirty = "s1", false
vim.cmd("wincmd p")
-- A third tabpage that nothing may touch, after the view's.
vim.cmd("$tabnew")
local other_tab = api.nvim_get_current_tabpage()
vim.cmd("vsplit")
api.nvim_set_current_tabpage(tab)

local saved_terminal = package.loaded["claudecode.terminal"]
package.loaded["claudecode.terminal"] = {
  get_active_terminal_bufnr = function() return claude_buf end,
  ensure_visible = function() end,
}

local function layout(tp)
  local out = {}
  for _, w in ipairs(api.nvim_tabpage_list_wins(tp)) do
    if api.nvim_win_get_config(w).relative == "" then out[#out + 1] = { w, api.nvim_win_get_buf(w) } end
  end
  return out
end
local layouts = { [editor_tab] = layout(editor_tab), [tab] = layout(tab), [other_tab] = layout(other_tab) }
local function untouched(what)
  for tp, before_layout in pairs(layouts) do
    t.eq(layout(tp), before_layout, ("%s: tabpage %d keeps its windows"):format(what, api.nvim_tabpage_get_number(tp)))
  end
end

local last_sent = draft:gsub("%.md$", "") .. ".last-sent.md"
local dir = scratch .. "/prompts"
vim.fn.mkdir(dir .. "/editor", "p")
local function prompt_lines()
  for _, w in ipairs(api.nvim_list_wins()) do
    local cfg = api.nvim_win_get_config(w)
    local title = cfg.relative == "editor" and cfg.title
    if type(title) == "table" then title = (title[1] or {})[1] end
    if type(title) == "string" and title:find("Prompt", 1, true) then
      return api.nvim_buf_get_lines(api.nvim_win_get_buf(w), 0, -1, false), w
    end
  end
end
local function close_prompts()
  for _, w in ipairs(api.nvim_list_wins()) do
    if select(2, prompt_lines()) == w then pcall(api.nvim_win_close, w, true) end
  end
  settle(100)
end
local released = {}
local real_release = editor._release
editor._release = function(sentinel) released[#released + 1] = sentinel end

-- Deliver: the stale entries are confirmed, the owner checks out.
f = assert(io.open(draft, "rb"))
local before_text = f:read("*a")
f:close()
fbuf = (function()
  comment(s.modified_win, { 6, 6 })
  return feedback._buf(draft)
end)()
f = assert(io.open(draft, "rb"))
before_text = f:read("*a")
f:close()
selects, answers, notes, resolved = {}, { choose("Deliver anyway") }, {}, {}
feedback.deliver(fbuf)
settle(100)
t.eq(kinds(), { "ai_review_stale" }, "delivery asks about the stale entries only")
t.eq(resolved[1] and resolved[1].conversation, "claude:s1", "the header's conversation is checked")
t.eq(resolved[1] and resolved[1].roots, { root, root }, "against the header's root and the view's")
t.eq(api.nvim_get_current_tabpage(), editor_tab, "the tab switches to where Claude's panel is shown")
t.eq(api.nvim_get_current_buf(), claude_buf, "the focus is in Claude's terminal")
local mode_after = api.nvim_get_mode().mode
vim.cmd("stopinsert")
t.ok(editor._seed_pending("claude"), "the feedback waits for Claude's prompt editor")
t.eq(editor._seed_pending("codex"), false, "and for Claude's alone")
t.eq(#floats_here(), 0, "no draft float in the tab it went to")
t.eq(#floats_here(tab), 0, "the draft's float is hidden in the view's tab")
untouched("a native delivery")
t.eq(vim.fn.filereadable(last_sent), 0, "nothing is archived before the editor has it")
f = assert(io.open(draft, "rb"))
t.eq(f:read("*a"), before_text, "and the draft is as it was")
f:close()
-- startinsert takes effect once the main loop runs a Normal-mode command,
-- which a headless spec never does; the real UI check sees Terminal mode.
t.ok(mode_after == "t" or mode_after == "nt", "the terminal is left for Terminal mode: " .. mode_after)

-- Codex opening its prompt meanwhile does not take Claude's feedback.
local codex_prompt = dir .. "/editor/0193.md"
vim.fn.writefile({ "codex's own box" }, codex_prompt)
editor.open(codex_prompt, codex_prompt .. ".done")
settle(200)
t.eq(prompt_lines(), { "codex's own box" }, "a Codex prompt opened meanwhile gets none of it")
t.ok(editor._seed_pending("claude"), "Claude's seed still waits")
t.eq(vim.fn.filereadable(last_sent), 0, "and the draft is still not archived")
t.ok(#draft_lines() > 0, "nor emptied")
close_prompts()

-- Claude's editor opens (ctrl+g arrived): the seed follows what was typed.
local claude_prompt = dir .. "/claude-prompt-7f0c.md"
vim.fn.writefile({ "typed in the box" }, claude_prompt)
editor.open(claude_prompt, claude_prompt .. ".done")
settle(200)
local shown = prompt_lines() or {}
t.eq(shown[1], "typed in the box", "the box keeps what was typed")
t.ok(shown[2] and shown[2]:match("^Review of changes since baseline") ~= nil, "the feedback follows it")
local shown_text = table.concat(shown, "\n")
t.ok(not shown_text:find("nvim-review", 1, true) and not shown_text:find("review-item", 1, true),
  "without the header or the review-item lines")
t.ok(shown_text:find("> typed, then the window closed", 1, true) ~= nil, "with the comments")
t.ok(shown_text:find("## ⚠ changed since this comment · f.txt:5", 1, true) ~= nil, "and the stale marks")
t.eq(draft_lines(), {}, "on_consumed empties the draft")
local archived = vim.fn.readfile(last_sent)
t.eq(table.concat(archived, "\n") .. "\n", before_text, "after keeping it as <id>.last-sent.md")
t.ok(not rounds._exempt({ kind = "round", root = root, id = vars.id }), "an empty draft no longer spares its round")
close_prompts()

-- Claude does not open its editor in time: the draft stays.
vim.g.ai_review = { seed_ttl_ms = 200 }
api.nvim_set_current_tabpage(tab)
comment(s.modified_win, { 7, 7 })
fbuf = feedback._buf(draft)
f = assert(io.open(draft, "rb"))
before_text = f:read("*a")
f:close()
selects, answers, notes = {}, {}, {}
feedback.deliver(fbuf)
vim.cmd("stopinsert")
t.ok(editor._seed_pending("claude"), "a second delivery is staged")
t.ok(vim.wait(2000, function() return noted("did not open its prompt editor") ~= nil end, 20),
  "after seed_ttl_ms it says Claude did not open its editor")
local warned = noted("did not open its prompt editor")
t.ok(warned and warned.level == WARN and warned.title == "AI review" and warned.msg:find("Claude Code", 1, true)
  and warned.msg:find("Draft kept", 1, true), "a WARN naming the agent, the draft kept")
f = assert(io.open(draft, "rb"))
t.eq(f:read("*a"), before_text, "the draft is untouched")
f:close()
t.eq(editor._seed_pending("claude"), false, "and the seed is gone")
t.eq(table.concat(vim.fn.readfile(last_sent), "\n") .. "\n", table.concat(archived, "\n") .. "\n",
  "last-sent still holds the delivery that arrived")
vim.g.ai_review = nil

-- Claude's prompt editor already open: the feedback goes straight in.
editor.open(claude_prompt, claude_prompt .. ".done")
settle(200)
api.nvim_set_current_tabpage(tab)
fbuf = (function()
  comment(s.modified_win, { 8, 8 })
  return feedback._buf(draft)
end)()
selects, answers, notes = {}, {}, {}
feedback.deliver(fbuf)
shown = prompt_lines() or {}
t.ok(find(shown, "## f.txt:8 (working tree)") ~= nil, "an open prompt editor gets the text appended")
t.eq(draft_lines(), {}, "and the draft is delivered at once")
t.eq(editor._seed_pending("claude"), false, "without staging a seed")
close_prompts()

-- A Codex prompt open is no Claude prompt.
editor.open(codex_prompt, codex_prompt .. ".done")
settle(200)
api.nvim_set_current_tabpage(tab)
comment(s.modified_win, { 9, 9 })
fbuf = feedback._buf(draft)
feedback.deliver(fbuf)
vim.cmd("stopinsert")
t.eq(prompt_lines(), { "codex's own box" }, "feedback for Claude never lands in Codex's open prompt")
t.ok(editor._seed_pending("claude") and #draft_lines() > 0, "it waits for Claude's, the draft kept")
close_prompts()
editor.stage_seed(nil, { provider = "claude" })
t.ok(noted("did not open its prompt editor") ~= nil and #draft_lines() > 0, "a cleared seed counts as not delivered")

package.loaded["claudecode.terminal"] = saved_terminal

---------------------------------------------------------------------------
-- An unowned draft (a view that is no round's)
---------------------------------------------------------------------------

local unowned = rounds.draft_path(root, "unowned")
vim.t[tab].ai_review = nil
vim.t[tab].codediff_baseline = nil
api.nvim_win_set_cursor(s.modified_win, { 5, 0 })
comment(s.modified_win)
lines = draft_lines(unowned)
t.eq(lines and lines[1], ("<!-- nvim-review round=unowned root=%s -->"):format(vim.json.encode(root)),
  "a view that is no round's writes the root's unowned draft, with no owner in its header")
t.eq(lines and lines[2], ("Review of changes (spec view) in %s:"):format(vim.fn.fnamemodify(root, ":~")),
  "its intro names what the view compares")
t.ok(index_of(lines, ("## f.txt:5 (working tree) · was 5 in %s"):format(sha:sub(1, 8))) ~= nil,
  "and its left side by revision")
feedback.hide(feedback._buf(unowned))
vim.t[tab].ai_review = vars
vim.t[tab].codediff_baseline = { sha = sha, kind = "round" }

---------------------------------------------------------------------------
-- Chat delivery
---------------------------------------------------------------------------

local chat_buf = api.nvim_create_buf(false, true)
api.nvim_buf_set_lines(chat_buf, 0, -1, false, { "## Me", "", "half typed" })
local added = {}
local chat_ui = {}
local chat = {
  id = 777,
  bufnr = chat_buf,
  adapter = { type = "http", name = "anthropic", formatted_name = "Anthropic" },
  ui = chat_ui,
  callbacks = {},
  prompt = {},
}
function chat:add_callback(event, fn)
  self.callbacks[event] = self.callbacks[event] or {}
  table.insert(self.callbacks[event], fn)
  return self
end
function chat.prompt:add(args)
  added[#added + 1] = args.content
  local text = vim.split(args.content, "\n", { plain = true })
  local last = api.nvim_buf_get_lines(chat_buf, -2, -1, false)[1]
  text[1] = last .. text[1]
  api.nvim_buf_set_lines(chat_buf, -2, -1, false, text)
end
function chat_ui:is_visible() return self.winnr ~= nil and api.nvim_win_is_valid(self.winnr) end
function chat_ui:is_visible_non_curtab()
  return self:is_visible() and api.nvim_win_get_tabpage(self.winnr) ~= api.nvim_get_current_tabpage()
end
function chat_ui:hide()
  if self:is_visible() then api.nvim_win_close(self.winnr, true) end
  self.winnr = nil
end
-- Upstream's single-slot open, standing in: a split in this tabpage.
local saved_chat_mod = package.loaded["codecompanion.interactions.chat"]
package.loaded["codecompanion.interactions.chat"] = {
  open = function(args)
    vim.cmd("botright split")
    api.nvim_win_set_buf(0, chat_buf)
    args.ui.winnr = api.nvim_get_current_win()
  end,
}
vim.fn.chdir(root)
rounds.attach_chat(chat)
vim.fn.chdir(spec_cwd)
local cc_conv = ("cc:%s:777"):format(rounds.nonce())
local companion = require("ai.companion")

-- Busy is more than a request in flight.
t.eq(companion.busy(chat), false, "an idle chat is not busy")
chat.current_request = {}
t.eq(companion.busy(chat), true, "a request in flight is busy")
chat.current_request = nil
chat._turn_in_progress = true
t.eq(companion.busy(chat), true, "between two steps of a tool loop (only _turn_in_progress set) is busy")
local ok, why = companion.add_text(chat, "\nmid loop")
t.eq({ ok, why, #added }, { false, "busy", 0 }, "add_text refuses then, adding nothing")
chat._turn_in_progress = nil
vim.bo[chat_buf].modifiable = false
t.eq(companion.busy(chat), true, "a buffer that is not modifiable is busy")
vim.bo[chat_buf].modifiable = true
t.eq({ companion.add_text({ id = 1, bufnr = -1 }, "x") }, { false, "gone" }, "a chat whose buffer is gone is refused")

-- A chat's round, in the same view.
local cc_vars = { id = "cc-round", sha = sha, conversation = cc_conv, source = "cc-http", root = root, late = false }
vim.t[tab].ai_review = cc_vars
local cc_draft = rounds.draft_path(root, "cc-round")
api.nvim_set_current_tabpage(tab)
comment(s.modified_win, { 5, 5 })
lines = draft_lines(cc_draft)
t.ok(lines and lines[2]:find("(API chat round)", 1, true) ~= nil, "a chat's round says so in its intro")

-- Mid tool loop: refused before anything moves, the draft kept.
chat._turn_in_progress = true
layouts = { [editor_tab] = layout(editor_tab), [other_tab] = layout(other_tab) }
selects, answers, notes = {}, {}, {}
feedback.deliver(feedback._buf(cc_draft))
t.ok(noted("The chat is replying") ~= nil, "a chat mid-turn is refused, saying so")
t.eq(#added, 0, "nothing is added to it")
t.eq(draft_lines(cc_draft), lines, "the draft is kept")
t.eq(api.nvim_get_current_tabpage(), tab, "and the tab stays")
chat._turn_in_progress = nil

-- Idle: delivered into the prompt, after a newline, and shown.
selects, answers, notes = {}, {}, {}
f = assert(io.open(cc_draft, "rb"))
before_text = f:read("*a")
f:close()
feedback.deliver(feedback._buf(cc_draft))
t.eq(#added, 1, "the chat gets the feedback once")
t.ok(added[1] and added[1]:sub(1, 1) == "\n", "starting with a newline, so it never joins half-typed text")
t.ok(added[1] and added[1]:find("## f.txt:5 (working tree)", 1, true) and not added[1]:find("review-item", 1, true),
  "the entries without their review-item lines")
t.eq(api.nvim_buf_get_lines(chat_buf, 2, 4, false), { "half typed", "Review of changes since baseline" ..
  (added[1] or ""):match("^\nReview of changes since baseline([^\n]*)") }, "what was typed stays on its own line")
t.eq(api.nvim_get_current_tabpage(), editor_tab, "a chat not on screen is shown in the tab before the view")
t.eq(api.nvim_get_current_buf(), chat_buf, "the cursor is in the chat")
t.eq(api.nvim_win_get_cursor(0)[1], api.nvim_buf_line_count(chat_buf), "at the end of its prompt")
vim.cmd("stopinsert")
t.eq(draft_lines(cc_draft), {}, "the draft is emptied")
t.eq(table.concat(vim.fn.readfile((cc_draft:gsub("%.md$", "")) .. ".last-sent.md"), "\n") .. "\n", before_text,
  "after keeping a copy")
t.eq(layout(other_tab), layouts[other_tab], "the third tabpage is untouched")

---------------------------------------------------------------------------
-- Two revisions: rev vs rev, and a file's history
---------------------------------------------------------------------------

local first = vim.trim(assert(git("rev-parse", "HEAD")))
assert(git("add", "-A"))
assert(git("commit", "-qm", "second"))
local second = vim.trim(assert(git("rev-parse", "HEAD")))
api.nvim_set_current_tabpage(editor_tab)
vim.cmd("only")
vim.cmd.edit(vim.fn.fnameescape(root .. "/f.txt"))
cd.open({ args = { first, second }, label = "two revs" })
t.ok(vim.wait(15000, shows("f.txt"), 20), "a rev-vs-rev view of f.txt opens")
local rev_tab = api.nvim_get_current_tabpage()
local rs = cd.session(rev_tab)
t.eq(rs.mode, "revisions", "comparing two commits")
local saved_tab, saved_s = tab, s
tab, s = rev_tab, rs
api.nvim_win_set_cursor(rs.modified_win, { 5, 0 })
comment(rs.modified_win)
local revs_draft = rounds.draft_path(root, "unowned")
lines = draft_lines(revs_draft)
t.ok(index_of(lines, ("## f.txt:5 (%s) · was 5 in %s"):format(second:sub(1, 8), first:sub(1, 8))) ~= nil,
  "a hunk between two commits names both")
t.ok(lines[#lines]:match("^<!%-%- review%-item") ~= nil, "and carries its review-item")
t.ok(index_of(lines, "Review of changes (two revs) in " .. vim.fn.fnamemodify(root, ":~") .. ":") ~= nil,
  "a new comparison in the unowned draft gets its own intro")
feedback.hide(feedback._buf(revs_draft))
comment(rs.modified_win, { 5, 6 })
t.ok(index_of(draft_lines(revs_draft), ("## f.txt:5-6 (%s side, not on disk) · comparing %s → %s")
  :format(second:sub(1, 8), first:sub(1, 8), second:sub(1, 8))) ~= nil, "a selection there names both revisions")
feedback.hide(feedback._buf(revs_draft))
cd.close(rev_tab)
vim.wait(3000, function() return not api.nvim_tabpage_is_valid(rev_tab) end, 20)

api.nvim_set_current_tabpage(editor_tab)
vim.cmd.edit(vim.fn.fnameescape(root .. "/f.txt"))
cd.open({ args = { "history", "%" }, label = "history · f.txt" })
local hist_ok = vim.wait(15000, function()
  local hs = cd.session(0)
  return hs ~= nil and hs.mode == "history" and shows("f.txt")()
end, 20)
t.ok(hist_ok, "f.txt's history opens on its newest commit")
local hist_tab = api.nvim_get_current_tabpage()
local hs = cd.session(hist_tab)
tab, s = hist_tab, hs
local commit_line
for line = 1, api.nvim_buf_line_count(hs.panel_bufnr) do
  api.nvim_win_set_cursor(hs.panel_win, { line, 0 })
  local hit = cd.panel_item(hist_tab, hs.panel_win)
  if hit and hit.type == "commit" and hit.commit == second then commit_line = line break end
end
t.ok(commit_line ~= nil, "panel_item finds the history's commit entry")
comment(hs.panel_win)
t.ok(index_of(draft_lines(revs_draft), ('## f.txt (changed in %s "second")'):format(second:sub(1, 8))) ~= nil,
  "a commit in a file's history: that file, changed in that commit")
feedback.hide(feedback._buf(revs_draft))
cd.close(hist_tab)
vim.wait(3000, function() return not api.nvim_tabpage_is_valid(hist_tab) end, 20)
tab, s = saved_tab, saved_s

---------------------------------------------------------------------------
-- comment() never raises
---------------------------------------------------------------------------

notes = {}
api.nvim_set_current_tabpage(other_tab)
feedback.comment({ tab = other_tab, win = api.nvim_get_current_win(), buf = api.nvim_get_current_buf(), mode = "n" })
t.ok(noted("no CodeDiff view") ~= nil, "outside a view it warns instead")
feedback.comment(nil)
t.ok(#notes >= 2, "and so with no arguments at all")

---------------------------------------------------------------------------
-- Cleanup
---------------------------------------------------------------------------

package.loaded["codecompanion.interactions.chat"] = saved_chat_mod
editor._release = real_release
rounds.resolve_sink = real_resolve
rounds.draft_path = real_draft_path
pcall(vim.fn.jobstop, claude_job)
api.nvim_set_current_tabpage(tab)
cd.close(tab)
vim.wait(3000, function() return not api.nvim_tabpage_is_valid(tab) end, 20)
vim.ui.select, vim.ui.input = real_select, real_input
vim.notify = real_notify
vim.fn.chdir(spec_cwd)
vim.g.ai_review = saved_review
for k, v in pairs(saved_env) do vim.env[k] = v end
vim.fn.delete(scratch, "rf")
t.done()
