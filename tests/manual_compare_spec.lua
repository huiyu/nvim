-- Manual comparison (lua/plugin/vcs/codediff.lua): <leader>gk compares any
-- two ends, <leader>gK saves a named baseline, <leader>gM offers baselines.
--
-- :CodeDiff is stubbed to record its arguments, and util.codediff.open to
-- record the tab variables a view would get, so no view opens and the native
-- library is not needed (tests/codediff_listing_spec.lua opens real ones).
-- vim.ui.select and vim.ui.input answer from a script. Pinned here:
--   * every cell of the from/to table, the swaps that keep the working tree
--     or the index on the right, and refusing the same end twice;
--   * a typed A...B or A... is a whole comparison, and only as the first end;
--     a typed name that is not a revision is refused;
--   * both ends holding the same content says so and opens nothing;
--   * baselines are passed as shas, newest first, this worktree's only, and
--     one against the working tree marks the view (codediff_baseline, plus
--     ai_review for a round through ai.review.rounds, which may be absent);
--   * <leader>gK names a saved baseline (subject and Label), defaults the
--     name to the time, and retention removes the oldest past 10 with a word;
--   * <leader>gM lists baselines next to branches, tags and commits.
-- Every repository lives under tempname() with a space in its path, with
-- git's system and global config shut out. Nothing here touches this
-- repository.
local t = dofile("tests/helper.lua")
local uv = vim.uv
local Config = require("lazy.core.config")

local plugin = Config.plugins["codediff.nvim"]
local function key(lhs)
  for _, spec in ipairs(plugin.keys) do
    if spec[1] == lhs then return spec end
  end
end
for lhs, desc in pairs({
  ["<leader>gk"] = "Compare two: worktree / index / baseline / ref",
  ["<leader>gK"] = "Save current code as a baseline",
}) do
  local spec = key(lhs)
  t.ok(spec ~= nil and spec.desc == desc and spec.mode == "n", lhs .. " is a Normal-mode key of the CodeDiff spec")
end

local gitconfig = vim.fn.tempname()
vim.fn.writefile({ "[init]", "\tdefaultBranch = main", "[gc]", "\tauto = 0" }, gitconfig)
vim.env.GIT_CONFIG_GLOBAL = gitconfig
vim.env.GIT_CONFIG_NOSYSTEM = "1"
vim.env.GIT_DIR, vim.env.GIT_WORK_TREE, vim.env.GIT_INDEX_FILE = nil, nil, nil
local saved_g = vim.g.ai_review
vim.g.ai_review = nil

