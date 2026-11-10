-- lua/util/baseline.lua: worktree snapshots kept as parentless commits under
-- refs/nvim-review/<wtid>/{round,saved}/<id>.
--
-- What is pinned here, every case in a throwaway repository under a path with
-- spaces, with git's system and global config shut out:
--   * the user's state is untouched: the real index (bytes and mtime), HEAD,
--     branches, tags, stash, reflogs and the gitdir's top level, around a
--     snapshot, two saves, a listing and a prune of a repository in every
--     state at once (staged, unstaged, intent-to-add, staged-but-reverted,
--     moved both ways, symlink, gitlink, unborn nested repo, non-ASCII names,
--     binary, an 11 MiB untracked file, a stash);
--   * untracked files are in the tree and ignored ones are not -- including
--     a file ignored only after an earlier snapshot -- while a force-added
--     ignored file stays;
--   * an untracked file over max_file_size is never hashed into .git/objects;
--   * racy git: a same-size edit in the second the index was written is seen;
--   * a baseline survives `gc --prune=now`, also one run from another linked
--     worktree, and each worktree has a wtid of its own;
--   * detached HEAD, an unborn repository with and without an index;
--   * no signing and no user hooks, whatever the config says;
--   * retention (defaults and ai.review.config), the exemption hook,
--     compare-and-swap deletes, and a listing that drops refs whose commit
--     is missing with one warning;
--   * a non-git directory, a bare repository and GIT_DIR give an error text;
--   * concurrency: requests coalesce in-process, and two child Nvims
--     snapshotting the same repository at once both succeed.
-- Nothing here touches this repository: no refs/nvim-review/* is created in it.
local t = dofile("tests/helper.lua")
local uv = vim.uv

local CONFIG_DIR = vim.fn.getcwd()
local WARN, INFO = vim.log.levels.WARN, vim.log.levels.INFO

t.ok(package.loaded["util.baseline"] == nil, "startup does not load util.baseline")
local config_refs = vim.split(vim.trim(vim.system({ "git", "for-each-ref", "--format=%(refname)", "refs/nvim-review/" },
  { cwd = CONFIG_DIR }):wait().stdout or ""), "\n", { plain = true, trimempty = true })
local B = require("util.baseline")

local tmp_root = vim.fn.tempname() .. " baseline spec"
vim.fn.mkdir(tmp_root, "p")
tmp_root = uv.fs_realpath(tmp_root)

-- git's system and global config are the spec's own; GIT_DIR and friends from
-- the caller's environment would point git elsewhere.
local saved_env = {}
for _, var in ipairs({ "GIT_CONFIG_NOSYSTEM", "GIT_CONFIG_GLOBAL", "GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE" }) do
  saved_env[var] = vim.env[var]
end
local gitconfig = tmp_root .. "/gitconfig"
vim.fn.writefile({
  "[init]", "\tdefaultBranch = main",
  "[user]", "\tname = Spec", "\temail = spec@example.invalid",
  "[advice]", "\taddEmbeddedRepo = false", "\tdetachedHead = false",
  "[gc]", "\tauto = 0",
}, gitconfig)
vim.env.GIT_CONFIG_NOSYSTEM = "1"
vim.env.GIT_CONFIG_GLOBAL = gitconfig
vim.env.GIT_DIR, vim.env.GIT_WORK_TREE, vim.env.GIT_INDEX_FILE = nil, nil, nil
local saved_g = vim.g.ai_review
vim.g.ai_review = nil

-- Helpers ------------------------------------------------------------------

local function sh(dir, cmd, opts)
  opts = opts or {}
  return vim.system(cmd, { cwd = dir, stdin = opts.stdin, env = opts.env }):wait()
end

-- Read-only queries carry --no-optional-locks: a plain `git status` (or any
-- refresh) rewrites .git/index itself and would blur the fingerprint.
local function git(dir, ...)
  local r = sh(dir, { "git", "--no-optional-locks", ... })
  return vim.trim(r.stdout or ""), r.code, r.stderr
end

local function must(dir, ...)
  local out, code, err = git(dir, ...)
  assert(code == 0, ("git %s failed in %s: %s"):format(table.concat({ ... }, " "), dir, err))
  return out
end

local function write(path, content)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local f = assert(io.open(path, "wb"))
  f:write(content)
  f:close()
end

local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function new_repo(name)
  local dir = tmp_root .. "/" .. name
  vim.fn.mkdir(dir, "p")
  must(dir, "init", "-q")
  return uv.fs_realpath(dir)
end

local function commit(dir, msg) must(dir, "commit", "-q", "--allow-empty", "-m", msg or "commit") end

-- Run an async API call to completion; returns what its callback received.
local function await(what, start)
  local result
  start(function(...)
    result = { n = select("#", ...), fast = vim.in_fast_event(), ... }
  end)
  if not vim.wait(30000, function() return result ~= nil end, 5) then error("timed out: " .. what) end
  return result
end

local function snapshot(dir, opts)
  local r = await("snapshot", function(cb) B.snapshot(dir, cb, opts) end)
  return r[1], r[2]
end

local function save(dir, kind, meta)
  local r = await("save", function(cb) B.save(dir, kind, meta, cb) end)
  return r[1], r[2]
end

local function list(dir, kind)
  local r = await("list", function(cb) B.list(dir, kind, cb) end)
  return r[1], r[2]
end

local function prune(dir, kind, opts)
  local r = await("prune", function(cb) B.prune(dir, kind, opts or {}, cb) end)
  return r[1], r[2]
end

local function delete(dir, entries)
  local r = await("delete", function(cb) B.delete(dir, entries, cb) end)
  return r[1], r[2]
end

-- path -> { mode, type, sha } for every entry of a tree, recursively.
local function tree_entries(dir, tree)
  local r = sh(dir, { "git", "--no-optional-locks", "ls-tree", "-r", "-z", tree })
  local out = {}
  for _, rec in ipairs(vim.split(r.stdout or "", "\0", { plain = true, trimempty = true })) do
    local mode, kind, sha, path = rec:match("^(%d+) (%a+) (%x+)\t(.*)$")
    if mode then out[path] = { mode = mode, type = kind, sha = sha } end
  end
  return out
end

local function blob(dir, tree, path)
  local r = sh(dir, { "git", "--no-optional-locks", "cat-file", "blob", tree .. ":" .. path })
  return r.code == 0 and r.stdout or nil
end

local function exists(dir, sha)
  return sh(dir, { "git", "--no-optional-locks", "cat-file", "-e", sha }).code == 0
end

local function temp_indexes(gitdir)
  local left = {}
  for name in vim.fs.dir(gitdir) do
    if name:match("^nvim%-review%-index") then left[#left + 1] = name end
  end
  return left
end

local function ref_names(dir, prefix)
  return vim.split(must(dir, "for-each-ref", "--format=%(refname)", prefix or "refs/nvim-review/"), "\n",
    { plain = true, trimempty = true })
end

-- Poll `cond` (which may itself wait on git) until it holds or time runs out.
local function eventually(cond, timeout)
  local deadline = uv.hrtime() + (timeout or 5000) * 1e6
  while not cond() do
    if uv.hrtime() > deadline then return false end
    vim.wait(20)
  end
  return true
end

-- Capture vim.notify while `fn` runs, plus whatever it scheduled.
local function notes_during(fn)
  local notes, real = {}, vim.notify
  vim.notify = function(msg, level, opts)
    notes[#notes + 1] = { msg = tostring(msg), level = level, title = opts and opts.title }
  end
  local ok, err = pcall(fn)
  vim.wait(50, function() return false end)
  vim.notify = real
  if not ok then error(err, 0) end
  return notes
end

-- Every piece of user state a snapshot could plausibly disturb.
local function fingerprint(dir)
  local gitdir = dir .. "/.git"
  local st = uv.fs_stat(gitdir .. "/index")
  local top = {}
  for name in vim.fs.dir(gitdir) do top[#top + 1] = name end
  table.sort(top)
  local logs = {}
  for name, kind in vim.fs.dir(gitdir .. "/logs", { depth = 10 }) do
    if kind == "file" then logs[#logs + 1] = name .. " " .. tostring(uv.fs_stat(gitdir .. "/logs/" .. name).size) end
  end
  table.sort(logs)
  return {
    index_bytes = read(gitdir .. "/index"),
    index_mtime = st and ("%d.%09d"):format(st.mtime.sec, st.mtime.nsec),
    ls_files = git(dir, "ls-files", "-s", "--debug"),
    head = git(dir, "rev-parse", "HEAD"),
    head_ref = git(dir, "symbolic-ref", "-q", "HEAD"),
    refs = git(dir, "for-each-ref", "--format=%(refname) %(objectname)", "refs/heads", "refs/tags", "refs/stash"),
    stash = git(dir, "stash", "list", "--format=%H %gs"),
    reflog = git(dir, "reflog", "show", "--format=%H %gs", "HEAD"),
    config = read(gitdir .. "/config"),
    gitdir_top = top,
    logs = logs,
  }
end

local function same_fingerprint(before, after, what)
  for key, value in pairs(before) do
    t.ok(vim.deep_equal(value, after[key]), ("%s: %s unchanged"):format(what, key))
  end
end

-- 1. A repository in every state at once -----------------------------------

local mixed = new_repo("mixed repo")
write(mixed .. "/a.txt", "a1\n")
write(mixed .. "/b.txt", "b1\n")
write(mixed .. "/c.txt", "c1\n")
write(mixed .. "/d.txt", "d1\n")
write(mixed .. "/e.txt", "e1\n")
write(mixed .. "/中文.txt", "zh1\n")
write(mixed .. "/bin.dat", "\0\1\2\255binary\0")
write(mixed .. "/.gitignore", "*.log\nbuild/\n")
assert(uv.fs_symlink("a.txt", mixed .. "/link"))
local sub = mixed .. "/sub"
vim.fn.mkdir(sub, "p")
must(sub, "init", "-q")
write(sub .. "/s.txt", "s\n")
must(sub, "add", "s.txt")
commit(sub, "sub")
must(mixed, "add", "--all")
commit(mixed, "initial")
must(mixed, "tag", "v1")
must(mixed, "branch", "feature")
write(mixed .. "/a.txt", "a-stash\n")
must(mixed, "stash", "push", "-q", "-m", "spec stash")

write(mixed .. "/a.txt", "a2\n") -- staged
must(mixed, "add", "a.txt")
write(mixed .. "/b.txt", "b2\n") -- unstaged
write(mixed .. "/c.txt", "c2\n") -- staged, then reverted in the worktree
must(mixed, "add", "c.txt")
write(mixed .. "/c.txt", "c1\n")
write(mixed .. "/new.txt", "new\n") -- intent to add
must(mixed, "add", "-N", "new.txt")
must(mixed, "mv", "d.txt", "d_renamed.txt") -- staged rename
assert(uv.fs_rename(mixed .. "/e.txt", mixed .. "/e_moved.txt")) -- worktree-only move
write(mixed .. "/u.txt", "u\n") -- untracked
write(mixed .. "/中文新.txt", "zh-new\n")
write(mixed .. "/x.log", "ignored\n")
write(mixed .. "/build/out.txt", "ignored\n")
write(mixed .. "/big.bin", string.rep("0123456789abcdef", 11 * 1024 * 1024 / 16)) -- 11 MiB
local empty_nested = mixed .. "/emptyrepo"
vim.fn.mkdir(empty_nested, "p")
must(empty_nested, "init", "-q") -- no commit: `git add` cannot record it
write(empty_nested .. "/n.txt", "n\n")
local big_sha = must(mixed, "hash-object", "big.bin") -- no -w: computes only

-- Fingerprint before anything here runs git in this repository.
local before = fingerprint(mixed)

local loc = assert(B.locate(mixed .. "/sub/s.txt"))
t.eq(loc.toplevel, mixed .. "/sub", "locate() from a file in a nested repository resolves that repository")
loc = assert(B.locate(mixed .. "/build"))
t.eq({ loc.toplevel, loc.gitdir }, { mixed, mixed .. "/.git" }, "locate() from a subdirectory finds the toplevel")
t.eq(loc.wtid, vim.fn.sha256(mixed .. "/.git"):sub(1, 12), "wtid is sha256(realpath(gitdir)):sub(1, 12)")

local r = await("snapshot", function(cb) B.snapshot(mixed, cb) end)
local tree, info = r[1], r[2]
t.ok(type(tree) == "string" and tree:match("^%x+$") ~= nil, "snapshot of the mixed repository yields a tree")
t.ok(r.fast == false, "callbacks run on the main loop, not in a fast event")
t.eq(info.skipped, { "big.bin" }, "info.skipped names the untracked file over max_file_size")
t.ok(type(info.unreadable) == "string" and info.unreadable:find("emptyrepo", 1, true) ~= nil,
  "a nested repository without a commit is skipped and reported, not fatal")

local entries = tree_entries(mixed, tree)
local contents = {
  ["a.txt"] = "a2\n", ["b.txt"] = "b2\n", ["c.txt"] = "c1\n", ["new.txt"] = "new\n",
  ["d_renamed.txt"] = "d1\n", ["e_moved.txt"] = "e1\n", ["u.txt"] = "u\n",
  ["中文.txt"] = "zh1\n", ["中文新.txt"] = "zh-new\n", ["bin.dat"] = "\0\1\2\255binary\0",
}
for path, want in pairs(contents) do
  t.eq(blob(mixed, tree, path), want, ("the tree holds the worktree content of %s"):format(path))
end
for _, path in ipairs({ "d.txt", "e.txt", "x.log", "build/out.txt", "big.bin", "emptyrepo", "emptyrepo/n.txt" }) do
  t.ok(entries[path] == nil, ("the tree leaves out %s"):format(path))
end
t.eq(entries.link and { entries.link.mode, blob(mixed, tree, "link") }, { "120000", "a.txt" },
  "a symlink is stored as a link")
t.eq(entries.sub and { entries.sub.mode, entries.sub.type }, { "160000", "commit" }, "a submodule is a gitlink")
t.ok(not exists(mixed, big_sha), "the 11 MiB untracked file was never hashed into .git/objects")

local round, round_info = save(mixed, "round", {
  subject = "Spec round 12:00:00",
  Source = "spec",
  Root = mixed,
  Late = true,
  Skipped = false,
  tree = tree,
  prune = false,
})
t.ok(round and round.tree == tree, "save() with meta.tree commits that tree")
t.ok(round_info and round_info.toplevel == mixed, "save() hands back the snapshot info")
local saved = save(mixed, "saved", { subject = "saved · before refactor", Label = "before refactor" })
t.ok(saved and saved.tree == tree, "save() without a tree snapshots first; an unchanged worktree gives the same tree")
t.ok(not exists(mixed, big_sha), "saving does not hash the big file either")

local function ref_pattern(kind)
  return "^refs/nvim%-review/" .. loc.wtid .. "/" .. kind .. "/%d%d%d%d%d%d%d%dT%d%d%d%d%d%d%-%x%x%x%x$"
end
t.ok(round.ref:match(ref_pattern("round")) ~= nil, "a round lives at refs/nvim-review/<wtid>/round/<id>")
t.ok(saved.ref:match(ref_pattern("saved")) ~= nil, "a saved baseline lives at refs/nvim-review/<wtid>/saved/<id>")
t.eq(must(mixed, "rev-parse", round.ref), round.sha, "the ref points at the baseline commit")

local raw = must(mixed, "cat-file", "commit", round.sha)
t.ok(not raw:find("\nparent ", 1, true), "a baseline commit has no parent")
t.ok(raw:find("\nauthor nvim review <nvim%-review@localhost> ") ~= nil
  and raw:find("\ncommitter nvim review <nvim%-review@localhost> ") ~= nil, "a baseline commit has the fixed identity")
t.ok(raw:find("\n\nSpec round 12:00:00\n\nNvim%-Review: 1\nLate: 1\nRoot: " .. vim.pesc(mixed) .. "\nSource: spec$") ~= nil,
  "the message is the subject plus minimal trailers (true -> 1, false omitted)")
t.eq(round.trailers, { Late = "1", Root = mixed, Source = "spec" }, "save() returns the trailers it wrote")

local listed = list(mixed)
t.eq(vim.tbl_map(function(e) return e.ref end, listed), { saved.ref, round.ref },
  "list() returns both kinds, newest first")
local listed_round = list(mixed, "round")[1]
t.eq(listed_round and {
  listed_round.sha, listed_round.tree, listed_round.subject, listed_round.trailers, listed_round.id, listed_round.root,
} or nil, { round.sha, tree, "Spec round 12:00:00", round.trailers, round.id, mixed },
  "list() parses sha, tree, subject, trailers and id back")
t.eq(list(mixed, "saved")[1].trailers, { Label = "before refactor" }, "a saved baseline keeps its Label")
t.eq(#prune(mixed, "round"), 0, "prune under the retention count deletes nothing")

same_fingerprint(before, fingerprint(mixed), "mixed repository")
t.eq(temp_indexes(mixed .. "/.git"), {}, "no temporary index is left in the gitdir")

-- 2. Ignored files follow the current .gitignore ------------------------------

local ign = new_repo("ignore")
write(ign .. "/a.txt", "a\n")
must(ign, "add", "a.txt")
commit(ign, "initial")
write(ign .. "/.env", "API_KEY=1\n")
local t1 = snapshot(ign)
t.eq(blob(ign, t1, ".env"), "API_KEY=1\n", "an untracked, unignored .env is in the snapshot")
write(ign .. "/.gitignore", ".env\n*.log\n")
write(ign .. "/.env", "API_KEY=2\n")
local t2 = snapshot(ign)
t.ok(tree_entries(ign, t2)[".env"] == nil, "a file ignored after an earlier snapshot is left out of the next")
write(ign .. "/forced.log", "first\n")
must(ign, "add", "-f", "forced.log")
write(ign .. "/forced.log", "second\n")
write(ign .. "/other.log", "ignored\n")
local t3 = snapshot(ign)
t.eq(blob(ign, t3, "forced.log"), "second\n", "a force-added ignored file stays, with its worktree content")
t.ok(tree_entries(ign, t3)["other.log"] == nil, "an ignored untracked file stays out")

-- 3. Racy git ------------------------------------------------------------------

local racy_checked, control_stale = 0, 0
for attempt = 1, 4 do
  if racy_checked >= 2 then break end
  local dir = new_repo("racy " .. attempt)
  commit(dir, "initial")
  local s = os.time()
  while os.time() == s do uv.sleep(5) end
  s = os.time()
  write(dir .. "/f", "AAAA\n")
  must(dir, "add", "f")
  write(dir .. "/f", "BBBB\n") -- same size, same second as the index write
  if os.time() == s then
    racy_checked = racy_checked + 1
    uv.sleep(1100)
    -- Control: a plain copy stamped "now" (not asserted; whether it goes
    -- stale depends on how git was built).
    local copy = dir .. "/.git/control-index"
    assert(uv.fs_copyfile(dir .. "/.git/index", copy))
    local env = { GIT_INDEX_FILE = copy }
    sh(dir, { "git", "-c", "core.hooksPath=/dev/null", "add", "--all" }, { env = env })
    local ctree = vim.trim(sh(dir, { "git", "write-tree" }, { env = env }).stdout or "")
    os.remove(copy)
    if blob(dir, ctree, "f") == "AAAA\n" then control_stale = control_stale + 1 end
    t.eq(blob(dir, snapshot(dir), "f"), "BBBB\n",
      ("racy git (try %d): a same-size edit in the index's second is in the snapshot"):format(racy_checked))
  end
end
t.ok(racy_checked >= 1, "the racy scenario was set up within one second at least once")
print(("info - control copy without the mtime went stale in %d of %d tries"):format(control_stale, racy_checked))

-- 4. gc ------------------------------------------------------------------------

local gc = new_repo("gc")
commit(gc, "initial")
write(gc .. "/u.txt", "gc-untracked\n")
local g1 = save(gc, "round", { subject = "gc 1", prune = false })
local g1_blob = tree_entries(gc, g1.tree)["u.txt"].sha
must(gc, "gc", "-q", "--prune=now")
t.ok(exists(gc, g1.sha) and exists(gc, g1_blob), "gc --prune=now keeps a baseline and its untracked blob")
write(gc .. "/u.txt", "gc-untracked 2\n")
local g2 = snapshot(gc)
t.eq(g2 and blob(gc, g2, "u.txt"), "gc-untracked 2\n", "a snapshot after gc --prune=now works")
t.eq(#list(gc, "round"), 1, "the baseline is still listed after gc")

-- 5. Linked worktrees ------------------------------------------------------------

local main = new_repo("wt main")
write(main .. "/a.txt", "a\n")
must(main, "add", "a.txt")
commit(main, "initial")
must(main, "worktree", "add", "-q", "--detach", tmp_root .. "/wt linked")
local linked = uv.fs_realpath(tmp_root .. "/wt linked")
local main_loc, linked_loc = B.locate(main), B.locate(linked)
t.eq(linked_loc.gitdir, uv.fs_realpath(must(linked, "rev-parse", "--absolute-git-dir")),
  "a linked worktree's gitdir is its own")
t.ok(vim.startswith(linked_loc.gitdir, main .. "/.git/worktrees/"), "under the main repository's worktrees/")
t.ok(main_loc.wtid ~= linked_loc.wtid, "two worktrees of one repository have different wtids")
write(linked .. "/ul.txt", "linked-secret\n")
local L = save(linked, "round", { subject = "linked", prune = false })
local L_blob = tree_entries(linked, L.tree)["ul.txt"].sha
write(main .. "/um.txt", "main-secret\n")
local M_ = save(main, "round", { subject = "main", prune = false })
t.ok(vim.startswith(L.ref, "refs/nvim-review/" .. linked_loc.wtid .. "/round/"), "the linked worktree's ref uses its wtid")
t.eq(vim.tbl_map(function(e) return e.sha end, list(main)), { M_.sha }, "list() in main shows only main's baselines")
t.eq(vim.tbl_map(function(e) return e.sha end, list(linked)), { L.sha }, "list() in linked shows only linked's")
t.ok(tree_entries(main, M_.tree)["um.txt"] ~= nil and tree_entries(main, M_.tree)["ul.txt"] == nil,
  "each worktree snapshots its own files")
must(main, "gc", "-q", "--prune=now")
t.ok(exists(linked, L.sha) and exists(linked, L_blob), "gc in the main worktree keeps the linked worktree's baseline")
local _, log_code = git(linked, "log", "--all", "--oneline")
t.eq(log_code, 0, "git log --all still works in the linked worktree after that gc")
t.eq(#list(linked), 1, "the linked baseline is still listed")
must(linked, "gc", "-q", "--prune=now")
t.ok(exists(main, M_.sha), "gc in the linked worktree keeps the main worktree's baseline")
t.eq(temp_indexes(main .. "/.git"), {}, "no temporary index left in the main gitdir")
t.eq(temp_indexes(linked_loc.gitdir), {}, "no temporary index left in the linked gitdir")

-- 6. Detached HEAD, unborn -------------------------------------------------------

local det = new_repo("detached")
write(det .. "/f", "1\n")
must(det, "add", "f")
commit(det, "one")
write(det .. "/f", "2\n")
must(det, "commit", "-q", "-am", "two")
must(det, "checkout", "-q", "--detach", "HEAD~1")
local det_head = must(det, "rev-parse", "HEAD")
write(det .. "/f", "3\n")
local D = save(det, "round", { subject = "detached", prune = false })
t.eq(D and blob(det, D.tree, "f"), "3\n", "a detached HEAD snapshots normally")
t.eq({ must(det, "rev-parse", "HEAD"), (select(2, git(det, "symbolic-ref", "-q", "HEAD"))) }, { det_head, 1 },
  "HEAD is still detached at the same commit")

local unborn = new_repo("unborn")
write(unborn .. "/x.txt", "x\n")
t.ok(uv.fs_stat(unborn .. "/.git/index") == nil, "fixture: a fresh repository has no index file")
local ut = snapshot(unborn)
t.eq(ut and blob(unborn, ut, "x.txt"), "x\n", "an unborn repository without an index snapshots its files")
t.ok(uv.fs_stat(unborn .. "/.git/index") == nil, "the snapshot did not create .git/index")
t.eq(temp_indexes(unborn .. "/.git"), {}, "and left no temporary index")
must(unborn, "add", "x.txt")
write(unborn .. "/y.txt", "y\n")
local U = save(unborn, "round", { subject = "unborn", prune = false })
t.eq(U and { blob(unborn, U.tree, "x.txt"), blob(unborn, U.tree, "y.txt") }, { "x\n", "y\n" },
  "an unborn repository with an index saves a baseline")
t.ok(select(2, git(unborn, "rev-parse", "-q", "--verify", "HEAD")) ~= 0, "HEAD is still unborn")

-- 7. No signing, no user hooks ----------------------------------------------------

local hooks = new_repo("hooks")
commit(hooks, "initial")
local hook_log = tmp_root .. "/hook log"
local gpg_log = tmp_root .. "/gpg log"
local function script(path, body)
  write(path, "#!/bin/sh\n" .. body .. "\n")
  uv.fs_chmod(path, tonumber("755", 8))
end
local hook_dir = tmp_root .. "/hooks path"
for _, dir in ipairs({ hooks .. "/.git/hooks", hook_dir }) do
  for _, name in ipairs({ "post-index-change", "reference-transaction", "pre-commit", "post-commit" }) do
    script(dir .. "/" .. name, ("echo %s >> %s"):format(name, vim.fn.shellescape(hook_log)))
  end
end
script(tmp_root .. "/fake gpg", ("echo called >> %s; exit 1"):format(vim.fn.shellescape(gpg_log)))
must(hooks, "config", "core.hooksPath", hook_dir)
must(hooks, "config", "commit.gpgSign", "true")
must(hooks, "config", "user.signingKey", "spec")
must(hooks, "config", "gpg.program", tmp_root .. "/fake gpg")
write(hooks .. "/u.txt", "u\n")
local H = save(hooks, "round", { subject = "hooks", prune = false })
t.ok(H ~= nil, "save() works with commit.gpgSign=true and a failing gpg.program")
t.ok(H and not must(hooks, "cat-file", "commit", H.sha):find("gpgsig", 1, true), "the baseline is not signed")
t.ok(uv.fs_stat(gpg_log) == nil, "gpg was never called")
local deleted = delete(hooks, H)
t.eq(#deleted, 1, "delete() removes the baseline ref")
t.ok(uv.fs_stat(hook_log) == nil, "no user hook ran (post-index-change, reference-transaction, commit hooks)")
must(hooks, "update-ref", "refs/heads/control", "HEAD")
t.ok(uv.fs_stat(hook_log) ~= nil, "control: the same hooks do run for a plain git update-ref")

-- 8. Errors: non-git, bare, GIT_DIR -----------------------------------------------

local plain = tmp_root .. "/plain dir"
vim.fn.mkdir(plain, "p")
local nloc, nerr = B.locate(plain)
t.eq({ nloc, nerr }, { nil, "not a git repository: " .. plain }, "locate() in a non-git directory says so")
t.eq({ snapshot(plain) }, { nil, "not a git repository: " .. plain }, "snapshot() degrades to (nil, err)")
t.eq({ save(plain, "saved", {}) }, { nil, "not a git repository: " .. plain }, "save() degrades to (nil, err)")
t.eq({ list(plain) }, { {}, "not a git repository: " .. plain }, "list() degrades to ({}, err)")
local bare = tmp_root .. "/bare.git"
must(tmp_root, "init", "-q", "--bare", bare)
local _, berr = B.locate(bare)
t.ok(berr and berr:find("^bare repository: ") ~= nil, "a bare repository is refused: " .. tostring(berr))
for _, var in ipairs({ "GIT_DIR", "GIT_WORK_TREE" }) do
  vim.env[var] = mixed .. "/.git"
  local _, err = B.locate(mixed)
  vim.env[var] = nil
  t.ok(err and err:find(var, 1, true) ~= nil, ("%s in the environment is refused: %s"):format(var, tostring(err)))
end

-- 9. Missing objects ------------------------------------------------------------

local miss = new_repo("missing")
commit(miss, "initial")
local m1 = save(miss, "round", { subject = "missing 1", prune = false })
local m2 = save(miss, "round", { subject = "missing 2", prune = false })
assert(os.remove(("%s/.git/objects/%s/%s"):format(miss, m1.sha:sub(1, 2), m1.sha:sub(3))))
local missing_listed
local notes = notes_during(function() missing_listed = list(miss, "round") end)
t.eq(vim.tbl_map(function(e) return e.sha end, missing_listed), { m2.sha }, "a ref whose commit is missing is not listed")
eventually(function() return #ref_names(miss) == 1 end)
t.eq(ref_names(miss), { m2.ref }, "that ref is removed")
t.ok(#notes == 1 and notes[1].level == WARN and notes[1].title == "Baselines"
  and notes[1].msg:find(m1.id, 1, true) ~= nil, "with one warning naming it")
t.eq(#notes_during(function() list(miss) end), 0, "the next listing has nothing to warn about")

-- 10. Retention ---------------------------------------------------------------

local ret = new_repo("retention")
commit(ret, "initial")
local ret_loc = B.locate(ret)
local empty_tree = must(ret, "hash-object", "-t", "tree", "-w", "--stdin")
-- Hand-made baselines one minute apart, so "oldest" is unambiguous.
local function make(kind, n, subject)
  local date = 1600000000 + n * 60
  local env = { GIT_COMMITTER_DATE = ("%d +0000"):format(date), GIT_AUTHOR_DATE = ("%d +0000"):format(date) }
  local sha = vim.trim(sh(ret, { "git", "commit-tree", empty_tree, "-m", subject .. "\n\nNvim-Review: 1" },
    { env = env }).stdout)
  local ref = ("refs/nvim-review/%s/%s/%s-%04x"):format(ret_loc.wtid, kind, os.date("!%Y%m%dT%H%M%S", date), n)
  assert(sh(ret, { "git", "update-ref", ref, sha }).code == 0)
  return ref
end
local round_refs, saved_refs = {}, {}
for i = 1, 22 do round_refs[i] = make("round", i, "r" .. i) end
for i = 1, 11 do saved_refs[i] = make("saved", i, "saved · s" .. i) end

local function subjects(dir, kind)
  return vim.tbl_map(function(e) return e.subject end, list(dir, kind))
end

local gone
notes = notes_during(function() gone = prune(ret, "round") end)
t.eq(vim.tbl_map(function(e) return e.subject end, gone), { "r2", "r1" }, "default retention keeps 20 rounds")
t.eq(#notes, 0, "deleting rounds is silent")
local left = subjects(ret, "round")
t.eq({ #left, left[1], left[#left] }, { 20, "r22", "r3" }, "the newest 20 rounds remain")
local saved_gone
notes = notes_during(function() saved_gone = prune(ret, "saved") end)
t.eq(vim.tbl_map(function(e) return e.subject end, saved_gone), { "saved · s1" }, "default retention keeps 10 saved")
t.ok(#notes == 1 and notes[1].level == INFO and notes[1].msg:find('"saved · s1"', 1, true) ~= nil,
  "deleting a saved baseline names it")

make("round", 23, "r23")
make("round", 24, "r24")
B.set_exempt(function(e) return e.subject == "r3" end)
gone = prune(ret, "round")
t.eq(vim.tbl_map(function(e) return e.subject end, gone), { "r4" }, "the exemption hook keeps an old round")
t.eq(#subjects(ret, "round"), 21, "the exempt round is kept beyond the count")
B.set_exempt(function() error("boom") end)
notes = notes_during(function() gone = prune(ret, "round") end)
t.eq(#gone, 0, "a failing exemption hook deletes nothing")
t.ok(#notes == 1 and notes[1].level == WARN, "and warns")
B.set_exempt(nil)
gone = prune(ret, "round", { exempt = function(e) return e.subject == "r3" end })
t.eq(#gone, 0, "opts.exempt is honoured as well")

vim.g.ai_review = { retention = { rounds = 3, saved = 2 } }
gone = prune(ret, "round")
t.eq(subjects(ret, "round"), { "r24", "r23", "r22" }, "retention.rounds from ai.review.config applies")
t.eq(#notes_during(function() prune(ret, "saved", { quiet = true }) end), 0, "opts.quiet silences the saved notice")
t.eq(#subjects(ret, "saved"), 2, "retention.saved from ai.review.config applies")
local auto = save(ret, "round", { subject = "auto" })
eventually(function() return #list(ret, "round") == 3 end)
t.eq(subjects(ret, "round"), { "auto", "r24", "r23" }, "save() prunes its kind afterwards")
vim.g.ai_review = nil

local victims = list(ret, "round")
local skipped
deleted, skipped = delete(ret, {
  { ref = victims[2].ref, sha = victims[3].sha }, -- stale old value
  { ref = victims[3].ref, sha = victims[3].sha },
  { ref = "refs/heads/main", sha = must(ret, "rev-parse", "HEAD") },
})
t.eq(vim.tbl_map(function(e) return e.ref end, deleted), { victims[3].ref }, "delete() is compare-and-swap per ref")
t.eq(#skipped, 2, "a stale old value and a ref outside refs/nvim-review/ are skipped")
t.eq(must(ret, "rev-parse", victims[2].ref), victims[2].sha, "the ref with a stale old value is untouched")
t.eq((select(2, git(ret, "rev-parse", "-q", "--verify", "refs/heads/main"))), 0, "refs/heads/main is untouched")
t.ok(auto ~= nil, "fixture: the auto-pruned save succeeded")

-- 11. Content-addressed dedupe --------------------------------------------------

local dd = new_repo("dedupe")
commit(dd, "initial")
write(dd .. "/u.txt", "same\n")
local d1 = snapshot(dd)
local objects = must(dd, "count-objects", "-v")
local d2 = snapshot(dd)
t.eq(d2, d1, "an unchanged worktree snapshots to the same tree")
t.eq(must(dd, "count-objects", "-v"), objects, "and writes no new object")
local s1 = save(dd, "saved", { subject = "one", tree = d1, prune = false })
local s2 = save(dd, "saved", { subject = "two", tree = d1, prune = false })
t.ok(s1.sha ~= s2.sha and s1.tree == s2.tree, "two baselines of one state share the tree")

-- 12. Many untracked files ---------------------------------------------------------

local many = new_repo("many")
commit(many, "initial")
sh(many, { "sh", "-c", "mkdir gen && cd gen && i=0; while [ $i -le 5000 ]; do : > f$i; i=$((i+1)); done" })
notes = notes_during(function() snapshot(many) end)
t.ok(#notes == 1 and notes[1].level == WARN and notes[1].msg:find("5001 untracked files", 1, true) ~= nil,
  "more than 5000 untracked files warns once")
t.eq(#notes_during(function() snapshot(many) end), 0, "and only once")

-- 13. Concurrency -----------------------------------------------------------------

local q = new_repo("queue")
write(q .. "/f", "0\n")
must(q, "add", "f")
commit(q, "initial")
local write_trees = 0
local real_system = vim.system
vim.system = function(cmd, ...)
  if cmd[#cmd] == "write-tree" then write_trees = write_trees + 1 end
  return real_system(cmd, ...)
end
local order, results = {}, {}
local function request(name, opts)
  B.snapshot(q, function(tree_) order[#order + 1] = name; results[name] = tree_ end, opts)
end
request("first")
write(q .. "/f", "1\n") -- after the first snapshot started
request("second")
B.snapshot(q, { priority = true }, function(tree_) order[#order + 1] = "urgent"; results.urgent = tree_ end)
request("third")
vim.wait(20000, function() return #order == 4 end, 5)
vim.system = real_system
t.eq(order, { "first", "urgent", "second", "third" }, "a priority request is answered ahead of waiting ones")
t.eq(write_trees, 2, "requests made while a snapshot runs share the next one")
t.eq(blob(q, results.second, "f"), "1\n", "a request made after a change sees it")
t.ok(results.urgent == results.second and results.third == results.second, "the coalesced requests got one tree")

local child_script = tmp_root .. "/child.lua"
vim.fn.writefile({
  "local B = require('util.baseline')",
  "local trees, errors, ref = {}, {}, nil",
  "local function step(n)",
  "  if n == 0 then",
  "    B.save(vim.env.BASELINE_DIR, 'round', { subject = 'child ' .. vim.env.CHILD, prune = false }, function(e, err)",
  "      ref = e and e.ref; if not e then errors[#errors + 1] = err end",
  "    end)",
  "    return",
  "  end",
  "  B.snapshot(vim.env.BASELINE_DIR, function(tree, err)",
  "    if tree then trees[#trees + 1] = tree else errors[#errors + 1] = err end",
  "    step(n - 1)",
  "  end)",
  "end",
  "step(8)",
  "local ok = vim.wait(30000, function() return ref ~= nil or #errors > 0 end, 5)",
  "vim.fn.writefile({ vim.json.encode({ trees = trees, errors = errors, ref = ref, ok = ok }) }, vim.env.CHILD_OUT)",
  "vim.cmd('cquit ' .. ((ok and #errors == 0) and 0 or 1))",
}, child_script)
local procs = new_repo("procs")
write(procs .. "/f", "f\n")
must(procs, "add", "f")
commit(procs, "initial")
write(procs .. "/u.txt", "u\n")
local children = {}
for i = 1, 2 do
  local out = ("%s/child %d.json"):format(tmp_root, i)
  children[i] = {
    out = out,
    job = vim.system({
      "nvim", "--headless", "-u", "NONE", "-i", "NONE", "-n", "--noplugin",
      "--cmd", "set rtp^=" .. vim.fn.fnameescape(CONFIG_DIR), "-c", "luafile " .. vim.fn.fnameescape(child_script),
    }, { env = { BASELINE_DIR = procs, CHILD = tostring(i), CHILD_OUT = out } }),
  }
end
local child_trees = {}
for i, child in ipairs(children) do
  local res = child.job:wait(60000)
  local report = vim.json.decode(read(child.out) or "{}")
  t.ok(res.code == 0 and report.ok and #report.errors == 0 and #report.trees == 8,
    ("child Nvim %d: 8 snapshots and a save, all succeeded (%s)"):format(i, vim.inspect(report.errors)))
  vim.list_extend(child_trees, report.trees or {})
  child.ref = report.ref
end
t.eq(#vim.tbl_keys(vim.iter(child_trees):fold({}, function(acc, v) acc[v] = true; return acc end)), 1,
  "every concurrent snapshot of the unchanged repository gave the same tree")
t.ok(children[1].ref and children[2].ref and children[1].ref ~= children[2].ref
  and #ref_names(procs) == 2, "both concurrent saves created their own ref")
t.eq(temp_indexes(procs .. "/.git"), {}, "concurrent snapshots leave no temporary index")

-- Cleanup -----------------------------------------------------------------------

for var, value in pairs(saved_env) do vim.env[var] = value end
vim.g.ai_review = saved_g
vim.fn.delete(tmp_root, "rf")
t.eq(ref_names(CONFIG_DIR), config_refs, "the spec created no refs/nvim-review/* in this repository")

t.done()
