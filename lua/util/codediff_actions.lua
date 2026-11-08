-- Hunk actions inside a CodeDiff view (,u ,U ,X), installed on every
-- `User CodeDiffKeys` pass through util.codediff.set_keys. CodeDiff is reached
-- only through util.codediff, gitsigns only through its public API.
--
-- What each key changes:
--
--   ,u / ,U  The real index, through gitsigns. gitsigns stages a line range of
--            the right pane against the index (unstages it against HEAD),
--            while a view whose left end is a baseline or a branch shows the
--            left side against the working tree. Where the two differ next
--            to the range -- an edit from before the round beside the agent's
--            hunk, a line staged inside it -- gitsigns' partial hunk carries
--            those lines along, so plan() works its stage out first and
--            refuses unless it replaces exactly the left side's lines, and
--            the callback checks the index it left. The status view diffs
--            against the index itself (<leader>gv), which the refusal points
--            to. CodeDiff's own hunk staging builds its patch against the left
--            side instead, and in a rev-vs-working-tree view it put lines at
--            the wrong place in the index without a word; its keys stay off
--            (lua/plugin/vcs/codediff.lua).
--   ,U       In the status view's Staged group (left HEAD, right the index):
--            CodeDiff's own unstage, through util.codediff, which is right
--            there and only there.
--   ,X       One hunk of the working-tree file, back to the baseline on the
--            left, in a baseline-vs-working-tree view only (vim.t.
--            codediff_baseline). Hunks only, by design: an added or deleted
--            file gets the command to run instead. The index is untouched,
--            only that buffer is written, and `u` then `:w` undoes it.
--
-- Which view gets which key (specs()):
--
--   status, Changes group (index vs working tree)   ,u -- no ,U: every hunk
--                                                    shown there is unstaged
--   status, Staged group (HEAD vs index)            ,U (CodeDiff's)
--   baseline vs working tree                        ,u ,U ,X
--   the same, a file on one side only               ,X, which only says what
--                                                    would do it
--   any other rev vs working tree                   ,u ,U
--
-- Before any of them acts, guard_fresh checks that it acts on what is on
-- screen: (a) no unsaved edits in the right pane, (b) the disk still holds
-- the buffer's bytes (and an index side still holds its text), (c) the hunk
-- recomputes to the ranges displayed, (d) the path is a regular file on both
-- ends, not conflicted, and without a filter attribute (Git LFS and the like).
-- ,X looks at the disk once more right before it writes; a stage that runs
-- later (gitsigns attaching first, its retry) refuses once the buffer has
-- changed at all. A refusal says why and leaves everything as it was.
local M = {}

local api = vim.api

local TITLE = "CodeDiff"
local LL = "<localleader>"

-- Modes of a plain file in a tree or the index; anything else is a symlink
-- (120000), a submodule (160000) or a directory.
local REGULAR = { ["100644"] = true, ["100755"] = true }
local KIND_OF_MODE = { ["120000"] = "a symlink", ["160000"] = "a submodule", ["040000"] = "a directory" }

local NEWLINE = { unix = "\n", dos = "\r\n", mac = "\r" }
-- The buffer options that decide the bytes :write puts on disk; ,X must
-- leave them as the file was read.
local WRITE_OPTIONS = { "endofline", "bomb", "fileformat", "fileencoding" }
-- The byte order mark :write puts first when 'bomb' is set.
local BOM = {
  ["utf-8"] = "\239\187\191",
  ["ucs-2"] = "\254\255", ["utf-16"] = "\254\255",
  ["ucs-2le"] = "\255\254", ["utf-16le"] = "\255\254",
  ["ucs-4"] = "\0\0\254\255", ["ucs-4le"] = "\255\254\0\0",
}

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = TITLE })
end

local function refuse(what, why)
  notify(what .. ": " .. why, vim.log.levels.WARN)
end

local function codediff() return require("util.codediff") end

local function valid_buf(buf)
  return type(buf) == "number" and api.nvim_buf_is_valid(buf)
end

local function valid_win(win)
  return type(win) == "number" and api.nvim_win_is_valid(win)
end

local function span(top, bot)
  return top == bot and ("line %d"):format(top) or ("lines %d-%d"):format(top, bot)
end

---------------------------------------------------------------------------
-- git, read-only
---------------------------------------------------------------------------

--- Run a read-only git command in `root`, synchronously: these run on a key
--- press, and the answer decides whether anything happens. The prefix is
--- util.baseline's (no optional locks, no user hooks); paths are literal.
---@return string? stdout, string? err, integer code
local function git(root, args)
  local cmd = require("util.baseline").git_cmd(vim.list_extend({ "--literal-pathspecs" }, args))
  -- text: the same CRLF handling as CodeDiff's own runner, so a revision's
  -- lines compare equal to the buffer CodeDiff made from them.
  local ok, proc = pcall(vim.system, cmd, { cwd = root, text = true, env = { GIT_NO_LAZY_FETCH = "1" } })
  if not ok then return nil, tostring(proc), -1 end
  local r = proc:wait(10000)
  if r.code ~= 0 then
    local err = vim.trim(r.stderr or "")
    return nil, err ~= "" and err or ("git exited with " .. tostring(r.code)), r.code
  end
  return r.stdout or "", nil, 0
end

local function fields(out)
  return vim.split(out, "\0", { plain = true, trimempty = true })
end

