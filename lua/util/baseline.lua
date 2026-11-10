-- Baselines: immutable snapshots of a worktree, kept as parentless commits
-- under refs/nvim-review/<wtid>/{round,saved}/<id>.
--
-- A snapshot never writes the user's state. Each one copies the real index to
-- a temporary file of its own, adds the worktree to that copy and writes its
-- tree, so HEAD, the real index, branches and stash stay byte-for-byte as they
-- were; the only lasting writes are objects and refs under refs/nvim-review/.
-- Why each step is the way it is:
--
--   * One temporary index per snapshot, never a fixed file. Seeding a fresh
--     copy each time applies the current .gitignore (a file ignored after an
--     earlier snapshot drops out), survives `gc --prune=now`, and leaves
--     nothing for two Nvims to fight over.
--   * The copy keeps the real index's mtime (minus a hair). git trusts an
--     entry's cached stat only when the entry is older than the index file;
--     a copy stamped "now" made every file staged in the second before the
--     real index was written look old, and a same-size edit in that second
--     was missed (5 of 5 tries without the stamp, 0 of 5 with it).
--   * Large untracked files are excluded by a `:(exclude,literal)` pathspec,
--     so they are never hashed into .git/objects. Tracked files are added
--     whatever their size, as `git add` would.
--   * Refs live in the shared namespace, one directory per worktree. Per-
--     worktree refs (refs/worktree/*) only count as gc roots in their own
--     worktree: a gc from another worktree deleted the commits and left
--     `git log --all` fatal there.
--
-- The trailers in a baseline's message are opaque key/value pairs to this
-- module; what Source or Conversation mean belongs to its callers. The
-- retention counts and the size cut-off come from ai.review.config, read on
-- each use.
--
-- Every callback runs on the main loop, scheduled.
local M = {}

local uv = vim.uv

M.NAMESPACE = "refs/nvim-review"
-- kind -> the ai.review.config retention key that caps it.
M.KINDS = { round = "rounds", saved = "saved" }

-- Prefix of every git call made here:
--   --no-optional-locks    no opportunistic index refresh, so nothing here
--                          competes with an agent's own `git add` for
--                          index.lock;
--   core.hooksPath         the user's hooks (post-index-change,
--                          reference-transaction) are not ours to fire;
--   core.splitIndex=false  the temporary index is written whole, never as a
--                          new shared index next to the user's.
local GIT = { "git", "--no-optional-locks", "-c", "core.hooksPath=/dev/null", "-c", "core.splitIndex=false" }

-- A missing object must never become a fetch from a promisor remote.
local ENV = { GIT_NO_LAZY_FETCH = "1" }

-- Fixed identity for every baseline commit, so no user config is needed and a
-- baseline can never be mistaken for the user's own commit.
local IDENTITY = {
  GIT_AUTHOR_NAME = "nvim review",
  GIT_AUTHOR_EMAIL = "nvim-review@localhost",
  GIT_COMMITTER_NAME = "nvim review",
  GIT_COMMITTER_EMAIL = "nvim-review@localhost",
}

-- Seconds taken off the copied index's mtime. Never later than the original
-- is what matters: an earlier stamp only makes git re-read more files, while
-- a double's rounding could otherwise land a hair later.
local RACY_MARGIN = 0.001

-- More untracked files than this usually means a missing .gitignore entry,
-- and every snapshot hashes them all again. Warned about once per gitdir.
local MANY_UNTRACKED = 5000

local warned = {}

local function warn(msg, key)
  key = key or msg
  if warned[key] then return end
  warned[key] = true
  vim.schedule(function() vim.notify(msg, vim.log.levels.WARN, { title = "Baselines" }) end)
end

local function noop() end

---The git argv for `args`, with the prefix every call here carries.
---@param args string[]
---@return string[]
function M.git_cmd(args)
  local cmd = vim.list_slice(GIT)
  vim.list_extend(cmd, args)
  return cmd
end

---Settings for this module, from the review config.
local function settings()
  return require("ai.review.config").get()
end

---Hand `cb` its arguments on the main loop. Each delivery is scheduled on its
---own, so a callback that raises cannot keep the next one from running.
local function deliver(cb, ...)
  local n, args = select("#", ...), { ... }
  vim.schedule(function() cb(unpack(args, 1, n)) end)
end

-- Run a git command; `cb(result)` runs on the main loop, so the next step may
-- use any API. A spawn that fails outright reads as a failed result.
local function run(loc, args, opts, cb)
  opts = opts or {}
  local spec = {
    cwd = loc.toplevel,
    env = vim.tbl_extend("force", ENV, opts.env or {}),
    stdin = opts.stdin,
  }
  local ok, err = pcall(vim.system, M.git_cmd(args), spec, function(r)
    vim.schedule(function() cb(r) end)
  end)
  if not ok then
    vim.schedule(function() cb({ code = -1, signal = 0, stdout = "", stderr = tostring(err) }) end)
  end
end

local function failure(what, r)
  local msg = vim.trim(r.stderr or "")
  if msg == "" then msg = ("exit %s"):format(tostring(r.code)) end
  return ("%s failed: %s"):format(what, msg)
end

local function lines(s) return vim.split(s or "", "\n", { plain = true, trimempty = true }) end

-- The nearest existing directory at or above `path`, resolved.
local function start_dir(path)
  local dir = vim.fs.abspath((path and path ~= "") and path or uv.cwd())
  while true do
    local st = uv.fs_stat(dir)
    if st then
      if st.type ~= "directory" then dir = vim.fs.dirname(dir) end
      return uv.fs_realpath(dir) or dir
    end
    local parent = vim.fs.dirname(dir)
    if parent == dir then return nil end
    dir = parent
  end
end

-- realpath(dir) -> location. A cached entry is dropped once its gitdir is gone.
local located = {}

---@class baseline.Location
---@field toplevel string realpath of the worktree's top level
---@field gitdir string realpath of its gitdir (.git, or .git/worktrees/<name>)
---@field wtid string first 12 hex digits of sha256(gitdir)

---The worktree that contains `path` (default: the cwd). Synchronous, and
---cached per directory. Refuses a bare repository, and refuses outright while
---GIT_DIR or GIT_WORK_TREE is set: then git's idea of "the repository" is no
---longer the directory's.
---@param path? string
---@return baseline.Location|nil loc, string? err
function M.locate(path)
  for _, var in ipairs({ "GIT_DIR", "GIT_WORK_TREE" }) do
    if uv.os_getenv(var) then
      return nil, ("%s is set in Nvim's environment; baselines are disabled"):format(var)
    end
  end
  local dir = start_dir(path)
  if not dir then return nil, "not a git repository: " .. tostring(path) end
  local hit = located[dir]
  if hit and uv.fs_stat(hit.gitdir) then return vim.deepcopy(hit) end
  located[dir] = nil
  if vim.in_fast_event() then return nil, "util.baseline.locate() needs the main loop" end

  -- LC_ALL=C keeps git's messages parseable; rev-parse runs no filters.
  local r = vim.system(M.git_cmd({ "rev-parse", "--is-bare-repository", "--absolute-git-dir", "--show-toplevel" }), {
    cwd = dir,
    text = true,
    env = vim.tbl_extend("force", ENV, { LC_ALL = "C", LANGUAGE = "C" }),
  }):wait()
  local out = lines(r.stdout)
  if r.code ~= 0 then
    if out[1] == "true" then
      return nil, ("bare repository: %s; baselines need a worktree"):format(out[2] or dir)
    end
    local msg = vim.trim(r.stderr or "")
    if msg == "" or msg:find("not a git repository", 1, true) then return nil, "not a git repository: " .. dir end
    return nil, ("git rev-parse failed in %s: %s"):format(dir, (msg:gsub("^fatal: ", "")))
  end
  if out[1] == "true" or not out[3] then
    return nil, ("bare repository: %s; baselines need a worktree"):format(out[2] or dir)
  end
  local gitdir = uv.fs_realpath(out[2]) or out[2]
  local loc = {
    toplevel = uv.fs_realpath(out[3]) or out[3],
    gitdir = gitdir,
    wtid = vim.fn.sha256(gitdir):sub(1, 12),
  }
  located[dir] = loc
  return vim.deepcopy(loc)
end

-- A temporary index in the gitdir, seeded from the real one. With no real
-- index yet (a fresh `git init`) the file is left absent, which git reads as
-- an empty index; an empty file would be a corrupt one.
local function temp_index(gitdir)
  local fd, path = uv.fs_mkstemp(gitdir .. "/nvim-review-index.XXXXXX")
  if not fd then return nil, ("cannot create a temporary index in %s: %s"):format(gitdir, tostring(path)) end
  uv.fs_close(fd)
  local real = gitdir .. "/index"
  -- Stat before copying: if the index is replaced in between, the copy is the
  -- newer file and the stamp the older one, which is the safe direction.
  local st = uv.fs_stat(real)
  if not st then
    uv.fs_unlink(path)
    return path
  end
  local ok, err = uv.fs_copyfile(real, path)
  if ok then
    local function seconds(ts) return ts.sec + ts.nsec / 1e9 end
    ok, err = uv.fs_utime(path, seconds(st.atime), seconds(st.mtime) - RACY_MARGIN)
  end
  if not ok then
    uv.fs_unlink(path)
    return nil, ("cannot seed the temporary index from %s: %s"):format(real, tostring(err))
  end
  return path
end

-- The snapshot itself: temporary index -> add --all -> write-tree.
-- `done(tree, info)` on success, `done(nil, err)` on failure.
local function take(loc, done)
  local max = settings().max_file_size
  local tmp, err = temp_index(loc.gitdir)
  if not tmp then return done(nil, err) end
  local env = { GIT_INDEX_FILE = tmp }
  local info = { skipped = {}, untracked = 0, toplevel = loc.toplevel, gitdir = loc.gitdir, wtid = loc.wtid }

  local finished = false
  local function finish(tree, e)
    if finished then return end
    finished = true
    uv.fs_unlink(tmp)
    uv.fs_unlink(tmp .. ".lock")
    if tree then return done(tree, info) end
    done(nil, e)
  end
  -- A step that raises still ends the snapshot: the queue waits on `done`.
  local function step(fn)
    return function(r)
      local ok, e = pcall(fn, r)
      if not ok then finish(nil, "snapshot failed: " .. tostring(e)) end
    end
  end

  -- The seeded copy answers "untracked" exactly as the real index would.
  run(loc, { "ls-files", "-z", "--others", "--exclude-standard" }, { env = env }, step(function(r)
    if r.code ~= 0 then return finish(nil, failure("git ls-files", r)) end
    local pathspec = { "." }
    for _, path in ipairs(vim.split(r.stdout or "", "\0", { plain = true, trimempty = true })) do
      info.untracked = info.untracked + 1
      -- lstat: an untracked symlink is stored as its target's name, however
      -- large the target.
      local st = uv.fs_lstat(loc.toplevel .. "/" .. path)
      if st and st.type == "file" and st.size > max then
        info.skipped[#info.skipped + 1] = path
        pathspec[#pathspec + 1] = ":(exclude,literal)" .. path
      end
    end
    if info.untracked > MANY_UNTRACKED then
      warn(("%s has %d untracked files; is a .gitignore entry missing? Every snapshot hashes them again.")
        :format(loc.toplevel, info.untracked), "untracked:" .. loc.gitdir)
    end
    -- Pathspecs on stdin, NUL-separated: no argv limit, any file name.
    -- --ignore-errors keeps going past an unreadable file or a nested
    -- repository without a commit; git then exits 1 having written the index.
    run(loc, { "add", "--all", "--ignore-errors", "--pathspec-from-file=-", "--pathspec-file-nul" }, {
      env = env,
      stdin = table.concat(pathspec, "\0") .. "\0",
    }, step(function(added)
      if added.code ~= 0 and added.code ~= 1 then return finish(nil, failure("git add", added)) end
      if added.code == 1 then info.unreadable = vim.trim(added.stderr or "") end
      run(loc, { "write-tree" }, { env = env }, step(function(w)
        local tree = vim.trim(w.stdout or "")
        if w.code ~= 0 or not tree:match("^%x+$") then return finish(nil, failure("git write-tree", w)) end
        finish(tree)
      end))
    end))
  end))
end

-- gitdir -> { running = bool, waiting = request[] }. One snapshot at a time
-- per gitdir, to bound the load; correctness does not depend on it, since
-- every snapshot has an index of its own.
local queues = {}

local function drain(loc)
  local q = queues[loc.gitdir]
  if not q or q.running or #q.waiting == 0 then return end
  -- Everything waiting shares the next snapshot: it starts after each of
  -- these requests was made, so it is as fresh as any of them asked for. A
  -- request made while a snapshot runs waits for the following one.
  local batch = q.waiting
  q.waiting, q.running = {}, true
  local called = false
  local function done(tree, info)
    if called then return end
    called = true
    q.running = false
    if #q.waiting > 0 then
      drain(loc)
    else
      queues[loc.gitdir] = nil
    end
    for _, request in ipairs(batch) do
      deliver(request.cb, tree, type(info) == "table" and vim.deepcopy(info) or info)
    end
  end
  local ok, err = pcall(take, loc, done)
  if not ok then done(nil, "snapshot failed: " .. tostring(err)) end
end

---@class baseline.Info
---@field skipped string[] untracked paths left out for size, relative to toplevel
---@field untracked integer untracked, non-ignored files seen
---@field unreadable? string git's complaint about files it could not index
---@field toplevel string
---@field gitdir string
---@field wtid string

---Snapshot the worktree that contains `root`: `cb(tree, info)`, or
---`cb(nil, err)` (a non-git directory degrades to that). Requests for one
---gitdir run one at a time and coalesce: all those waiting share the next
---snapshot. `opts.priority` puts a request first in line, so a prompt's
---baseline is not delivered behind a listing refresh. `(root, opts, cb)` is
---accepted as well.
---@param root string
---@param cb fun(tree: string|nil, info: baseline.Info|string)
---@param opts? { priority?: boolean }
function M.snapshot(root, cb, opts)
  if type(cb) == "table" then cb, opts = opts, cb end
  cb, opts = cb or noop, opts or {}
  if vim.in_fast_event() then
    return vim.schedule(function() M.snapshot(root, cb, opts) end)
  end
  local loc, err = M.locate(root)
  if not loc then return deliver(cb, nil, err) end
  local q = queues[loc.gitdir]
  if not q then
    q = { running = false, waiting = {} }
    queues[loc.gitdir] = q
  end
  local request = { cb = cb }
  if opts.priority then
    -- Behind earlier priority requests, ahead of everything else.
    local at = 1
    while q.waiting[at] and q.waiting[at].priority do at = at + 1 end
    request.priority = true
    table.insert(q.waiting, at, request)
  else
    q.waiting[#q.waiting + 1] = request
  end
  drain(loc)
end

local function one_line(value)
  return vim.trim((tostring(value):gsub("[\r\n]+", " ")))
end

-- Keys of `meta` that are trailers: they start with an uppercase letter.
-- Lowercase keys are options (subject, tree, prune, exempt).
local function trailer_keys(meta)
  local keys = {}
  for key, value in pairs(meta) do
    if type(key) == "string" and key:match("^%u[%w-]*$") and key ~= "Nvim-Review"
      and value ~= nil and value ~= false then
      keys[#keys + 1] = key
    end
  end
  table.sort(keys)
  return keys
end

local function message(kind, meta)
  local subject = meta.subject and one_line(meta.subject) or ""
  if subject == "" then subject = ("nvim review %s %s"):format(kind, os.date("%H:%M:%S")) end
  local out = { subject, "", "Nvim-Review: 1" }
  for _, key in ipairs(trailer_keys(meta)) do
    local value = meta[key] == true and "1" or one_line(meta[key])
    out[#out + 1] = ("%s: %s"):format(key, value)
  end
  return table.concat(out, "\n") .. "\n"
end

-- YYYYMMDDTHHMMSS-xxxx in UTC. The four hex digits hold the millisecond in
-- their upper ten bits and six bits of the pid below, so ids sort by creation
-- time to the millisecond and two Nvims rarely meet; a collision fails
-- `create` and is retried with the next pid bits.
local function make_id(sec, usec, attempt)
  local ms = math.floor(usec / 1000)
  local bits = (uv.os_getpid() + attempt) % 64
  return ("%s-%04x"):format(os.date("!%Y%m%dT%H%M%S", sec), ms * 64 + bits)
end

local function ref_name(loc, kind, id)
  return ("%s/%s/%s/%s"):format(M.NAMESPACE, loc.wtid, kind, id)
end

local function create_ref(loc, kind, sha, sec, usec, attempt, cb)
  local id = make_id(sec, usec, attempt)
  local ref = ref_name(loc, kind, id)
  -- `create` fails when the ref exists, so a baseline is never overwritten.
  -- No reflog: core.logAllRefUpdates=always would otherwise keep a log of
  -- every baseline next to the user's own.
  run(loc, { "-c", "core.logAllRefUpdates=false", "update-ref", "--stdin" }, {
    stdin = ("create %s %s\n"):format(ref, sha),
  }, function(r)
    if r.code == 0 then return cb(ref, id) end
    if attempt < 8 then return create_ref(loc, kind, sha, sec, usec, attempt + 1, cb) end
    cb(nil, failure("git update-ref", r))
  end)
end

---@class baseline.Entry
---@field kind "round"|"saved"
---@field id string
---@field ref string
---@field sha string the baseline commit (also as `oid`)
---@field oid string
---@field tree string
---@field time integer committer time, seconds since the epoch
---@field subject string
---@field trailers table<string, string>
---@field root string toplevel of the worktree it belongs to
---@field wtid string

---Store a baseline: snapshot the worktree (or take `meta.tree`), commit it
---without a parent under the fixed identity, and create
---refs/nvim-review/<wtid>/<kind>/<id>. Then prune that kind, unless
---`meta.prune == false`; `meta.exempt` is passed on to prune.
---
---`meta.subject` is the first line (the display text); every key starting
---with an uppercase letter becomes a trailer (`true` -> "1", false/nil
---omitted). `cb(entry, info)`, or `cb(nil, err)`.
---@param root string
---@param kind "round"|"saved"
---@param meta? table
---@param cb? fun(entry: baseline.Entry|nil, info: baseline.Info|string|nil)
function M.save(root, kind, meta, cb)
  assert(M.KINDS[kind], "util.baseline.save: kind must be round or saved")
  meta, cb = meta or {}, cb or noop
  if vim.in_fast_event() then
    return vim.schedule(function() M.save(root, kind, meta, cb) end)
  end
  local loc, err = M.locate(root)
  if not loc then return deliver(cb, nil, err) end

  local function commit(tree, info)
    if not tree then return deliver(cb, nil, info) end
    -- One clock reading names the ref and dates the commit. The dates are
    -- set explicitly so a GIT_*_DATE in Nvim's environment cannot reorder
    -- baselines.
    local sec, usec = uv.gettimeofday()
    local zone = os.date("%z", sec)
    local date = ("%d %s"):format(sec, zone:match("^[+-]%d%d%d%d$") and zone or "+0000")
    local env = vim.tbl_extend("force", IDENTITY, { GIT_AUTHOR_DATE = date, GIT_COMMITTER_DATE = date })
    local msg = message(kind, meta)
    -- --no-gpg-sign: a baseline is never signed, whatever commit.gpgSign says.
    run(loc, { "commit-tree", "--no-gpg-sign", tree, "-F", "-" }, { env = env, stdin = msg }, function(r)
      local sha = vim.trim(r.stdout or "")
      if r.code ~= 0 or not sha:match("^%x+$") then return deliver(cb, nil, failure("git commit-tree", r)) end
      create_ref(loc, kind, sha, sec, usec, 0, function(ref, id)
        if not ref then return deliver(cb, nil, id) end
        local trailers = {}
        for _, key in ipairs(trailer_keys(meta)) do
          trailers[key] = meta[key] == true and "1" or one_line(meta[key])
        end
        deliver(cb, {
          kind = kind,
          id = id,
          ref = ref,
          sha = sha,
          oid = sha,
          tree = tree,
          time = sec,
          subject = vim.split(msg, "\n", { plain = true })[1],
          trailers = trailers,
          root = loc.toplevel,
          wtid = loc.wtid,
        }, info)
        if meta.prune ~= false then M.prune(loc.toplevel, kind, { exempt = meta.exempt }) end
      end)
    end)
  end

  if meta.tree then
    commit(meta.tree, { skipped = {}, untracked = 0, toplevel = loc.toplevel, gitdir = loc.gitdir, wtid = loc.wtid })
  else
    M.snapshot(loc.toplevel, commit, { priority = kind == "round" })
  end
end

-- Parse `git cat-file --batch` output into one record per requested object,
-- in request order: { type, body } or { missing = true }.
local function parse_batch(out, count)
  local records, pos = {}, 1
  for i = 1, count do
    local eol = out:find("\n", pos, true)
    if not eol then break end
    local header = out:sub(pos, eol - 1)
    local kind, size = header:match("^%x+ (%a+) (%d+)$")
    if kind then
      size = tonumber(size)
      records[i] = { type = kind, body = out:sub(eol + 1, eol + size) }
      pos = eol + size + 2
    else
      records[i] = { missing = true }
      pos = eol + 1
    end
  end
  return records
end

local function parse_commit(body)
  local head, msg = body:match("^(.-)\n\n(.*)$")
  head, msg = head or body, msg or ""
  local tree = head:match("^tree (%x+)")
  local time = tonumber(head:match("\ncommitter [^\n]* (%d+) [+-]%d+"))
  local msg_lines = vim.split(msg, "\n", { plain = true })
  local trailers = {}
  for i = 2, #msg_lines do
    local key, value = msg_lines[i]:match("^(%u[%w-]*): (.*)$")
    if key and key ~= "Nvim-Review" then trailers[key] = vim.trim(value) end
  end
  return { tree = tree, time = time or 0, subject = msg_lines[1] or "", trailers = trailers }
end

---When `entry` was taken, to the millisecond: its `time` plus the millisecond
---its id holds (make_id), so two baselines of one second keep their order.
---`time` alone when the id is not one of ours.
---@param entry baseline.Entry
---@return number
function M.time_of(entry)
  local time = type(entry) == "table" and tonumber(entry.time) or 0
  local hex = type(entry.id) == "string" and entry.id:match("^%d%d%d%d%d%d%d%dT%d%d%d%d%d%d%-(%x%x%x%x)$")
  if not hex then return time end
  local ms = math.floor(tonumber(hex, 16) / 64)
  return ms < 1000 and time + ms / 1000 or time
end

---The baselines of `kind` ("round", "saved", or nil for both) in the worktree
---that contains `root`, newest first: `cb(entries)`, or `cb({}, err)`.
---A ref whose commit is missing (deleted by hand, or by a gc that could not
---see it) is not listed: it is removed, compare-and-swap, with one warning.
---`(root, cb)` lists both kinds.
---@param root string
---@param kind? "round"|"saved"
---@param cb fun(entries: baseline.Entry[], err?: string)
function M.list(root, kind, cb)
  if type(kind) == "function" then kind, cb = nil, kind end
  assert(kind == nil or M.KINDS[kind], "util.baseline.list: kind must be round, saved or nil")
  cb = cb or noop
  if vim.in_fast_event() then
    return vim.schedule(function() M.list(root, kind, cb) end)
  end
  local loc, err = M.locate(root)
  if not loc then return deliver(cb, {}, err) end
  local base = ("%s/%s/"):format(M.NAMESPACE, loc.wtid)
  -- Names and object ids only: for-each-ref need not read the objects, so a
  -- missing one cannot fail the listing.
  run(loc, { "for-each-ref", "--format=%(refname)%00%(objectname)", base .. (kind and kind .. "/" or "") }, {},
    function(r)
      if r.code ~= 0 then return deliver(cb, {}, failure("git for-each-ref", r)) end
      local refs = {}
      for _, line in ipairs(lines(r.stdout)) do
        local name, sha = line:match("^(.-)%z(%x+)$")
        local k, id = (name or ""):sub(#base + 1):match("^(%l+)/(.+)$")
        if name and vim.startswith(name, base) and M.KINDS[k] then
          refs[#refs + 1] = { ref = name, sha = sha, kind = k, id = id }
        end
      end
      if #refs == 0 then return deliver(cb, {}) end
      local stdin = table.concat(vim.tbl_map(function(e) return e.sha end, refs), "\n") .. "\n"
      run(loc, { "cat-file", "--batch" }, { stdin = stdin }, function(c)
        if c.code ~= 0 then return deliver(cb, {}, failure("git cat-file", c)) end
        local records = parse_batch(c.stdout or "", #refs)
        local entries, missing = {}, {}
        for i, ref in ipairs(refs) do
          local rec = records[i]
          if rec and rec.missing then
            missing[#missing + 1] = ref
          elseif rec and rec.type == "commit" then
            local parsed = parse_commit(rec.body)
            entries[#entries + 1] = {
              kind = ref.kind,
              id = ref.id,
              ref = ref.ref,
              sha = ref.sha,
              oid = ref.sha,
              tree = parsed.tree,
              time = parsed.time,
              subject = parsed.subject,
              trailers = parsed.trailers,
              root = loc.toplevel,
              wtid = loc.wtid,
            }
          end
        end
        table.sort(entries, function(a, b)
          if a.time ~= b.time then return a.time > b.time end
          return a.id > b.id
        end)
        if #missing > 0 then
          M.delete(loc.toplevel, missing)
          local ids = table.concat(vim.tbl_map(function(e) return e.kind .. "/" .. e.id end, missing), ", ")
          warn(("Removed %d baseline ref(s) in %s whose commit is missing (git gc, or deleted by hand): %s")
            :format(#missing, loc.toplevel, ids))
        end
        deliver(cb, entries)
      end)
    end)
end

---Delete baseline refs, each only if it still points where the caller saw it
---(compare-and-swap on `sha`): `entries` are list() entries, or anything with
---`ref` and `sha`. Refs outside refs/nvim-review/ are never touched. A ref
---that moved or is already gone is skipped, not an error.
---`cb(deleted, skipped)`.
---@param root string
---@param entries table|table[]
---@param cb? fun(deleted: table[], skipped: table[])
function M.delete(root, entries, cb)
  cb = cb or noop
  if entries.ref then entries = { entries } end
  if vim.in_fast_event() then
    return vim.schedule(function() M.delete(root, entries, cb) end)
  end
  local loc = M.locate(root)
  local valid, skipped = {}, {}
  for _, e in ipairs(entries) do
    local sha = e.sha or e.oid
    if type(e.ref) == "string" and vim.startswith(e.ref, M.NAMESPACE .. "/") and type(sha) == "string"
      and sha:match("^%x+$") then
      valid[#valid + 1] = { entry = e, line = ("delete %s %s\n"):format(e.ref, sha) }
    else
      skipped[#skipped + 1] = e
    end
  end
  if not loc or #valid == 0 then return deliver(cb, {}, entries) end
  local function update(items, done)
    local stdin = table.concat(vim.tbl_map(function(v) return v.line end, items))
    run(loc, { "update-ref", "--stdin" }, { stdin = stdin }, function(r) done(r.code == 0) end)
  end
  update(valid, function(ok)
    if ok then return deliver(cb, vim.tbl_map(function(v) return v.entry end, valid), skipped) end
    -- A transaction fails whole when one old value is stale (another Nvim
    -- pruned it first, or it moved). Retry one at a time so the rest go.
    local deleted, i = {}, 0
    local function step()
      i = i + 1
      local item = valid[i]
      if not item then return deliver(cb, deleted, skipped) end
      update({ item }, function(one)
        table.insert(one and deleted or skipped, item.entry)
        step()
      end)
    end
    step()
  end)
end

-- Supplied by the review layer: true keeps an entry that retention would
-- delete (a round with a non-empty feedback draft).
local exempt_hook

---Set (or clear, with nil) the retention exemption: `fn(entry) -> boolean`,
---called for each entry past the retention count. Without one, nothing is
---exempt.
---@param fn? fun(entry: baseline.Entry): boolean
function M.set_exempt(fn)
  exempt_hook = fn
end

local function is_exempt(entry, extra)
  for _, fn in pairs({ hook = exempt_hook, extra = extra }) do
    local ok, keep = pcall(fn, entry)
    if not ok then
      -- A predicate that fails cannot vouch for a deletion.
      warn("Baseline retention exemption failed: " .. tostring(keep), "exempt-error")
      return true
    end
    if keep then return true end
  end
  return false
end

---Apply retention to `kind` in the worktree that contains `root`: keep the
---newest N (ai.review.config retention.rounds / retention.saved), delete the
---rest except exempt ones (the set_exempt hook, or `opts.exempt`). Deleting a
---saved baseline names it in a notification unless `opts.quiet`.
---`cb(deleted)`, or `cb({}, err)`. Objects are left to git's own gc.
---@param root string
---@param kind "round"|"saved"
---@param opts? { exempt?: fun(entry: baseline.Entry): boolean, quiet?: boolean }
---@param cb? fun(deleted: baseline.Entry[], err?: string)
function M.prune(root, kind, opts, cb)
  assert(M.KINDS[kind], "util.baseline.prune: kind must be round or saved")
  if type(opts) == "function" then opts, cb = nil, opts end
  opts, cb = opts or {}, cb or noop
  if vim.in_fast_event() then
    return vim.schedule(function() M.prune(root, kind, opts, cb) end)
  end
  local keep = settings().retention[M.KINDS[kind]]
  M.list(root, kind, function(entries, err)
    if err then return cb({}, err) end
    local doomed = {}
    for i = keep + 1, #entries do
      if not is_exempt(entries[i], opts.exempt) then doomed[#doomed + 1] = entries[i] end
    end
    if #doomed == 0 then return cb({}) end
    M.delete(root, doomed, function(deleted)
      if kind == "saved" and #deleted > 0 and not opts.quiet then
        local names = vim.tbl_map(function(e) return ("%q"):format(e.subject) end, deleted)
        vim.notify(("Removed %d old saved baseline(s), keeping the newest %d: %s")
          :format(#deleted, keep, table.concat(names, ", ")), vim.log.levels.INFO, { title = "Baselines" })
      end
      cb(deleted)
    end)
  end)
end

return M
