local M = {}
local health = vim.health
local function env_value(name)
  local value = vim.env[name]
  return (value ~= nil and value ~= "") and value or nil
end

local function plural(n, word)
  return ("%d %s%s"):format(n, word, n == 1 and "" or "s")
end

local function split_lines(s)
  return vim.split(s or "", "\n", { plain = true, trimempty = true })
end

-- git in `dir`, synchronously, with util.baseline's prefix: no optional locks
-- (a plain status rewrites .git/index) and none of the user's hooks.
-- GIT_NO_LAZY_FETCH keeps a missing object from becoming a fetch.
---@return string? stdout, string? err
local function git(dir, args)
  local ok, r = pcall(function()
    return vim.system(require("git_review.baseline").git_cmd(args), {
      cwd = dir,
      text = true,
      env = { GIT_NO_LAZY_FETCH = "1", LC_ALL = "C" },
    }):wait(10000)
  end)
  if not ok then return nil, tostring(r) end
  if r.code ~= 0 then return nil, vim.trim(r.stderr or "") end
  return r.stdout or ""
end

-- One section of the review checks: a check that raises is reported in its
-- own section instead of ending `:checkhealth config` there.
local function section(name, check)
  health.start(name)
  local ok, err = pcall(check)
  if not ok then health.error("this check failed: " .. tostring(err)) end
end

-- CodeDiff's install layout, as its README documents it: the plugin root holds
-- VERSION and the native library, named libvscode_diff_<VERSION>.<ext> by its
-- installer or libvscode_diff.<ext> by a local build.
local LIB_EXT = ({ OSX = "dylib", Windows = "dll" })[jit.os] or "so"
local EXE_SUFFIX = jit.os == "Windows" and ".exe" or ""

local function first_line(path)
  local file = io.open(path, "r")
  if not file then return nil end
  local line = file:read("*l")
  file:close()
  return line and vim.trim(line) or nil
end

-- The library's own version, from CodeDiff's FFI wrapper (codediff.core.diff
-- get_version). Requiring that module loads codediff.nvim -- lazy's module
-- loader runs the spec's config -- and the library itself, which is why only
-- this check calls it, and only once the library file is known to exist. The
-- require would also download a library CodeDiff takes for stale; a health
-- check never downloads, so VSCODE_DIFF_NO_AUTO_INSTALL is held on for the
-- require and put back at once.
---@return string? version, string? err
local function library_version()
  local diff = package.loaded["codediff.core.diff"]
  if not diff then
    local saved = vim.env.VSCODE_DIFF_NO_AUTO_INSTALL
    vim.env.VSCODE_DIFF_NO_AUTO_INSTALL = "1"
    local ok, mod = pcall(require, "codediff.core.diff")
    vim.env.VSCODE_DIFF_NO_AUTO_INSTALL = saved
    if not ok then return nil, tostring(mod) end
    diff = mod
  end
  if type(diff) ~= "table" or type(diff.get_version) ~= "function" then
    return nil, "codediff.core.diff has no get_version"
  end
  local ok, version = pcall(diff.get_version)
  if not ok then return nil, tostring(version) end
  return tostring(version)
end

