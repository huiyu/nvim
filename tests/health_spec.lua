local t = dofile("tests/helper.lua")
local uv = vim.uv

-- `:checkhealth config`, collected by replacing vim.health's writers.
--
-- The tree-sitter CLI is gated on nvim-treesitter's own floor: main builds
-- every parser with `tree-sitter build`, so a missing or older CLI means no
-- parser installs or updates. Stand-in executables on PATH play each case.
--
-- The review-loop sections (CodeDiff, git, hooks, baselines, settings):
--   * none of them reports an error on a working setup;
--   * a missing native library or file watcher is a WARN with a hint, and the
--     check does not load CodeDiff to find that out; a stale CodeDiff release
--     is named; a non-executable CODEDIFF_WATCHER_PATH or hook script is a
--     WARN that says how to fix it;
--   * in a throwaway repository with a saved and a round baseline the counts
--     are right; a removed linked worktree's baselines and CodeCompanion's old
--     refs are each reported with a cleanup command, and that command, run
--     as printed, deletes exactly those refs; only a non-empty draft counts
--     as one with feedback, and last-sent copies and conflict files are
--     counted apart;
--   * outside a repository the baseline section says so;
--   * every vim.g.ai_review setting is listed with where its value comes from,
--     and a rejected or trimmed one is named.
-- Every check runs from a temporary directory, so none reads or writes this
-- repository's refs.
local CONFIG_DIR = vim.fn.getcwd()

