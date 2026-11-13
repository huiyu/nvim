-- The listing patch in lua/util/codediff.lua: what a revision-vs-working-tree
-- view lists, through the replaced get_diff_revision and through real views
-- opened by <leader>gk and <leader>gM (lua/plugins/git/codediff.lua).
--
-- Pinned here:
--   * a baseline against the working tree lists A/M/D/R from the two trees:
--     an untracked file the baseline captured and then changed is M, not
--     D + ??; a plain `mv` is R; non-ASCII names come through; a type change
--     is M; ignored files stay out;
--   * a branch that tracks a file this checkout leaves untracked lists it as
--     M (critique t19), in a <leader>gM view as well;
--   * an untracked file over max_file_size is never shown as deleted, and is
--     named once per path per view;
--   * neither is any other path the revision has that is still on disk:
--     ignored now (a .env a baseline captured), unreadable, a directory
--     where a file was, or (case-insensitive file systems) renamed in case
--     only; each is named with its reason in the same notice;
--   * <leader>gk opens a repository whose path holds `$app` (CodeDiff
--     expands -C), and a branch named history as a revision view, not as
--     CodeDiff's history subcommand;
--   * a modified buffer whose file changed on disk is named once per disk
--     mtime, and only for files the listing shows;
--   * a failing snapshot falls back to upstream's listing with one warning.
--
-- Needs CodeDiff's native library; tests/run.sh sets VSCODE_DIFF_NO_AUTO_INSTALL
-- so a missing one fails here instead of being downloaded. Every repository
-- lives under tempname() with a space in its path, and git runs with an empty
-- global config. Nothing here touches this repository.
local t = dofile("tests/helper.lua")
local uv = vim.uv
local Config = require("lazy.core.config")

local plugin = Config.plugins["codediff.nvim"]
local libs = vim.fn.glob(plugin.dir .. "/libvscode_diff*", false, true)
if #libs == 0 then
  t.ok(false, "CodeDiff's native library is installed in " .. plugin.dir .. " (see docs/DIAGNOSTICS.md)")
  t.done()
  return
end

local gitconfig = vim.fn.tempname()
vim.fn.writefile({ "[init]", "\tdefaultBranch = main", "[gc]", "\tauto = 0" }, gitconfig)
vim.env.GIT_CONFIG_GLOBAL = gitconfig
vim.env.GIT_CONFIG_NOSYSTEM = "1"
vim.env.GIT_DIR, vim.env.GIT_WORK_TREE, vim.env.GIT_INDEX_FILE = nil, nil, nil
-- Small enough for fixtures of a few KiB.
vim.g.ai_review = { max_file_size = 1024 }

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
local function settle(ms) vim.wait(ms or 100, function() return false end, 10) end

local function key(lhs)
  for _, spec in ipairs(plugin.keys) do
    if spec[1] == lhs then return spec[2] end
  end
end

local function repo(name)
  local root = vim.fn.tempname() .. " " .. name
  vim.fn.mkdir(root, "p")
  root = uv.fs_realpath(root)
  local function git(...)
    local command = { "git", "-C", root, "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid" }
    local result = vim.system(vim.list_extend(command, { ... }), { text = true }):wait()
    return result.code == 0, result.stderr, vim.trim(result.stdout or "")
  end
  assert(git("init", "-q", "-b", "main"))
  return root, git
end
local function write(root, path, lines) vim.fn.writefile(lines, root .. "/" .. path) end
local function numbered(name)
  local lines = {}
  for i = 1, 20 do lines[i] = ("%s line %d"):format(name, i) end
  return lines
end