-- The watcher CodeDiff would start, found in its own order
-- (core/installer/watcher.lua ensure) after CODEDIFF_WATCHER_PATH: a local
-- build in the plugin root, the release it downloads there, then PATH. The
-- release it wants is that installer's VERSION, read once CodeDiff is loaded
-- (requiring it before would load the plugin); until then any downloaded
-- release counts.
local function find_watcher(plugin)
  local names = { "codediff-watcher" .. EXE_SUFFIX }
  local wanted
  if plugin._ and plugin._.loaded then
    local ok, installer = pcall(require, "codediff.core.installer.watcher")
    wanted = ok and type(installer) == "table" and type(installer.VERSION) == "string" and installer.VERSION or nil
  end
  if wanted then
    names[#names + 1] = ("codediff-watcher_%s%s"):format(wanted, EXE_SUFFIX)
  elseif vim.fn.isdirectory(plugin.dir) == 1 then
    for name in vim.fs.dir(plugin.dir) do
      if name:match("^codediff%-watcher_") then names[#names + 1] = name end
    end
  end
  for _, name in ipairs(names) do
    local path = plugin.dir .. "/" .. name
    if vim.fn.filereadable(path) == 1 then return path end
  end
  local on_path = vim.fn.exepath("codediff-watcher")
  return on_path ~= "" and on_path or nil
end

local function check_codediff()
  local ok, lazy = pcall(require, "lazy.core.config")
  local plugin = ok and type(lazy.plugins) == "table" and lazy.plugins["codediff.nvim"] or nil
  if not plugin or vim.fn.isdirectory(plugin.dir or "") == 0 then
    health.error("codediff.nvim is not installed — no <leader>g diff views and no review views", { ":Lazy install" })
    return
  end
  local dir = plugin.dir

  -- The same comparison util.codediff.setup makes before it patches anything.
  local version = first_line(dir .. "/VERSION")
  local pinned = require("git_review.view").VERSION
  if version == pinned then
    health.ok(("codediff.nvim %s, the release util.codediff is written against — its patches are on"):format(version))
  else
    health.warn(("codediff.nvim %s is not the %s util.codediff is written against — "
      .. "its path fix, revision listing and history limit are off"):format(version or "(no VERSION file)", pinned), {
        ":Lazy restore codediff.nvim goes back to the commit in lazy-lock.json",
        "For an intended update: run tests/codediff_spec.lua, then raise VERSION in local-plugin/git-review.nvim/lua/git_review/view.lua",
      })
  end

  local no_auto = env_value("VSCODE_DIFF_NO_AUTO_INSTALL")
  local versioned = ("libvscode_diff_%s.%s"):format(version or "<version>", LIB_EXT)
  local lib
  -- CodeDiff loads the versioned file first and a local build after it.
  for _, name in ipairs({ versioned, "libvscode_diff." .. LIB_EXT }) do
    if vim.fn.filereadable(dir .. "/" .. name) == 1 then
      lib = name
      break
    end
  end
  if not lib then
    health.warn(("native diff library %s is missing from %s — no diff view opens until it is there")
      :format(versioned, dir), {
      no_auto and ":CodeDiff install downloads it (VSCODE_DIFF_NO_AUTO_INSTALL stops the download on first use)"
        or "CodeDiff downloads it on first use (curl or wget, github.com); :CodeDiff install does it now",
      "See docs/DIAGNOSTICS.md",
    })
  else
    local got, err = library_version()
    if not got then
      health.error(("native diff library %s does not load — CodeDiff cannot diff: %s"):format(lib, err), {
        ":CodeDiff install! reinstalls it",
        jit.os == "Linux" and "On Linux it also needs libgomp.so.1; see CodeDiff's README" or nil,
      })
    elseif version and got ~= version then
      health.warn(("native diff library %s reports %s, codediff.nvim is %s"):format(lib, got, version),
        { ":CodeDiff install! fetches the matching one" })
    else
      health.ok(("native diff library %s loads (%s)"):format(got, lib))
    end
  end
  if no_auto then
    health.info(("VSCODE_DIFF_NO_AUTO_INSTALL=%s — CodeDiff never downloads its library on its own; "
      .. ":CodeDiff install still does"):format(no_auto))
  end

  -- Only "1" counts here: the installer compares the value, where the library
  -- loader above takes any non-empty value.
  local watcher_no_auto = env_value("CODEDIFF_WATCHER_NO_AUTO_INSTALL")
  if watcher_no_auto == "1" then
    health.info("CODEDIFF_WATCHER_NO_AUTO_INSTALL=1 — CodeDiff never downloads its file watcher")
  elseif watcher_no_auto then
    health.info(("CODEDIFF_WATCHER_NO_AUTO_INSTALL=%s has no effect — only 1 stops the watcher download")
      :format(watcher_no_auto))
  end

  local polling = "CodeDiff polls the repository every 500 ms instead"
  local override = env_value("CODEDIFF_WATCHER_PATH")
  if override and vim.fn.executable(override) == 1 then
    health.ok(("file watcher %s (CODEDIFF_WATCHER_PATH) — views refresh on file events"):format(override))
    return
  end
  -- CodeDiff takes any readable override and only fails when it starts it;
  -- one it cannot read, it passes over.
  if override and vim.fn.filereadable(override) == 1 then
    health.warn(("CODEDIFF_WATCHER_PATH=%s is not executable — %s"):format(override, polling),
      { "chmod +x " .. vim.fn.shellescape(override) })
    return
  end
  if override then
    health.warn(("CODEDIFF_WATCHER_PATH=%s does not exist — CodeDiff ignores it"):format(override))
  end
  local watcher = find_watcher(plugin)
  if watcher then
    health.ok(("file watcher %s — views refresh on file events"):format(watcher))
  else
    health.warn("no CodeDiff file watcher — " .. polling, {
      watcher_no_auto == "1"
          and "CODEDIFF_WATCHER_NO_AUTO_INSTALL=1 keeps CodeDiff from downloading it: unset it and open a diff view"
        or "CodeDiff downloads it on the first diff view (curl or wget, github.com)",
      "Or put codediff-watcher on PATH, or point CODEDIFF_WATCHER_PATH at one",
    })
  end
end

-- util.baseline hands `git add` its pathspecs on stdin (--pathspec-from-file),
-- which git learned in 2.26; with an older git every snapshot fails. Nothing
-- else in the review loop or the diff views needs a newer one.
local GIT_MIN = "2.26"

local function check_git()
  if vim.fn.executable("git") ~= 1 then
    health.error("git not found — no diff views and no review baselines")
    return
  end
  local out = vim.system({ "git", "--version" }, { text = true }):wait(5000)
  local version = vim.version.parse(out.stdout or "")
  if version and vim.version.ge(version, GIT_MIN) then
    health.ok(("git %s — review baselines need %s or later"):format(tostring(version), GIT_MIN))
  else
    health.error(("git %s — review baselines need %s or later (git add --pathspec-from-file); every snapshot fails")
      :format(version and tostring(version) or "(unknown version)", GIT_MIN),
      { "Install a newer git (brew install git)" })
  end
end

local function wtid_of(gitdir)
  return vim.fn.sha256(gitdir):sub(1, 12)
end

-- `cd <root> && git for-each-ref ... | git update-ref --stdin`: deletes every
-- ref under the given prefixes, in the repository at `root`.
local function delete_refs_command(root, prefixes)
  local quoted = vim.tbl_map(vim.fn.shellescape, prefixes)
  return ("cd %s && git for-each-ref --format='delete %%(refname)' %s | git update-ref --stdin")
    :format(vim.fn.shellescape(root), table.concat(quoted, " "))
end

-- Refs under refs/nvim-review/ whose worktree id names no worktree of this
-- repository any more (`git worktree remove`, or a moved repository). They
-- keep their commits from gc and nothing deletes them on its own.
local function check_orphans(loc, namespace)
  local common, err = git(loc.toplevel, { "rev-parse", "--git-common-dir" })
  local refs, refs_err = git(loc.toplevel, { "for-each-ref", "--format=%(refname)%00%(objectname)", namespace .. "/" })
  if not (common and refs) then
    health.warn("could not look for baselines of removed worktrees: " .. tostring(err or refs_err))
    return
  end
  -- Every worktree's gitdir, hashed the way util.baseline.locate names it:
  -- the common dir is the main worktree's, linked ones live under worktrees/.
  common = vim.trim(common)
  if common:sub(1, 1) ~= "/" then common = loc.toplevel .. "/" .. common end
  common = vim.uv.fs_realpath(common) or common
  local alive = { [loc.wtid] = true, [wtid_of(common)] = true }
  if vim.fn.isdirectory(common .. "/worktrees") == 1 then
    for name, kind in vim.fs.dir(common .. "/worktrees") do
      local gitdir = common .. "/worktrees/" .. name
      if kind == "directory" then alive[wtid_of(vim.uv.fs_realpath(gitdir) or gitdir)] = true end
    end
  end

  local orphans, order = {}, {}
  for _, line in ipairs(split_lines(refs)) do
    local name, sha = line:match("^(.-)%z(%x+)$")
    local wtid, kind = (name or ""):match("^" .. vim.pesc(namespace) .. "/([^/]+)/([^/]+)/")
    if wtid and not alive[wtid] then
      local o = orphans[wtid]
      if not o then
        o = { refs = 0, shas = {} }
        orphans[wtid], order[#order + 1] = o, wtid
      end
      o.refs = o.refs + 1
      -- Rounds carry a Root trailer and saved baselines do not: rounds first.
      table.insert(o.shas, kind == "round" and 1 or #o.shas + 1, sha)
    end
  end
  if #order == 0 then
    health.ok("no baseline refs of removed worktrees")
    return
  end
  table.sort(order)
  local described, prefixes, total = {}, {}, 0
  for _, wtid in ipairs(order) do
    local o = orphans[wtid]
    total = total + o.refs
    local root
    for i = 1, math.min(#o.shas, 3) do
      local body = git(loc.toplevel, { "cat-file", "commit", o.shas[i] })
      root = body and body:match("\nRoot: ([^\n]+)")
      if root then break end
    end
    described[#described + 1] = ("%s (%s%s)"):format(wtid, plural(o.refs, "ref"), root and (", Root " .. root) or "")
    prefixes[#prefixes + 1] = ("%s/%s/"):format(namespace, wtid)
  end
  health.warn(("%s of worktrees that no longer exist: %s — they keep their commits from gc, "
    .. "and nothing deletes them on its own"):format(plural(total, "baseline ref"), table.concat(described, "; ")),
    { "To delete them (from any worktree of this repository):", delete_refs_command(loc.toplevel, prefixes) })
end

local function check_baselines(context)
  local cwd = vim.fn.getcwd()
  if vim.fn.executable("git") ~= 1 then
    health.info("git not found — no baselines to count")
    return
  end
  local B = require("git_review.baseline")
  local loc, err = B.locate(cwd)
  if not loc then
    if err:find("not a git repository", 1, true) then
      health.info(("%s is not in a Git worktree — baselines belong to one, so there is nothing to count here")
        :format(cwd))
    elseif err:find("^bare repository") then
      health.info(err)
    elseif err:find("is set in Nvim's environment", 1, true) then
      health.warn(err, { "Start Nvim without GIT_DIR and GIT_WORK_TREE" })
    else
      health.warn(err)
    end
    return
  end

  local retention = context.retention or require("git_review").options().retention
  local done, entries, list_err = false, nil, nil
  B.list(loc.toplevel, function(found, e) entries, list_err, done = found, e, true end)
  vim.wait(10000, function() return done end, 20)
  if not done or list_err then
    health.warn(("could not list the baselines of %s: %s"):format(loc.toplevel, list_err or "timed out"))
  else
    local count = { round = 0, saved = 0 }
    for _, entry in ipairs(entries) do count[entry.kind] = (count[entry.kind] or 0) + 1 end
    health.ok(("%d round and %d saved baselines for %s (worktree id %s); retention keeps the newest %s and %s")
      :format(count.round, count.saved, loc.toplevel, loc.wtid,
        retention.rounds or "caller policy", retention.saved))
  end

  check_orphans(loc, B.NAMESPACE)

  -- CodeCompanion's own code_review (turned off in
  -- lua/plugin/ai/codecompanion.lua) kept its baselines as per-worktree refs.
  local cc, cc_err = git(loc.toplevel, { "for-each-ref", "--format=%(refname)", "refs/worktree/codecompanion/" })
  local cc_refs = split_lines(cc)
  if not cc then
    health.warn("could not look for CodeCompanion's refs: " .. tostring(cc_err))
  elseif #cc_refs == 0 then
    health.ok("no refs/worktree/codecompanion/* left by CodeCompanion's code_review")
  else
    health.warn(("%s under refs/worktree/codecompanion/ in this worktree, left by CodeCompanion's code_review, "
      .. "which this config turns off; nothing reads them"):format(plural(#cc_refs, "ref")),
      { "To delete them:", delete_refs_command(loc.toplevel, { "refs/worktree/codecompanion/" }) })
  end

end
function M.check(context)
  context = context or {}
  section("config: CodeDiff", check_codediff)
  section("config: git", check_git)
  section("config: review baselines", function() check_baselines(context) end)
end
return M
