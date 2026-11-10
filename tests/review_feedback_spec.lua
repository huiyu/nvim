-- Review feedback (lua/ai/review/feedback.lua): the entries ,C writes from a
-- real CodeDiff view, the draft and its float, the staleness check, and
-- delivery to a native agent (its prompt editor's seed) and to a chat. Also:
-- the draft's structure is the header and markers carrying its nonce, so
-- quoted or typed lines that look like its own (a heading, a fence, another
-- draft's header and markers) are text, and its own stay its own when a line
-- is joined onto them; every way of closing the float saves it; a draft with
-- no feedback left is an empty file, its open float keeping a header and an
-- intro to type under that are no part of the file; and two Nvims on one
-- draft -- the second one a second copy of the module, with buffers of its
-- own -- merge what they type entry by entry, never write delivered entries
-- back, and say why whatever they set aside was.
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

-- sd and the other window keys are which-key's, mapped once its loader has
-- run at VimEnter; a spec runs before that point.
require("lazy").load({ plugins = { "which-key.nvim" } })
vim.api.nvim_exec_autocmds("VimEnter", { modeline = false })
t.ok(vim.wait(1000, function() return vim.fn.maparg("sd", "n") ~= "" end, 10), "the window keys are mapped")

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

-- `notes` is reset by each case; everything feedback itself shows or asks is
-- also kept for the readability check at the end.
local notes, every_note, every_prompt = {}, {}, {}
local function from_feedback()
  local caller = debug.getinfo(3, "S")
  return caller ~= nil and caller.source:find("ai/review/feedback.lua", 1, true) ~= nil
end
local real_notify = vim.notify
vim.notify = function(msg, level, opts)
  notes[#notes + 1] = { msg = tostring(msg), level = level or INFO, title = opts and opts.title }
  if from_feedback() then every_note[#every_note + 1] = notes[#notes] end
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
  if from_feedback() then every_prompt[#every_prompt + 1] = selects[#selects] end
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
-- Feedback here is for Claude alone. Were any to reach Codex, its real
-- edit_prompt would start a Codex terminal in this Nvim: it only counts.
local codex = require("ai.backend.codex")
local real_codex_edit_prompt, codex_fed = codex.edit_prompt, 0
codex.edit_prompt = function() codex_fed = codex_fed + 1 end

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
-- A Markdown file whose lines look like a draft's own: another draft's
-- entry marker, header and intro marker, an intro and a heading. An entry
-- quotes them as they are.
local readme = {
  "# Demo",
  '<!-- nvim-review-item n=0123456789ab id=1.1.1 path="x.txt" side="new" digest="none" -->',
  '<!-- nvim-review n=0123456789ab round=elsewhere root="/nowhere" -->',
  "<!-- nvim-review-intro n=0123456789ab id=1.1.2 -->",
  "Review of changes since baseline 2020-01-01 00:00:00 (Codex round) in ~/elsewhere:",
  "## Install",
  "run it",
}
vim.fn.writefile(readme, root .. "/README.md")

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
--- What the entry marker on line `i` of a draft says, when it carries the
--- nonce of the draft's header (line 1); nil when it is no such marker.
local function item_at(lines, i)
  local head = lines and lines[1] and feedback._parse_header(lines[1])
  local body = head and lines[i] and lines[i]:match("^<!%-%- nvim%-review%-item (.-) %-%->$")
  if not body then return nil end
  local a = {}
  for key, value in body:gmatch('(%w+)="([^"]*)"') do a[key] = value end
  for key, value in body:gmatch('(%w+)=([^%s"]+)') do a[key] = a[key] or value end
  if a.n ~= head.n or not a.id then return nil end
  return { path = a.path, side = a.side, digest = a.digest }
end
local function digest(path)
  local f = io.open(root .. "/" .. path, "rb")
  if not f then return "none" end
  local text = f:read("*a")
  f:close()
  return "sha256:" .. vim.fn.sha256(text)
end

--- Press ,C as attach() would: in `win`, Normal mode or a line range; through
--- `via` (another Nvim's module, below) instead of this one's when given.
local function comment(win, range, via)
  api.nvim_set_current_tabpage(tab)
  api.nvim_set_current_win(win)
  local mod = via or feedback
  mod.comment({
    tab = tab, win = win, buf = api.nvim_win_get_buf(win),
    mode = range and "v" or "n", range = range and { first = range[1], last = range[2] } or nil,
  })
  -- comment() ends in startinsert!, which would otherwise take effect on the
  -- spec's next command.
  vim.cmd("stopinsert")
end

--- How many lines of the draft are `want`.
local function exactly(want, path)
  return #vim.tbl_filter(function(l) return l == want end, draft_lines(path) or {})
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
local head = lines and feedback._parse_header(lines[1]) or {}
t.ok(type(head.n) == "string" and head.n:match("^" .. ("%x"):rep(12) .. "$") ~= nil, "a new draft has a nonce of its own")
t.eq(lines and lines[1], ("<!-- nvim-review n=%s round=%s sha=%s conversation=claude:s1 root=%s -->")
  :format(head.n, vars.id, sha, vim.json.encode(root)), "the draft starts with its header: nonce, round, sha, conversation, root")
t.eq(lines and lines[2], ("<!-- nvim-review-intro n=%s id=%s -->"):format(head.n, lines and lines[2]:match("id=([%d.]+)")),
  "then the intro's marker, with the nonce")
t.ok(lines and lines[3]:match("^Review of changes since baseline %d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d %(Claude round%) in .+:$") ~= nil,
  "then the intro names the baseline's time and source: " .. tostring(lines and lines[3]))
local at = index_of(lines, "## f.txt:5 (working tree) · was 5 at the baseline")
t.ok(at ~= nil, "the hunk's heading gives both sides' lines, the left as the baseline's")
t.eq(lines and at and vim.list_slice(lines, at + 1, at + 12), {
  "```diff", "@@ -2,7 +2,7 @@",
  " f line 2", " f line 3", " f line 4", "-f line 5", "+f line 5 CHANGED", " f line 6", " f line 7", " f line 8",
  "```", "> ",
}, "the hunk is quoted as a diff of both sides with three lines of context, then the comment line")
t.eq(lines and at and item_at(lines, at - 1), { path = "f.txt", side = "new", digest = digest("f.txt") },
  "the entry's marker, right before its heading, names the real path and the file's digest")

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
  { "```text", "f line 4", "f line 5", "```", "> " }, "it quotes the baseline's lines")
t.eq(lines and at and item_at(lines, at - 1), { path = "f.txt", side = "old", digest = digest("f.txt") },
  "under the working tree's path")
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
t.ok(at ~= nil and lines[at + 1] == "> "
  and vim.deep_equal(item_at(lines, at - 1), { path = "gone.txt", side = "file", digest = "none" }),
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
t.ok(at ~= nil and lines[at + 2] == "gone 1"
  and vim.deep_equal(item_at(lines, at - 1), { path = "gone.txt", side = "old", digest = "none" }),
  "a deleted file's lines: the baseline's real path (original.absolute), never codediff://")
hide_float()
api.nvim_win_set_cursor(s.original_win, { 1, 0 })
local gone_entries = count(draft_lines(), "## gone.txt")
comment(s.original_win)
t.eq(count(draft_lines(), "## gone.txt"), gone_entries + 1, "Normal mode there adds an entry too")
t.eq(exactly("## gone.txt:1 (baseline side, not on disk)"), 1, "quoting the cursor line of the baseline side")
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
-- The header names the root, and so does the intro (in full when the scratch
-- directory is outside $HOME); an entry's heading or marker never does.
local in_scratch = vim.fs.basename(scratch) .. "/"
local absolute = {}
for i, l in ipairs(draft_lines()) do
  local named = l:match('^<!%-%- nvim%-review%-item .-path=("[^"]*")')
  named = named and vim.json.decode(named)
  local heading = l:match("^## ") ~= nil
  if i > 1 and ((heading and (l:find(in_scratch, 1, true) or l:match("^## /")))
      or (named and (named:sub(1, 1) == "/" or named:find(in_scratch, 1, true)))) then
    absolute[#absolute + 1] = l
  end
end
t.eq(absolute, {}, "entries name their files relative to the root: no heading or marker holds a full path")
t.eq(count(draft_lines(), "Review of changes since baseline"), 1, "still one intro")

-- Lines that look like the draft's own, quoted, stay the file's: the quote
-- keeps them as they are, and the draft never reads them as its own.
t.ok(select_file("README.md"), "the explorer selects README.md")
local intro_line = draft_lines()[3]
comment(s.modified_win, { 2, 7 })
local readme_quote = vim.list_extend({ "```markdown" }, vim.list_slice(readme, 2, 7))
readme_quote[#readme_quote + 1] = "```"
lines = draft_lines()
at = index_of(lines, "## README.md:2-7 (working tree)")
t.eq(lines and at and vim.list_slice(lines, at + 1, at + #readme_quote), readme_quote,
  "lines shaped like another draft's markers and header, an intro and a heading are quoted as they are")
hide_float()

-- Back to f.txt for what follows.
t.ok(select_file("f.txt"), "the explorer selects f.txt again")

---------------------------------------------------------------------------
-- The draft's file is the truth: typing, closing, another Nvim
---------------------------------------------------------------------------

api.nvim_win_set_cursor(s.modified_win, { 5, 0 })
comment(s.modified_win)
t.eq(exactly(intro_line), 1, "a quoted intro is the file's: the next entry from the same view adds none")
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
-- Two Nvims on one draft
---------------------------------------------------------------------------

-- The other Nvim: a second copy of the module, with drafts and buffers of its
-- own, on the same files. Its float's buffer cannot take the draft's name
-- while this one's has it; the module never reads that name.
local other = (function()
  local mine = package.loaded["ai.review.feedback"]
  package.loaded["ai.review.feedback"] = nil
  local mod = require("ai.review.feedback")
  package.loaded["ai.review.feedback"] = mine
  return mod
end)()
t.ok(other ~= feedback, "a second Nvim's module")

--- Feedback from here on goes to round `id`'s draft, in the same view.
local function use_round(id)
  vim.t[tab].ai_review = vim.tbl_extend("force", vars, { id = id })
  return rounds.draft_path(root, id)
end
--- Type `text` over the comment line of the entry headed `heading` in `buf`.
local function type_comment(buf, heading, text)
  local now = api.nvim_buf_get_lines(buf, 0, -1, false)
  for i = (index_of(now, heading) or #now + 1) + 1, #now do
    if now[i]:match("^>") then return api.nvim_buf_set_lines(buf, i - 1, i, false, { text }) end
  end
  error("no comment line under " .. heading)
end

do
  local shared = use_round("two-nvims")
  local E1, E2 = "## f.txt:5 (working tree) · was 5 at the baseline", "## f.txt:3 (working tree)"
  -- A comments on one hunk, B on another: B's ,C writes on top of A's.
  api.nvim_win_set_cursor(s.modified_win, { 5, 0 })
  comment(s.modified_win)
  local a_buf = feedback._buf(shared)
  comment(s.modified_win, { 3, 3 }, other)
  local b_buf = other._buf(shared)
  t.ok(a_buf and b_buf and a_buf ~= b_buf, "each Nvim shows the draft in a buffer of its own")
  -- A types and leaves; then B, whose buffer A's write has overtaken.
  notes = {}
  type_comment(a_buf, E1, "> c1 from A")
  feedback.hide(a_buf)
  type_comment(b_buf, E2, "> c2 from B")
  other.hide(b_buf)
  lines = draft_lines(shared)
  t.ok(index_of(lines, "> c1 from A") ~= nil and index_of(lines, "> c2 from B") ~= nil,
    "two Nvims commenting on one draft: both comments reach the file")
  t.eq({ exactly(E1, shared), exactly(E2, shared) }, { 1, 1 }, "each entry once")
  t.eq(noted("changed elsewhere"), nil, "with no warning: they changed different lines")

  -- Both type over the same comment: the file keeps the version it has, the
  -- one saved second goes beside it.
  comment(s.modified_win, { 7, 7 })
  a_buf = feedback._buf(shared)
  comment(s.modified_win, { 8, 8 }, other)
  b_buf = other._buf(shared)
  type_comment(a_buf, E1, "> A's second thought")
  feedback.hide(a_buf)
  notes = {}
  type_comment(b_buf, E1, "> B's second thought")
  other.hide(b_buf)
  lines = draft_lines(shared)
  local aside = (shared:gsub("%.md$", "")) .. ".conflict.md"
  t.ok(index_of(lines, "> A's second thought") ~= nil and index_of(lines, "> B's second thought") == nil
    and index_of(lines, "## f.txt:8 (working tree)") ~= nil,
    "the same line changed in both: the file keeps what it had, B's entry included")
  t.ok(index_of(draft_lines(aside), "> B's second thought") ~= nil, "B's version is written beside it")
  local warned_aside = noted("changed elsewhere in the same lines")
  t.ok(warned_aside and warned_aside.level == WARN and warned_aside.title == "AI review"
    and warned_aside.msg:find(vim.fn.fnamemodify(aside, ":~"), 1, true) ~= nil, "and B is warned, naming that file")
end

---------------------------------------------------------------------------
-- Every way of closing the float saves it
---------------------------------------------------------------------------

do
  local closing = use_round("closing")
  t.ok(vim.fn.maparg("sd", "n"):find("WindowCloseCurrent", 1, true) ~= nil, "sd closes the current window")
  for _, how in ipairs({
    { ":close", function() vim.cmd("close") end },
    { "nvim_win_close(win, false)", function(w) api.nvim_win_close(w, false) end },
    { "sd", function() api.nvim_feedkeys("sd", "mx", false) end },
  }) do
    comment(s.modified_win, { 4, 4 })
    local w = api.nvim_get_current_win()
    local b = api.nvim_win_get_buf(w)
    local said = "> closed with " .. how[1]
    -- An Ex substitution: a change made outside Insert mode, so no InsertLeave
    -- has saved it.
    vim.cmd(("silent keeppatterns s/^> $/%s/"):format(vim.fn.escape(said, "/\\&~")))
    t.ok(vim.bo[b].modified, how[1] .. ": the draft is edited in Normal mode, not saved yet")
    local ok, err = pcall(how[2], w)
    t.ok(ok and not api.nvim_win_is_valid(w), how[1] .. " closes the float: " .. tostring(err))
    t.eq(exactly(said, closing), 1, how[1] .. " saves the edit first")
    settle(50)
  end
  t.eq(#floats_here(), 0, "no draft float is left")
end

---------------------------------------------------------------------------
-- A draft with no feedback left is no draft
---------------------------------------------------------------------------

do
  local emptied = use_round("emptied")
  local emptied_round = { kind = "round", root = root, id = "emptied" }
  comment(s.modified_win, { 4, 4 })
  local b = feedback._buf(emptied)
  t.ok(rounds._exempt(emptied_round), "a draft with an entry spares its round")
  -- The entry deleted, its header and intro kept.
  api.nvim_buf_set_lines(b, 3, -1, false, {})
  feedback.hide(b)
  t.eq(uv.fs_stat(emptied).size, 0, "a draft left with its header and intro alone is written as an empty file")
  t.eq(rounds._exempt(emptied_round), false, "and spares its round no more")

  -- A header and intro left on disk some other way: <C-d> empties the file.
  comment(s.modified_win, { 4, 4 })
  b = feedback._buf(emptied)
  vim.fn.writefile(vim.list_slice(draft_lines(emptied), 1, 3), emptied)
  notes, selects = {}, {}
  feedback.deliver(b)
  t.ok(noted("The draft is empty") ~= nil and #selects == 0, "delivering it says there is nothing to deliver")
  t.eq(uv.fs_stat(emptied).size, 0, "and empties the file")
  local kept = api.nvim_buf_get_lines(b, 0, -1, false)
  t.ok(feedback._parse_header(kept[1]) ~= nil and index_of(kept, intro_line) ~= nil and find(kept, "## ") == nil,
    "while the float keeps its header and intro to type under: " .. vim.inspect(kept))

  -- The next ,C starts the draft again.
  comment(s.modified_win, { 5, 5 })
  lines = draft_lines(emptied)
  t.ok(lines and feedback._parse_header(lines[1]) ~= nil and lines[3] == intro_line,
    "the next ,C writes the header and intro again")
  local w = api.nvim_get_current_win()
  t.eq(api.nvim_win_get_buf(w), feedback._buf(emptied), "and shows the draft")
  t.eq(api.nvim_buf_get_lines(feedback._buf(emptied), 0, -1, false), lines, "as the file holds it")
  t.eq(lines and lines[api.nvim_win_get_cursor(w)[1] - 1], "```", "the cursor on its entry's comment line")
  t.eq(lines and lines[api.nvim_win_get_cursor(w)[1]], "> ", "which is empty")
  feedback.hide(feedback._buf(emptied))
end

---------------------------------------------------------------------------
-- The draft's structure: nothing typed or quoted takes it apart
---------------------------------------------------------------------------

do
  -- Delivery stops at resolve_sink here: what reaches it is the question.
  local real_resolve_sink = rounds.resolve_sink
  local sunk = {}
  rounds.resolve_sink = function(conversation) sunk[#sunk + 1] = conversation end
  local function header_of(ls) return ls and ls[1] and feedback._parse_header(ls[1]) end
  local function intro_index(ls)
    for i, l in ipairs(ls or {}) do
      if l:match("^Review of changes since baseline") then return i end
    end
  end
  --- Whether any conflict file beside `path` holds `line`.
  local function aside_has(path, line)
    for _, file in ipairs(vim.fn.glob((path:gsub("%.md$", "")) .. ".conflict*.md", false, true)) do
      if index_of(vim.fn.readfile(file), line) then return file end
    end
  end

  -- Every entry deleted in the open float: the file is empty, the float keeps
  -- its header and intro, and a note typed there afterwards delivers.
  local p = use_round("structure-settled")
  comment(s.modified_win, { 4, 4 })
  local b = feedback._buf(p)
  local intro_at = intro_index(api.nvim_buf_get_lines(b, 0, -1, false))
  api.nvim_buf_set_lines(b, intro_at, -1, false, {})
  vim.cmd("write")
  t.eq(uv.fs_stat(p).size, 0, "a draft emptied in its float is written as an empty file")
  local now = api.nvim_buf_get_lines(b, 0, -1, false)
  t.ok(header_of(now) ~= nil and intro_index(now) ~= nil,
    "the open float keeps its header and intro: " .. vim.inspect(now))
  api.nvim_buf_set_lines(b, -1, -1, false, { "", "Please also rename foo to bar everywhere." })
  notes, sunk = {}, {}
  feedback.deliver(b)
  t.eq(noted("lost its first line"), nil, "a note typed there afterwards has its header")
  t.eq(sunk, { "claude:s1" }, "and goes to the round's conversation")
  lines = draft_lines(p)
  t.ok(header_of(lines) ~= nil and index_of(lines, "Please also rename foo to bar everywhere.") ~= nil,
    "the file holds the note under the header")
  feedback.hide(b)

  -- The header line deleted in the float: it is the draft's metadata, so the
  -- next save writes it again.
  p = use_round("structure-headless")
  comment(s.modified_win, { 4, 4 })
  b = feedback._buf(p)
  api.nvim_buf_set_lines(b, 0, 1, false, {})
  type_comment(b, "## f.txt:4 (working tree)", "> the header line was deleted")
  notes, sunk = {}, {}
  feedback.deliver(b)
  t.eq(noted("lost its first line"), nil, "deleting the header line in the float loses nothing")
  t.eq(sunk, { "claude:s1" }, "the draft still delivers to its conversation")
  t.ok(header_of(draft_lines(p)) ~= nil, "the file's first line is its header again")
  t.ok(header_of(api.nvim_buf_get_lines(b, 0, -1, false)) ~= nil, "and the float's")
  feedback.hide(b)

  -- Two Nvims starting the draft at once: B types into its float after a
  -- delivery emptied it, while A's ,C writes it afresh (the verifier's
  -- probe_top).
  p = use_round("structure-top")
  comment(s.modified_win, { 4, 4 })
  feedback.hide(feedback._buf(p))
  comment(s.modified_win, { 3, 3 }, other)
  b = other._buf(p)
  vim.fn.writefile({}, p)
  notes = {}
  other.deliver(b)
  t.ok(noted("The draft is empty") ~= nil, "B finds the draft delivered")
  api.nvim_win_set_cursor(s.modified_win, { 5, 0 })
  comment(s.modified_win)
  local a = feedback._buf(p)
  api.nvim_buf_set_lines(b, -1, -1, false, { "General note from B." })
  notes = {}
  other.hide(b)
  lines = draft_lines(p)
  t.ok(header_of(lines) ~= nil, "both start the draft: its first line is still the header " .. vim.inspect(lines))
  t.ok(index_of(lines, "General note from B.") ~= nil
    and index_of(lines, "## f.txt:5 (working tree) · was 5 at the baseline") ~= nil, "with B's note and A's entry")
  t.eq(noted("changed elsewhere"), nil, "and no warning: neither typed over the other")
  notes, sunk = {}, {}
  feedback.deliver(a)
  t.eq(noted("lost its first line"), nil, "A can deliver it")
  t.eq(sunk, { "claude:s1" }, "to the round's conversation")
  feedback.hide(a)

  -- A comment B typed on an entry delivered meanwhile, saved after A's next
  -- ,C: never grafted onto A's new entry (the verifier's probe_graft).
  p = use_round("structure-graft")
  local E1, E3 = "## f.txt:5 (working tree) · was 5 at the baseline", "## f.txt:10 (working tree) · new since the baseline"
  api.nvim_win_set_cursor(s.modified_win, { 5, 0 })
  comment(s.modified_win, nil, other)
  b = other._buf(p)
  api.nvim_set_current_win(s.modified_win)
  type_comment(b, E1, "> B: this hunk at line 5 is wrong")
  vim.fn.writefile({}, p)
  api.nvim_win_set_cursor(s.modified_win, { 10, 0 })
  comment(s.modified_win)
  a = feedback._buf(p)
  notes = {}
  other.hide(b)
  lines = draft_lines(p)
  t.eq(index_of(lines, "> B: this hunk at line 5 is wrong"), nil,
    "a comment on an entry delivered elsewhere lands on no other entry: " .. vim.inspect(lines))
  local at3 = index_of(lines, E3)
  t.ok(at3 ~= nil and exactly(E3, p) == 1 and index_of(lines, E1) == nil, "the draft holds A's new entry alone")
  t.eq(at3 and lines[#lines], "> ", "its comment line untouched")
  local aside = aside_has(p, "> B: this hunk at line 5 is wrong")
  t.ok(aside ~= nil, "B's comment is kept beside the draft")
  local warned_graft = noted("deleted elsewhere")
  t.ok(warned_graft and warned_graft.level == WARN and aside
    and warned_graft.msg:find(vim.fn.fnamemodify(aside, ":~"), 1, true) ~= nil, "and B is warned, naming that file")
  feedback.hide(a)

  -- The same with A's float still open through the delivery: A's next ,C goes
  -- on under the nonce A knows, so only the entries' ids tell them apart.
  p = use_round("structure-graft-nonce")
  api.nvim_win_set_cursor(s.modified_win, { 5, 0 })
  comment(s.modified_win, nil, other)
  b = other._buf(p)
  comment(s.modified_win, { 3, 3 })
  a = feedback._buf(p)
  local nonce = (feedback._parse_header(draft_lines(p)[1]) or {}).n
  api.nvim_set_current_win(s.modified_win)
  type_comment(b, E1, "> B: this hunk at line 5 is wrong")
  vim.fn.writefile({}, p)
  api.nvim_win_set_cursor(s.modified_win, { 10, 0 })
  comment(s.modified_win)
  t.eq(a, feedback._buf(p), "A's float stayed open")
  t.eq((feedback._parse_header(draft_lines(p)[1]) or {}).n, nonce, "and A's ,C keeps the nonce it knows")
  notes = {}
  other.hide(b)
  lines = draft_lines(p)
  t.eq(index_of(lines, "> B: this hunk at line 5 is wrong"), nil, "B's comment lands on no other entry of that nonce")
  t.ok(exactly(E3, p) == 1 and index_of(lines, E1) == nil and index_of(lines, "## f.txt:3 (working tree)") == nil
    and lines[#lines] == "> ", "the draft holds A's new entry alone, untouched: " .. vim.inspect(lines))
  t.ok(aside_has(p, "> B: this hunk at line 5 is wrong") ~= nil and noted("deleted elsewhere") ~= nil,
    "B's comment is kept beside the draft, with a warning")
  feedback.hide(a)

  -- A fence typed in a comment and left open: every later entry is still an
  -- entry (the verifier's probe_classify).
  p = use_round("structure-fence")
  local pw = on_item("new.txt")
  comment(pw)
  b = feedback._buf(p)
  type_comment(b, "## new.txt (R old.txt→new.txt)", "> try this instead:")
  now = api.nvim_buf_get_lines(b, 0, -1, false)
  local c = index_of(now, "> try this instead:")
  api.nvim_buf_set_lines(b, c, c, false, { "```sh", "echo better" })
  feedback.hide(b)
  comment(s.modified_win, { 4, 4 })
  b = feedback._buf(p)
  local new_txt = vim.fn.readfile(root .. "/new.txt", "b")
  vim.fn.writefile(vim.list_extend(vim.deepcopy(new_txt), { "changed" }), root .. "/new.txt", "b")
  notes, selects, answers, sunk = {}, {}, { choose("Edit first") }, {}
  feedback.deliver(b)
  vim.fn.writefile(new_txt, root .. "/new.txt", "b")
  t.eq(kinds(), { "ai_review_stale" }, "an unclosed fence in a comment hides no entry from the staleness check")
  local why_fence = noted("Changed since you commented")
  t.ok(why_fence and why_fence.msg:find("\nnew.txt\n", 1, true) ~= nil, "the notice names that entry's file")
  lines = draft_lines(p)
  t.ok(index_of(lines, "## ⚠ changed since this comment · new.txt (R old.txt→new.txt)") ~= nil,
    "and its heading is marked")
  local msg = feedback._message(lines)
  t.ok(not msg:find("review-item", 1, true) and not msg:find("nvim-review", 1, true),
    "what would be sent holds none of the draft's own lines")
  t.ok(msg:find("echo better", 1, true) ~= nil and msg:find("## f.txt:4 (working tree)", 1, true) ~= nil,
    "and all of its text")
  feedback.hide(b)

  -- Another draft's real header and markers, pasted into a comment, are text.
  local px = use_round("structure-x")
  pw = on_item("new.txt")
  comment(pw)
  local pasted = vim.tbl_filter(function(l) return l:match("^<!%-%-") ~= nil end, draft_lines(px))
  feedback.hide(feedback._buf(px))
  p = use_round("structure-y")
  comment(s.modified_win, { 3, 3 })
  b = feedback._buf(p)
  type_comment(b, "## f.txt:3 (working tree)", "> as in the other draft:")
  now = api.nvim_buf_get_lines(b, 0, -1, false)
  c = index_of(now, "> as in the other draft:")
  api.nvim_buf_set_lines(b, c, c, false, pasted)
  vim.fn.writefile(vim.list_extend(vim.deepcopy(new_txt), { "changed" }), root .. "/new.txt", "b")
  notes, selects, answers, sunk = {}, {}, {}, {}
  feedback.deliver(b)
  vim.fn.writefile(new_txt, root .. "/new.txt", "b")
  t.ok(#pasted >= 2, "the other draft has a header and markers to paste")
  t.eq({ kinds(), sunk }, { {}, { "claude:s1" } }, "another draft's markers are no entries of this one")
  msg = feedback._message(draft_lines(p))
  t.ok(msg:find(table.concat(pasted, "\n"), 1, true) ~= nil, "they are text, sent as typed")
  feedback.hide(b)

  -- An intro's line is no feedback even once its marker is deleted: a draft
  -- left with just that line is empty, so it spares no round and sends nothing.
  p = use_round("structure-intro-alone")
  comment(s.modified_win, { 3, 3 })
  feedback.hide(feedback._buf(p))
  local alone = draft_lines(p)
  local intro_text = alone[find(alone, "Review of changes ")]
  t.eq(feedback._message({ alone[1], intro_text, "" }), "", "an intro line without its marker is not feedback")

  -- An entry's marker joined onto the comment above it (J), and text typed
  -- after another's (A): both are still this draft's markers, so their
  -- entries are still checked, and neither marker is sent.
  p = use_round("structure-joined")
  comment(s.modified_win, { 4, 4 })
  b = feedback._buf(p)
  type_comment(b, "## f.txt:4 (working tree)", "> rename it back")
  feedback.hide(b)
  pw = on_item("new.txt")
  comment(pw)
  feedback.hide(feedback._buf(p))
  comment(pw)
  b = feedback._buf(p)
  api.nvim_buf_set_lines(b, -2, -1, false, { "> second" })
  now = api.nvim_buf_get_lines(b, 0, -1, false)
  c = index_of(now, "> rename it back")
  api.nvim_win_set_cursor(0, { c, 0 })
  vim.cmd("normal! 3J")
  now = api.nvim_buf_get_lines(b, 0, -1, false)
  t.ok(now[c]:match("^> rename it back <!%-%- nvim%-review%-item .*%-%->$") ~= nil, "J joins the marker on: " .. now[c])
  local last_marker
  for i, l in ipairs(now) do
    if l:match("^<!%-%- nvim%-review%-item ") then last_marker = i end
  end
  api.nvim_buf_set_lines(b, last_marker - 1, last_marker, false, { now[last_marker] .. "see below:" })
  vim.fn.writefile(vim.list_extend(vim.deepcopy(new_txt), { "changed" }), root .. "/new.txt", "b")
  notes, selects, answers, sunk = {}, {}, { choose("Edit first") }, {}
  feedback.deliver(b)
  vim.fn.writefile(new_txt, root .. "/new.txt", "b")
  t.eq(kinds(), { "ai_review_stale" }, "a joined marker hides no entry from the staleness check")
  local why_joined = noted("Changed since you commented")
  t.ok(why_joined and why_joined.msg:find("\nnew.txt\n", 1, true) ~= nil, "the notice names that entry's file")
  lines = draft_lines(p)
  t.eq({ exactly("## ⚠ changed since this comment · new.txt (R old.txt→new.txt)", p),
    exactly("## ⚠ changed since this comment · new.txt", p) }, { 1, 1 }, "both entries are marked")
  c = find(lines, "> rename it back")
  t.ok(c and lines[c]:match("^> rename it back%s*$") and item_at(lines, c + 1) ~= nil
    and item_at(lines, c + 1).path == "new.txt", "the save puts the marker back on a line of its own")
  msg = feedback._message(lines)
  t.ok(not msg:find("nvim-review", 1, true) and msg:find("> rename it back", 1, true) ~= nil
    and msg:find("\nsee below:\n", 1, true) ~= nil and msg:find("> second", 1, true) ~= nil,
    "what would be sent holds no marker, and all the text: " .. msg)
  feedback.hide(b)

  -- Another Nvim's template float (the draft delivered, nothing typed there)
  -- written while this one starts the draft again: the template's intro is
  -- not the draft's (the verifier's p6).
  local function restarted(name)
    p = use_round(name)
    comment(s.modified_win, { 4, 4 })
    feedback.hide(feedback._buf(p))
    settle(50)
    comment(s.modified_win, { 3, 3 }, other)
    b = other._buf(p)
    local before_nonce = (feedback._parse_header(draft_lines(p)[1]) or {}).n
    vim.fn.writefile({}, p)
    notes = {}
    other.deliver(b)
    t.ok(noted("The draft is empty") ~= nil and index_of(api.nvim_buf_get_lines(b, 0, -1, false), intro_line) ~= nil,
      name .. ": B's float shows the template")
    api.nvim_win_set_cursor(s.modified_win, { 5, 0 })
    comment(s.modified_win)
    a = feedback._buf(p)
    t.ok((feedback._parse_header(draft_lines(p)[1]) or {}).n ~= before_nonce, name .. ": A starts it with a new nonce")
    notes = {}
  end
  local function intro_sent(ls)
    local _, n = feedback._message(ls):gsub(vim.pesc(intro_line), "")
    return n
  end
  restarted("structure-template")
  api.nvim_buf_call(b, function() vim.cmd("write") end)
  lines = draft_lines(p)
  t.eq({ exactly(intro_line, p), intro_sent(lines) }, { 1, 1 },
    "an untouched template written over it adds no intro: " .. vim.inspect(lines))
  t.eq(noted("elsewhere"), nil, "and no warning")
  t.eq(api.nvim_buf_get_lines(b, 0, -1, false), lines, "B's float now shows the draft")
  feedback.hide(a)
  other.hide(b)

  -- The same with a note typed under the template's intro: it goes under
  -- the draft's, before A's entry.
  restarted("structure-template-note")
  api.nvim_buf_set_lines(b, -1, -1, false, { "General note from B." })
  other.hide(b)
  lines = draft_lines(p)
  t.eq({ exactly(intro_line, p), intro_sent(lines) }, { 1, 1 }, "a note typed there adds no intro either")
  local ni, ei = index_of(lines, "General note from B."), index_of(lines, "## f.txt:5 (working tree) · was 5 at the baseline")
  t.ok(ni and ei and index_of(lines, intro_line) < ni and ni < ei, "the note is under it, before A's entry: "
    .. vim.inspect(lines))
  t.eq(noted("elsewhere"), nil, "with no warning")
  feedback.hide(a)

  -- One save that clashes on an entry and finds another delivered or deleted
  -- elsewhere: the warning says both.
  p = use_round("structure-mixed")
  local Ef, Eg = "## f.txt:5 (working tree) · was 5 at the baseline", "## f.txt:3 (working tree)"
  api.nvim_win_set_cursor(s.modified_win, { 5, 0 })
  comment(s.modified_win)
  comment(s.modified_win, { 3, 3 })
  feedback.hide(feedback._buf(p))
  comment(s.modified_win, { 8, 8 }, other)
  b = other._buf(p)
  comment(s.modified_win, { 9, 9 })
  a = feedback._buf(p)
  type_comment(a, Eg, "> A on g")
  now = api.nvim_buf_get_lines(a, 0, -1, false)
  local ef = index_of(now, Ef)
  api.nvim_buf_set_lines(a, ef - 2, index_of(now, Eg) - 2, false, {})
  feedback.hide(a)
  t.eq(exactly(Ef, p), 0, "A deleted one entry")
  type_comment(b, Ef, "> B on f")
  type_comment(b, Eg, "> B on g")
  notes = {}
  other.hide(b)
  lines = draft_lines(p)
  t.ok(index_of(lines, "> A on g") ~= nil and index_of(lines, "> B on g") == nil and index_of(lines, Ef) == nil,
    "the file keeps A's comment, and no deleted entry")
  local mixed = aside_has(p, "> B on g")
  t.ok(mixed ~= nil and mixed == aside_has(p, "> B on f"), "both of B's are kept beside it")
  local warned_mixed = noted(vim.fn.fnamemodify(mixed or "", ":~"))
  t.ok(warned_mixed and warned_mixed.msg:find("in the same lines", 1, true) ~= nil
    and warned_mixed.msg:find("delivered or deleted", 1, true) ~= nil,
    "the warning names both reasons: " .. tostring(warned_mixed and warned_mixed.msg))

  rounds.resolve_sink = real_resolve_sink
end
vim.t[tab].ai_review = vars

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
vim.fn.writefile(vim.list_extend(vim.deepcopy(readme), { "agent wrote more" }), root .. "/README.md")
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
-- <C-d> with the focus elsewhere: Edit first has to bring the draft back.
api.nvim_set_current_win(s.modified_win)
feedback.deliver(fbuf)
t.eq(kinds(), { "ai_review_stale" }, "a changed file asks before delivering")
t.ok(selects[1] and vim.deep_equal(selects[1].items, { "Deliver anyway", "Edit first" }), "deliver anyway, or edit first")
local why_stale = noted("Changed since you commented")
t.ok(why_stale and why_stale.msg:find("\nf.txt\n", 1, true) and why_stale.msg:find("\nadded.txt\n", 1, true),
  "a notice beside it names the files, a deleted one included " .. vim.inspect(why_stale))
t.ok(selects[1] and selects[1].prompt == "3 files changed since you commented. Deliver anyway?",
  "and the question counts them: " .. tostring(selects[1] and selects[1].prompt))
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
at = index_of(lines, "## ⚠ changed since this comment · README.md:2-7 (working tree)")
t.ok(at ~= nil, "an entry quoting a heading has its own heading marked")
at = index_of(lines, readme_quote[2])
t.eq(lines and at and vim.list_slice(lines, at - 1, at + #readme_quote - 2), readme_quote,
  "and its quote, the heading in it included, is left as it is")
t.eq(api.nvim_win_get_buf(api.nvim_get_current_win()), fbuf, "Edit first brings the draft back into focus")
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
-- startinsert takes effect once the main loop runs a Normal-mode command,
-- which a headless spec never does (the real UI check sees Terminal mode):
-- what is asked for, and where, is what the spec can see.
local real_cmd = vim.cmd
local inserts = {}
vim.cmd = setmetatable({}, {
  __index = real_cmd,
  __call = function(_, c, ...)
    if c == "startinsert" then inserts[#inserts + 1] = api.nvim_get_current_buf() end
    return real_cmd(c, ...)
  end,
})
local delivered_ok, delivered_err = pcall(feedback.deliver, fbuf)
settle(100)
vim.cmd = real_cmd
t.ok(delivered_ok, "delivery runs: " .. tostring(delivered_err))
t.eq(kinds(), { "ai_review_stale" }, "delivery asks about the stale entries only")
t.eq(resolved[1] and resolved[1].conversation, "claude:s1", "the header's conversation is checked")
t.eq(resolved[1] and resolved[1].roots, { root, root }, "against the header's root and the view's")
t.eq(api.nvim_get_current_tabpage(), editor_tab, "the tab switches to where Claude's panel is shown")
t.eq(api.nvim_get_current_buf(), claude_buf, "the focus is in Claude's terminal")
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
t.eq(inserts, { claude_buf }, "Terminal mode is asked for once, in Claude's terminal")

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
t.eq(vim.tbl_filter(function(l)
  return l:match("^<!%-%- nvim%-review") and l ~= readme[2] and l ~= readme[3] and l ~= readme[4]
end, shown), {}, "without the header or the markers")
t.ok(shown_text:find(table.concat(vim.list_extend({ "## ⚠ changed since this comment · README.md:2-7 (working tree)" },
  readme_quote), "\n"), 1, true) ~= nil, "a quote is sent byte for byte, lines shaped like the draft's own included")
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

-- A ,C while the delivery waits for Claude's editor: once the editor has the
-- feedback, the draft keeps only the entry added since, under its intro.
api.nvim_set_current_tabpage(tab)
comment(s.modified_win, { 6, 6 })
fbuf = feedback._buf(draft)
-- A general note under the intro goes out with this delivery, and only once.
do
  local at = index_of(api.nvim_buf_get_lines(fbuf, 0, -1, false), intro_line)
  api.nvim_buf_set_lines(fbuf, at, at, false, { "Overall: keep the public API stable." })
end
selects, answers, notes = {}, {}, {}
feedback.deliver(fbuf)
vim.cmd("stopinsert")
t.ok(editor._seed_pending("claude"), "a delivery is staged")
api.nvim_set_current_tabpage(tab)
comment(s.modified_win, { 3, 3 })
type_comment(feedback._buf(draft), "## f.txt:3 (working tree)", "> added while the seed waited")
editor.open(claude_prompt, claude_prompt .. ".done")
settle(200)
shown_text = table.concat(prompt_lines() or {}, "\n")
t.ok(shown_text:find("## f.txt:6 (working tree)", 1, true) ~= nil and shown_text:find("## f.txt:7", 1, true) ~= nil
  and not shown_text:find("added while the seed waited", 1, true), "the editor gets what was delivered")
lines = draft_lines()
t.ok(feedback._parse_header(lines[1]) ~= nil and exactly(intro_line) == 1, "the draft keeps its header and intro")
t.ok(index_of(lines, "## f.txt:3 (working tree)") ~= nil and index_of(lines, "> added while the seed waited") ~= nil,
  "and the entry added meanwhile, with its comment")
t.eq({ find(lines, "## f.txt:6"), find(lines, "## f.txt:7") }, {}, "but none of what was delivered " .. vim.inspect(lines))
t.ok(shown_text:find("Overall: keep the public API stable.", 1, true) ~= nil, "the note under the intro was delivered")
t.eq(find(lines, "Overall: keep the public API stable."), nil, "and is not kept to be sent again")
close_prompts()

-- Claude's prompt editor already open: the feedback goes straight in.
editor.open(claude_prompt, claude_prompt .. ".done")
settle(200)
api.nvim_set_current_tabpage(tab)
fbuf = (function()
  comment(s.modified_win, { 8, 8 })
  return feedback._buf(draft)
end)()
-- Another Nvim has the draft open meanwhile.
comment(s.modified_win, { 4, 4 }, other)
local b_buf = other._buf(draft)
selects, answers, notes = {}, {}, {}
feedback.deliver(fbuf)
shown = prompt_lines() or {}
t.ok(find(shown, "## f.txt:8 (working tree)") ~= nil, "an open prompt editor gets the text appended")
t.eq(draft_lines(), {}, "and the draft is delivered at once")
t.eq(editor._seed_pending("claude"), false, "without staging a seed")

-- The other Nvim then saves a comment typed into an entry just delivered.
api.nvim_set_current_tabpage(tab)
type_comment(b_buf, "## f.txt:4 (working tree)", "> typed in B after A delivered")
notes = {}
other.hide(b_buf)
t.eq(draft_lines(), {}, "what was delivered is not written back")
local b_aside = (draft:gsub("%.md$", "")) .. ".conflict.md"
t.ok(index_of(draft_lines(b_aside), "> typed in B after A delivered") ~= nil, "what B typed is kept beside the draft")
t.ok(noted(vim.fn.fnamemodify(b_aside, ":~")) ~= nil, "and B is told where")

-- Untouched there, its <C-d> finds nothing left to send.
comment(s.modified_win, { 9, 9 })
comment(s.modified_win, { 10, 10 }, other)
fbuf, b_buf = feedback._buf(draft), other._buf(draft)
feedback.deliver(fbuf)
t.eq(draft_lines(), {}, "delivered again in A")
local prompt_before = prompt_lines()
api.nvim_set_current_tabpage(tab)
notes = {}
other.deliver(b_buf)
t.ok(noted("The draft is empty") ~= nil, "B's <C-d> on a draft delivered elsewhere finds it empty")
t.eq(prompt_lines(), prompt_before, "and sends nothing twice")
local caught_up = api.nvim_buf_get_lines(b_buf, 0, -1, false)
t.ok(feedback._parse_header(caught_up[1]) ~= nil and index_of(caught_up, intro_line) ~= nil and find(caught_up, "## ") == nil,
  "B's float catches up with the file: its header and intro, no entry " .. vim.inspect(caught_up))
other.hide(b_buf)

-- What B typed below the last of the delivered entries is that entry's: it
-- goes beside the draft with it, and B is told where.
comment(s.modified_win, { 11, 11 })
comment(s.modified_win, { 12, 12 }, other)
fbuf, b_buf = feedback._buf(draft), other._buf(draft)
feedback.deliver(fbuf)
t.eq(draft_lines(), {}, "and once more")
api.nvim_set_current_tabpage(tab)
api.nvim_buf_set_lines(b_buf, -1, -1, false, { "", "A note typed in B after A delivered." })
notes = {}
other.hide(b_buf)
t.eq(draft_lines(), {}, "a note B typed under an entry delivered elsewhere is not written back with it")
local note_aside
for _, file in ipairs(vim.fn.glob((draft:gsub("%.md$", "")) .. ".conflict*.md", false, true)) do
  if index_of(vim.fn.readfile(file), "A note typed in B after A delivered.") then note_aside = file end
end
t.ok(note_aside ~= nil and noted(vim.fn.fnamemodify(note_aside, ":~")) ~= nil, "it is kept beside the draft, B told where")
-- An empty draft again, for what follows.
vim.fn.writefile({}, draft)
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
t.eq(lines and lines[1], ("<!-- nvim-review n=%s round=unowned root=%s -->")
  :format((feedback._parse_header(lines[1]) or {}).n, vim.json.encode(root)),
  "a view that is no round's writes the root's unowned draft, with no owner in its header")
t.eq(lines and lines[3], ("Review of changes (spec view) in %s:"):format(vim.fn.fnamemodify(root, ":~")),
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
-- Upstream's own window for a chat, standing in: ui:open splits one in this
-- tabpage, and Chat.open with a window (the handoff from another chat,
-- lua/ai/companion.lua show) takes that one.
function chat_ui:open()
  vim.cmd("botright split")
  api.nvim_win_set_buf(0, chat_buf)
  self.winnr = api.nvim_get_current_win()
end
local saved_chat_mod = package.loaded["codecompanion.interactions.chat"]
package.loaded["codecompanion.interactions.chat"] = {
  open = function(args)
    api.nvim_win_set_buf(args.winnr, chat_buf)
    args.ui.winnr = args.winnr
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
t.ok(lines and lines[3]:find("(API chat round)", 1, true) ~= nil, "a chat's round says so in its intro")

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
t.ok(added[1] and added[1]:find("## f.txt:5 (working tree)", 1, true) and not added[1]:find("nvim-review", 1, true),
  "the entries without their markers")
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
at = index_of(lines, ("## f.txt:5 (%s) · was 5 in %s"):format(second:sub(1, 8), first:sub(1, 8)))
t.ok(at ~= nil, "a hunk between two commits names both")
t.eq(at and item_at(lines, at - 1), { path = "f.txt", side = "new", digest = digest("f.txt") }, "under its marker")
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
-- Everything feedback showed above stays readable
---------------------------------------------------------------------------

-- Short lines, one clause each: the snacks notifier cuts a long line off at
-- its width instead of wrapping it. vim.ui.select is the snacks picker, whose
-- prompt is a one-line title. A path in this spec is a long scratch one: on a line of its
-- own it is left as it is, elsewhere it counts as a typical one.
do
  local function lines_of(text)
    local out = {}
    for _, line in ipairs(vim.split(text, "\n", { plain = true })) do
      line = line:gsub(vim.pesc(scratch) .. "[^\n]-%.md", "\0"):gsub(vim.pesc(scratch) .. "/proj one", "\0")
      if line ~= "\0" then out[#out + 1] = (line:gsub("%z", "~/src/project")) end
    end
    return out
  end
  local too_long = {}
  for _, note in ipairs(every_note) do
    for _, line in ipairs(lines_of(note.msg)) do
      if vim.fn.strdisplaywidth(line) > 60 then too_long[#too_long + 1] = line end
    end
  end
  t.ok(#every_note >= 10, ("the cases above showed feedback's notices (%d)"):format(#every_note))
  t.eq(too_long, {}, "every line of every notice is at most 60 cells, or a path alone")
  too_long = {}
  for _, s in ipairs(every_prompt) do
    for _, text in ipairs(vim.list_extend({ s.prompt }, s.items)) do
      if text:find("\n", 1, true) or vim.fn.strdisplaywidth((lines_of(text)[1] or "")) > 70 then
        too_long[#too_long + 1] = text
      end
    end
  end
  t.ok(#every_prompt >= 3, ("and asked its questions (%d)"):format(#every_prompt))
  t.eq(too_long, {}, "every prompt and choice is one line of at most 70 cells")
end

---------------------------------------------------------------------------
-- Cleanup
---------------------------------------------------------------------------

t.eq(codex_fed, 0, "nothing went to Codex")
codex.edit_prompt = real_codex_edit_prompt
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