--- "M b.txt", "R e.txt→e_renamed.txt", sorted.
local function shown(entries)
  local out = {}
  for _, e in ipairs(entries or {}) do
    out[#out + 1] = e.old_path and ("%s %s→%s"):format(e.status, e.old_path, e.path) or (e.status .. " " .. e.path)
  end
  table.sort(out)
  return out
end

-- Load CodeDiff the way its first key does: the spec's config runs setup.
require("lazy").load({ plugins = { "codediff.nvim" } })
local cd = require("util.codediff")
local lifecycle = require("codediff.ui.lifecycle")
local changes = require("codediff.core.git.changes")
t.ok(not cd.degraded(), "the installed CodeDiff is the version util.codediff was written against")
t.ok(changes.nvim_config_patched == true, "the revision listing is patched")
t.ok(require("codediff.core.git").get_diff_revision == changes.get_diff_revision, "and so is core.git's copy")

--- The patched listing of `rev` against the working tree of `root`.
local function listing(rev, root, pathspec)
  local got
  changes.get_diff_revision(rev, root, function(err, result) got = { err = err, result = result } end, pathspec)
  vim.wait(10000, function() return got ~= nil end, 10)
  settle(20) -- scheduled notices
  return got and got.result and shown(got.result.unstaged), got and got.err
end

local B = require("util.baseline")
local function save(root, kind, meta)
  local entry, err
  B.save(root, kind, meta, function(e, info)
    entry, err = e, e == nil and info or nil
  end)
  vim.wait(10000, function() return entry ~= nil or err ~= nil end, 10)
  return entry, err
end

-- vim.ui.select / vim.ui.input answer from a script: each select takes the
-- first item its predicate accepts, each input returns the next string.
local real_select, real_input = vim.ui.select, vim.ui.input
local script = {}
vim.ui.select = function(items, _, on_choice)
  local want = table.remove(script, 1)
  for _, item in ipairs(items) do
    if type(want) == "function" and want(item) then return on_choice(item) end
  end
  on_choice(nil)
end
vim.ui.input = function(_, on_confirm) on_confirm(table.remove(script, 1)) end
local function display(text)
  return function(item) return item.display and item.display:find(text, 1, true) ~= nil end
end

--- A revision view in the current tabpage with its first file loaded.
local function ready()
  local s = cd.session(0)
  if not s or s.mode ~= "revision" or not s.modified_bufnr or not vim.api.nvim_buf_is_valid(s.modified_bufnr) then
    return false
  end
  local raw = lifecycle.get_session(s.tabpage)
  return raw.refresh ~= nil and raw.refresh.loading == false and raw.panel.data.status_result ~= nil
    and vim.api.nvim_buf_get_name(s.modified_bufnr) ~= ""
end
local function view_list(tab)
  return shown(lifecycle.get_session(tab).panel.data.status_result.unstaged)
end
local function close(tab)
  cd.close(tab)
  return vim.wait(3000, function() return not vim.api.nvim_tabpage_is_valid(tab) end, 20)
end

vim.o.lines, vim.o.columns = 45, 180
local cwd = vim.fn.getcwd()

---------------------------------------------------------------------------
-- A round baseline against the working tree (the exp-repo case)
---------------------------------------------------------------------------

local root, git = repo("listing spec")
for _, name in ipairs({ "a", "b", "c", "e", "s" }) do write(root, name .. ".txt", numbered(name)) end
write(root, "中文.txt", { "中文内容", "第二行" })
write(root, ".gitignore", { "*.log" })
assert(git("add", "."))
assert(git("commit", "-qm", "init"))
-- Untracked when the baseline is taken, so it captures them.
write(root, "u.txt", { "untracked one" })
write(root, "big.bin", { string.rep("b", 100) })
write(root, "x.log", { "ignored" })
local round = save(root, "round", {
  subject = "nvim review: Claude round 11:22:33", Source = "claude", Conversation = "claude:spec", Root = root,
})
t.ok(round ~= nil and round.sha:match("^%x+$") ~= nil, "a round baseline is saved")

-- What an agent then does.
write(root, "agent.txt", { "new from the agent" })
local b = numbered("b")
b[7] = "b line 7 CHANGED"
write(root, "b.txt", b)
os.remove(root .. "/c.txt")
assert(os.rename(root .. "/e.txt", root .. "/e_renamed.txt"))
write(root, "u.txt", { "untracked one", "and a second line" })
write(root, "新文件.txt", { "新内容" })
write(root, "中文.txt", { "中文内容 改", "第二行" })
os.remove(root .. "/s.txt")
assert(uv.fs_symlink("a.txt", root .. "/s.txt"))
write(root, "big.bin", { string.rep("b", 2048) }) -- grown past max_file_size
write(root, "huge.bin", { string.rep("h", 4096) }) -- new, and over it
write(root, "y.log", { "ignored too" })

local EXPECTED = {
  "A agent.txt", "A 新文件.txt", "D c.txt", "M b.txt", "M s.txt", "M u.txt", "M 中文.txt", "R e.txt→e_renamed.txt",
}
table.sort(EXPECTED)

-- Through <leader>gk: the round baseline, then the working tree. The round is
-- picked by its sha, since ai.review.labels names it in the picker; the tab
-- variables and label the view gets are manual_compare_spec's and
-- review_view_spec's.
local function the_round(item) return item.rev == round.sha end
vim.cmd.cd(vim.fn.fnameescape(root))
vim.cmd.enew()
local editor_tab = vim.api.nvim_get_current_tabpage()
notices = {}
script = { the_round, display("Working tree") }
key("<leader>gk")()
t.ok(vim.wait(15000, ready, 20), "<leader>gk opens the round baseline against the working tree")
local view_tab = vim.api.nvim_get_current_tabpage()
t.eq(view_list(view_tab), EXPECTED, "the view lists A/M/D/R from the two trees")
t.eq(cd.session(0).base_revision, round.sha, "CodeDiff was given the baseline's sha")
t.eq(count("Not compared"), 1, "the skipped files are named once")
t.ok(said("big.bin") and said("huge.bin") and said("1024 bytes"), "both of them, with the limit")

-- A refresh lists through the patch again: a new file shows, no notice repeats.
write(root, "fresh.txt", { "written while the view is open" })
vim.api.nvim_set_current_win(cd.session(0).panel_win)
vim.api.nvim_feedkeys("R", "xt", false)
t.ok(vim.wait(5000, function()
  return vim.list_contains(view_list(view_tab), "A fresh.txt")
end, 20), "a refresh lists a file added since")
t.eq(count("Not compared"), 1, "and does not name the skipped files again")

-- The file panes: the baseline's copy of u.txt on the left, the real file
-- on the right.
local panel = cd.session(0)
local row
for i, line in ipairs(vim.api.nvim_buf_get_lines(panel.panel_bufnr, 0, -1, false)) do
  if line:find("u.txt", 1, true) then row = i end
end
t.ok(row ~= nil, "u.txt is in the explorer")
vim.api.nvim_win_set_cursor(panel.panel_win, { row, 0 })
vim.api.nvim_feedkeys(vim.keycode("<CR>"), "xt", false)
t.ok(vim.wait(5000, function()
  local s = cd.session(0)
  return s and s.modified and s.modified.relative == "u.txt" and vim.api.nvim_buf_is_valid(s.modified_bufnr)
    and vim.api.nvim_buf_get_name(s.modified_bufnr) == root .. "/u.txt"
end, 20), "selecting u.txt puts the real file on the right")
local left_name = vim.api.nvim_buf_get_name(cd.session(0).original_bufnr)
t.ok(left_name:match("^codediff://") ~= nil and left_name:find(round.sha, 1, true) ~= nil,
  "and the baseline's copy on the left (" .. left_name:sub(1, 40) .. "...)")

t.ok(close(view_tab), "the view closes")
-- Per view: opening it again names the skipped files again.
notices = {}
script = { the_round, display("Working tree") }
key("<leader>gk")()
t.ok(vim.wait(15000, ready, 20), "the same comparison opens again")
t.eq(count("Not compared"), 1, "and names the skipped files once more, for this view")
t.ok(close(vim.api.nvim_get_current_tabpage()), "and closes")
vim.api.nvim_set_current_tabpage(editor_tab)

-- Straight through the patched function: the same list, and a pathspec.
local with_fresh = vim.deepcopy(EXPECTED)
with_fresh[#with_fresh + 1] = "A fresh.txt"
table.sort(with_fresh)
t.eq((listing(round.sha, root)), with_fresh, "get_diff_revision lists the same entries")
t.eq((listing(round.sha, root, { "b.txt" })), { "M b.txt" }, "and honours a pathspec")
t.eq((listing(round.sha, root, { "big.bin" })), {}, "a pathspec on a skipped file lists nothing, not a deletion")

---------------------------------------------------------------------------
-- Unsaved buffers whose file changed on disk
---------------------------------------------------------------------------

vim.cmd.edit(vim.fn.fnameescape(root .. "/b.txt"))
local b_buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(b_buf, 0, 1, false, { "an unsaved edit" })
local later = os.time() + 5
write(root, "b.txt", vim.list_extend({ "changed on disk" }, numbered("b")))
uv.fs_utime(root .. "/b.txt", later, later)
notices = {}
listing(round.sha, root)
t.eq(count("b.txt: unsaved changes here"), 1, "a modified buffer whose file changed on disk is named")
t.ok(said(":e! takes the disk's version"), "with both ways out")
listing(round.sha, root)
t.eq(count("b.txt: unsaved changes here"), 1, "once per disk mtime")
uv.fs_utime(root .. "/b.txt", later + 5, later + 5)
listing(round.sha, root)
t.eq(count("b.txt: unsaved changes here"), 2, "and again when the disk changes again")

-- A file the listing does not show says nothing, whatever its buffer holds.
vim.cmd.edit(vim.fn.fnameescape(root .. "/a.txt"))
local a_buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(a_buf, 0, 1, false, { "an unsaved edit" })
uv.fs_utime(root .. "/a.txt", later, later)
listing(round.sha, root)
t.ok(not said("a.txt: unsaved changes here"), "an unlisted file is not named")
for _, buf in ipairs({ a_buf, b_buf }) do
  vim.api.nvim_buf_call(buf, function() vim.cmd("silent edit!") end)
end
notices = {}
listing(round.sha, root)
t.ok(not said("unsaved changes here"), "a buffer reloaded from disk is not named")
vim.cmd.enew()

---------------------------------------------------------------------------
-- A branch that tracks a file this checkout leaves untracked (t19), via <leader>gM
---------------------------------------------------------------------------

local port_root, pgit = repo("listing t19")
write(port_root, "keep.txt", { "kept" })
assert(pgit("add", "."))
assert(pgit("commit", "-qm", "init"))
assert(pgit("checkout", "-qb", "other"))
write(port_root, "port.lua", { "return 1" })
assert(pgit("add", "port.lua"))
assert(pgit("commit", "-qm", "port"))
assert(pgit("checkout", "-q", "main"))
write(port_root, "port.lua", { "return 2" }) -- untracked on main
t.eq((listing("other", port_root)), { "M port.lua" }, "a file the branch tracks and main leaves untracked is M")

vim.cmd.cd(vim.fn.fnameescape(port_root))
notices = {}
script = { function(item) return item.rev == "other" end }
key("<leader>gM")()
t.ok(vim.wait(15000, ready, 20), "<leader>gM opens the branch against the working tree")
local port_tab = vim.api.nvim_get_current_tabpage()
t.eq(view_list(port_tab), { "M port.lua" }, "and lists it as M, not D + ??")
t.eq(vim.t.codediff_baseline, nil, "a branch is not marked as a baseline")
t.ok(close(port_tab), "the view closes")
vim.api.nvim_set_current_tabpage(editor_tab)

---------------------------------------------------------------------------
-- Paths the revision has that are still on disk, but not in the snapshot
---------------------------------------------------------------------------

local out_root, ogit = repo("listing left out")
write(out_root, "kept.txt", { "kept" })
assert(ogit("add", "."))
assert(ogit("commit", "-qm", "init"))
-- Untracked when the baseline is taken, so it captures them.
write(out_root, ".env", { "API_KEY=first-secret-value" })
write(out_root, "locked.txt", { "readable when the baseline was taken" })
write(out_root, "dirfile", { "a plain file at the baseline" })
write(out_root, "Notes.md", { "first draft of the notes" })
local left_round = save(out_root, "round", { subject = "nvim review: left out" })
t.ok(left_round ~= nil, "a baseline holding .env, locked.txt, dirfile and Notes.md is saved")
-- Then .env is ignored and its secret rotated, locked.txt cannot be read,
-- dirfile is a directory, and Notes.md is NOTES.md with other text.
write(out_root, ".gitignore", { ".env" })
write(out_root, ".env", { "API_KEY=rotated-secret-value" })
local locked = out_root .. "/locked.txt"
uv.fs_chmod(locked, tonumber("000", 8))
local unreadable = io.open(locked, "r") == nil -- not as root
os.remove(out_root .. "/dirfile")
vim.fn.mkdir(out_root .. "/dirfile", "p")
write(out_root, "dirfile/inner.txt", { "inside the new directory" })
assert(os.rename(out_root .. "/Notes.md", out_root .. "/NOTES.md"))
write(out_root, "NOTES.md", { "nothing in common with what was there" })
-- Where the file system folds case (macOS by default), Notes.md still
-- resolves, to NOTES.md, and a restore of it would overwrite that.
local folds = uv.fs_lstat(out_root .. "/notes.md") ~= nil
local expected = { "A .gitignore", "A NOTES.md", "A dirfile/inner.txt" }
if not folds then expected[#expected + 1] = "D Notes.md" end
table.sort(expected)
local on_disk = {}
if folds then on_disk[#on_disk + 1] = "Notes.md" end
on_disk[#on_disk + 1] = "dirfile"
if unreadable then on_disk[#on_disk + 1] = "locked.txt" end
notices = {}
t.eq((listing(left_round.sha, out_root)), expected, "a path that is still on disk is not listed as deleted")
t.eq(count("Not compared"), 1, "what was left out is named in one notice")
t.ok(said("Not compared (ignored, still on disk): .env"), "an ignored file as ignored")
t.ok(said("Not compared (still on disk, so not listed as deleted): " .. table.concat(on_disk, ", ")),
  "the rest as still on disk: " .. table.concat(on_disk, ", "))
listing(left_round.sha, out_root)
t.eq(count("Not compared"), 1, "and not named again for the same view")
uv.fs_chmod(locked, tonumber("644", 8))

---------------------------------------------------------------------------
-- A root CodeDiff's expand() would rewrite, and a branch named history
---------------------------------------------------------------------------

-- `$app` is unset, so expand() drops it. Not a set variable like $HOME:
-- gitsigns expands those in a repository's path (vim.fs.normalize) and fails.
local dollar_root, dgit = repo("listing my$app")
t.ok(dollar_root:find("listing my$app", 1, true) ~= nil, "the fixture's path holds a literal $app")
write(dollar_root, "a.txt", { "one" })
assert(dgit("add", "."))
assert(dgit("commit", "-qm", "one"))
assert(dgit("branch", "history"))
write(dollar_root, "a.txt", { "two" })
local _, _, history_sha = dgit("rev-parse", "history")
vim.api.nvim_set_current_dir(dollar_root)
vim.cmd.enew()
notices = {}
script = { function(item) return item.kind == "rev" and item.rev == "history" end, display("Working tree") }
key("<leader>gk")()
t.ok(vim.wait(15000, ready, 20), "<leader>gk history → working tree opens a revision view")
local dollar_tab = vim.api.nvim_get_current_tabpage()
local ds = cd.session(0)
t.eq(ds and ds.git_root, dollar_root, "of the repository whose path holds $app")
t.eq(ds and ds.base_revision, history_sha, "against the branch's commit")
t.eq(vim.t.codediff_label, "history → working tree", "labelled with the branch")
t.eq(ds and ds.mode, "revision", "a revision view, not CodeDiff's history")
t.eq(ds and ds.mode == "revision" and view_list(dollar_tab) or nil, { "M a.txt" }, "listing what changed since")
t.ok(not said("Not a git repository"), "CodeDiff found the repository")
t.ok(ds and close(dollar_tab), "the view closes")
vim.api.nvim_set_current_tabpage(editor_tab)

---------------------------------------------------------------------------
-- A failing snapshot falls back to upstream's listing
---------------------------------------------------------------------------

local real_snapshot = B.snapshot
B.snapshot = function(_, cb) vim.schedule(function() cb(nil, "spec: no snapshot") end) end
notices = {}
local upstream = listing(round.sha, root)
t.ok(upstream ~= nil and vim.list_contains(upstream, "D u.txt") and vim.list_contains(upstream, "?? u.txt"),
  "a failed snapshot gives upstream's listing (D + ?? for u.txt)")
t.ok(said("fell back to upstream's") and said("spec: no snapshot"), "with a warning that says why")
B.snapshot = function() error("spec: snapshot raised") end
upstream = listing(round.sha, root)
t.ok(upstream ~= nil and vim.list_contains(upstream, "?? u.txt"), "a snapshot that raises falls back as well")
t.eq(count("fell back to upstream's"), 1, "warning only once")
B.snapshot = real_snapshot
t.ok(not vim.list_contains(listing(round.sha, root), "?? u.txt"), "the patched listing is back afterwards")

vim.ui.select, vim.ui.input = real_select, real_input
vim.notify = real_notify
vim.g.ai_review = nil
local cleanup = t.process_cleanup()
cleanup()
vim.cmd.cd(vim.fn.fnameescape(cwd))
for _, dir in ipairs({ root, port_root, out_root, dollar_root }) do vim.fn.delete(dir, "rf") end
vim.fn.delete(gitconfig)

t.done()