local notices = {}
local real_notify = vim.notify
vim.notify = function(msg, level) notices[#notices + 1] = { msg = tostring(msg), level = level } end
local function count(text)
  local n = 0
  for _, m in ipairs(notices) do
    if m.msg:find(text, 1, true) then n = n + 1 end
  end
  return n
end
local function said(text) return count(text) > 0 end
local function settle(ms) vim.wait(ms or 50, function() return false end, 10) end

-- :CodeDiff and util.codediff.open record what they were asked.
local opened, specs = {}, {}
local real_codediff = rawget(vim.cmd, "CodeDiff")
vim.cmd.CodeDiff = function(opts) opened[#opened + 1] = vim.deepcopy(opts.args) end
local cd = require("util.codediff")
local real_open = cd.open
cd.open = function(spec)
  specs[#specs + 1] = vim.deepcopy(spec)
  return real_open(spec)
end

-- Each vim.ui.select takes the first item its predicate accepts (none:
-- cancelled); each vim.ui.input returns the next string (CANCEL: nil).
local CANCEL = {}
local script = {}
local real_select, real_input = vim.ui.select, vim.ui.input
local offered = {} ---@type table[][] the items of every select, in order
vim.ui.select = function(items, _, on_choice)
  offered[#offered + 1] = items
  local want = table.remove(script, 1)
  for _, item in ipairs(items) do
    if type(want) == "function" and want(item) then return on_choice(item) end
  end
  on_choice(nil)
end
vim.ui.input = function(_, on_confirm)
  local text = table.remove(script, 1)
  on_confirm(text ~= CANCEL and text or nil)
end
local function display(text)
  return function(item) return item.display and item.display:find(text, 1, true) ~= nil end
end
local function rev(name) return function(item) return item.kind == "rev" and item.rev == name end end
local WORKING, INDEX, TYPE = display("Working tree"), display("Index (staged)"), display("Type a revision")

--- Press `lhs` with `steps` scripted; returns what :CodeDiff got (nil if
--- nothing opened) and the open() spec.
local function press(lhs, steps, done)
  script, opened, specs, offered, notices = { unpack(steps) }, {}, {}, {}, {}
  key(lhs)[2]()
  vim.wait(10000, done or function() return #opened > 0 or said("Compare:") end, 10)
  settle()
  return opened[1], specs[1]
end

local function repo(name)
  local root = vim.fn.tempname() .. " " .. name
  vim.fn.mkdir(root, "p")
  root = uv.fs_realpath(root)
  local function git(...)
    local command = { "git", "-C", root, "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid" }
    local result = vim.system(vim.list_extend(command, { ... }), { text = true }):wait()
    assert(result.code == 0, table.concat({ ... }, " ") .. ": " .. (result.stderr or ""))
    return vim.trim(result.stdout or "")
  end
  git("init", "-q", "-b", "main")
  return root, git
end
local function write(root, path, lines) vim.fn.writefile(lines, root .. "/" .. path) end

local B = require("util.baseline")
local function baselines(root, kind)
  local got
  B.list(root, kind, function(entries) got = entries end)
  vim.wait(5000, function() return got ~= nil end, 10)
  return got or {}
end

local cwd = vim.fn.getcwd()

---------------------------------------------------------------------------
-- Outside a repository
---------------------------------------------------------------------------

local outside = vim.fn.tempname() .. " outside"
vim.fn.mkdir(outside, "p")
vim.cmd.cd(vim.fn.fnameescape(outside))
vim.cmd.enew()
local tabs = #vim.api.nvim_list_tabpages()
for _, lhs in ipairs({ "<leader>gk", "<leader>gK" }) do
  notices = {}
  t.ok(pcall(key(lhs)[2]), lhs .. " outside a repository does not raise")
  t.ok(said("not a git repository"), lhs .. " reports git's reason")
end
t.eq(#vim.api.nvim_list_tabpages(), tabs, "and neither opens anything")

---------------------------------------------------------------------------
-- The fixture: main with two commits, branches and a tag, a dirty tree
---------------------------------------------------------------------------

local root, git = repo("compare spec")
write(root, "a.txt", { "one" })
git("add", ".")
git("commit", "-qm", "one")
git("tag", "v1")
git("branch", "old")
write(root, "a.txt", { "two" })
git("commit", "-qam", "two")
git("branch", "same")
write(root, "s.txt", { "staged" })
git("add", "s.txt")
-- A branch whose tree is the index exactly.
local index_tree = git("write-tree")
git("branch", "idx", git("commit-tree", index_tree, "-p", "HEAD", "-m", "index"))
write(root, "a.txt", { "three" })   -- unstaged
write(root, "n.txt", { "untracked" })
vim.cmd.cd(vim.fn.fnameescape(root))
vim.cmd.enew()

---------------------------------------------------------------------------
-- <leader>gK: a named baseline
---------------------------------------------------------------------------

press("<leader>gK", { "before refactor" }, function() return said("Saved baseline") end)
local saved = baselines(root, "saved")
t.eq(#saved, 1, "<leader>gK saves one baseline")
t.eq(saved[1] and saved[1].subject, "saved · before refactor", "its subject names it for the pickers")
t.eq(saved[1] and saved[1].trailers.Label, "before refactor", "and its Label trailer holds the name")
t.ok(said('Saved baseline "before refactor" (' .. saved[1].sha:sub(1, 8) .. ")"), "saving says so")
t.eq(#baselines(root, "round"), 0, "it opens no round")
local before_refactor = saved[1]

press("<leader>gK", { "" }, function() return said("Saved baseline") end)
saved = baselines(root, "saved")
t.ok(#saved == 2 and saved[1].trailers.Label:match("^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d$") ~= nil,
  "an empty name is the time (" .. tostring(saved[1] and saved[1].trailers.Label) .. ")")
t.eq(saved[1].subject, "saved · " .. saved[1].trailers.Label, "in the subject as well")
local timed = saved[1]
press("<leader>gK", { CANCEL }, function() return false end)
t.eq(#baselines(root, "saved"), 2, "cancelling the name saves nothing")

-- A round, as the review loop would store one.
local round
B.save(root, "round", {
  subject = "nvim review: Claude round 10:00:00", Source = "claude", Conversation = "claude:spec", Root = root,
}, function(entry) round = entry end)
vim.wait(5000, function() return round ~= nil end, 10)
t.ok(round ~= nil, "a round baseline is stored")
-- Work after the baselines, so they differ from the working tree.
write(root, "later.txt", { "written after the baselines" })

---------------------------------------------------------------------------
-- <leader>gk: the candidates
---------------------------------------------------------------------------

press("<leader>gk", { function() return false end }, function() return #offered > 0 end)
local items = offered[1] or {}
local function position(pred)
  for i, item in ipairs(items) do
    if pred(item) then return i end
  end
end
t.eq(position(WORKING), 1, "the working tree is offered first")
t.eq(position(INDEX), 2, "then the index")
t.ok(position(rev(round.sha)) and position(rev(timed.sha)) and position(rev(before_refactor.sha))
  and position(rev(round.sha)) < position(rev(timed.sha)) and position(rev(timed.sha)) < position(rev(before_refactor.sha)),
  "then the baselines, newest first, by sha")
t.ok(position(display("saved · before refactor · ")) ~= nil, "a saved baseline shows its name and time")
t.ok(position(display("nvim review: Claude round 10:00:00 · ")) ~= nil, "a round shows its subject and time")
t.ok(position(rev("main")) and position(rev("old")) and position(rev("v1")), "then branches and tags")
t.ok(position(rev(git("rev-parse", "--short", "HEAD"))) ~= nil, "and recent commits")
t.eq(position(TYPE), #items, "with free input last")
t.eq(#opened, 0, "cancelling the first pick opens nothing")
t.eq(vim.tbl_filter(function(item) return (item.rev or ""):find("nvim-review", 1, true) ~= nil end, items), {},
  "no candidate names a ref under refs/nvim-review")

-- A linked worktree has baselines of its own, and gk lists only those.
local linked = vim.fn.tempname() .. " linked worktree"
git("worktree", "add", "-q", "-b", "linked", linked)
linked = uv.fs_realpath(linked)
local linked_saved
B.save(linked, "saved", { subject = "saved · in the linked worktree", Label = "in the linked worktree" },
  function(entry) linked_saved = entry end)
vim.wait(5000, function() return linked_saved ~= nil end, 10)
press("<leader>gk", { function() return false end }, function() return #offered > 0 end)
items = offered[1] or {}
t.ok(position(rev(linked_saved.sha)) == nil, "another worktree's baseline is not offered here")
vim.cmd.cd(vim.fn.fnameescape(linked))
press("<leader>gk", { function() return false end }, function() return #offered > 0 end)
items = offered[1] or {}
t.ok(position(rev(linked_saved.sha)) ~= nil and position(rev(round.sha)) == nil, "and the other way round")
vim.cmd.cd(vim.fn.fnameescape(root))

---------------------------------------------------------------------------
-- <leader>gk: every cell
---------------------------------------------------------------------------

local function C(...) return vim.list_extend({ "-C", root }, { ... }) end

local args, spec = press("<leader>gk", { rev("old"), WORKING })
t.eq(args, C("old"), "rev → working tree: :CodeDiff -C root rev")
t.eq(spec and spec.label, "old → working tree", "labelled")
t.eq(spec and spec.tab_vars, nil, "a branch sets no tab variables")
args = press("<leader>gk", { rev("old"), INDEX })
t.eq(args, C("--staged", "old"), "rev → index: --staged rev")
args, spec = press("<leader>gk", { rev("old"), rev("main") })
t.eq(args, C("old", "main"), "rev → rev: both revisions")
t.eq(spec and spec.label, "old → main", "labelled")

args, spec = press("<leader>gk", { INDEX, WORKING })
t.eq(args, C(), "index → working tree: the status view")
t.eq(spec and spec.label, "index/HEAD ↔ working tree", "labelled as the status view is")
t.ok(said("Index → working tree is the status view"), "with a word about its Changes group")

args = press("<leader>gk", { INDEX, INDEX })
t.eq(args, nil, "index → index is refused")
t.ok(said("Compare: pick two different ends; both are the index"), "saying why")
args = press("<leader>gk", { WORKING, WORKING })
t.eq(args, nil, "working tree → working tree is refused")
t.ok(said("both are the working tree"), "saying why")
args = press("<leader>gk", { rev("main"), rev("main") })
t.eq(args, nil, "the same revision twice is refused")
t.ok(said("both are main"), "saying why")

args = press("<leader>gk", { INDEX, rev("old") })
t.eq(args, C("--staged", "old"), "index → rev swaps into rev → index")
t.ok(said("Swapped the ends: CodeDiff shows the index on the right"), "and says so")
args = press("<leader>gk", { WORKING, INDEX })
t.eq(args, C(), "working tree → index swaps into the status view")
t.ok(said("shows the working tree on the right") and said("is the status view"), "with both notes")
args = press("<leader>gk", { WORKING, rev("old") })
t.eq(args, C("old"), "working tree → rev swaps into rev → working tree")
t.ok(said("Swapped the ends: CodeDiff shows the working tree on the right"), "and says so")

-- Baselines go as shas, and against the working tree mark the view.
args, spec = press("<leader>gk", { rev(before_refactor.sha), WORKING })
t.eq(args, C(before_refactor.sha), "a saved baseline → working tree passes its sha")
t.eq(spec and spec.label, "saved · before refactor → working tree", "labelled with its subject")
t.eq(spec and spec.tab_vars, { codediff_baseline = { sha = before_refactor.sha, kind = "saved" } },
  "and marks the view as a saved baseline's")
args, spec = press("<leader>gk", { WORKING, rev(before_refactor.sha) })
t.eq(args, C(before_refactor.sha), "picked the other way round, it swaps")
t.eq(spec and spec.tab_vars, { codediff_baseline = { sha = before_refactor.sha, kind = "saved" } }, "and marks it too")
args, spec = press("<leader>gk", { rev(before_refactor.sha), INDEX })
t.eq(args, C("--staged", before_refactor.sha), "a baseline → index")
t.eq(spec and spec.tab_vars, nil, "is not a baseline view")

local saved_rounds = package.loaded["ai.review.rounds"]
local REVIEW = { id = round.id, sha = round.sha, conversation = "claude:spec", source = "claude", root = root, late = false }
local asked
package.loaded["ai.review.rounds"] = {
  review_vars = function(entry)
    asked = entry
    return entry.kind == "round" and vim.deepcopy(REVIEW) or nil
  end,
}
args, spec = press("<leader>gk", { rev(round.sha), WORKING })
t.eq(args, C(round.sha), "a round → working tree passes its sha")
t.eq(spec and spec.tab_vars, { codediff_baseline = { sha = round.sha, kind = "round" }, ai_review = REVIEW },
  "and the view carries the round from ai.review.rounds")
t.ok(asked and asked.sha == round.sha and asked.ref == round.ref, "review_vars gets the util.baseline entry")
asked = nil
press("<leader>gk", { rev(before_refactor.sha), WORKING })
t.eq(asked, nil, "a saved baseline does not consult ai.review.rounds")
package.loaded["ai.review.rounds"] = { review_vars = function() error("spec: review_vars raised") end }
args, spec = press("<leader>gk", { rev(round.sha), WORKING })
t.eq({ args, spec and spec.tab_vars }, { C(round.sha), { codediff_baseline = { sha = round.sha, kind = "round" } } },
  "a failing review_vars still opens the round, without ai_review")
package.loaded["ai.review.rounds"] = nil
package.preload["ai.review.rounds"] = function() error("spec: no such module") end
args, spec = press("<leader>gk", { rev(round.sha), WORKING })
t.eq({ args, spec and spec.tab_vars }, { C(round.sha), { codediff_baseline = { sha = round.sha, kind = "round" } } },
  "and so does a missing ai.review.rounds")
package.preload["ai.review.rounds"] = nil
-- The real ai.review.rounds reads the round's own trailers.
package.loaded["ai.review.rounds"] = nil
args, spec = press("<leader>gk", { rev(round.sha), WORKING })
t.eq(spec and spec.tab_vars, {
  codediff_baseline = { sha = round.sha, kind = "round" },
  ai_review = { id = round.id, sha = round.sha, conversation = "claude:spec", source = "claude", root = root, late = false },
}, "with lua/ai/review/rounds.lua the view carries the round its trailers name")
package.loaded["ai.review.rounds"] = saved_rounds

---------------------------------------------------------------------------
-- <leader>gk: typed revisions
---------------------------------------------------------------------------

args, spec = press("<leader>gk", { TYPE, "old...main" })
t.eq(args, C("old...main"), "a typed A...B opens as typed")
t.eq(#offered, 1, "without a second pick")
t.eq(spec and spec.label, "old...main", "labelled as typed")
args, spec = press("<leader>gk", { TYPE, "old..." })
t.eq(args, C("old..."), "a typed A... compares the working tree with the merge base")
t.eq(#offered, 1, "also without a second pick")
t.eq(spec and spec.label, "old... → working tree", "labelled with the working tree")
args = press("<leader>gk", { rev("old"), TYPE, "old...main" })
t.eq(args, nil, "A...B as the second end is refused")
t.ok(said("old...main is a comparison of its own; type it as the first end"), "saying why")
args = press("<leader>gk", { TYPE, "HEAD~1", WORKING })
t.eq(args, C("HEAD~1"), "a typed revision is an end like any other")
args = press("<leader>gk", { TYPE, "no-such-rev" })
t.eq(args, nil, "a typed name that is not a revision is refused")
t.ok(said("Compare: not a revision: no-such-rev"), "saying so")
args = press("<leader>gk", { TYPE, "--staged" })
t.eq(args, nil, "so is anything that would read as a flag")
args = press("<leader>gk", { TYPE, "nope...main" })
t.eq(args, nil, "a range whose ends do not resolve is refused")
t.ok(said("Compare:"), "with git's reason")
press("<leader>gk", { TYPE, CANCEL }, function() return false end)
t.eq(#opened, 0, "cancelling the input opens nothing")

---------------------------------------------------------------------------
-- <leader>gk: both ends the same
---------------------------------------------------------------------------

args = press("<leader>gk", { rev("old"), rev("v1") })
t.eq(args, nil, "two names of one commit open nothing")
t.ok(said("Compare: no differences, old → v1"), "and say so")
args = press("<leader>gk", { rev("idx"), INDEX })
t.eq(args, nil, "a revision equal to the index opens nothing")
t.ok(said("no differences, idx → index"), "and says so")
args = press("<leader>gk", { TYPE, "main...same" })
t.eq(args, nil, "a range whose ends agree opens nothing")
press("<leader>gK", { "now" }, function() return said("Saved baseline") end)
local now = baselines(root, "saved")[1]
args = press("<leader>gk", { rev(now.sha), WORKING })
t.eq(args, nil, "a baseline of the current tree against the working tree opens nothing")
t.ok(said("no differences, saved · now → working tree"), "and says so")
write(root, "n.txt", { "untracked, and changed" })
args = press("<leader>gk", { rev(now.sha), WORKING })
t.eq(args, C(now.sha), "an untracked file changed since makes a difference")

local clean, cgit = repo("compare clean")
write(clean, "a.txt", { "one" })
cgit("add", ".")
cgit("commit", "-qm", "one")
vim.cmd.cd(vim.fn.fnameescape(clean))
args = press("<leader>gk", { INDEX, WORKING })
t.eq(args, nil, "the index against a working tree that matches it opens nothing")
t.ok(said("no differences, index/HEAD ↔ working tree"), "and says so")
write(clean, "new.txt", { "untracked" })
args = press("<leader>gk", { WORKING, INDEX })
t.eq(args, { "-C", clean }, "an untracked file is a difference between them")
vim.cmd.cd(vim.fn.fnameescape(root))

---------------------------------------------------------------------------
-- <leader>gM: baselines next to the refs
---------------------------------------------------------------------------

args, spec = press("<leader>gM", { rev(before_refactor.sha) })
items = offered[1] or {}
t.ok(position(rev(round.sha)) and position(rev(before_refactor.sha)) and position(rev("main"))
  and position(rev("v1")), "<leader>gM offers baselines next to branches and tags")
t.ok(position(rev(round.sha)) < position(rev("main")), "baselines first")
t.eq(args, C(before_refactor.sha), "a baseline is diffed against the working tree by sha")
t.eq(spec and spec.label, "saved · before refactor → working tree", "labelled with its subject")
t.eq(spec and spec.tab_vars, { codediff_baseline = { sha = before_refactor.sha, kind = "saved" } },
  "and marked as a baseline view")
args, spec = press("<leader>gM", { rev("old") })
t.eq(args, C("old"), "a branch still diffs by name")
t.eq(spec and spec.label, "old → working tree", "labelled as before")

---------------------------------------------------------------------------
-- Retention of saved baselines
---------------------------------------------------------------------------

local have = #baselines(root, "saved")
for i = have + 1, 10 do
  press("<leader>gK", { "filler " .. i }, function() return said("Saved baseline") end)
end
t.eq(#baselines(root, "saved"), 10, "ten saved baselines are kept")
press("<leader>gK", { "the eleventh" }, function() return said("Removed 1 old saved baseline") end)
saved = baselines(root, "saved")
t.eq(#saved, 10, "an eleventh removes the oldest")
t.eq(saved[1].subject, "saved · the eleventh", "keeping the new one")
t.ok(not vim.tbl_contains(vim.tbl_map(function(e) return e.sha end, saved), before_refactor.sha),
  "the oldest is gone")
t.ok(said('"saved · before refactor"'), "and the notice names it")
t.eq(#baselines(root, "round"), 1, "rounds are not touched")

vim.cmd.CodeDiff = real_codediff
cd.open = real_open
vim.ui.select, vim.ui.input = real_select, real_input
vim.notify = real_notify
vim.g.ai_review = saved_g
vim.cmd.cd(vim.fn.fnameescape(cwd))
git("worktree", "remove", "--force", linked)
for _, dir in ipairs({ root, clean, outside, linked }) do vim.fn.delete(dir, "rf") end
vim.fn.delete(gitconfig)

t.done()