local messages = {}
local writers = {}
for _, level in ipairs({ "start", "ok", "info", "warn", "error" }) do
  writers[level] = vim.health[level]
  vim.health[level] = function(msg, advice)
    messages[#messages + 1] = { level = level, msg = msg, advice = type(advice) == "table" and advice or { advice } }
  end
end

local root = vim.fn.tempname() .. " health spec"
vim.fn.mkdir(root, "p")
root = uv.fs_realpath(root)
local outside = root .. "/not a repository"
vim.fn.mkdir(outside, "p")

-- git's system and global config are the spec's own.
local ENV = { "GIT_CONFIG_NOSYSTEM", "GIT_CONFIG_GLOBAL", "GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE",
  "VSCODE_DIFF_NO_AUTO_INSTALL", "CODEDIFF_WATCHER_NO_AUTO_INSTALL", "CODEDIFF_WATCHER_PATH" }
local saved_env = {}
for _, var in ipairs(ENV) do saved_env[var] = vim.env[var] end
local gitconfig = root .. "/gitconfig"
vim.fn.writefile({
  "[init]", "\tdefaultBranch = main",
  "[user]", "\tname = Spec", "\temail = spec@example.invalid",
  "[gc]", "\tauto = 0",
}, gitconfig)
vim.env.GIT_CONFIG_NOSYSTEM = "1"
vim.env.GIT_CONFIG_GLOBAL = gitconfig
vim.env.GIT_DIR, vim.env.GIT_WORK_TREE, vim.env.GIT_INDEX_FILE = nil, nil, nil
vim.env.CODEDIFF_WATCHER_PATH = nil
-- tests/run.sh sets both; the spec may run on its own.
vim.env.VSCODE_DIFF_NO_AUTO_INSTALL = "1"
vim.env.CODEDIFF_WATCHER_NO_AUTO_INSTALL = "1"
local saved_g = vim.g.ai_review
vim.g.ai_review = nil
vim.cmd.cd(vim.fn.fnameescape(outside))

---@param path? string the PATH to run the check under
---@return { level: string, msg: string, advice: string[] }[]
local function run(path, what)
  local saved = vim.env.PATH
  if path then vim.env.PATH = path end
  messages = {}
  local ok, err = pcall(require("config.health").check)
  vim.env.PATH = saved
  t.ok(ok, (what or "the health check") .. " runs to completion" .. (ok and "" or (": " .. tostring(err))))
  return messages
end

-- The messages under one `health.start(name)`.
local function section(msgs, name)
  local out, inside = {}, false
  for _, m in ipairs(msgs) do
    if m.level == "start" then
      inside = m.msg == name
    elseif inside then
      out[#out + 1] = m
    end
  end
  return out
end

local function find(msgs, text)
  for _, m in ipairs(msgs) do
    if m.level ~= "start" and m.msg:find(text, 1, true) then return m end
  end
end

-- The level of the first line containing `text`, or nil.
local function level_of(msgs, text)
  local m = find(msgs, text)
  return m and m.level
end

local function advice_with(m, text)
  for _, line in ipairs(m and m.advice or {}) do
    if line:find(text, 1, true) then return line end
  end
end

local REVIEW = { "config: CodeDiff", "config: git", "config: review hooks", "config: review baselines",
  "config: review settings (vim.g.ai_review)" }

local function no_review_errors(msgs, what)
  for _, name in ipairs(REVIEW) do
    local sec = section(msgs, name)
    t.ok(#sec > 0, ("%s: %s has lines"):format(what, name))
    local errors = vim.tbl_map(function(m) return m.msg end,
      vim.tbl_filter(function(m) return m.level == "error" end, sec))
    t.eq(errors, {}, ("%s: %s reports no error"):format(what, name))
  end
end

-- PATH without any directory that has `exe`.
local function path_without(exe)
  local dirs = vim.split(vim.env.PATH or "", ":", { plain = true, trimempty = true })
  return table.concat(vim.tbl_filter(function(d) return vim.fn.executable(d .. "/" .. exe) == 0 end, dirs), ":")
end

local function sh(dir, cmd)
  return vim.system(cmd, { cwd = dir, text = true }):wait()
end

local function must(dir, ...)
  local r = sh(dir, { "git", "--no-optional-locks", ... })
  assert(r.code == 0, ("git %s failed in %s: %s"):format(table.concat({ ... }, " "), dir, r.stderr))
  return vim.trim(r.stdout or "")
end

local function refs(dir, prefix)
  return vim.split(must(dir, "for-each-ref", "--format=%(refname)", prefix), "\n", { plain = true, trimempty = true })
end

---@param start fun(cb: fun(...))
local function await(start)
  local done, results = false, nil
  start(function(...) results, done = { ... }, true end)
  vim.wait(20000, function() return done end, 20)
  assert(done, "timed out")
  return unpack(results)
end

-- CodeDiff without its library or watcher -----------------------------------

-- The check reads the plugin's directory from lazy's record of it; pointing
-- that at a stand-in with only a VERSION file plays an install whose library
-- and watcher were never downloaded, at a release util.codediff was not
-- written against. Done first, before any check has loaded CodeDiff.
local plugin = require("lazy.core.config").plugins["codediff.nvim"]
local real_dir = plugin.dir
local stand_in = root .. "/codediff stand-in"
vim.fn.mkdir(stand_in, "p")
vim.fn.writefile({ "9.9.9" }, stand_in .. "/VERSION")
local ext = ({ OSX = "dylib", Windows = "dll" })[jit.os] or "so"
local pinned = require("util.codediff").VERSION
local no_watcher_path = path_without("codediff-watcher")

-- Run with the stand-in, then put both download switches back on.
local function codediff_stand_in()
  plugin.dir = stand_in
  local ok, msgs = pcall(run, no_watcher_path, "with CodeDiff's library missing")
  plugin.dir = real_dir
  vim.env.VSCODE_DIFF_NO_AUTO_INSTALL, vim.env.CODEDIFF_WATCHER_NO_AUTO_INSTALL = "1", "1"
  assert(ok, msgs)
  return section(msgs, "config: CodeDiff")
end

local missing = codediff_stand_in()
local stale = find(missing, "codediff.nvim 9.9.9 is not the " .. pinned)
t.eq(stale and stale.level, "warn", "a CodeDiff release util.codediff was not written against is a warning")
t.ok(stale and stale.msg:find("revision listing", 1, true), "it says what is switched off")
local nolib = find(missing, ("native diff library libvscode_diff_9.9.9.%s is missing"):format(ext))
t.eq(nolib and nolib.level, "warn", "a missing native library is a warning, not an error")
t.ok(advice_with(nolib, ":CodeDiff install downloads it"), "with auto-install off, the hint is :CodeDiff install")
t.ok(find(missing, "VSCODE_DIFF_NO_AUTO_INSTALL=1 —"), "a set VSCODE_DIFF_NO_AUTO_INSTALL is reported")
t.ok(find(missing, "CODEDIFF_WATCHER_NO_AUTO_INSTALL=1 —"), "a set CODEDIFF_WATCHER_NO_AUTO_INSTALL is reported")
local nowatch = find(missing, "no CodeDiff file watcher")
t.eq(nowatch and nowatch.level, "warn", "a missing file watcher is a warning")
t.ok(nowatch and nowatch.msg:find("polls the repository every 500 ms", 1, true), "it says CodeDiff polls instead")
t.ok(advice_with(nowatch, "unset it and open a diff view"), "with its download off, the hint says how to get it")
t.ok(advice_with(nowatch, "CODEDIFF_WATCHER_PATH"), "the hint names CODEDIFF_WATCHER_PATH")
t.eq(vim.tbl_filter(function(m) return m.level == "error" end, missing), {}, "nothing missing is an error")
t.ok(package.loaded["codediff.core.diff"] == nil and plugin._.loaded == nil,
  "without the library file, the check does not load CodeDiff")

vim.env.VSCODE_DIFF_NO_AUTO_INSTALL, vim.env.CODEDIFF_WATCHER_NO_AUTO_INSTALL = nil, "0"
local fetching = codediff_stand_in()
local nolib2 = find(fetching, "native diff library")
t.ok(advice_with(nolib2, "CodeDiff downloads it on first use"),
  "with auto-install on, the hint is the first-use download")
t.ok(find(fetching, "CODEDIFF_WATCHER_NO_AUTO_INSTALL=0 has no effect"),
  "a value other than 1 is named as having no effect")
t.ok(advice_with(find(fetching, "no CodeDiff file watcher"), "on the first diff view"),
  "with its download on, the watcher hint is the first view")
t.ok(find(fetching, "VSCODE_DIFF_NO_AUTO_INSTALL=") == nil, "an unset VSCODE_DIFF_NO_AUTO_INSTALL is not reported")

-- A CODEDIFF_WATCHER_PATH CodeDiff would take but cannot start.
local plain_file = root .. "/watcher stand-in"
vim.fn.writefile({ "#!/bin/sh" }, plain_file)
vim.fn.setfperm(plain_file, "rw-r--r--")
vim.env.CODEDIFF_WATCHER_PATH = plain_file
local override = section(run(nil, "with a non-executable CODEDIFF_WATCHER_PATH"), "config: CodeDiff")
local not_exec = find(override, "CODEDIFF_WATCHER_PATH=" .. plain_file .. " is not executable")
t.eq(not_exec and not_exec.level, "warn", "a non-executable CODEDIFF_WATCHER_PATH is a warning")
t.ok(advice_with(not_exec, "chmod +x " .. vim.fn.shellescape(plain_file)), "the hint is chmod +x on that path")
local lib = find(override, "native diff library " .. pinned .. " loads")
t.eq(lib and lib.level, "ok", "the installed library loads and reports its version")
t.ok(plugin._.loaded ~= nil, "reading that version is what loads CodeDiff")
vim.env.CODEDIFF_WATCHER_PATH = root .. "/no such watcher"
local gone = find(section(run(nil, "with a missing CODEDIFF_WATCHER_PATH"), "config: CodeDiff"), "does not exist")
t.eq(gone and gone.level, "warn", "a CODEDIFF_WATCHER_PATH that does not exist is a warning")
vim.env.CODEDIFF_WATCHER_PATH = nil

-- tree-sitter -------------------------------------------------------------

local function fake_cli(output)
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  local exe = dir .. "/tree-sitter"
  vim.fn.writefile({ "#!/bin/sh", "printf '%s\\n' " .. vim.fn.shellescape(output) }, exe)
  vim.fn.setfperm(exe, "rwxr-xr-x")
  return dir
end

---@param path string the PATH to run the check under
---@return { level: string, msg: string }?
local function tree_sitter_line(path)
  for _, m in ipairs(run(path)) do
    if m.msg:find("^tree%-sitter") then return m end
  end
end

-- /usr/bin and /bin hold no tree-sitter on macOS or the CI image.
local base = "/usr/bin:/bin"

local floor = tree_sitter_line(fake_cli("tree-sitter 0.26.1") .. ":" .. base)
t.eq(floor and floor.level, "ok", "the documented floor passes")
t.ok(floor and floor.msg:find("0.26.1", 1, true), "the found version is reported")

local newer = tree_sitter_line(fake_cli("tree-sitter 0.27.2 (abcdef012345)") .. ":" .. base)
t.eq(newer and newer.level, "ok", "a newer CLI passes")

local old = tree_sitter_line(fake_cli("tree-sitter 0.25.10") .. ":" .. base)
t.eq(old and old.level, "error", "a CLI below the floor is an error")
t.ok(old and old.msg:find("needs 0.26.1", 1, true), "the error names the floor")

local garbled = tree_sitter_line(fake_cli("no version here") .. ":" .. base)
t.eq(garbled and garbled.level, "error", "an unreadable version is not taken as good enough")

local missing_ts = tree_sitter_line(base)
t.eq(missing_ts and missing_ts.level, "error", "a missing CLI is an error")
t.ok(missing_ts and missing_ts.msg:find("not found", 1, true), "the error says it is not found")

-- Hooks -------------------------------------------------------------------

local hook = require("ai.review.hook")
local real_script = hook.script
local function with_script(path)
  hook.script = function() return path end
  local ok, msgs = pcall(run, nil, "with a stand-in hook script")
  hook.script = real_script
  assert(ok, msgs)
  return section(msgs, "config: review hooks")
end
local plain_hook = root .. "/agent-hook stand-in"
vim.fn.writefile({ "#!/bin/sh" }, plain_hook)
vim.fn.setfperm(plain_hook, "rw-r--r--")
local hooks = with_script(plain_hook)
local hook_line = find(hooks, plain_hook .. " is not executable")
t.eq(hook_line and hook_line.level, "warn", "a hook script that is not executable is a warning")
t.ok(hook_line and hook_line.msg:find("open no review round", 1, true), "it says what stops working")
t.ok(advice_with(hook_line, "chmod +x " .. vim.fn.shellescape(plain_hook)), "the hint is chmod +x on the script")
t.eq(level_of(hooks, "Claude --settings is valid"), "ok", "the Claude settings still check out against the stand-in")
local absent = find(with_script(root .. "/no agent-hook"), "is missing")
t.eq(absent and absent.level, "warn", "a missing hook script is a warning")

-- Inside a repository -------------------------------------------------------

local B = require("util.baseline")
local repo = root .. "/repo one"
vim.fn.mkdir(repo, "p")
must(repo, "init", "-q")
vim.fn.writefile({ "one" }, repo .. "/a.txt")
must(repo, "add", "a.txt")
must(repo, "commit", "-q", "-m", "init")
local saved_entry, saved_err = await(function(cb)
  B.save(repo, "saved", { subject = "saved · spec", Label = "spec" }, cb)
end)
assert(saved_entry, saved_err)
local round_entry, round_err = await(function(cb)
  B.save(repo, "round", { subject = "spec round", Source = "manual", Root = repo }, cb)
end)
assert(round_entry, round_err)

-- A linked worktree with a round of its own: alive, it is not an orphan.
local linked = root .. "/linked tree"
must(repo, "worktree", "add", "-q", "--detach", linked)
linked = uv.fs_realpath(linked)
local linked_wtid = assert(B.locate(linked)).wtid
local linked_entry, linked_err = await(function(cb)
  B.save(linked, "round", { subject = "linked round", Source = "manual", Root = linked }, cb)
end)
assert(linked_entry, linked_err)
-- What CodeCompanion's code_review left behind (interactions/code_review/baseline.lua).
must(repo, "update-ref", "refs/worktree/codecompanion/baseline", "HEAD")
must(repo, "update-ref", "refs/worktree/codecompanion/baselines/x", "HEAD")

vim.g.ai_review = {
  retention = { rounds = 30 },
  sources = { codex = false },
  always_confirm = { "codex", "nobody" },
  bogus = true,
}
-- The drafts directory of this repository: one draft with feedback, one that
-- delivery emptied, the last-sent copy and two conflict files.
local draft_dir = vim.fs.dirname(require("ai.review.rounds").draft_path(repo, "unowned"))
vim.fn.mkdir(draft_dir, "p")
vim.fn.writefile({ "## a.txt:1 (working tree)", "> look" }, draft_dir .. "/held.md")
vim.fn.writefile({}, draft_dir .. "/sent.md")
vim.fn.writefile({ "## a.txt:1 (working tree)", "> sent" }, draft_dir .. "/sent.last-sent.md")
vim.fn.writefile({ "> typed here" }, draft_dir .. "/held.conflict.md")
vim.fn.writefile({ "> typed again" }, draft_dir .. "/held.conflict-2.md")

vim.cmd.cd(vim.fn.fnameescape(repo))
local inside = run(nil, "inside a repository")
no_review_errors(inside, "inside a repository")

local baselines = section(inside, "config: review baselines")
local counts = find(baselines, "1 round and 1 saved baselines for " .. repo)
t.eq(counts and counts.level, "ok", "the worktree's round and saved baselines are counted")
t.ok(counts and counts.msg:find("retention keeps the newest 30 and 10", 1, true), "with the retention in effect")
t.eq(level_of(baselines, "no baseline refs of removed worktrees"), "ok", "a live linked worktree is no orphan")
local cc = find(baselines, "2 refs under refs/worktree/codecompanion/")
t.eq(cc and cc.level, "warn", "CodeCompanion's leftover refs are a warning")
local drafts = find(baselines, ("feedback drafts for this worktree live in %s/ai-review/"):format(vim.fn.stdpath("state")))
t.ok(drafts and drafts.msg:find(draft_dir, 1, true), "where the drafts live is named")
t.ok(drafts and drafts.msg:find(": 1 draft with feedback, 1 last-sent copy, 2 conflict files", 1, true),
  "only a non-empty draft has feedback; last-sent copies and conflict files are counted apart")
vim.fn.delete(draft_dir, "rf")

local cc_cmd = advice_with(cc, "git update-ref --stdin")
t.ok(cc_cmd and vim.startswith(cc_cmd, "cd " .. vim.fn.shellescape(repo) .. " && "),
  "the cleanup command names the repository")
local ran = sh(outside, { "sh", "-c", cc_cmd or "false" })
t.eq(ran.code, 0, "the CodeCompanion cleanup command runs as printed")
t.eq(refs(repo, "refs/worktree/codecompanion/"), {}, "and deletes those refs")
t.eq(#refs(repo, "refs/nvim-review/"), 3, "and no baseline")

local git_line = find(section(inside, "config: git"), "review baselines need 2.26 or later")
t.eq(git_line and git_line.level, "ok", "git's version is checked against the baseline floor")

local review_hooks = section(inside, "config: review hooks")
t.eq(level_of(review_hooks, "agent-hook executable"), "ok", "the hook script is executable")
t.eq(level_of(review_hooks, "Claude --settings is valid"), "ok", "the Claude --settings JSON checks out")
local codex = find(review_hooks, "Codex -c hooks= is valid")
t.ok(codex and codex.level == "ok" and codex.msg:find("trusted_hash matches", 1, true),
  "the Codex trusted_hash matches")
t.ok(find(review_hooks, "sources.codex = false — native Codex prompts open no review round"),
  "a source turned off is named")
t.ok(find(review_hooks, "sources.claude =") == nil, "a source left on is not")

local settings = section(inside, "config: review settings (vim.g.ai_review)")
t.ok(find(settings, "retention.rounds = 30 (vim.g.ai_review)"),
  "an override is marked as coming from vim.g.ai_review")
t.ok(find(settings, "retention.saved = 10 (default)"), "a default is marked as one")
t.ok(find(settings, "seed_ttl_ms = 10000 (default)"), "seed_ttl_ms is listed")
t.ok(find(settings, 'always_confirm = { "codex" } (vim.g.ai_review)'), "a list shows what was kept of it")
-- Paths walked from the defaults, independently of the check's own walk.
local function setting_paths(node, prefix, out)
  for key, value in pairs(node) do
    local path = prefix == "" and key or prefix .. "." .. key
    if type(value) == "table" and next(value) ~= nil and not vim.islist(value) then
      setting_paths(value, path, out)
    else
      out[#out + 1] = path
    end
  end
  return out
end
local paths = setting_paths(require("ai.review.config").defaults(), "", {})
local unlisted = vim.tbl_filter(function(path) return find(settings, path .. " = ") == nil end, paths)
t.eq(unlisted, {}, "every setting is listed")
t.eq(#vim.tbl_filter(function(m) return m.level == "info" end, settings), #paths, "each one once")
local rejected = find(settings, "not applied")
t.ok(rejected and rejected.level == "warn" and rejected.msg:find("vim.g.ai_review.bogus", 1, true),
  "an unknown key is named")
local trimmed = find(settings, "applied without the entries")
t.ok(trimmed and trimmed.msg:find("vim.g.ai_review.always_confirm", 1, true), "a list that lost entries is named")
vim.g.ai_review = nil

-- Removing the linked worktree leaves its round behind.
must(repo, "worktree", "remove", "--force", linked)
local after = section(run(nil, "after git worktree remove"), "config: review baselines")
local orphan = find(after, "of worktrees that no longer exist")
t.eq(orphan and orphan.level, "warn", "the removed worktree's baselines are a warning")
t.ok(orphan and orphan.msg:find(linked_wtid, 1, true), "naming its worktree id")
t.ok(orphan and orphan.msg:find("Root " .. linked, 1, true), "and the root its rounds were taken in")
t.ok(orphan and orphan.msg:find("1 baseline ref of", 1, true), "with the number of refs")
t.eq(level_of(after, "no refs/worktree/codecompanion/*"), "ok", "CodeCompanion's refs are gone")
local orphan_cmd = advice_with(orphan, "git update-ref --stdin")
ran = sh(outside, { "sh", "-c", orphan_cmd or "false" })
t.eq(ran.code, 0, "the orphan cleanup command runs as printed")
local left = refs(repo, "refs/nvim-review/")
t.eq(#left, 2, "it deletes the removed worktree's ref and nothing else")
t.eq(vim.tbl_filter(function(r) return r:find(linked_wtid, 1, true) ~= nil end, left), {},
  "none of that worktree is left")
t.eq(level_of(section(run(nil, "after the cleanup"), "config: review baselines"), "no baseline refs of removed worktrees"),
  "ok", "and the next check finds no orphan")

-- GIT_DIR in Nvim's environment turns baselines off.
vim.env.GIT_DIR = repo .. "/.git"
local git_dir = find(section(run(nil, "with GIT_DIR set"), "config: review baselines"), "GIT_DIR is set")
vim.env.GIT_DIR = nil
t.eq(git_dir and git_dir.level, "warn", "GIT_DIR in the environment is a warning")

-- Outside a repository ------------------------------------------------------

vim.cmd.cd(vim.fn.fnameescape(outside))
local out_msgs = run(nil, "outside a repository")
no_review_errors(out_msgs, "outside a repository")
local not_repo = find(section(out_msgs, "config: review baselines"), "is not in a Git worktree")
t.eq(not_repo and not_repo.level, "info", "outside a repository the baseline section says so")
t.ok(not_repo and not_repo.msg:find(outside, 1, true), "naming the directory")

-- AI backends ---------------------------------------------------------------

-- There is no default backend: a missing agent CLI or ACP bridge is a
-- warning -- unavailable, not broken, and left out of the new-chat picker --
-- whichever provider offers it. Only nothing at all to start a chat with is an
-- error.
local ai = require("ai.config")
local stand_ins = root .. "/no agents"
vim.fn.mkdir(stand_ins, "p")
local cut = stand_ins .. ":/usr/bin:/bin"
local backends = section(run(cut, "with no agent on PATH"), "config: AI backends")
t.ok(#backends > 0, "the AI backends section has lines")
local head = backends[1]
t.ok(head and head.level == "info" and head.msg:find("in the order of lua/ai/config.lua", 1, true) ~= nil,
  "it opens with the providers' order, naming no default: " .. tostring(head and head.msg))
t.eq(find(backends, "default backend"), nil, "and no line names a default backend")
t.eq(level_of(backends, ":AI provider"), nil, "and no longer offers :AI provider")
-- Judged on the same PATH the check ran on: a CLI in /usr/bin is found.
local real_path = vim.env.PATH
vim.env.PATH = cut
local missing = {}
for _, b in ipairs(ai.backends()) do
  if b.kind ~= "http" and not b.available then missing[#missing + 1] = b.command end
end
vim.env.PATH = real_path
t.ok(#missing > 0, "some agent CLI or bridge is missing on that PATH, to check against")
for _, exe in ipairs(missing) do
  t.eq(level_of(backends, exe .. " not found"), "warn", exe .. " missing: a warning, whichever provider offers it")
end
-- Nothing at all: no CLI, no bridge and no NVIM_* key.
local saved_keys = {}
for _, name in ipairs(ai.key_names()) do
  local var = ai.key_profiles[name].api_key
  saved_keys[var] = vim.env[var]
  vim.env[var] = nil
end
local none = section(run(cut, "with nothing available"), "config: AI backends")
t.eq(level_of(none, "No AI backend is available"), "error", "nothing to start a chat with is an error")
vim.env[ai.key_profiles[ai.key_names()[1]].api_key] = "spec"
local one_key = section(run(cut, "with one API key"), "config: AI backends")
t.eq(find(one_key, "No AI backend is available"), nil, "one API key is enough to start a chat")
for var, value in pairs(saved_keys) do vim.env[var] = value end
local g_before = vim.g.ai_review
vim.g.ai_review = { sources = { codecompanion_acp = false, codecompanion_http = false } }
local hooks_off = section(run(nil, "with the chat sources off"), "config: review hooks")
vim.g.ai_review = g_before
t.ok(find(hooks_off, "sources.codecompanion_acp = false — ACP chats (<leader>an)") ~= nil
  and find(hooks_off, "sources.codecompanion_http = false — API chats (<leader>an)") ~= nil,
  "a chat source switched off is named by the key that starts those chats")
t.eq(find(hooks_off, "<leader>ag") or find(hooks_off, "<leader>ah"), nil, "never by the retired <leader>ag/ah")

-- Cleanup -------------------------------------------------------------------

vim.cmd.cd(vim.fn.fnameescape(CONFIG_DIR))
for _, var in ipairs(ENV) do vim.env[var] = saved_env[var] end
vim.g.ai_review = saved_g
for level, fn in pairs(writers) do vim.health[level] = fn end
vim.fn.delete(draft_dir, "rf")
vim.fn.delete(root, "rf")
t.done()
