-- ,S ,U ,X inside CodeDiff views (lua/util/codediff_actions.lua), driven
-- through real views of temporary repositories opened with util.codediff.open
-- and the tab variables a baseline view carries.
--
-- Needs CodeDiff's native library; tests/run.sh sets VSCODE_DIFF_NO_AUTO_INSTALL
-- so a missing one fails here instead of being downloaded. Every repository
-- lives under tempname() with a space in its path, and git runs with an empty
-- global config. "The index is unchanged" is judged by `ls-files -s`: CodeDiff
-- itself runs `git diff`, which may refresh .git/index's stat data.
local t = dofile("tests/helper.lua")
local Config = require("lazy.core.config")

t.eq(package.loaded["util.codediff_actions"], nil, "util.codediff_actions is not loaded at startup")
local plugin = Config.plugins["codediff.nvim"]
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
local function heard() return vim.inspect(vim.tbl_map(function(n) return n.msg end, notices)) end

local function settle(ms) vim.wait(ms or 100, function() return false end, 10) end
local function map(buf, lhs, mode)
  return vim.api.nvim_buf_call(buf, function() return vim.fn.maparg(lhs, mode or "n", false, true) end)
end
local function desc(buf, lhs, mode) return map(buf, lhs, mode).desc end

local dirs = {}
local function repo(name)
  local root = vim.fn.tempname() .. " " .. name
  vim.fn.mkdir(root, "p")
  root = vim.uv.fs_realpath(root)
  dirs[#dirs + 1] = root
  local function git(...)
    local command = { "git", "-C", root, "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid" }
    local result = vim.system(vim.list_extend(command, { ... }), { text = true }):wait()
    return result.code == 0 and result.stdout or nil, result.stderr
  end
  assert(git("init", "-q", "-b", "main"))
  return root, git
end

local function rows(from, to, fmt)
  local out = {}
  for i = from, to do out[#out + 1] = fmt:format(i) end
  return out
end
local function concat(...)
  local out = {}
  for _, list in ipairs({ ... }) do vim.list_extend(out, list) end
  return out
end
local function lines_of(text) return vim.split(text or "", "\n", { plain = true, trimempty = true }) end

local cd = require("util.codediff")
local editor_tab = vim.api.nvim_get_current_tabpage()
vim.o.lines, vim.o.columns = 50, 200
local cwd = vim.fn.getcwd()

--- A view in the current tabpage that shows `rel` and carries this config's
--- keys (util.codediff blocks `;` in the same pass that fires CodeDiffKeys).
local function ready(rel)
  return function()
    local s = cd.session(0)
    if not s then return false end
    local raw = require("codediff.ui.lifecycle").get_session(s.tabpage)
    if not raw or not raw.refresh or raw.refresh.loading ~= false then return false end
    for _, buf in ipairs({ s.modified_bufnr, s.original_bufnr }) do
      if type(buf) == "number" and vim.api.nvim_buf_is_valid(buf) then
        local name = vim.api.nvim_buf_get_name(buf)
        if name:sub(-#rel - 1) == "/" .. rel and desc(buf, ";") == "Disabled in CodeDiff" then return true end
      end
    end
    return false
  end
end

--- Open a view from the editor tabpage with `file` as the current buffer, so
--- CodeDiff selects it in its explorer.
local function open(root, rel, args, vars)
  vim.api.nvim_set_current_tabpage(editor_tab)
  vim.cmd.cd(vim.fn.fnameescape(root))
  vim.cmd.edit(vim.fn.fnameescape(root .. "/" .. rel))
  cd.open({ args = args, label = "spec view", tab_vars = vars })
  local ok = vim.wait(15000, ready(rel), 20)
  t.ok(ok, ("a view of %s opens (%s)"):format(rel, table.concat(args, " ")))
  return vim.api.nvim_get_current_tabpage(), cd.session(0)
end

local function close(tab)
  if vim.api.nvim_tabpage_is_valid(tab) then
    cd.close(tab)
    vim.wait(3000, function() return not vim.api.nvim_tabpage_is_valid(tab) end, 20)
  end
  vim.api.nvim_set_current_tabpage(editor_tab)
end

--- Run a pane's buffer-local Normal-mode key the way a mapping would.
local function press(win, line, lhs)
  vim.api.nvim_set_current_win(win)
  vim.api.nvim_win_set_cursor(win, { line, 0 })
  local m = map(vim.api.nvim_win_get_buf(win), lhs)
  assert(m.callback, lhs .. " is mapped in this pane")
  m.callback()
end

--- Select lines in `win` and type `lhs` there, in Visual mode.
local function visual(win, top, count, lhs)
  vim.api.nvim_set_current_win(win)
  local keys = ("%dGV%s%s"):format(top, count > 0 and (count .. "j") or "", lhs)
  vim.api.nvim_feedkeys(keys, "x", false)
end

--- Wait until the view in `win` draws a hunk at `line` that a fresh diff of
--- its buffers agrees with: it has caught up with the last write.
local function caught_up(win, line)
  return vim.wait(8000, function()
    if not vim.api.nvim_win_is_valid(win) then return false end
    vim.api.nvim_win_set_cursor(win, { line, 0 })
    return cd.fresh_hunk(0, win) ~= nil
  end, 50)
end

local function keyset(bufs)
  local found = {}
  for _, buf in ipairs(bufs) do
    for _, lhs in ipairs({ ",S", ",U", ",X" }) do
      for _, mode in ipairs({ "n", "x" }) do
        local d = desc(buf, lhs, mode)
        if d then found[#found + 1] = mode .. lhs end
      end
    end
  end
  table.sort(found)
  return vim.fn.uniq(found)
end

---------------------------------------------------------------------------
-- A baseline view where the baseline is not the index (design exp2)
---------------------------------------------------------------------------

local root, git = repo("hunk actions")
local base = rows(1, 20, "f line %d")
vim.fn.writefile(base, root .. "/f.txt")
vim.fn.writefile({ "g one", "g two" }, root .. "/g.txt")
assert(git("add", "."))
assert(git("commit", "-qm", "one"))
vim.fn.writefile({ "g one", "g two v2" }, root .. "/g.txt")
assert(git("commit", "-qam", "two"))
-- Unstaged edits from before the round: the baseline has them, the index not.
local user = rows(1, 3, "USER %d")
vim.fn.writefile(concat(user, base), root .. "/f.txt")
local entry
require("util.baseline").save(root, "round", { subject = "spec round" }, function(e, info)
  entry = e or false
  if not e then print("baseline: " .. tostring(info)) end
end)
t.ok(vim.wait(10000, function() return entry ~= nil end, 20) and entry, "a round baseline is taken")
local sha = entry.sha
local when = os.date("%H:%M:%S", entry.time)
-- The agent's round: one inserted line, two changed lines.
local agent_insert = { "AGENT INSERT" }
local agent_change = { "f line 15 AGENT", "f line 16 AGENT" }
local working = concat(user, rows(1, 7, "f line %d"), agent_insert, rows(8, 14, "f line %d"), agent_change,
  rows(17, 20, "f line %d"))
vim.fn.writefile(working, root .. "/f.txt")
local function index() return lines_of(git("show", ":f.txt")) end
local function disk() return vim.fn.readfile(root .. "/f.txt") end
local function ls_files() return git("--no-optional-locks", "ls-files", "-s") end

local tab, s = open(root, "f.txt", { sha }, { codediff_baseline = { sha = sha, kind = "round" } })
local right, left, buf, lbuf = s.modified_win, s.original_win, s.modified_bufnr, s.original_bufnr
t.eq(s.mode, "revision", "the baseline view compares a revision with the working tree")

for _, b in ipairs({ buf, lbuf }) do
  local where = b == buf and "the right pane" or "the left pane"
  t.eq(desc(b, ",S"), "Stage hunk", ",S stages the hunk in " .. where)
  t.eq(desc(b, ",U"), "Unstage hunk", ",U unstages it in " .. where)
  t.eq(desc(b, ",X"), "Discard hunk back to baseline " .. when, ",X names the baseline it discards back to in " .. where)
  t.eq(desc(b, ",S", "x"), "Stage selected lines", "Visual ,S stages the selected lines in " .. where)
  t.eq(desc(b, ",X", "x"), "Discard selected hunks back to baseline " .. when, "Visual ,X in " .. where)
end
t.eq(map(s.panel_bufnr, ",S"), {}, "the explorer gets none of them")

-- Each stage ends with a notice once gitsigns is done with it, and the file
-- stays locked a moment longer while gitsigns' own index watcher catches up
-- (codediff_actions refuses a stage in that window). The next key waits for
-- both, as a person would.
local function finished(text)
  -- 10 s: a stage may first wait up to 5 s for gitsigns to attach.
  local ok = vim.wait(10000, function() return said(text) ~= nil end, 20)
  settle(700)
  return ok
end
local gs = require("gitsigns")
--- Wait until gitsigns' hunks for `b` are `want` (a count, or a predicate
--- over the hunk list), having it look the index entry up again itself
--- first. Its gitdir watcher is what notices an index change, and on a
--- loaded CI runner that came after 5 s or not at all (#36); the product
--- refuses a stage meanwhile, but the next assertions here would not wait.
--- refresh() is no substitute: it re-reads the blob gitsigns already names,
--- the pre-change one. change_base(nil) -- the index, as the buffer already
--- diffs against -- asks git for the entry again. A diff under way reports
--- no hunks, so a count of 0 also waits for the status counts of a finished
--- one. A read that does not match (a write still settling) asks again.
local function gitsigns_sees(b, want)
  local pending, asked = false, 0
  local function ask()
    pending, asked = true, vim.uv.now()
    vim.api.nvim_buf_call(b, function()
      gs.change_base(nil, false, function() pending = false end)
    end)
  end
  local function matches(hunks)
    if type(want) == "function" then return want(hunks) end
    if #hunks ~= want then return false end
    if want > 0 then return true end
    local st = vim.b[b].gitsigns_status_dict
    return type(st) == "table" and st.added ~= nil and st.added + (st.changed or 0) + (st.removed or 0) == 0
  end
  ask()
  return vim.wait(10000, function()
    if pending then return false end
    local hunks = gs.get_hunks(b)
    if hunks and matches(hunks) then return true end
    if vim.uv.now() - asked >= 500 then ask() end
    return false
  end, 20)
end
local function unstaged_count(n) return gitsigns_sees(buf, n) end

-- ,S on the inserted line: gitsigns, which is not attached yet, stages it
-- against the index, after f line 7 -- not after the baseline's line 10.
gs.detach(buf)
t.eq(gs.get_hunks(buf), nil, "gitsigns starts detached from the file")
notices = {}
press(right, 11, ",S")
press(right, 11, ",S")
t.ok(said("the previous stage of f.txt is still running") ~= nil, "a second ,S while the first runs is refused " .. heard())
press(right, 11, ",X")
t.ok(said("a stage of f.txt is still running") ~= nil, "and so is ,X, which would change the lines being staged " .. heard())
t.eq(disk(), working, "which leaves the file alone")
local staged_insert = concat(rows(1, 7, "f line %d"), agent_insert, rows(8, 20, "f line %d"))
t.ok(vim.wait(5000, function() return vim.deep_equal(index(), staged_insert) end, 20),
  ",S stages exactly the inserted line, at its place in the index")
t.ok(finished("Staged line 11 of f.txt"), "and says what it staged " .. heard())
t.ok(gs.get_hunks(buf) ~= nil, "after attaching gitsigns first")
t.eq(index(), staged_insert, "the refused second press changed nothing")
t.eq(disk(), working, "the working tree is untouched")
t.ok(not vim.bo[buf].modified, "and so is the buffer")
t.ok(unstaged_count(2), "gitsigns sees the line staged")

-- gitsigns' stage_hunk toggles; each key does only what it says.
notices = {}
press(right, 11, ",S")
t.ok(said("nothing in line 11 of f.txt differs from the index") ~= nil, ",S on a staged hunk refuses instead of unstaging " .. heard())
t.eq(index(), staged_insert, "and leaves the index alone")
notices = {}
press(right, 19, ",U")
t.ok(said("lines 19-20 of f.txt still has unstaged changes") ~= nil, ",U on an unstaged hunk refuses instead of staging " .. heard())
t.eq(index(), staged_insert, "and leaves the index alone")
notices = {}
press(right, 11, ",U")
t.ok(finished("Unstaged line 11 of f.txt"), ",U unstages the hunk again " .. heard())
t.eq(index(), base, "the index is back where it was")
t.ok(unstaged_count(3), "gitsigns sees it unstaged")

-- gitsigns' own index watcher can drop its copy of the index while a stage
-- computes its hunk; the stage then fails on an assertion and writes nothing
-- (seen on CI: cache.lua "assertion failed!"). One such failure is retried.
do
  local real, failures = gs.stage_hunk, 0
  gs.stage_hunk = function(range, opts, cb)
    if failures == 0 then
      failures = 1
      return cb("...gitsigns/cache.lua:363: assertion failed!")
    end
    return real(range, opts, cb)
  end
  notices = {}
  press(right, 11, ",S")
  t.ok(finished("Staged line 11 of f.txt"), "a stage gitsigns fails without writing the index is retried " .. heard())
  gs.stage_hunk = real
  t.eq(failures, 1, "after that one failure")
  t.eq(said("failed"), nil, "without reporting it")
  t.eq(index(), staged_insert, "and stages the line")
  t.ok(unstaged_count(2), "gitsigns sees it staged")
  -- ,U itself is covered above; the spec puts the index back by hand.
  assert(git("reset", "-q", "--", "f.txt"))
  t.ok(unstaged_count(3), "gitsigns catches up with the reset")
end

-- gitsigns throttles attaches per buffer: one asked for while another is
-- under way returns at once, before that one has attached (seen on CI as
-- "gitsigns does not track f.txt"). A stage that had to attach first waits
-- for the attach to land.
do
  local real = gs.attach
  gs.detach(buf)
  t.ok(vim.wait(2000, function() return gs.get_hunks(buf) == nil end, 20), "gitsigns detached again")
  gs.attach = function(opts, cb)
    vim.defer_fn(function() real(opts) end, 300)
    if cb then cb() end
  end
  notices = {}
  press(right, 11, ",S")
  t.ok(finished("Staged line 11 of f.txt"), "a stage whose attach returned early still stages " .. heard())
  gs.attach = real
  t.eq(said("does not track"), nil, "without calling the file untracked")
  t.eq(index(), staged_insert, "the inserted line is staged")
  assert(git("reset", "-q", "--", "f.txt"))
  t.ok(unstaged_count(3), "gitsigns catches up with the reset")

  -- An attach can also come to nothing on a busy machine (CI): the stage
  -- asks again rather than give up after the first.
  gs.detach(buf)
  t.ok(vim.wait(2000, function() return gs.get_hunks(buf) == nil end, 20), "gitsigns detached once more")
  local asked = 0
  gs.attach = function(opts, cb)
    asked = asked + 1
    if asked == 1 then
      if cb then cb() end
      return
    end
    return real(opts, cb)
  end
  notices = {}
  press(right, 11, ",S")
  t.ok(finished("Staged line 11 of f.txt"), "a stage whose first attach came to nothing still stages " .. heard())
  gs.attach = real
  t.ok(asked >= 2, "after asking gitsigns to attach again")
  t.eq(index(), staged_insert, "the inserted line is staged")
  assert(git("reset", "-q", "--", "f.txt"))
  t.ok(unstaged_count(3), "gitsigns catches up with the reset")
  -- Let gitsigns' index watcher fire on the reset before the next stage.
  settle(700)
end

-- From the left pane: the hunk under the cursor there (baseline lines 18-19).
local staged_change = concat(rows(1, 14, "f line %d"), agent_change, rows(17, 20, "f line %d"))
notices = {}
press(left, 18, ",S")
t.ok(finished("Staged lines 19-20 of f.txt"), ",S from the left pane stages that hunk " .. heard())
t.eq(index(), staged_change, "both changed lines, nothing else")
t.ok(unstaged_count(2), "gitsigns sees it staged")
notices = {}
press(left, 18, ",U")
t.ok(finished("Unstaged lines 19-20 of f.txt"), "and ,U there unstages it " .. heard())
t.eq(index(), base, "back to the index it started from")
t.ok(unstaged_count(3), "gitsigns sees it unstaged")

-- Visual: the selected lines, from the right pane only.
notices = {}
visual(right, 1, 2, ",S")
t.ok(said("the selection holds no change this view shows") ~= nil,
  "Visual ,S over lines the view shows unchanged refuses, though they differ from the index " .. heard())
t.eq(index(), base, "so the pre-round edits stay unstaged")
notices = {}
visual(left, 18, 0, ",S")
t.ok(said("select the lines in the right pane") ~= nil, "Visual ,S in the left pane refuses " .. heard())
t.eq(vim.fn.mode(), "n", "and leaves Visual mode")
local staged_both = concat(rows(1, 7, "f line %d"), agent_insert, rows(8, 14, "f line %d"), agent_change,
  rows(17, 20, "f line %d"))
notices = {}
visual(right, 11, 9, ",S")
t.ok(finished("Staged lines 11-20 of f.txt"), "Visual ,S stages the selected lines " .. heard())
t.eq(index(), staged_both, "both hunks in them")
t.ok(unstaged_count(1), "leaving only the pre-round edits unstaged")
notices = {}
visual(right, 11, 9, ",U")
t.ok(finished("Unstaged lines 11-20 of f.txt"), "Visual ,U unstages them again " .. heard())
t.eq(index(), base, "all of them")
t.ok(unstaged_count(3), "gitsigns sees them unstaged")

-- An outside `git add` gitsigns has not caught up with: its stage_hunk would
-- see nothing unstaged and toggle to unstaging. ,S refuses instead -- as
-- "not caught up" while gitsigns is behind, as "nothing differs" once it has
-- caught up -- and never touches the index. Behind is held, not raced: ,S
-- is handed the hunks gitsigns had before the add, which is all a gitdir
-- watcher that has not fired yet leaves it with, since that watcher may
-- notice the add before the key or not for seconds (#36).
do
  local behind, real = gs.get_hunks(buf), gs.get_hunks
  t.eq(#(behind or {}), 3, "(gitsigns has the three unstaged hunks before the add)")
  assert(git("add", "f.txt"))
  gs.get_hunks = function(b)
    if b == buf then return vim.deepcopy(behind) end
    return real(b)
  end
  notices = {}
  local ok, err = pcall(press, right, 11, ",S")
  gs.get_hunks = real
  assert(ok, err)
  t.ok(said("gitsigns has not caught up with f.txt yet; try again in a moment") ~= nil,
    ",S after an outside git add refuses while gitsigns is behind " .. heard())
  t.eq(index(), working, "and leaves the index as the outside add left it")
  t.ok(gitsigns_sees(buf, 0), "gitsigns catches up with the add")
  notices = {}
  press(right, 11, ",S")
  t.ok(said("nothing in line 11 of f.txt differs from the index") ~= nil,
    "once it has, ,S says nothing differs instead " .. heard())
  t.eq(index(), working, "and still leaves the index alone")
  assert(git("reset", "-q", "--", "f.txt"))
  t.eq(index(), base, "(the spec puts the index back)")
  t.ok(unstaged_count(3), "gitsigns catches up with the reset")
  settle(700)
end

---------------------------------------------------------------------------
-- ,X: one hunk back to the baseline, nothing else
---------------------------------------------------------------------------

local gbuf = vim.fn.bufadd(root .. "/g.txt")
vim.fn.bufload(gbuf)
vim.api.nvim_buf_set_lines(gbuf, 0, 1, false, { "g one, edited and not saved" })
local index_before = ls_files()
notices = {}
press(right, 11, ",X")
local without_insert = concat(user, rows(1, 14, "f line %d"), agent_change, rows(17, 20, "f line %d"))
t.eq(disk(), without_insert, ",X writes the file with only that hunk back to the baseline")
t.ok(not vim.bo[buf].modified, "the buffer is saved")
t.eq(ls_files(), index_before, "the index is untouched")
t.ok(vim.bo[gbuf].modified and vim.fn.readfile(root .. "/g.txt")[1] == "g one",
  "another buffer's unsaved edit is neither written nor dropped")
vim.api.nvim_buf_delete(gbuf, { force = true }) -- the spec's own scratch edit
t.ok(said("index untouched; u then :w to undo") ~= nil, "the notice says how to undo it " .. heard())
t.ok(said("Discarded the hunk at line 11 of f.txt back to baseline " .. when) ~= nil, "and which hunk went back")
local function undo_and_write()
  vim.api.nvim_win_call(right, function() vim.cmd("silent undo") end)
  local undone = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  vim.api.nvim_win_call(right, function() vim.cmd("silent write") end)
  return undone
end
t.eq(undo_and_write(), working, "u brings the hunk back")
t.eq(disk(), working, "and :w writes it again")
t.ok(caught_up(right, 11), "the view catches up with the writes")

notices = {}
visual(right, 11, 8, ",X")
t.ok(said("only partly selected") ~= nil, "Visual ,X over part of a hunk refuses: whole hunks only " .. heard())
t.eq(disk(), working, "and writes nothing")
notices = {}
visual(right, 11, 9, ",X")
t.eq(disk(), concat(user, base), "Visual ,X over two whole hunks puts both back")
t.ok(said("Discarded 2 hunks of f.txt") ~= nil, "and says how many " .. heard())
t.eq(ls_files(), index_before, "the index is still untouched")
t.eq(undo_and_write(), working, "one u brings both back")
t.ok(caught_up(right, 11), "the view catches up again")

---------------------------------------------------------------------------
-- guard_fresh refuses whatever is not what the view shows
---------------------------------------------------------------------------

-- (a) unsaved edits in the right pane.
vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "USER 1, edited" })
for _, key in ipairs({ ",X", ",S" }) do
  notices = {}
  press(right, 11, key)
  t.ok(said("f.txt has unsaved changes: :w or :e! first") ~= nil, key .. " refuses over unsaved edits " .. heard())
end
t.eq(disk(), working, "and nothing is written")
t.eq(index(), base, "or staged")
vim.api.nvim_buf_call(buf, function() vim.cmd("silent undo") end)
t.ok(not vim.bo[buf].modified, "the edit is undone")

-- (b) the disk changed under an unmodified buffer.
local external = vim.deepcopy(working)
external[#external] = "f line 20 EXTERNAL"
vim.fn.writefile(external, root .. "/f.txt")
notices = {}
press(right, 11, ",X")
t.ok(said("f.txt changed on disk since it was displayed") ~= nil, ",X refuses when the disk moved on " .. heard())
t.eq(disk(), external, "and keeps the external write")
t.eq(vim.api.nvim_buf_get_lines(buf, -2, -1, false), { "f line 20 EXTERNAL" }, "the buffer is reloaded")
vim.fn.writefile(working, root .. "/f.txt")
vim.cmd.checktime(buf)
t.ok(caught_up(right, 11), "the view catches up with the restored file")

-- (b) once more, right before the write: an agent's write that lands while
-- guard_fresh runs its git calls (here, during `git check-attr`) survives.
do
  local late = vim.deepcopy(working)
  late[#late] = "f line 20 AGENT LATE"
  local real_system, landed = vim.system, false
  vim.system = function(cmd, ...)
    if type(cmd) == "table" and vim.tbl_contains(cmd, "check-attr") then
      vim.system, landed = real_system, true
      vim.fn.writefile(late, root .. "/f.txt")
    end
    return real_system(cmd, ...)
  end
  notices = {}
  press(right, 11, ",X")
  vim.system = real_system
  t.ok(landed, "(the agent's write landed during the check)")
  t.ok(said("f.txt changed on disk since it was displayed") ~= nil,
    ",X refuses when the disk moved while it checked " .. heard())
  t.eq(disk(), late, "and the agent's write is not overwritten")
  vim.fn.writefile(working, root .. "/f.txt")
  vim.cmd.checktime(buf)
  t.ok(caught_up(right, 11), "the view catches up with the restored file")
end

-- The same bytes written again (only the mtime moves) are no reason to
-- refuse, and :write must not stop to ask whether to overwrite them.
settle(20)
vim.fn.writefile(working, root .. "/f.txt")
notices = {}
press(right, 11, ",X")
t.eq(disk(), without_insert, ",X goes ahead after a rewrite that changed no bytes " .. heard())
t.eq(undo_and_write(), working, "and u still brings the hunk back")
t.ok(caught_up(right, 11), "the view catches up")

-- (c) the buffer and the disk agree, but the view has not redrawn yet. No
-- reload follows such a refusal, so it asks the view to recompute itself.
t.eq(type(require("codediff.ui.refresh").request), "function", "CodeDiff's refresh.request exists (util.codediff.refresh)")
vim.api.nvim_buf_set_lines(buf, 0, 0, false, { "NEW TOP" })
vim.api.nvim_buf_call(buf, function() vim.cmd("silent noautocmd write") end)
local real_refresh, refreshed = cd.refresh, {}
cd.refresh = function(tab)
  refreshed[#refreshed + 1] = tab
  return real_refresh(tab)
end
for _, key in ipairs({ ",X", ",S" }) do
  notices, refreshed = {}, {}
  press(right, 11, key)
  t.ok(said("the hunk changed since it was displayed") ~= nil, key .. " refuses a hunk the diff no longer has " .. heard())
  t.eq(refreshed, { tab }, key .. " has that view refresh")
end
cd.refresh = real_refresh
t.eq(disk(), concat({ "NEW TOP" }, working), "and nothing is written")
t.eq(index(), base, "or staged")
vim.api.nvim_buf_set_lines(buf, 0, 1, false, {})
vim.api.nvim_buf_call(buf, function() vim.cmd("silent noautocmd write") end)
t.ok(caught_up(right, 11), "the view catches up once more")

---------------------------------------------------------------------------
-- A stage that runs later still stages only the lines the key was pressed on
---------------------------------------------------------------------------

-- The agent rewrites the line and the buffer reloads (as CodeDiff's refresh
-- or the CursorHold :checktime would) while the stage is on its way. Buffer
-- and disk agree again by then; the lines are not the ones on screen.
do
  local rewritten = vim.deepcopy(working)
  rewritten[11] = "AGENT INSERT v2, never displayed"
  local function reload_with(lines)
    vim.fn.writefile(lines, root .. "/f.txt")
    vim.cmd.checktime(buf)
  end
  local function refused_later()
    return vim.wait(5000, function() return said("f.txt changed while staging; nothing was staged") ~= nil end, 20)
  end

  -- While gitsigns attaches a buffer it has not seen yet.
  gs.detach(buf)
  local real_attach, reloaded = gs.attach, nil
  gs.attach = function(opts, callback)
    gs.attach = real_attach
    return real_attach(opts, function(...)
      reload_with(rewritten)
      reloaded = vim.api.nvim_buf_get_lines(buf, 10, 11, false)[1]
      return callback(...)
    end)
  end
  notices = {}
  press(right, 11, ",S")
  t.ok(refused_later(), ",S refuses when the buffer reloads while gitsigns attaches " .. heard())
  gs.attach = real_attach
  t.eq(reloaded, rewritten[11], "(the buffer had reloaded the agent's rewrite)")
  t.eq(index(), base, "and nothing is staged")
  if not vim.deep_equal(index(), base) then assert(git("reset", "-q", "--", "f.txt")) end -- keep the next case apart
  reload_with(working)
  t.ok(caught_up(right, 11), "the view catches up with the restored file")
  t.ok(unstaged_count(3), "gitsigns is attached again")

  -- Before the retry: the first stage did nothing, as one caught by gitsigns'
  -- gitdir watcher does, and the reload lands before the second.
  local real_stage = gs.stage_hunk
  gs.stage_hunk = function(_, _, callback)
    gs.stage_hunk = real_stage
    reload_with(rewritten)
    callback()
  end
  notices = {}
  press(right, 11, ",S")
  t.ok(refused_later(), "the retry refuses when the buffer reloaded in between " .. heard())
  gs.stage_hunk = real_stage
  t.eq(index(), base, "and nothing is staged")
  reload_with(working)
  t.ok(caught_up(right, 11), "the view catches up with the restored file")
  t.ok(unstaged_count(3), "and so does gitsigns")
  settle(700)
end

---------------------------------------------------------------------------
-- Keys follow the view: a tab that stops being a baseline view loses ,X
---------------------------------------------------------------------------

local actions = require("util.codediff_actions")
vim.t[tab].codediff_baseline = nil
actions.attach(tab)
t.eq(keyset({ buf, lbuf }), { "n,S", "n,U", "x,S", "x,U" }, "without codediff_baseline the next pass releases ,X")
vim.t[tab].codediff_baseline = { sha = sha, kind = "round" }
actions.attach(tab)
t.eq(desc(buf, ",X"), "Discard hunk back to baseline " .. when, "and the pass after it installs ,X again")
vim.t[tab].codediff_baseline = { sha = string.rep("0", 40), kind = "round" }
actions.attach(tab)
t.eq(map(buf, ",X"), {}, "a codediff_baseline that is not the view's left end installs no ,X")
vim.t[tab].codediff_baseline = { sha = sha, kind = "round" }
actions.attach(tab)
close(tab)
t.eq(keyset({ buf }), {}, "closing the view hands the file's keys back")

-- rev vs working tree without a baseline (<leader>gm): stage keys, no ,X.
tab, s = open(root, "f.txt", { "HEAD" }, nil)
t.eq(keyset({ s.modified_bufnr, s.original_bufnr }), { "n,S", "n,U", "x,S", "x,U" }, "a rev-vs-working-tree view has ,S ,U and no ,X")
close(tab)

---------------------------------------------------------------------------
-- The status view: Changes through gitsigns, Staged through CodeDiff
---------------------------------------------------------------------------

local sroot, sgit = repo("hunk actions status")
local st = rows(1, 10, "st line %d")
vim.fn.writefile(st, sroot .. "/st.txt")
vim.fn.writefile(rows(1, 5, "ch line %d"), sroot .. "/ch.txt")
assert(sgit("add", "."))
assert(sgit("commit", "-qm", "status"))
local st_staged = vim.deepcopy(st)
st_staged[2], st_staged[8] = "st line 2 staged", "st line 8 staged"
vim.fn.writefile(st_staged, sroot .. "/st.txt")
assert(sgit("add", "st.txt"))
local ch = rows(1, 5, "ch line %d")
ch[3] = "ch line 3 changed"
vim.fn.writefile(ch, sroot .. "/ch.txt")

tab, s = open(sroot, "st.txt", {}, nil)
t.eq({ s.mode, s.modified_revision }, { "status", ":0" }, "st.txt opens in the Staged group")
t.eq(keyset({ s.modified_bufnr, s.original_bufnr }), { "n,U", "x,U" }, "the Staged group has ,U only")
notices = {}
press(s.modified_win, 2, ",U")
t.ok(vim.wait(5000, function()
  local cached = sgit("diff", "--cached", "--", "st.txt") or ""
  return not cached:find("st line 2 staged", 1, true) and cached:find("st line 8 staged", 1, true) ~= nil
end, 20), ",U there unstages that hunk through CodeDiff and keeps the other " .. heard())
t.eq(vim.fn.readfile(sroot .. "/st.txt"), st_staged, "the working tree is untouched")
close(tab)

tab, s = open(sroot, "ch.txt", {}, nil)
t.eq({ s.mode, s.modified_revision }, { "status", nil }, "ch.txt opens in the Changes group")
t.eq(keyset({ s.modified_bufnr, s.original_bufnr }), { "n,S", "x,S" },
  "the Changes group has ,S only: no ,U, which every hunk there would refuse, and no ,X")
notices = {}
press(s.modified_win, 3, ",S")
t.ok(vim.wait(5000, function() return (sgit("show", ":ch.txt") or ""):find("ch line 3 changed", 1, true) ~= nil end, 20),
  ",S there stages the hunk " .. heard())
t.ok(finished("Staged line 3 of ch.txt"), "and says so " .. heard())
close(tab)

---------------------------------------------------------------------------
-- ,S ,U change the index only as the view shows: left side -> working tree
---------------------------------------------------------------------------

do
  local iroot, igit = repo("hunk actions index")
  local abc = { "A", "B", "C", "D", "E", "F" }
  local d_base = rows(1, 10, "d %d")
  vim.fn.writefile(abc, iroot .. "/f.txt")
  vim.fn.writefile(d_base, iroot .. "/d.txt")
  assert(igit("add", "."))
  assert(igit("commit", "-qm", "index"))
  -- Before the round, neither staged: C deleted, and line 5 of d.txt edited.
  local without_c = { "A", "B", "D", "E", "F" }
  vim.fn.writefile(without_c, iroot .. "/f.txt")
  local d_user = vim.deepcopy(d_base)
  d_user[5] = "d 5 USER"
  vim.fn.writefile(d_user, iroot .. "/d.txt")
  local round
  require("util.baseline").save(iroot, "round", { subject = "index round" }, function(e) round = e or false end)
  t.ok(vim.wait(10000, function() return round ~= nil end, 20) and round, "a round baseline is taken")
  local ivars = { codediff_baseline = { sha = round.sha, kind = "round" } }
  -- The agent's round: B changed; d 6, just below the edited d 5, and d 9
  -- deleted.
  local f_agent = { "A", "B AGENT", "D", "E", "F" }
  vim.fn.writefile(f_agent, iroot .. "/f.txt")
  vim.fn.writefile({ "d 1", "d 2", "d 3", "d 4", "d 5 USER", "d 7", "d 8", "d 10" }, iroot .. "/d.txt")
  local function iindex(rel) return lines_of(igit("show", ":" .. rel)) end
  local function refused(text)
    return vim.wait(5000, function() return said(text) ~= nil end, 20) and said("<leader>gv") ~= nil
  end

  -- The view shows line 2 alone (B -> B AGENT); the index still has C, and
  -- gitsigns' hunk against it is B C -> B AGENT.
  tab, s = open(iroot, "f.txt", { round.sha }, ivars)
  local fbuf = s.modified_bufnr
  notices = {}
  press(s.modified_win, 2, ",S")
  t.ok(refused("the index differs from the left side around line 2 of f.txt"),
    ",S refuses a stage that would also take the deletion of C from before the round, and points to <leader>gv " .. heard())
  t.eq(iindex("f.txt"), abc, "the index is unchanged")

  -- With the deletion of C staged, the baseline is the index there: ,S
  -- stages exactly the line on screen.
  local blob = vim.system({ "git", "-C", iroot, "hash-object", "-w", "--stdin" },
    { stdin = table.concat(without_c, "\n") .. "\n", text = true }):wait()
  assert(igit("update-index", "--cacheinfo", "100644," .. vim.trim(blob.stdout) .. ",f.txt"))
  t.ok(gitsigns_sees(fbuf, function(h)
    return #h == 1 and h[1].added.start == 2 and h[1].removed.count == 1
  end), "gitsigns sees the index without C")
  notices = {}
  press(s.modified_win, 2, ",S")
  t.ok(finished("Staged line 2 of f.txt (the index only)"), "with the baseline equal to the index, ,S stages " .. heard())
  t.eq(iindex("f.txt"), f_agent, "that line and nothing else")
  t.ok(gitsigns_sees(fbuf, 0), "gitsigns sees it staged")
  -- Unstaging goes back to HEAD, which still has C: B AGENT -> B C.
  notices = {}
  press(s.modified_win, 2, ",U")
  t.ok(refused("HEAD differs from the left side around line 2 of f.txt"),
    ",U refuses an unstage that would also put C back into the index " .. heard())
  t.eq(iindex("f.txt"), f_agent, "the index is unchanged")
  close(tab)

  -- Deletions: gitsigns stages one from the line above it.
  tab, s = open(iroot, "d.txt", { round.sha }, ivars)
  notices = {}
  press(s.modified_win, 6, ",S")
  t.ok(refused("the index differs from the left side around line 5 of d.txt"),
    ",S refuses the deletion of d 6: the line above it is the unstaged edit of d 5 " .. heard())
  t.eq(iindex("d.txt"), d_base, "the index is unchanged")
  notices = {}
  press(s.modified_win, 8, ",S")
  t.ok(finished("Staged line 7 of d.txt (the index only)"), ",S stages the deletion of d 9 below an untouched line " .. heard())
  t.eq(iindex("d.txt"), concat(rows(1, 8, "d %d"), { "d 10" }), "and only that deletion")
  close(tab)
end

---------------------------------------------------------------------------
-- ,X writes the hunks and nothing a BufWritePre hook would add
---------------------------------------------------------------------------

do
  local eroot, egit = repo("hunk actions eol")
  vim.fn.writefile({ "root = true", "", "[*]", "insert_final_newline = true", "trim_trailing_whitespace = true" },
    eroot .. "/.editorconfig")
  -- No final newline, and trailing blanks on line 2: Nvim's editorconfig
  -- would add the one and trim the other in its BufWritePre.
  local ebase = { "a", "b  ", "c", "d", "e", "f", "g" }
  local function put(lines) vim.fn.writefile(lines, eroot .. "/e.txt", "b") end
  local function bytes()
    local f = assert(io.open(eroot .. "/e.txt", "rb"))
    local data = f:read("*a")
    f:close()
    return data
  end
  put(ebase)
  assert(egit("add", "."))
  assert(egit("commit", "-qm", "eol"))
  local esha = vim.trim(assert(egit("rev-parse", "HEAD")))
  local eagent = vim.deepcopy(ebase)
  eagent[4], eagent[6] = "d AGENT", "f AGENT"
  put(eagent)
  tab, s = open(eroot, "e.txt", { esha }, { codediff_baseline = { sha = esha, kind = "saved" } })
  local ebuf, ewin = s.modified_bufnr, s.modified_win
  t.eq({ vim.bo[ebuf].endofline, vim.bo[ebuf].fixendofline }, { false, true },
    "e.txt reads without a final newline, and editorconfig asks for one")
  local pre, post = 0, 0
  local group = vim.api.nvim_create_augroup("hunk_actions_spec_write", { clear = true })
  vim.api.nvim_create_autocmd("BufWritePre", { group = group, buffer = ebuf, callback = function() pre = pre + 1 end })
  vim.api.nvim_create_autocmd("BufWritePost", { group = group, buffer = ebuf, callback = function() post = post + 1 end })
  local eventignore = vim.o.eventignore
  notices = {}
  press(ewin, 4, ",X")
  local one_back = vim.deepcopy(eagent)
  one_back[4] = "d"
  t.eq(bytes(), table.concat(one_back, "\n"), ",X writes only the hunk: no final newline added, no blanks trimmed")
  t.ok(said("Discarded the hunk at line 4 of e.txt") ~= nil and said("also changed") == nil, "and says so, with no warning " .. heard())
  t.eq({ pre, post }, { 0, 1 }, "BufWritePre is skipped for that write, BufWritePost runs")
  t.eq(vim.o.eventignore, eventignore, "'eventignore' is as it was")
  t.eq(vim.bo[ebuf].fixendofline, true, "and so is 'fixendofline'")

  -- A BufWritePost hook that changes how the file will be written next is
  -- reported, though the lines match.
  t.ok(caught_up(ewin, 6), "the view catches up with the write")
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group, buffer = ebuf, once = true,
    callback = function() vim.bo[ebuf].endofline = true end,
  })
  notices = {}
  press(ewin, 6, ",X")
  t.ok(said("something the write ran also changed e.txt ('endofline')") ~= nil,
    "a hook that changed 'endofline' during ,X is reported " .. heard())
  vim.api.nvim_del_augroup_by_id(group)
  vim.bo[ebuf].endofline = false -- the spec's own hook, undone
  close(tab)
end

---------------------------------------------------------------------------
-- (d) path types, the filter attribute and one-sided baseline views
---------------------------------------------------------------------------

local droot, dgit = repo("hunk actions guards")
vim.fn.writefile(rows(1, 5, "plain %d"), droot .. "/plain.txt")
vim.fn.writefile({ "s one", "s two" }, droot .. "/s.txt")
vim.fn.writefile({ "target-of-link", "more" }, droot .. "/l.txt")
vim.fn.writefile({ "plain file" }, droot .. "/sub")
vim.fn.writefile({ "ft one", "ft two" }, droot .. "/ft.txt")
vim.fn.writefile({ "ft.txt filter=spec-filter" }, droot .. "/.gitattributes")
vim.fn.writefile({ "gone" }, droot .. "/gone.txt")
assert(dgit("add", "."))
assert(dgit("commit", "-qm", "guards"))
-- The baseline: HEAD's tree with l.txt a symlink and sub a submodule.
local head = vim.trim(assert(dgit("rev-parse", "HEAD")))
local index_file = vim.fn.tempname()
local function plumbing(args, stdin)
  local command = vim.list_extend({ "git", "-C", droot, "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid" }, args)
  local r = vim.system(command, { text = true, stdin = stdin, env = { GIT_INDEX_FILE = index_file } }):wait()
  assert(r.code == 0, r.stderr)
  return vim.trim(r.stdout)
end
plumbing({ "read-tree", "HEAD" })
local link_blob = plumbing({ "hash-object", "-w", "--stdin" }, "target-of-link")
plumbing({ "update-index", "--index-info" }, ("120000 %s\tl.txt\n160000 %s\tsub\n"):format(link_blob, head))
local dsha = plumbing({ "commit-tree", plumbing({ "write-tree" }), "-m", "spec baseline" })
vim.fn.delete(index_file)
local dvars = { codediff_baseline = { sha = dsha, kind = "saved" } }
local dwhen = os.date("%H:%M:%S", tonumber(vim.trim(assert(dgit("show", "-s", "--format=%ct", dsha)))))
-- The working tree since: an edit, s.txt now a symlink, sub edited, the
-- filtered file edited, one file deleted and one created.
vim.fn.writefile({ "plain 1", "plain 2", "plain 3 edited", "plain 4", "plain 5" }, droot .. "/plain.txt")
vim.fn.writefile({ "s one", "s two AGENT" }, droot .. "/s-real.txt")
vim.fn.delete(droot .. "/s.txt")
vim.uv.fs_symlink("s-real.txt", droot .. "/s.txt")
vim.fn.writefile({ "plain file", "agent line" }, droot .. "/sub")
vim.fn.writefile({ "ft one", "ft two AGENT" }, droot .. "/ft.txt")
vim.fn.delete(droot .. "/gone.txt")
vim.fn.writefile({ "brand new" }, droot .. "/new.txt")
local function snapshot(rel) return vim.fn.readfile(droot .. "/" .. rel) end

for _, case in ipairs({
  { rel = "s.txt", line = 2, why = "s.txt is a symlink in the working tree", keys = { ",X", ",S" } },
  { rel = "l.txt", line = 2, why = "l.txt is a symlink on the left, a file here: a type change", keys = { ",X", ",S" } },
  { rel = "sub", line = 1, why = "sub is a submodule on the left", keys = { ",X" } },
  { rel = "ft.txt", line = 2, why = "ft.txt has a filter attribute (filter=spec-filter", keys = { ",X", ",S" } },
}) do
  tab, s = open(droot, case.rel, { dsha }, dvars)
  local before, dindex = snapshot(case.rel), dgit("--no-optional-locks", "ls-files", "-s")
  t.ok(s.single_side == nil and desc(s.modified_bufnr, ",X") ~= nil, case.rel .. " is shown two-sided, with ,X")
  for _, key in ipairs(case.keys) do
    notices = {}
    press(s.modified_win, case.line, key)
    t.ok(said(case.why) ~= nil, ("%s refuses: %s %s"):format(key, case.why, heard()))
  end
  t.eq(snapshot(case.rel), before, case.rel .. " is left as it was")
  t.eq(dgit("--no-optional-locks", "ls-files", "-s"), dindex, "and so is the index")
  close(tab)
end

-- One-sided files: hunks only, so ,X says what would do it.
tab, s = open(droot, "plain.txt", { dsha }, dvars)
local plain_buf = s.modified_bufnr
t.eq(keyset({ plain_buf, s.original_bufnr }), { "n,S", "n,U", "n,X", "x,S", "x,U", "x,X" }, "plain.txt has all three keys")
-- Walk the explorer to the deleted file: the pass for it releases the rest.
local reached = false
for _ = 1, 12 do
  require("codediff").next_file()
  reached = vim.wait(5000, function()
    local c = cd.session(0)
    return c ~= nil and c.original.relative == "gone.txt" and ready("gone.txt")()
  end, 20)
  if reached then break end
end
t.ok(reached, "the explorer reaches the deleted file")
s = cd.session(0)
t.eq(s.single_side, "original", "gone.txt is one-sided")
t.eq(keyset({ s.original_bufnr, s.modified_bufnr }), { "n,X", "x,X" }, "a one-sided file gets ,X only")
t.eq(desc(s.original_bufnr, ",X"), "Discard deletion since baseline " .. dwhen .. ": show command",
  "which says it only shows the command")
t.eq(keyset({ plain_buf }), {}, "the file the view left has its keys handed back")
notices = {}
press(s.original_win, 1, ",X")
local restore = ("git -C %s --literal-pathspecs restore --source=%s --worktree -- %s"):format(
  vim.fn.shellescape(droot), dsha, vim.fn.shellescape("gone.txt"))
t.ok(said(restore) ~= nil, ",X on a deleted file gives the copyable restore command " .. heard())
t.eq(vim.fn.filereadable(droot .. "/gone.txt"), 0, "and restores nothing itself")
-- Something back at the path before the view caught up (or upstream's
-- listing calling a present path deleted): the restore would write over it.
vim.fn.writefile({ "back, by hand" }, droot .. "/gone.txt")
notices = {}
press(s.original_win, 1, ",X")
t.ok(said("gone.txt shows as deleted since baseline") ~= nil and said("restore --source") == nil,
  ",X prints no restore over a file that is back on disk " .. heard())
t.eq(vim.fn.readfile(droot .. "/gone.txt"), { "back, by hand" }, "and leaves it")
vim.fn.delete(droot .. "/gone.txt")
close(tab)

tab, s = open(droot, "new.txt", { dsha }, dvars)
t.eq(s.single_side, "modified", "new.txt is one-sided")
t.eq(keyset({ s.modified_bufnr, s.original_bufnr }), { "n,X", "x,X" }, "with ,X only")
notices = {}
press(s.modified_win, 1, ",X")
t.ok(said("new.txt is new since baseline") ~= nil and said("delete the file yourself") ~= nil,
  ",X on a new file says to delete it yourself " .. heard())
t.eq(snapshot("new.txt"), { "brand new" }, "and leaves it")
close(tab)

-- Outside a baseline view a one-sided file gets nothing.
tab, s = open(droot, "new.txt", { "HEAD" }, nil)
t.eq(keyset({ s.modified_bufnr, s.original_bufnr }), {}, "a one-sided file in a plain rev view gets none of the keys")
close(tab)

-- The restore command takes the path literally: read as a glob, `[id]*.txt`
-- also matches id.txt, and would put the baseline back over its edit.
do
  local lroot, lgit = repo("hunk actions literal")
  local odd = "[id]*.txt"
  vim.fn.writefile({ "odd one" }, lroot .. "/" .. odd)
  vim.fn.writefile({ "id base" }, lroot .. "/id.txt")
  assert(lgit("add", "."))
  assert(lgit("commit", "-qm", "literal"))
  local lsha = vim.trim(assert(lgit("rev-parse", "HEAD")))
  vim.fn.delete(lroot .. "/" .. odd)
  vim.fn.writefile({ "id USER WORK" }, lroot .. "/id.txt")
  tab, s = open(lroot, "id.txt", { lsha }, { codediff_baseline = { sha = lsha, kind = "saved" } })
  local found = false
  for _ = 1, 4 do
    require("codediff").next_file()
    found = vim.wait(5000, function()
      local c = cd.session(0)
      return c ~= nil and c.original.relative == odd and ready(odd)()
    end, 20)
    if found then break end
  end
  t.ok(found, "the explorer reaches " .. odd)
  s = cd.session(0)
  notices = {}
  press(s.original_win, 1, ",X")
  local n = said(odd .. " was deleted since baseline")
  local printed = n and n.msg:match("\n(git %-C [^\n]+)$")
  t.eq(printed, ("git -C %s --literal-pathspecs restore --source=%s --worktree -- %s"):format(
    vim.fn.shellescape(lroot), lsha, vim.fn.shellescape(odd)), ",X gives the restore command with a literal pathspec " .. heard())
  local r = vim.system({ "sh", "-c", printed or "false" }, { text = true }):wait()
  t.eq(r.code, 0, "the printed command runs " .. (r.stderr or ""))
  t.eq(vim.fn.readfile(lroot .. "/" .. odd), { "odd one" }, "it brings " .. odd .. " back")
  t.eq(vim.fn.readfile(lroot .. "/id.txt"), { "id USER WORK" }, "and leaves id.txt, which the glob would match, alone")
  close(tab)
end

vim.notify = real_notify
local cleanup = t.process_cleanup()
cleanup()
vim.cmd.cd(vim.fn.fnameescape(cwd))
for _, dir in ipairs(dirs) do vim.fn.delete(dir, "rf") end
vim.fn.delete(gitconfig)

t.done()