--- The index entries for `path`: more than one, or a stage above 0, is a
--- conflict.
---@return { mode: string, oid: string, stage: integer }[]? entries, string? err
local function index_entries(root, path)
  local out, err = git(root, { "ls-files", "-s", "-z", "--", path })
  if not out then return nil, err end
  local entries = {}
  for _, record in ipairs(fields(out)) do
    local mode, oid, stage, name = record:match("^(%d+) (%x+) (%d)\t(.*)$")
    if name == path then entries[#entries + 1] = { mode = mode, oid = oid, stage = tonumber(stage) } end
  end
  return entries
end

--- The index blob of `path`, or "" when it has none (a conflict, untracked).
local function index_oid(root, path)
  local entries = index_entries(root, path) or {}
  return #entries == 1 and entries[1].oid or ""
end

--- The mode of `path` in the tree of `rev`: false when it has no such entry.
---@return string|false|nil mode, string? err
local function tree_mode(root, rev, path)
  local out, err = git(root, { "ls-tree", "-z", rev, "--", path })
  if not out then return nil, err end
  for _, record in ipairs(fields(out)) do
    local mode, name = record:match("^(%d+) %a+ %x+\t(.*)$")
    if name == path then return mode end
  end
  return false
end

--- The `filter` attribute of `path`: "unspecified", "unset", or a driver.
local function filter_of(root, path)
  local out, err = git(root, { "check-attr", "-z", "filter", "--", path })
  if not out then return nil, err end
  -- <path> NUL filter NUL <value> NUL
  local f = vim.split(out, "\0", { plain = true })
  return f[3] or "unspecified"
end

--- The lines of `rev:path` exactly as CodeDiff fills a revision buffer.
local function revision_lines(root, rev, path)
  local out = git(root, { "show", rev .. ":" .. path })
  if not out then return nil end
  local lines = vim.split(out, "\n", { plain = true })
  if lines[#lines] == "" then table.remove(lines) end
  return #lines > 0 and lines or { "" }
end

local times = {} ---@type table<string, integer|false>

--- When a baseline was taken, for a key's description.
local function baseline_label(root, baseline)
  local t = type(baseline.time) == "number" and baseline.time or nil
  if not t then
    if times[baseline.sha] == nil then
      local out = git(root, { "show", "-s", "--format=%ct", baseline.sha })
      times[baseline.sha] = tonumber(vim.trim(out or "")) or false
    end
    t = times[baseline.sha] or nil
  end
  if not t then return baseline.sha:sub(1, 8) end
  return os.date(os.date("%Y%m%d", t) == os.date("%Y%m%d") and "%H:%M:%S" or "%Y-%m-%d %H:%M", t)
end

---------------------------------------------------------------------------
-- Which view this is (the matrix of keys per view)
---------------------------------------------------------------------------

local function real_file(buf)
  if not valid_buf(buf) or vim.bo[buf].buftype ~= "" then return false end
  local name = api.nvim_buf_get_name(buf)
  return name ~= "" and not name:match("^%w+://")
end

--- The baseline this tab compares against, if the tab says it is a baseline
--- view and its left end really is that baseline.
local function baseline_of(tab, s)
  local b = vim.t[tab].codediff_baseline
  if type(b) ~= "table" then return nil end
  local sha = b.sha or b[1]
  local left = s.base_revision
  if type(sha) ~= "string" or not sha:match("^%x+$") or type(left) ~= "string" then return nil end
  if left:sub(1, #sha) ~= sha and sha:sub(1, #left) ~= left then return nil end
  return { sha = sha, kind = b.kind, time = b.time }
end

---@class codediff_actions.View
---@field kind "changes"|"staged"|"revision"|"one-sided"
---@field stage? boolean ,u through gitsigns, and ,U except in the Changes group
---@field baseline? { sha: string, kind?: string, time?: integer }
---@field side? "original"|"modified" the pane a one-sided view keeps

--- What the view in `tab` shows, as far as these keys care; nil where none
--- of them applies (rev vs rev, --staged, history, conflicts, a single file,
--- the welcome page, a one-sided file outside a baseline view).
---@return codediff_actions.View?
local function classify(tab, s)
  if not s or s.conflict or not s.git_root or type(s.original) ~= "table" or type(s.modified) ~= "table" then
    return nil
  end
  local both = s.single_side == nil and s.original.relative ~= "" and s.modified.relative ~= ""
    and valid_buf(s.original_bufnr) and valid_buf(s.modified_bufnr)
  if s.mode == "status" then
    if not both then return nil end
    if s.modified_revision == nil and real_file(s.modified_bufnr) then return { kind = "changes", stage = true } end
    if s.modified_revision == ":0" then return { kind = "staged" } end
    return nil
  end
  if s.mode ~= "revision" or s.modified_revision ~= nil then return nil end
  local baseline = baseline_of(tab, s)
  if both then
    if not real_file(s.modified_bufnr) then return nil end
    return { kind = "revision", stage = true, baseline = baseline }
  end
  local side = s.single_side
  if baseline and (side == "original" or side == "modified") and s[side].relative ~= "" then
    return { kind = "one-sided", side = side, baseline = baseline }
  end
  return nil
end

---------------------------------------------------------------------------
-- guard_fresh
---------------------------------------------------------------------------

--- The bytes :write would put on disk for `buf` as it stands, nil when they
--- cannot be worked out here. 'fileformat', 'eol', 'bomb' and
--- 'fileencoding' are what read the file; 'fixeol' only matters to a write.
local function buffer_bytes(buf)
  if api.nvim_buf_call(buf, function() return vim.fn.line2byte(1) end) == -1 then
    return "" -- an empty buffer is written as an empty file
  end
  local bo = vim.bo[buf]
  local nl = bo.binary and "\n" or NEWLINE[bo.fileformat] or "\n"
  local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
  for i, line in ipairs(lines) do lines[i] = (line:gsub("\n", "\0")) end -- NUL is stored as NL
  local text = table.concat(lines, nl) .. (bo.eol and nl or "")
  local enc = (bo.fileencoding ~= "" and bo.fileencoding or vim.o.encoding):lower()
  if enc ~= "utf-8" and enc ~= "utf8" then
    text = vim.iconv(text, "utf-8", enc)
    if not text then return nil end
  end
  if bo.bomb and not bo.binary then
    if not BOM[enc] then return nil end
    text = BOM[enc] .. text
  end
  return text
end

local function disk_bytes(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  return data
end

--- `path` as it is now, for (b) to compare with later: the stat first, so a
--- write landing between the two shows up in the bytes.
local function disk_state(path)
  local st = vim.uv.fs_stat(path)
  return { stat = st, bytes = disk_bytes(path) }
end

--- Whether `path` is still exactly what disk_state saw: same bytes, and the
--- same inode, size and mtime (to the nanosecond), so a write that put the
--- same bytes back in between is not taken for no write at all.
local function unmoved(path, seen)
  local was, now = seen and seen.stat, disk_state(path)
  local st = now.stat
  return was ~= nil and st ~= nil and st.dev == was.dev and st.ino == was.ino and st.size == was.size
    and st.mtime.sec == was.mtime.sec and st.mtime.nsec == was.mtime.nsec
    and now.bytes ~= nil and now.bytes == seen.bytes
end

local function describe_mode(mode)
  return KIND_OF_MODE[mode] or ("mode " .. tostring(mode))
end

--- (d): both ends are regular files, the index entry (when it matters) is a
--- regular, unconflicted file, and no filter rewrites the path's bytes.
local function check_paths(ctx)
  local s, root = ctx.s, ctx.s.git_root
  local left, right = s.original.relative, s.modified.relative
  if ctx.right_is_file then
    local st = vim.uv.fs_lstat(api.nvim_buf_get_name(s.modified_bufnr))
    if not st then return nil, right .. " is gone from the working tree" end
    if st.type == "link" then return nil, right .. " is a symlink in the working tree" end
    if st.type ~= "file" then return nil, right .. " is not a regular file in the working tree" end
  end
  local rev = s.original_revision
  local mode, err
  if type(rev) == "string" and rev:match("^:%d$") then
    local entries
    entries, err = index_entries(root, left)
    mode = entries and #entries == 1 and entries[1].stage == 0 and entries[1].mode or false
  elseif type(rev) == "string" then
    mode, err = tree_mode(root, rev, left)
  end
  if mode == nil then return nil, ("cannot read %s on the left: %s"):format(left, err or "no revision") end
  if not REGULAR[mode] then
    if mode == false then return nil, left .. " is not a single entry on the left" end
    return nil, ("%s is %s on the left, a file here: a type change"):format(left, describe_mode(mode))
  end
  if ctx.index then
    local entries
    entries, err = index_entries(root, right)
    if not entries then return nil, ("cannot read the index: %s"):format(err) end
    if #entries == 0 then
      return nil, right .. " is not in the index; stage the whole file (git add, or - in <leader>gv)"
    end
    if #entries > 1 or entries[1].stage ~= 0 then return nil, right .. " is conflicted in the index" end
    if not REGULAR[entries[1].mode] then
      return nil, ("%s is %s in the index"):format(right, describe_mode(entries[1].mode))
    end
  end
  local filter
  filter, err = filter_of(root, right)
  if not filter then return nil, ("cannot read the attributes of %s: %s"):format(right, err) end
  if filter ~= "unspecified" and filter ~= "unset" then
    return nil, ("%s has a filter attribute (filter=%s, e.g. Git LFS)"):format(right, filter)
  end
  return true
end

--- The displayed hunks a selection [top, bot] of the right pane touches, each
--- checked against a fresh diff. util.codediff answers for a window's cursor,
--- so the cursor walks the range and goes back where it was. A deletion
--- drawn just above `top` is outside the selection.
local function hunks_in(tab, win, top, bot)
  local cd = codediff()
  local view = api.nvim_win_call(win, vim.fn.winsaveview)
  local found, seen, stale = {}, {}, nil
  local ok, err = pcall(function()
    local line = top
    while line <= bot do
      api.nvim_win_set_cursor(win, { line, 0 })
      local h = cd.hunk_at_cursor(tab, win)
      local m = h and h.modified
      if h and not seen[h.index] and not (m.start_line == m.end_line and m.start_line == top) then
        seen[h.index] = true
        found[#found + 1] = h
        local fresh, why = cd.fresh_hunk(tab, win)
        if not fresh then stale = stale or why or "the hunk changed since it was displayed" end
      end
      line = (m and m.end_line > line) and m.end_line or line + 1
    end
  end)
  api.nvim_win_call(win, function() vim.fn.winrestview(view) end)
  if not ok then return nil, tostring(err) end
  if stale then return nil, stale end
  if #found == 0 then return nil, "the selection holds no change this view shows" end
  return found
end

--- After a refusal past (a): have Nvim look at the file again (deferred, as
--- :checktime from a mapping is), and the view recompute itself: a hunk can
--- be stale while buffer and disk agree, and no reload would follow then.
local function catch_up(ctx)
  if ctx.right_is_file then pcall(vim.cmd.checktime, ctx.s.modified_bufnr) end
  codediff().refresh(ctx.tab)
end

local function changed_on_disk(path)
  return path .. " changed on disk since it was displayed; try again once the view has caught up"
end

--- Everything an action checks before it changes anything. Returns the
--- hunks to act on (one, or those a Visual selection touches), or nil and
--- why not. For a right pane that is a file, ctx.seen is the disk as (b)
--- found it, for a last look right before a write (unmoved).
---@param ctx { tab: integer, s: table, win: integer, range?: integer[], right_is_file: boolean, index?: boolean, seen?: table }
---@return table[]? hunks, string? why
local function guard_fresh(ctx)
  local s, cd = ctx.s, codediff()
  local right = s.modified_bufnr
  if ctx.right_is_file and vim.bo[right].modified then
    -- (a) unsaved edits would be written along with the hunk, or be what
    -- the hunk is measured against.
    return nil, s.modified.relative .. " has unsaved changes: :w or :e! first"
  end
  local function refused(why)
    catch_up(ctx)
    return nil, why
  end
  if ctx.right_is_file then
    -- (b) an agent may have written the file since the view drew it.
    local want = buffer_bytes(right)
    if not want then
      return nil, ("cannot compare %s with the disk (fileencoding %s)"):format(s.modified.relative, vim.bo[right].fileencoding)
    end
    ctx.seen = disk_state(api.nvim_buf_get_name(right))
    if ctx.seen.bytes ~= want then return refused(changed_on_disk(s.modified.relative)) end
  end
  -- (b) for the index: a side that shows it must still show what it holds.
  for _, side in ipairs({ "original", "modified" }) do
    local rev, path = s[side .. "_revision"], s[side].relative
    if type(rev) == "string" and rev:match("^:%d$") and path ~= "" then
      local lines = revision_lines(s.git_root, rev, path)
      if not lines or not vim.deep_equal(lines, api.nvim_buf_get_lines(s[side .. "_bufnr"], 0, -1, false)) then
        return refused(("the index entry of %s changed since it was displayed; try again once the view has caught up"):format(path))
      end
    end
  end
  -- (c) the hunk under the cursor (or each one the selection touches) is
  -- still what a fresh diff of the two buffers says.
  local hunks, why
  if ctx.range then
    hunks, why = hunks_in(ctx.tab, ctx.win, ctx.range[1], ctx.range[2])
  else
    local h
    h, why = cd.fresh_hunk(ctx.tab, ctx.win)
    hunks = h and { h } or nil
  end
  if not hunks then return refused(why) end
  -- (d)
  local ok
  ok, why = check_paths(ctx)
  if not ok then return refused(why) end
  return hunks
end

---------------------------------------------------------------------------
-- ,u / ,U through gitsigns
---------------------------------------------------------------------------

--- Whether gitsigns would count hunk `h` as inside [top, bot]: the same four
--- cases as its create_partial_hunk, so "no unstaged hunk touches the range"
--- here means gitsigns' stage_hunk takes its unstage branch there.
local function touches(h, top, bot)
  local start = h.added.start
  local vend = start + math.max(h.added.count - 1, 0)
  return (math.max(start, 1) >= top and vend <= bot)
    or (start >= top and start <= bot)
    or (vend >= top and vend <= bot)
    or (start <= top and vend >= bot)
end

--- gitsigns' unstaged hunks for `buf`, once it has diffed the buffer at all.
--- It reports none both before its first diff and while it redoes one; its
--- status counts appear with the first diff and tell those apart. A buffer
--- that was off screen when gitsigns got to it waits for a BufEnter that a
--- pane filled by CodeDiff may never get, so that one is asked for.
local function unstaged_hunks(buf)
  local gs = require("gitsigns")
  local function counted()
    local st = vim.b[buf].gitsigns_status_dict
    if type(st) ~= "table" or st.added == nil then return nil end
    return (st.added or 0) + (st.changed or 0) + (st.removed or 0)
  end
  local hunks = gs.get_hunks(buf)
  if hunks and #hunks == 0 and counted() ~= 0 then
    if counted() == nil then gs.refresh() end
    vim.wait(2000, function()
      hunks = gs.get_hunks(buf)
      return hunks == nil or #hunks > 0 or counted() == 0
    end, 20)
  end
  return hunks
end

local WHITESPACE = {
  iwhite = "ignore_whitespace_change",
  iwhiteall = "ignore_whitespace",
  iwhiteeol = "ignore_whitespace_change_at_eol",
  iblank = "ignore_blank_lines",
}

--- The diff options gitsigns derives from 'diffopt' (its default diff_opts).
--- `greedy`: without linematch, as gitsigns diffs for a stage of a range.
local function diff_options(greedy)
  local opts = { result_type = "indices" }
  for _, item in ipairs(vim.opt.diffopt:get()) do
    local algorithm, linematch = item:match("^algorithm:(%a+)$"), item:match("^linematch:(%d+)$")
    if algorithm then opts.algorithm = algorithm end
    if linematch and not greedy then opts.linematch = tonumber(linematch) end
    if item == "indent-heuristic" then opts.indent_heuristic = true end
    if WHITESPACE[item] then opts[WHITESPACE[item]] = true end
  end
  return opts
end

local function has_linematch()
  for _, item in ipairs(vim.opt.diffopt:get()) do
    if item:match("^linematch:%d+$") then return true end
  end
  return false
end

--- `old` against `new` the way gitsigns diffs them (lines joined without a
--- final newline), as { old start, old count, new start, new count } each.
---@return integer[][]?
local function diff_hunks(old, new, greedy)
  local diff = vim.text and vim.text.diff or vim.diff
  local ok, result = pcall(diff, table.concat(old, "\n"), table.concat(new, "\n"), diff_options(greedy))
  return ok and type(result) == "table" and result or nil
end

--- Whether lines [top, bot] of `buf` differ from the `index` lines, judged
--- from the index itself rather than from gitsigns' copy of it. nil: the
--- diff failed.
local function index_touched(index, buf, top, bot)
  local hunks = diff_hunks(index, api.nvim_buf_get_lines(buf, 0, -1, false), false)
  if not hunks then return nil end
  for _, d in ipairs(hunks) do
    if touches({ added = { start = d[3], count = d[4] } }, top, bot) then return true end
  end
  return false
end

--- gitsigns' create_partial_hunk, on diff_hunks output: staging new lines
--- [top, bot] replaces old lines [first, first + count) with them (count 0:
--- they go in before old line `first`). nil when no hunk touches the range.
---@return integer? first, integer? count
local function partial(hunks, top, bot)
  local pretop, precount, unused = top, bot - top + 1, 0
  for _, d in ipairs(hunks) do
    local removed, start, added = d[2], d[3], d[4]
    local vend = start + math.max(added - 1, 0)
    local net, in_range = added - removed, 0
    -- A deletion at the very top starts at line 0; gitsigns puts it on 1.
    if math.max(start, 1) >= top and vend <= bot then
      in_range = net
    else
      local above_bot = math.max(0, bot + 1 - (start + removed))
      local above_top = math.max(0, top - (start + removed))
      if start >= top and start <= bot then
        in_range = above_bot
      elseif vend >= top and vend <= bot then
        in_range = net - above_top
        pretop = pretop - above_top
      elseif start <= top and vend >= bot then
        in_range = above_bot - above_top
        pretop = pretop - above_top
      else
        unused = unused + 1
      end
      if top > vend then pretop = pretop - net end
    end
    precount = precount - in_range
  end
  if unused == #hunks or precount < 0 then return nil end
  return pretop, precount
end

local function slice(lines, first, count) return vim.list_slice(lines, first, first + count - 1) end

--- `lines` with [first, first + count) replaced by `with`, as revision_lines
--- would read the result back.
local function splice(lines, first, count, with)
  local out = vim.list_slice(lines, 1, first - 1)
  vim.list_extend(out, with)
  vim.list_extend(out, vim.list_slice(lines, first + count))
  return #out > 0 and out or { "" }
end

--- HEAD's copy of `path`: {} when HEAD has no such file, or no HEAD exists
--- yet (an unborn branch), which is what gitsigns unstages against then.
local function head_lines(root, path)
  local mode, err = tree_mode(root, "HEAD", path)
  if mode == false then return {} end
  if mode == nil then
    if select(3, git(root, { "rev-parse", "--verify", "-q", "HEAD" })) == 1 then return {} end
    return nil, err
  end
  if not REGULAR[mode] then return nil, ("%s is %s in HEAD"):format(path, describe_mode(mode)) end
  return revision_lines(root, "HEAD", path)
end

--- What gitsigns' stage_hunk({ top, bot }) does to the index, worked out the
--- way it does it: create_partial_hunk on a greedy diff of the index (of HEAD
--- to unstage, its toggle) against the buffer. That is the change on screen
--- only when the lines it replaces are the left side's own, line for line:
--- with an edit from before the round next to the agent's hunk (the
--- baseline has it, the index not), the partial hunk takes the index's line
--- along -- the line above a deletion is part of the range -- and the stage
--- changes more than the view shows. In the status view the left side is
--- the index, so the two always agree there.
---@param p { root: string, path: string, buf: integer, left: integer, index: string[] }
---@return string[]? index the stage should leave, string? why
local function plan(p, top, bot, unstage)
  if not valid_buf(p.left) then return nil, "the view moved on" end
  local lines, left_lines = api.nvim_buf_get_lines(p.buf, 0, -1, false), api.nvim_buf_get_lines(p.left, 0, -1, false)
  local where = ("%s of %s"):format(span(top, bot), p.path)
  local left, index = diff_hunks(left_lines, lines, true), diff_hunks(p.index, lines, true)
  if not left or not index then return nil, "cannot diff " .. p.path end
  -- What the same stage would replace on the left side: the change shown.
  local lfirst, lcount = partial(left, top, bot)
  local shown = lfirst and slice(left_lines, lfirst, lcount)
  local added = slice(lines, top, bot - top + 1)
  if not unstage then
    local first, count = partial(index, top, bot)
    if not first then return nil, ("nothing in %s differs from the index"):format(where) end
    if not vim.deep_equal(slice(p.index, first, count), shown) then
      return nil, ("the index differs from the left side around %s, so staging it would take more than this view shows; stage it in <leader>gv, which compares with the index"):format(where)
    end
    return splice(p.index, first, count, added)
  end
  local head, why = head_lines(p.root, p.path)
  if not head then return nil, ("cannot read HEAD's copy of %s: %s"):format(p.path, why or "unknown error") end
  local staged = diff_hunks(head, lines, true)
  if not staged then return nil, "cannot diff " .. p.path end
  if not has_linematch() then
    -- Without linematch gitsigns uses its staged hunks as they are, which
    -- leave out every hunk the index-vs-buffer diff has at the same lines.
    staged = vim.tbl_filter(function(d)
      for _, u in ipairs(index) do
        if u[3] == d[3] and u[4] == d[4] then return false end
      end
      return true
    end, staged)
  end
  local first, count = partial(staged, top, bot)
  if not first then return nil, ("nothing in %s is staged"):format(where) end
  if not vim.deep_equal(slice(head, first, count), shown) then
    return nil, ("HEAD differs from the left side around %s, so unstaging it would take more than this view shows; unstage it in <leader>gv, which shows what is staged"):format(where)
  end
  -- The index lines the range stands for: the buffer's own, since no
  -- unstaged change touches it (stage() made sure), at the place gitsigns
  -- maps them to.
  local itop, ibot = top, bot
  for _, d in ipairs(index) do
    local vend = d[3] + math.max(d[4] - 1, 0)
    if top > vend then itop = itop - (d[4] - d[2]) end
    if bot > vend then ibot = ibot - (d[4] - d[2]) end
  end
  if not vim.deep_equal(slice(p.index, itop, ibot - itop + 1), added) then
    return nil, ("%s still has unstaged changes: stage or discard them first"):format(where)
  end
  return splice(p.index, itop, ibot - itop + 1, slice(head, first, count))
end

local in_flight = {} ---@type table<integer, table> buffer -> the stage running on it

--- The pane the action is pressed in, or nil and why not.
local function pane(s, visual)
  local win = api.nvim_get_current_win()
  if visual and win ~= s.modified_win then
    return nil, "select the lines in the right pane (the working tree)"
  end
  if win ~= s.original_win and win ~= s.modified_win then return nil, "put the cursor in a diff pane" end
  return win
end

---@param tab integer
---@param unstage boolean
---@param range? integer[] a Visual selection of the right pane
local function stage(tab, unstage, range)
  local what = unstage and "Unstage" or "Stage"
  local s = codediff().session(tab)
  local view = classify(tab, s)
  if not view or not view.stage then return refuse(what, "this view has no hunk to stage here") end
  local win, why = pane(s, range ~= nil)
  if not win then return refuse(what, why) end
  local root, path, buf, mwin = s.git_root, s.modified.relative, s.modified_bufnr, s.modified_win
  -- One at a time per file, and not until gitsigns has settled: its gitdir
  -- watcher reacts to the index write 200 ms (debounced) after a stage's
  -- callback, and drops the buffer's hunks without taking the lock a stage
  -- holds. A stage that started in that window waited out gitsigns' hunk
  -- wait and did nothing (measured: 0 ms apart failed, 300 ms always
  -- worked); our pre-checks would also read hunks the last stage changed.
  if in_flight[buf] then return refuse(what, "the previous stage of " .. path .. " is still running") end
  local hunks
  hunks, why = guard_fresh({ tab = tab, s = s, win = win, range = range, right_is_file = true, index = true })
  if not hunks then return refuse(what, why) end
  -- [top, bot] below are lines of the buffer as guard_fresh just saw it.
  -- The stage may run later -- after gitsigns attaches, after the wait in
  -- unstaged_hunks, on the retry -- and an autoread reload in between
  -- (CodeDiff's refresh and the CursorHold :checktime both run one) leaves
  -- buffer and disk agreeing on lines nobody looked at. A reload moves the
  -- changedtick, which is what each attempt compares.
  local tick, name, lbuf = api.nvim_buf_get_changedtick(buf), api.nvim_buf_get_name(buf), s.original_bufnr
  local function moved()
    if not (valid_buf(buf) and valid_win(mwin) and api.nvim_win_get_buf(mwin) == buf) then
      return "the view moved on"
    end
    if api.nvim_buf_get_changedtick(buf) ~= tick or vim.bo[buf].modified then
      return path .. " changed while staging; nothing was staged"
    end
  end

  -- The right pane's lines. A deletion has no lines there: gitsigns keeps it
  -- on the line above (on line 1 for one at the top).
  local top, bot
  if range then
    top, bot = range[1], range[2]
  else
    local m = hunks[1].modified
    if m.start_line == m.end_line then
      top = math.max(m.start_line - 1, 1)
      bot = top
    else
      top, bot = m.start_line, m.end_line - 1
    end
  end

  local token = {}
  in_flight[buf] = token
  local function release()
    if in_flight[buf] == token then in_flight[buf] = nil end
  end
  local function finish(settled)
    if settled then return vim.defer_fn(release, 500) end
    release()
  end
  vim.defer_fn(release, 10000) -- a callback that never comes must not lock the file

  local gs = require("gitsigns")
  local run
  ---@param attempt integer
  run = function(attempt)
    local why_not = moved()
    if not why_not and disk_bytes(name) ~= buffer_bytes(buf) then
      why_not = path .. " changed on disk while staging; nothing was staged"
    end
    if why_not then
      finish()
      return refuse(what, why_not)
    end
    local hunks_now = unstaged_hunks(buf)
    local touched = false
    for _, h in ipairs(hunks_now or {}) do touched = touched or touches(h, top, bot) end
    local cached = unstage and select(3, git(root, { "diff", "--cached", "--quiet", "--", path }))
    -- gitsigns' stage_hunk is a toggle: with no unstaged change in the range
    -- it unstages instead. Each key does only what it says, and only when
    -- gitsigns' hunks agree with the index as it is now: a gitsigns that has
    -- not caught up with an outside `git add` would decide the toggle on
    -- the old index.
    local index = hunks_now and revision_lines(root, ":0", path)
    local actual = index and index_touched(index, buf, top, bot)
    if not hunks_now then
      why_not = "gitsigns does not track " .. path
    elseif not index then
      why_not = "cannot read the index entry of " .. path
    elseif actual == nil then
      why_not = "cannot diff " .. path .. " against the index"
    elseif actual ~= touched then
      why_not = "gitsigns has not caught up with " .. path .. " yet; try again in a moment"
    elseif not unstage and not touched then
      why_not = ("nothing in %s of %s differs from the index"):format(span(top, bot), path)
    elseif unstage and touched then
      why_not = ("%s of %s still has unstaged changes: stage or discard them first"):format(span(top, bot), path)
    elseif unstage and cached == 0 then
      why_not = path .. " has nothing staged"
    end
    local after, before
    if not why_not then
      after, why_not = plan({ root = root, path = path, buf = buf, left = lbuf, index = index }, top, bot, unstage)
      before = index_oid(root, path)
    end
    -- The last look: unstaged_hunks' wait ran the event loop, and nothing
    -- from here to stage_hunk does.
    why_not = why_not or moved()
    if why_not then
      finish()
      return refuse(what, why_not)
    end
    local ok, err = pcall(api.nvim_win_call, mwin, function()
      gs.stage_hunk({ top, bot }, nil, function(stage_err)
        vim.schedule(function()
          if stage_err then
            finish(true)
            return notify(("%s %s of %s failed: %s"):format(what, span(top, bot), path, stage_err), vim.log.levels.ERROR)
          end
          if index_oid(root, path) == before then
            -- The first time gitsigns' gitdir watcher fires after it attached
            -- a buffer it drops its copy of the index, without the lock a
            -- stage holds, and a stage caught in that does nothing at all
            -- (the index is unchanged, so trying again is safe). Once more,
            -- after the watcher's 200 ms debounce.
            if attempt == 1 then return vim.defer_fn(function() run(2) end, 400) end
            finish(true)
            return refuse(what, ("the index did not change for %s of %s"):format(span(top, bot), path))
          end
          finish(true)
          -- gitsigns reads the lines and its copy of the index after taking
          -- its lock, past our last look: say so if that was not the plan.
          if not vim.deep_equal(revision_lines(root, ":0", path), after) then
            return notify(("%s %s of %s: the index did not come out as planned (it or the file changed meanwhile); check it in <leader>gv"):format(
              what, span(top, bot), path), vim.log.levels.WARN)
          end
          notify(("%sd %s of %s (the index only)"):format(what, span(top, bot), path))
        end)
      end)
    end)
    if not ok then
      finish()
      notify(("%s %s of %s failed: %s"):format(what, span(top, bot), path, tostring(err)), vim.log.levels.ERROR)
    end
  end
  if gs.get_hunks(buf) == nil then
    gs.attach({ bufnr = buf }, function() vim.schedule(function() run(1) end) end)
  else
    run(1)
  end
end

--- ,U in the Staged group: CodeDiff unstages the hunk under the cursor.
local function unstage_staged(tab)
  local what = "Unstage"
  local s = codediff().session(tab)
  local view = classify(tab, s)
  if not view or view.kind ~= "staged" then return refuse(what, "this view has no staged hunk here") end
  local win, why = pane(s, false)
  if not win then return refuse(what, why) end
  local hunks
  hunks, why = guard_fresh({ tab = tab, s = s, win = win, right_is_file = false, index = true })
  if not hunks then return refuse(what, why) end
  if not codediff().unstage_hunk(tab) then refuse(what, "CodeDiff's unstage is not available") end
end

---------------------------------------------------------------------------
-- ,X back to the baseline
---------------------------------------------------------------------------

local function inside(h, top, bot)
  local m = h.modified
  if m.start_line == m.end_line then return m.start_line > top and m.start_line <= bot end
  return m.start_line >= top and m.end_line - 1 <= bot
end

---@param tab integer
---@param range? integer[] a Visual selection of the right pane
local function discard(tab, range)
  local what = "Discard"
  local s = codediff().session(tab)
  local view = classify(tab, s)
  if not view or view.kind ~= "revision" or not view.baseline then
    return refuse(what, "only a baseline-vs-working-tree view discards hunks")
  end
  local win, why = pane(s, range ~= nil)
  if not win then return refuse(what, why) end
  -- gitsigns reads the lines it stages after its lock, so a discard in
  -- between would change what it stages.
  if in_flight[s.modified_bufnr] then
    return refuse(what, "a stage of " .. s.modified.relative .. " is still running")
  end
  local ctx = { tab = tab, s = s, win = win, range = range, right_is_file = true }
  local hunks
  hunks, why = guard_fresh(ctx)
  if not hunks then return refuse(what, why) end
  if range then
    for _, h in ipairs(hunks) do
      if not inside(h, range[1], range[2]) then
        local m = h.modified
        return refuse(what, ("the hunk at %s is only partly selected: ,X discards whole hunks"):format(
          span(m.start_line, math.max(m.start_line, m.end_line - 1))))
      end
    end
  end
  local buf, orig, path = s.modified_bufnr, s.original_bufnr, s.modified.relative
  if not vim.bo[buf].modifiable or vim.bo[buf].readonly then return refuse(what, path .. " is read-only") end
  local name = api.nvim_buf_get_name(buf)
  local kept = {}
  for _, option in ipairs(WRITE_OPTIONS) do kept[option] = vim.bo[buf][option] end

  -- Only this buffer, and only what (a) and (b) proved is on disk plus the
  -- hunks. BufWritePre is skipped for this one write: conform formats there,
  -- lua/lang/go.lua organizes imports there whatever vim.b.autoformat says,
  -- and Nvim's own editorconfig sets 'endofline' and trims whitespace there.
  -- BufWritePost still runs, so LSP, gitsigns and the view hear about the
  -- write. 'fixeol' off: no newline added to a file that had none; and
  -- vim.b.autoformat off for a formatter that runs after the write. `!`
  -- because unmoved() has just compared the bytes themselves: an agent that
  -- rewrote the file with the same bytes before the key press moved only its
  -- mtime, and :write would stop to ask about that (a :checktime from a
  -- mapping is postponed, so it cannot settle it).
  local autoformat, fixeol, eventignore = vim.b[buf].autoformat, vim.bo[buf].fixeol, vim.o.eventignore
  vim.b[buf].autoformat, vim.bo[buf].fixeol = false, false
  vim.o.eventignore = eventignore == "" and "BufWritePre" or (eventignore .. ",BufWritePre")
  local stale, expected, want
  local ok, err = pcall(function()
    -- (b) once more, the last thing before the buffer changes: guard_fresh's
    -- own git calls take a few ms, and an agent's write landing in them
    -- would be lost to the `write!`. Nothing from here to the write runs a
    -- process or the event loop.
    if not unmoved(name, ctx.seen) then
      stale = true
      return
    end
    -- Bottom-up, so the ranges above stay where they were drawn.
    table.sort(hunks, function(a, b) return a.modified.start_line > b.modified.start_line end)
    for _, h in ipairs(hunks) do
      local o, m = h.original, h.modified
      api.nvim_buf_set_lines(buf, m.start_line - 1, m.end_line - 1, false,
        api.nvim_buf_get_lines(orig, o.start_line - 1, o.end_line - 1, false))
    end
    expected, want = api.nvim_buf_get_lines(buf, 0, -1, false), buffer_bytes(buf)
    api.nvim_buf_call(buf, function() vim.cmd("silent lockmarks write!") end)
  end)
  vim.o.eventignore = eventignore
  if valid_buf(buf) then vim.b[buf].autoformat, vim.bo[buf].fixeol = autoformat, fixeol end
  if stale then
    catch_up(ctx)
    return refuse(what, changed_on_disk(path))
  end
  if not ok then
    return notify(("%s: writing %s failed (%s); %s"):format(what, path, tostring(err),
      expected and "the buffer holds the change, u undoes it" or "nothing was changed"), vim.log.levels.ERROR)
  end
  -- What a BufWritePost hook may still have changed.
  local changed = {}
  if not vim.deep_equal(api.nvim_buf_get_lines(buf, 0, -1, false), expected) then changed[#changed + 1] = "lines" end
  for _, option in ipairs(WRITE_OPTIONS) do
    if vim.bo[buf][option] ~= kept[option] then changed[#changed + 1] = "'" .. option .. "'" end
  end
  if #changed == 0 and want and disk_bytes(name) ~= want then changed[#changed + 1] = "the bytes on disk" end
  if #changed > 0 then
    notify(("%s: something the write ran also changed %s (%s); u undoes lines, not options"):format(
      what, path, table.concat(changed, ", ")), vim.log.levels.WARN)
  end
  local where = #hunks == 1 and ("the hunk at " .. span(hunks[1].modified.start_line,
    math.max(hunks[1].modified.start_line, hunks[1].modified.end_line - 1))) or (#hunks .. " hunks")
  notify(("Discarded %s of %s back to baseline %s; index untouched; u then :w to undo"):format(
    where, path, baseline_label(s.git_root, view.baseline)))
end

--- ,X in a one-sided baseline view: hunks only, so say what would do it.
local function one_sided_hint(tab)
  local s = codediff().session(tab)
  local view = classify(tab, s)
  if not view or view.kind ~= "one-sided" then return end
  local when = baseline_label(s.git_root, view.baseline)
  if view.side == "original" then
    -- Only for a path that is gone: the restore writes the baseline's file
    -- over whatever is there, a directory and its untracked work included.
    -- util.codediff's listing never calls a path on disk deleted, but a view
    -- drawn before the file came back can, and so can upstream's listing,
    -- which that one falls back to.
    if vim.uv.fs_lstat(s.git_root .. "/" .. s.original.relative) then
      codediff().refresh(tab)
      return notify(("%s shows as deleted since baseline %s, but something is at that path now; no restore command, since it would overwrite that"):format(
        s.original.relative, when), vim.log.levels.WARN)
    end
    -- A literal pathspec: as a glob, `[id].txt` or `*` in the name would
    -- also restore every other path it matches, over their edits.
    local cmd = ("git -C %s --literal-pathspecs restore --source=%s --worktree -- %s"):format(
      vim.fn.shellescape(s.git_root), view.baseline.sha, vim.fn.shellescape(s.original.relative))
    notify(("%s was deleted since baseline %s. ,X only restores hunks; to bring the file back:\n%s"):format(
      s.original.relative, when, cmd), vim.log.levels.WARN)
  else
    notify(("%s is new since baseline %s. ,X only restores hunks: delete the file yourself if it should go"):format(
      s.modified.relative, when), vim.log.levels.WARN)
  end
end

---------------------------------------------------------------------------
-- Keys
---------------------------------------------------------------------------

local function leave_visual()
  if vim.fn.mode():match("^[vV\22]") then vim.cmd.normal({ vim.keycode("<Esc>"), bang = true }) end
end

--- A Visual-mode rhs: hands `fn` the selected lines, in Normal mode.
local function selection(fn)
  return function()
    local a, b = vim.fn.line("v"), vim.fn.line(".")
    leave_visual()
    fn({ math.min(a, b), math.max(a, b) })
  end
end

---@return util.codediff.Key[]
local function specs(tab, s)
  local view = classify(tab, s)
  local keys = {}
  local function add(mode, key, rhs, desc, on)
    keys[#keys + 1] = { mode, LL .. key, rhs, desc = desc, on = on }
  end
  if not view then return keys end
  if view.kind == "staged" then
    add("n", "U", function() unstage_staged(tab) end, "Unstage hunk", "panes")
    add("x", "U", function()
      leave_visual()
      refuse("Unstage", "the Staged group unstages whole hunks: ,U in Normal mode")
    end, "Unstage hunk (Normal mode here)", "panes")
  elseif view.stage then
    add("n", "u", function() stage(tab, false) end, "Stage hunk", "panes")
    add("x", "u", selection(function(r) stage(tab, false, r) end), "Stage selected lines", "panes")
    -- The Changes group shows only unstaged hunks, which ,U refuses: its
    -- staged lines are in the Staged group, with CodeDiff's ,U.
    if view.kind ~= "changes" then
      add("n", "U", function() stage(tab, true) end, "Unstage hunk", "panes")
      add("x", "U", selection(function(r) stage(tab, true, r) end), "Unstage selected lines", "panes")
    end
    if view.baseline then
      local when = baseline_label(s.git_root, view.baseline)
      add("n", "X", function() discard(tab) end, "Discard hunk back to baseline " .. when, "panes")
      add("x", "X", selection(function(r) discard(tab, r) end), "Discard selected hunks back to baseline " .. when, "panes")
    end
  elseif view.kind == "one-sided" then
    local when = baseline_label(s.git_root, view.baseline)
    local desc = view.side == "original" and ("Restore from baseline " .. when .. ": show the command")
      or ("New since baseline " .. when .. ": how to discard it")
    add({ "n", "x" }, "X", function()
      leave_visual()
      one_sided_hint(tab)
    end, desc, view.side)
  end
  return keys
end

--- Install this module's keys on the view in `tab` (0 = current), per the
--- view's kind; a pass that no longer applies a key releases it. Runs on
--- every `User CodeDiffKeys`, i.e. after each file switch or refresh.
---@param tab integer
function M.attach(tab)
  tab = (tab == nil or tab == 0) and api.nvim_get_current_tabpage() or tab
  if type(tab) ~= "number" or not api.nvim_tabpage_is_valid(tab) then return end
  local cd = codediff()
  local s = cd.session(tab)
  if not s then return end
  cd.set_keys(tab, specs(tab, s), "actions")
end

return M
