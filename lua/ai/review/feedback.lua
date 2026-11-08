-- Review feedback (design §4.1-4.5): ,C in a CodeDiff view adds an entry to a
-- markdown draft and shows the draft in a float; <C-d> there delivers it to the
-- conversation the round belongs to.
--
-- Drafts. One per round (<round-id>.md) and one per root for views that are no
-- round's (unowned.md), at rounds.draft_path(). The first line is the header
--
--   <!-- nvim-review round=<id> sha=<sha> conversation=<id> root="<path>" -->
--
-- (an unowned draft has neither sha nor conversation), and delivery checks
-- against that line alone (rounds.resolve_sink), so a draft still delivers
-- after retention pruned its round's ref, or from an Nvim started since. Every
-- Nvim reads and writes the same file: ,C reads it, appends, writes it back,
-- and keeps no copy of its own between presses; what is typed in a float is
-- merged into what the file holds by then (save). Retention spares a round
-- whose draft is a non-empty file (rounds._exempt); a delivered draft is
-- emptied, and so is one with no feedback left.
-- An intro line opens the entries: a round's names its baseline, once; any
-- other view's names what it compares, again whenever a later entry comes
-- from a view that compares something else.
--
-- Entries (§4.2). A path is the real one, relative to the root -- the working
-- tree's file, the baseline's for a deletion, never a codediff:// name. The
-- left pane's line numbers are the baseline's, which no file on disk has, so an
-- entry always quotes the code: the hunk under the cursor as a diff of both
-- sides, or the selected lines of one side. A file in the explorer gets its
-- name and status only. Every entry ends with a "> " line for the comment and
--
--   <!-- review-item path="<path>" side="new|old|file" digest="sha256:<hex>" -->
--
-- whose digest is the working-tree file's content when the comment was made
-- (or what the view showed, when it had not caught up with the disk yet).
-- Delivery hashes the file again; a mismatch, a deletion included, marks the
-- entry "⚠ changed since this comment" and asks before sending. Whole files,
-- not hunks: it may warn more often than needed, never less.
--
-- Delivery (§4.3). The header and the review-item lines stay behind; the rest
-- goes to resolve_sink's target, after a tab switch: to the tabpage that shows
-- the target's terminal or chat, else -- from a CodeDiff view -- to the tab
-- before it. A native agent gets the text through its own ctrl+g editor
-- (ai.feed -> edit_prompt, seeded for that agent only, or appended to its
-- prompt when one is already open); a chat through companion.add_text. The
-- draft is copied to <id>.last-sent.md and emptied only once the text has
-- arrived: when the agent's prompt editor has it, or add_text succeeded. A
-- native agent that does not open its editor within seed_ttl_ms leaves the
-- draft as it was.
--
-- Loaded by the first ,C (lua/ai/review attach()). Reaches CodeDiff only
-- through util.codediff and CodeCompanion only through ai.companion.
local M = {}

local api, uv = vim.api, vim.uv
local INFO, WARN = vim.log.levels.INFO, vim.log.levels.WARN

-- Lines of unchanged context around a hunk, as git diff shows them.
local CONTEXT = 3

local STALE = "⚠ changed since this comment"

-- Intro wording per round source, as rounds.lua names them in its subjects.
local SOURCES = { claude = "Claude", codex = "Codex", ["cc-acp"] = "Agent chat", ["cc-http"] = "API chat", manual = "Manual" }

local HEADER = "^<!%-%- nvim%-review (.-)%s*%-%->%s*$"
local ITEM = "^<!%-%- review%-item (.-)%s*%-%->%s*$"
local INTRO = "^Review of changes .+ in .+:$"

-- Short lines, a clause each, with a path or an error's own words on a line
-- of their own: the snacks notifier cuts a long line off instead of wrapping
-- it (as in rounds.lua). tests/review_feedback_spec.lua pins the lengths.
---@param lines string|string[]
---@param level? integer
local function notify(lines, level)
  local msg = type(lines) == "table" and table.concat(lines, "\n") or lines
  vim.notify(msg, level or WARN, { title = "AI review" })
end

local function tilde(path)
  return vim.fn.fnamemodify(path, ":~")
end

local function real(path)
  return uv.fs_realpath(path) or path
end

local function rounds() return require("ai.review.rounds") end
local function codediff() return require("util.codediff") end

local function valid_buf(buf)
  return type(buf) == "number" and api.nvim_buf_is_valid(buf)
end

local function agent_label(agent)
  local p = require("ai.config").providers[agent]
  return p and p.label or tostring(agent)
end

---------------------------------------------------------------------------
-- Files
---------------------------------------------------------------------------

---@return string? text nil when the file cannot be read (missing, a directory)
local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local text = f:read("*a")
  f:close()
  return text
end

--- Replace `path` in one step, through a temporary file beside it: another
--- Nvim reading the draft meanwhile sees the old text or the new, never half.
---@return boolean ok, string? err
local function write(path, text)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local tmp = ("%s.%d.tmp"):format(path, uv.os_getpid())
  local f, err = io.open(tmp, "wb")
  if not f then return false, err end
  local ok, werr = f:write(text)
  f:close()
  if not ok then
    os.remove(tmp)
    return false, werr
  end
  local renamed, rerr = uv.fs_rename(tmp, path)
  if not renamed then
    os.remove(tmp)
    return false, rerr
  end
  return true
end

local function split(text)
  if text == nil or text == "" then return {} end
  local lines = vim.split(text, "\n", { plain = true })
  if lines[#lines] == "" then table.remove(lines) end
  return lines
end

local function join(lines)
  return #lines == 0 and "" or table.concat(lines, "\n") .. "\n"
end

local function last_sent_path(path)
  return (path:gsub("%.md$", "")) .. ".last-sent.md"
end

--- The content of the working-tree file `path` (relative to `root`), as the
--- digest a review-item carries; "none" for a file that is not there.
local function digest_of(root, path)
  local text = read(root .. "/" .. path)
  if text == nil then return "none" end
  return "sha256:" .. vim.fn.sha256(text)
end

---------------------------------------------------------------------------
-- The header and review-item lines
---------------------------------------------------------------------------

--- An attribute value: bare when it is plainly a word, a JSON string otherwise.
local function bare(value)
  if value:match("^[%w_.:@+-]+$") then return value end
  return vim.json.encode(value)
end

--- `key=value key="json string" ...` as a table.
local function parse_attrs(body)
  local out, i = {}, 1
  while i <= #body do
    local _, e, key = body:find("^%s*([%w_]+)=", i)
    if not e then break end
    i = e + 1
    if body:sub(i, i) == '"' then
      local j = i + 1
      while j <= #body do
        local c = body:sub(j, j)
        if c == "\\" then
          j = j + 2
        elseif c == '"' then
          break
        else
          j = j + 1
        end
      end
      local ok, value = pcall(vim.json.decode, body:sub(i, j))
      if ok and type(value) == "string" then out[key] = value end
      i = j + 1
    else
      local value = body:match("^%S+", i) or ""
      out[key] = value
      i = i + #value
    end
  end
  return out
end

---@class ai.review.DraftHeader
---@field round string the round id, or "unowned"
---@field sha? string
---@field conversation? string
---@field root string

---@param h ai.review.DraftHeader
local function header_line(h)
  local parts = { "round=" .. bare(h.round) }
  if h.sha then parts[#parts + 1] = "sha=" .. bare(h.sha) end
  if h.conversation then parts[#parts + 1] = "conversation=" .. bare(h.conversation) end
  parts[#parts + 1] = "root=" .. vim.json.encode(h.root)
  return ("<!-- nvim-review %s -->"):format(table.concat(parts, " "))
end

---@return ai.review.DraftHeader?
local function parse_header(line)
  local body = type(line) == "string" and line:match(HEADER)
  if not body then return nil end
  local a = parse_attrs(body)
  if not a.round or not a.root or a.root == "" then return nil end
  return { round = a.round, sha = a.sha, conversation = a.conversation, root = a.root }
end

local function item_line(path, side, digest)
  return ("<!-- review-item path=%s side=%s digest=%s -->"):format(
    vim.json.encode(path), vim.json.encode(side), vim.json.encode(digest))
end

local function is_intro(line)
  return line:match(INTRO) ~= nil
end

--- What each line of a draft is, the way markdown reads it. A line inside a
--- code fence is quoted code, whatever it looks like: an entry quotes the
--- file's lines as they are (lines_entry), so a quoted "## " heading, or a
--- line shaped like a header, review-item or intro, is the file's text and
--- never the draft's. A fence opens on three or more backticks or tildes (a
--- backtick fence's info string has none) and closes on a run of the same
--- character at least as long with nothing after it, as in CommonMark;
--- fence_for makes an entry's closing fence its opening one, longer than any
--- run it quotes.
---@param lines string[]
---@return string[] kinds "header", "item", "heading", "intro", "fence", "code" or "text", per line
local function classify(lines)
  local kinds, open = {}, nil
  for i, line in ipairs(lines) do
    local kind
    if open then
      local run = line:match("^ ? ? ?(`+)%s*$") or line:match("^ ? ? ?(~+)%s*$")
      if run and run:sub(1, 1) == open:sub(1, 1) and #run >= #open then
        kind, open = "fence", nil
      else
        kind = "code"
      end
    else
      local run, info = line:match("^ ? ? ?(```+)(.*)$")
      if run and info:find("`", 1, true) then run = nil end
      run = run or line:match("^ ? ? ?(~~~+)")
      if run then
        kind, open = "fence", run
      elseif parse_header(line) then
        kind = "header"
      elseif line:match(ITEM) then
        kind = "item"
      elseif line:match("^## ") then
        kind = "heading"
      elseif is_intro(line) then
        kind = "intro"
      else
        kind = "text"
      end
    end
    kinds[i] = kind
  end
  return kinds
end

local function last_intro(lines)
  local kinds = classify(lines)
  for i = #lines, 1, -1 do
    if kinds[i] == "intro" then return lines[i] end
  end
end

--- What the agent is sent: the draft without its header and review-item
--- lines, blank lines trimmed at both ends; "" when it holds no feedback.
local function message(lines)
  local kinds, out, content = classify(lines), {}, false
  for i, line in ipairs(lines) do
    if kinds[i] ~= "header" and kinds[i] ~= "item" then
      out[#out + 1] = line
      if kinds[i] ~= "intro" and vim.trim(line) ~= "" then content = true end
    end
  end
  if not content then return "" end
  while vim.trim(out[1]) == "" do table.remove(out, 1) end
  while vim.trim(out[#out]) == "" do table.remove(out) end
  return table.concat(out, "\n")
end

---------------------------------------------------------------------------
-- The view ,C was pressed in
---------------------------------------------------------------------------

local function short(rev)
  if type(rev) ~= "string" then return nil end
  return rev:match("^%x+$") and #rev > 12 and rev:sub(1, 8) or rev
end

--- One end of the comparison, as an entry names it.
---@param requested? string what was asked for (a name, or a sha)
---@param resolved? string the session's revision: nil = working tree, ":0" = index
local function end_name(requested, resolved)
  if resolved == nil then return "working tree" end
  if resolved == ":0" then return "index" end
  if resolved == ":2" or resolved == ":3" then return "conflict side " .. resolved end
  if type(requested) == "string" and requested ~= "" and requested ~= "WORKING" then return short(requested) end
  return short(resolved)
end

---@class ai.review.View
---@field tab integer
---@field s table util.codediff.session()
---@field root string the view's repository, realpath'd
---@field round? table vim.t.ai_review of a round view
---@field left { name: string, was: string, new: string } how entries name the left end
---@field right { name: string }
---@field two_revs boolean both ends are commits (rev vs rev, history)

---@return ai.review.View? view, string? why
local function view_of(tab)
  local s = codediff().session(tab)
  if not s then return nil, "There is no CodeDiff view in this tab." end
  if type(s.git_root) ~= "string" or s.git_root == "" then
    return nil, "This view compares files outside a Git repository;\nreview feedback needs one."
  end
  local root = real(s.git_root)
  if root:find("\n", 1, true) then return nil, "A repository path with a newline\ncannot hold a review draft." end
  local vars = vim.t[tab].ai_review
  local round = type(vars) == "table" and type(vars.id) == "string" and vars.id ~= "" and vars or nil
  if round and type(round.root) == "string" and real(round.root) ~= root then
    return nil, table.concat({
      "This view's repository is not its round's:", tilde(root),
      "The round was taken in:", tilde(round.root),
      "Feedback not recorded.",
    }, "\n")
  end
  local requested = type(s.source_revisions) == "table" and s.source_revisions or {}
  local baseline = round ~= nil or type(vim.t[tab].codediff_baseline) == "table"
  local left
  if baseline then
    left = { name = "baseline", was = "at the baseline", new = "new since the baseline" }
  else
    local name = end_name(requested.original, s.original_revision)
    local where = (name == "index" or name == "working tree") and ("the " .. name) or name
    left = { name = name, was = "in " .. where, new = "not in " .. where }
  end
  local function commit(rev) return type(rev) == "string" and rev:sub(1, 1) ~= ":" end
  return {
    tab = tab,
    s = s,
    root = root,
    round = round,
    left = left,
    right = { name = end_name(requested.modified, s.modified_revision) },
    two_revs = commit(s.original_revision) and commit(s.modified_revision),
  }
end

--- The real path of one side, relative to the view's repository.
local function rel_path(view, side)
  local p = view.s[side]
  if type(p) ~= "table" or type(p.absolute) ~= "string" or p.absolute == "" then return nil end
  if p.absolute:match("^%a[%w+.-]*://") then return nil end
  return vim.fs.relpath(view.s.git_root, p.absolute) or vim.fs.relpath(view.root, real(p.absolute))
    or (p.relative ~= "" and p.relative or nil)
end

--- The file an entry is about: the working tree's path, or the baseline's for
--- a file deleted since; and the old path of a rename.
local function file_of(view)
  local new, old = rel_path(view, "modified"), rel_path(view, "original")
  return new or old, (new and old and old ~= new) and old or nil
end

--- When a round's baseline was taken, from its commit: nil when git cannot
--- say (the object is gone).
---@return integer?
local function baseline_time(view)
  local sha = view.round.sha
  if type(sha) ~= "string" or not sha:match("^%x+$") then return nil end
  local ok, proc = pcall(vim.system, require("util.baseline").git_cmd({ "show", "-s", "--format=%ct", sha }),
    { cwd = view.root, text = true, env = { GIT_NO_LAZY_FETCH = "1" } })
  local r = ok and proc:wait(5000) or nil
  return r and r.code == 0 and tonumber(vim.trim(r.stdout or "")) or nil
end

--- The line that opens this view's entries in a draft. A round's names its
--- baseline; any other view's names what it compares.
---@param time? integer the round's baseline time
local function intro_for(view, time)
  if view.round then
    local source = SOURCES[view.round.source] or "Review"
    local when = time and os.date("%Y-%m-%d %H:%M:%S", time) or short(view.round.sha) or view.round.id
    return ("Review of changes since baseline %s (%s round) in %s:"):format(when, source, tilde(view.root))
  end
  local label = vim.t[view.tab].codediff_label
  if type(label) ~= "string" or label == "" then
    label = ("%s → %s"):format(view.left.name, view.right.name)
  end
  return ("Review of changes (%s) in %s:"):format(label, tilde(view.root))
end

---------------------------------------------------------------------------
-- Entries
---------------------------------------------------------------------------

---@class ai.review.Entry
---@field lines string[]
---@field comment integer index of the "> " line in `lines`

local function span(first, last)
  return last > first and ("%d-%d"):format(first, last) or tostring(first)
end

--- A code fence longer than any backtick run in `lines`.
local function fence_for(lines)
  local longest = 2
  for _, line in ipairs(lines) do
    for run in line:gmatch("`+") do longest = math.max(longest, #run) end
  end
  return ("`"):rep(longest + 1)
end

local function language(buf, path)
  local ft = valid_buf(buf) and vim.bo[buf].filetype or ""
  if ft == "" then ft = vim.filetype.match({ filename = path }) or "" end
  return ft
end

local function real_file(buf)
  if not valid_buf(buf) or vim.bo[buf].buftype ~= "" then return false end
  local name = api.nvim_buf_get_name(buf)
  return name ~= "" and not name:match("^%a[%w+.-]*://")
end

local function buf_lines(buf)
  return valid_buf(buf) and api.nvim_buf_get_lines(buf, 0, -1, false) or {}
end

--- The digest for an entry quoting `buf`: the working-tree file as it is on
--- disk -- unless `buf` is that file, unmodified, and still shows other text
--- (the view had not caught up with a write yet). Then it is what the view
--- showed, which the disk no longer holds, so delivery flags the entry.
local function digest_for(view, path, buf)
  local disk = digest_of(view.root, path)
  if real_file(buf) and not vim.bo[buf].modified and disk ~= "none" then
    local on_disk, shown = vim.fn.readfile(view.root .. "/" .. path), buf_lines(buf)
    -- An empty file is no lines on disk and one empty line in a buffer.
    if #on_disk == 0 then on_disk = { "" } end
    if not vim.deep_equal(on_disk, shown) then
      return "sha256:" .. vim.fn.sha256(join(shown))
    end
  end
  return disk
end

local function finish(heading, body, path, side, digest)
  local lines = { heading }
  vim.list_extend(lines, body)
  lines[#lines + 1] = "> "
  local comment = #lines
  lines[#lines + 1] = item_line(path, side, digest)
  return { lines = lines, comment = comment }
end

--- The hunk under the cursor, as a unified diff of both panes' text.
---@return ai.review.Entry
local function hunk_entry(view, hunk)
  local s = view.s
  local path, renamed_from = file_of(view)
  local old, new = buf_lines(s.original_bufnr), buf_lines(s.modified_bufnr)
  local o, m = hunk.original, hunk.modified
  -- Context only while both sides agree: the next hunk may be that close.
  local before, after = 0, 0
  while before < CONTEXT do
    local oi, mi = o.start_line - before - 1, m.start_line - before - 1
    if oi < 1 or mi < 1 or old[oi] ~= new[mi] then break end
    before = before + 1
  end
  while after < CONTEXT do
    local oi, mi = o.end_line + after, m.end_line + after
    if old[oi] == nil or old[oi] ~= new[mi] then break end
    after = after + 1
  end
  local diff = {}
  for k = before, 1, -1 do diff[#diff + 1] = " " .. new[m.start_line - k] end
  for i = o.start_line, o.end_line - 1 do diff[#diff + 1] = "-" .. (old[i] or "") end
  for i = m.start_line, m.end_line - 1 do diff[#diff + 1] = "+" .. (new[i] or "") end
  for k = 0, after - 1 do diff[#diff + 1] = " " .. new[m.end_line + k] end
  local function range(r)
    local count = (r.end_line - r.start_line) + before + after
    local start = r.start_line - before
    -- Unified diff puts an empty range after the line it follows.
    if count == 0 then start = start - 1 end
    return count == 1 and tostring(start) or ("%d,%d"):format(start, count)
  end

  local o_count, m_count = o.end_line - o.start_line, m.end_line - m.start_line
  local right = view.right.name
  if s.modified_revision == nil and valid_buf(s.modified_bufnr) and vim.bo[s.modified_bufnr].modified then
    right = right .. ", unsaved buffer"
  end
  local here
  if m_count > 0 then
    here = ("## %s:%s (%s)"):format(path, span(m.start_line, m.end_line - 1), right)
  elseif m.start_line > 1 then
    here = ("## %s (%s): removed after line %d"):format(path, right, m.start_line - 1)
  else
    here = ("## %s (%s): removed at the top"):format(path, right)
  end
  local there
  if o_count > 0 then
    there = renamed_from and ("was %s in %s %s"):format(span(o.start_line, o.end_line - 1), renamed_from, view.left.was)
      or ("was %s %s"):format(span(o.start_line, o.end_line - 1), view.left.was)
  else
    there = view.left.new
  end
  local fence = fence_for(diff)
  local body = { fence .. "diff", ("@@ -%s +%s @@"):format(range(o), range(m)) }
  vim.list_extend(body, diff)
  body[#body + 1] = fence
  return finish(here .. " · " .. there, body, path, "new", digest_for(view, path, s.modified_bufnr))
end

--- Lines `first`..`last` of one pane, quoted as they are shown there.
---@param side "original"|"modified"|"result"
---@return ai.review.Entry
local function lines_entry(view, side, buf, first, last)
  local s = view.s
  local path, renamed_from = file_of(view)
  local label
  if side == "original" then
    label = view.left.name .. " side" .. (renamed_from and (", as " .. renamed_from) or "") .. ", not on disk"
  else
    label = side == "result" and "merge result" or view.right.name
    if not real_file(buf) then
      label = label .. " side, not on disk"
    elseif vim.bo[buf].modified then
      label = label .. ", unsaved buffer"
    end
  end
  local heading = ("## %s:%s (%s)"):format(path, span(first, last), label)
  if view.two_revs then heading = ("%s · comparing %s → %s"):format(heading, view.left.name, view.right.name) end
  local code = api.nvim_buf_get_lines(buf, first - 1, last, false)
  local fence = fence_for(code)
  local body = { fence .. language(buf, path) }
  vim.list_extend(body, code)
  body[#body + 1] = fence
  local digest = side == "original" and digest_of(view.root, path) or digest_for(view, path, buf)
  return finish(heading, body, path, side == "original" and "old" or "new", digest)
end

local STATUS = { ["??"] = "A" }

--- A file picked in the explorer or history list: its name and status only.
---@return ai.review.Entry
local function item_entry(view, item)
  -- A commit of a single file's history stands for that file's change.
  local status = STATUS[item.status] or item.status or (item.type == "commit" and "changed") or "?"
  if (status == "R" or status == "C") and item.old_path then
    status = ("%s %s→%s"):format(status, item.old_path, item.path)
  end
  if item.group == "staged" then
    status = status .. ", staged"
  elseif item.group == "conflicts" then
    status = status .. ", conflicted"
  end
  if item.commit then
    status = ("%s in %s"):format(status, short(item.commit))
    if item.subject then status = ("%s %q"):format(status, item.subject) end
  end
  return finish(("## %s (%s)"):format(item.path, status), {}, item.path, "file", digest_of(view.root, item.path))
end

---@return ai.review.Entry? entry, string? why
local function build_entry(view, opts)
  local s, buf, win = view.s, opts.buf, opts.win
  if buf == s.panel_bufnr then
    local item = codediff().panel_item(view.tab, win)
    if not item or not item.path or (item.type ~= "file" and item.type ~= "commit") then
      return nil, "Put the cursor on a file in the list,\nor on a hunk in a diff pane."
    end
    return item_entry(view, item)
  end
  local side = (buf == s.modified_bufnr and "modified") or (buf == s.original_bufnr and "original")
    or (buf == s.result_bufnr and "result") or nil
  if not side or not valid_buf(buf) then return nil, "Press ,C in a diff pane or in the file list of this view." end
  if not file_of(view) then return nil, "This pane shows no file to comment on." end
  if opts.mode == "v" and type(opts.range) == "table" then
    local count = api.nvim_buf_line_count(buf)
    local first = math.max(1, math.min(opts.range.first or 1, count))
    local last = math.max(first, math.min(opts.range.last or first, count))
    return lines_entry(view, side, buf, first, last)
  end
  local hunk = side ~= "result" and codediff().hunk_at_cursor(view.tab, win) or nil
  if hunk then return hunk_entry(view, hunk) end
  -- Not on a change: the cursor line, quoted the way a selection would be.
  local line = api.nvim_win_get_cursor(win)[1]
  return lines_entry(view, side, buf, line, line)
end

---------------------------------------------------------------------------
-- The draft float
---------------------------------------------------------------------------

---@class ai.review.Draft
---@field buf integer
---@field path string
---@field synced string the file's text when this buffer last matched it
---@field view_root string the root of the view that last added to it

---@type table<integer, ai.review.Draft>
local drafts = {}
---@type table<string, integer>
local buf_of = {}

local function buffer_text(buf)
  local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
  if #lines == 1 and lines[1] == "" then return "" end
  return join(lines)
end

--- Show `text` in the draft buffer: what the file now holds.
local function load(d, text)
  local lines = split(text)
  if #lines == 0 then lines = { "" } end
  api.nvim_buf_set_lines(d.buf, 0, -1, false, lines)
  vim.bo[d.buf].modified = false
  d.synced = text
end

--- What the file holds for a draft whose text is `text`: nothing at all once
--- no feedback is left. A header and an intro alone count as empty for
--- delivery (message), so they count as empty on disk too, where retention
--- spares a round only for a non-empty draft (rounds._exempt). The next ,C
--- writes both again.
local function settled(text)
  return message(split(text)) == "" and "" or text
end

--- The changes that turn `base` into `lines`, each as the base lines it
--- replaces (lo+1..hi; none when lo == hi, an insertion there) and the new
--- ones.
---@return { lo: integer, hi: integer, new: string[] }[]
local function changes(base, lines)
  local out = {}
  for _, h in ipairs(vim.text.diff(join(base), join(lines), { result_type = "indices" })) do
    local lo = h[2] == 0 and h[1] or h[1] - 1
    out[#out + 1] = { lo = lo, hi = lo + h[2], new = vim.list_slice(lines, h[3], h[3] + h[4] - 1) }
  end
  return out
end

--- A three-way merge of two versions of a draft against the one both started
--- from, line by line. Changes to different lines of `base` are both made;
--- two insertions at the same place are both kept, `ours` first; a change
--- both made alike is made once.
---@return string[]? merged nil when the two changed the same lines differently
local function merge3(base, ours, theirs)
  local list = changes(base, ours)
  local mine = #list
  for _, c in ipairs(changes(base, theirs)) do
    local dup = false
    for i = 1, mine do
      local o = list[i]
      if o.lo == c.lo and o.hi == c.hi and vim.deep_equal(o.new, c.new) then
        dup = true
      elseif o.lo < c.hi and c.lo < o.hi then
        return nil
      end
    end
    if not dup then
      c.theirs = true
      list[#list + 1] = c
    end
  end
  -- By position; at one position an insertion before a replacement, and ours
  -- before theirs. Neither side's own changes overlap, nor (checked) do the
  -- two sides'.
  table.sort(list, function(a, b)
    if a.lo ~= b.lo then return a.lo < b.lo end
    if a.hi ~= b.hi then return a.hi < b.hi end
    return not a.theirs and b.theirs == true
  end)
  local out, pos = {}, 0
  for _, c in ipairs(list) do
    for k = pos + 1, c.lo do out[#out + 1] = base[k] end
    vim.list_extend(out, c.new)
    pos = c.hi
  end
  for k = pos + 1, #base do out[#out + 1] = base[k] end
  return out
end

--- Where a draft's version that lost a merge is written: beside it, under a
--- name no earlier one took.
local function conflict_path(path)
  local stem = (path:gsub("%.md$", ""))
  local candidate, n = stem .. ".conflict.md", 1
  while uv.fs_stat(candidate) do
    n = n + 1
    candidate = ("%s.conflict-%d.md"):format(stem, n)
  end
  return candidate
end

--- Write what is typed in the draft buffer to its file. Another Nvim may have
--- written the file meanwhile -- a ,C of its own, a comment typed there, a
--- delivery that emptied it: that is merged with this buffer's changes,
--- against the text both started from (d.synced). Where the two changed the
--- same lines, the file keeps what it has -- entries another Nvim delivered
--- stay delivered -- and this buffer's text is written beside it
--- (<id>.conflict.md), with a warning naming it: nothing typed in either Nvim
--- is lost.
---@return boolean ok
local function save(buf)
  local d = drafts[buf]
  if not d or not api.nvim_buf_is_loaded(buf) or not vim.bo[buf].modified then return true end
  local text = buffer_text(buf)
  local disk = read(d.path) or ""
  local merged = text
  if disk ~= d.synced and disk ~= text then
    local ours = split(text)
    local lines = merge3(split(d.synced), ours, split(disk))
    if lines then
      -- A delivery elsewhere took the header with what it sent; what was
      -- added here still needs it.
      if parse_header(ours[1]) and not vim.list_contains(classify(lines), "header") then
        table.insert(lines, 1, ours[1])
      end
      merged = join(lines)
    else
      local aside = conflict_path(d.path)
      local ok, err = write(aside, text)
      if not ok then
        notify({
          "Could not save the review draft:", tilde(d.path),
          "It was changed elsewhere in the same lines,",
          "and what was typed here could not be written to:", tilde(aside), tostring(err),
        })
        return false
      end
      notify({
        "The draft was changed elsewhere in the same lines",
        "while it was open here:", tilde(d.path),
        "It keeps that version; what was typed here is in:", tilde(aside),
      })
      merged = disk
    end
  end
  merged = settled(merged)
  if merged ~= disk then
    local ok, err = write(d.path, merged)
    if not ok then
      notify({ "Could not save the review draft:", tilde(d.path), tostring(err) })
      return false
    end
  end
  if merged ~= text then
    local cursor = api.nvim_get_current_buf() == buf and api.nvim_win_get_cursor(0) or nil
    load(d, merged)
    if cursor then pcall(api.nvim_win_set_cursor, 0, cursor) end
  else
    d.synced = merged
    vim.bo[buf].modified = false
  end
  return true
end

--- The windows in this tabpage that show `buf`: the draft's floats.
local function windows_here(buf)
  local out = {}
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    if api.nvim_win_get_buf(win) == buf then out[#out + 1] = win end
  end
  return out
end

--- Hide the draft in this tabpage; it stays on disk. Other tabpages' windows
--- are theirs.
function M.hide(buf)
  if not drafts[buf] then return end
  save(buf)
  for _, win in ipairs(windows_here(buf)) do
    pcall(api.nvim_win_close, win, false)
  end
end

local deliver

local function create_buffer(path)
  local buf = api.nvim_create_buf(false, true)
  -- acwrite: the file is written here, by save(), so Vim never compares its
  -- timestamp with a write another Nvim made -- the W12 prompt that would
  -- otherwise come up mid-delivery.
  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].swapfile = false
  -- hide, then wiped once saved (BufHidden below): with bufhidden=wipe Nvim
  -- refuses :close, <C-w>c and sd (nvim_win_close(win, false)) over a draft
  -- edited in Normal mode (E37), before any autocmd could save it.
  vim.bo[buf].bufhidden = "hide"
  pcall(api.nvim_buf_set_name, buf, path)
  local d = { buf = buf, path = path, synced = "" }
  drafts[buf] = d
  buf_of[path] = buf
  local ul = vim.bo[buf].undolevels
  vim.bo[buf].undolevels = -1
  load(d, read(path) or "")
  vim.bo[buf].undolevels = ul
  vim.bo[buf].filetype = "markdown"
  -- @file completion (lua/ai/mention.lua), as in the agent's prompt editor.
  vim.b[buf].ai_prompt = true
  -- A draft is not reformatted by a save: prettier would reflow quoted code.
  vim.b[buf].autoformat = false

  local group = api.nvim_create_augroup(("ai_review_draft_%d"):format(buf), { clear = true })
  api.nvim_create_autocmd("BufWriteCmd", {
    group = group,
    buffer = buf,
    callback = function()
      -- :w always writes, even unchanged.
      vim.bo[buf].modified = true
      save(buf)
    end,
  })
  -- Typed text reaches the file whenever the float is left, hidden or closed
  -- -- by q, :q, :close, <C-w>c, sd, a click elsewhere or quitting Nvim.
  api.nvim_create_autocmd({ "InsertLeave", "WinLeave", "BufWinLeave", "BufUnload", "QuitPre", "FocusLost" }, {
    group = group,
    buffer = buf,
    callback = function() save(buf) end,
  })
  -- Shown nowhere any more, and saved: the file holds it, so the buffer goes.
  -- One whose save failed stays (hidden, modified) for the next ,C to retry.
  api.nvim_create_autocmd("BufHidden", {
    group = group,
    buffer = buf,
    callback = function()
      save(buf)
      vim.schedule(function()
        if valid_buf(buf) and not vim.bo[buf].modified and #vim.fn.win_findbuf(buf) == 0 then
          pcall(api.nvim_buf_delete, buf, {})
        end
      end)
    end,
  })
  api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      if api.nvim_buf_is_valid(buf) then save(buf) end
    end,
  })
  api.nvim_create_autocmd("BufWipeout", {
    group = group,
    buffer = buf,
    callback = function()
      drafts[buf] = nil
      if buf_of[path] == buf then buf_of[path] = nil end
      pcall(api.nvim_del_augroup_by_id, group)
    end,
  })

  -- <C-d> as in the agent's prompt editor: hand it over. Left alone: <C-c>
  -- (leaving Insert mode), <C-o> and <C-y>.
  vim.keymap.set({ "n", "i" }, "<C-d>", function()
    if vim.fn.mode() ~= "n" then vim.cmd("stopinsert") end
    -- After the mapping, in Normal mode: delivery moves between tabpages.
    vim.schedule(function() M.deliver(buf) end)
  end, { buffer = buf, desc = "Deliver review feedback", silent = true })
  vim.keymap.set("n", "q", function() M.hide(buf) end,
    { buffer = buf, desc = "Hide review draft (kept)", silent = true, nowait = true })
  return buf
end

local function open_window(buf, info)
  local width = math.min(100, math.floor(vim.o.columns * 0.8))
  local height = math.min(20, math.floor(vim.o.lines * 0.5))
  local win = api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = (" Review feedback · %s "):format(info.title),
    title_pos = "center",
  })
  -- A float copies the options of the window it was opened from: a diff
  -- pane's binds would tie the draft's scrolling to the diff.
  vim.wo[win].scrollbind = false
  vim.wo[win].cursorbind = false
  vim.wo[win].foldenable = false
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].winbar = ("  <C-d> deliver to %s   ·   q hide (draft kept)"):format(info.to)
  -- @file completes against the cwd: the round's root, like the entries' paths.
  pcall(api.nvim_win_call, win, function() vim.cmd.lcd(vim.fn.fnameescape(info.root)) end)
  return win
end

--- Show the draft at `path` in a float in this tabpage, the cursor at the end
--- of line `line`, in Insert mode.
local function show(path, info, line)
  local buf = buf_of[path]
  if not valid_buf(buf) or not drafts[buf] then buf = create_buffer(path) end
  local d = drafts[buf]
  d.view_root = info.root
  if d.synced ~= (read(path) or "") and not vim.bo[buf].modified then load(d, read(path) or "") end
  local win = windows_here(buf)[1] or open_window(buf, info)
  api.nvim_set_current_win(win)
  line = math.min(line, api.nvim_buf_line_count(buf))
  api.nvim_win_set_cursor(win, { line, #(api.nvim_buf_get_lines(buf, line - 1, line, false)[1] or "") })
  vim.cmd("startinsert!")
end

--- Bring the draft buffer of `path`, if any, up to date with its file.
local function reload(path)
  local buf = buf_of[path]
  local d = buf and drafts[buf]
  if d and api.nvim_buf_is_loaded(buf) and not vim.bo[buf].modified then load(d, read(path) or "") end
end

---------------------------------------------------------------------------
-- ,C
---------------------------------------------------------------------------

--- Append `entry` to the draft at `path`: the header first when the file has
--- none, and this view's intro when the draft's last one is another's.
---@return integer? line the entry's "> " line in the file, string? err
local function append(path, header, intro, entry)
  local lines = split(read(path) or "")
  if not parse_header(lines[1]) then table.insert(lines, 1, header_line(header)) end
  if last_intro(lines) ~= intro then
    if #lines > 1 then lines[#lines + 1] = "" end
    lines[#lines + 1] = intro
  end
  lines[#lines + 1] = ""
  local at = #lines + entry.comment
  vim.list_extend(lines, entry.lines)
  local ok, err = write(path, join(lines))
  if not ok then return nil, err end
  return at
end

local function comment(opts)
  opts = opts or {}
  local tab = opts.tab or api.nvim_get_current_tabpage()
  local view, why = view_of(tab)
  if not view then return notify(why) end
  opts.buf = opts.buf or api.nvim_get_current_buf()
  opts.win = opts.win or api.nvim_get_current_win()
  local entry, missing = build_entry(view, opts)
  if not entry then return notify(missing) end

  local round = view.round
  local id = round and round.id or "unowned"
  local path = rounds().draft_path(view.root, id)
  -- What is typed in an open draft goes to the file before ,C reads it.
  local open = buf_of[path]
  if valid_buf(open) and not save(open) then return end
  local header = { round = id, sha = round and round.sha, conversation = round and round.conversation, root = view.root }
  local time = round and baseline_time(view)
  local line, err = append(path, header, intro_for(view, time), entry)
  if not line then return notify({ "Could not write the review draft:", tilde(path), tostring(err) }) end
  reload(path)

  local title
  if round then
    title = ("%s round %s"):format(SOURCES[round.source] or "Review", time and os.date("%H:%M:%S", time) or id)
  else
    title = tilde(view.root) .. " (no round)"
  end
  local to = round and round.conversation and rounds().label(round.conversation) or "a session you pick"
  show(path, { root = view.root, title = title, to = to }, line)
end

---Add an entry for what ,C was pressed on to the right draft, and show the
---draft in a float with the cursor on the entry's comment line, in Insert
---mode. `opts.tab`/`win`/`buf` are where ,C was pressed; `mode` "v" with
---`range` (1-based, inclusive, ordered) quotes those lines of that pane.
---Never raises: every failure is a warning.
---@param opts { tab: integer, win: integer, buf: integer, mode: "n"|"v", range?: { first: integer, last: integer } }
function M.comment(opts)
  local ok, err = xpcall(comment, debug.traceback, opts)
  if not ok then notify("Review feedback failed:\n" .. tostring(err)) end
end

---------------------------------------------------------------------------
-- Delivery
---------------------------------------------------------------------------

--- Entries whose file changed since their comment, marked in `lines`: the
--- entry's heading, never a quoted line that looks like one (classify).
---@return string[] paths the files concerned, each once
local function mark_stale(lines, root)
  local kinds, paths, heading = classify(lines), {}, nil
  for i, line in ipairs(lines) do
    if kinds[i] == "item" then
      local a = parse_attrs(line:match(ITEM))
      if a.path and a.digest and digest_of(root, a.path) ~= a.digest then
        if not vim.list_contains(paths, a.path) then paths[#paths + 1] = a.path end
        if heading and not lines[heading]:find(STALE, 1, true) then
          lines[heading] = ("## %s · %s"):format(STALE, lines[heading]:sub(4))
        end
      end
      heading = nil
    elseif kinds[i] == "heading" then
      heading = i
    end
  end
  return paths
end

--- The draft at `path` was delivered as `snapshot`: keep it as
--- <id>.last-sent.md, and empty the draft -- or, when ,C added to it
--- meanwhile, keep only what came after, under its header and intro.
local function delivered(path, snapshot)
  local copy = last_sent_path(path)
  local ok, err = write(copy, snapshot)
  if not ok then
    return notify({ "Delivered, but the draft was kept:", "no copy could be written to", tilde(copy), tostring(err) })
  end
  -- A draft reopened meanwhile (another ,C) may hold typing not saved yet:
  -- it belongs to what stays.
  local open = buf_of[path]
  if open then save(open) end
  local now = read(path) or ""
  local rest
  if now == snapshot then
    rest = ""
  elseif now:sub(1, #snapshot) == snapshot then
    local lines = split(snapshot)
    local head = { lines[1] }
    head[#head + 1] = last_intro(lines)
    -- What came after may be blank lines only: then nothing stays.
    rest = settled(join(head) .. now:sub(#snapshot + 1))
  else
    return notify({
      "Delivered. The draft was edited meanwhile,",
      "so it was kept as it is. What was sent is in:", tilde(copy),
    }, INFO)
  end
  ok, err = write(path, rest)
  if not ok then notify({ "Delivered, but the draft could not be emptied:", tostring(err) }) end
  reload(path)
end

--- Is a window showing `buf` on screen? A float parked with `hide` is not.
local function shown(win, buf)
  if api.nvim_win_get_buf(win) ~= buf then return false end
  return not api.nvim_win_get_config(win).hide
end

--- Go to the tabpage that shows the target's terminal or chat; else, from a
--- CodeDiff view, to the tab before it (where the view was opened from). Only
--- which tabpage is current changes.
local function switch_tab(target)
  local current = api.nvim_get_current_tabpage()
  local tabs = api.nvim_list_tabpages()
  for _, tab in ipairs(tabs) do
    for _, win in ipairs(api.nvim_tabpage_list_wins(tab)) do
      if shown(win, target.buf) then
        if tab ~= current then api.nvim_set_current_tabpage(tab) end
        return
      end
    end
  end
  if package.loaded["util.codediff"] and codediff().session(current) then
    local nr = api.nvim_tabpage_get_number(current)
    if nr > 1 then api.nvim_set_current_tabpage(tabs[nr - 1]) end
  end
end

--- Into the agent's terminal, in Terminal mode, when this tabpage shows it.
local function enter_terminal(buf)
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    if shown(win, buf) then
      api.nvim_set_current_win(win)
      vim.cmd("startinsert")
      return
    end
  end
end

---@param path string
---@param target ai.review.Target
local function sink(path, target)
  local snapshot = read(path) or ""
  local text = message(split(snapshot))
  if text == "" then return notify("The draft is empty: nothing to deliver.") end

  if target.kind == "cc" then
    local companion = require("ai.companion")
    if companion.busy(target.chat) then
      return notify({ "The chat is replying.", "Draft kept: deliver again once it is done." })
    end
    local buf = buf_of[path]
    if buf then M.hide(buf) end
    switch_tab(target)
    local ok, why, err = companion.add_text(target.chat, "\n" .. text)
    if not ok then
      if why == "busy" then return notify({ "The chat is replying.", "Draft kept: deliver again once it is done." }) end
      if why == "gone" then return notify("That chat no longer exists. Draft kept.") end
      return notify({ "Could not add the feedback to the chat. Draft kept:", tostring(err or why) })
    end
    delivered(path, snapshot)
    local shown_ok, show_err = pcall(companion.show_input, target.chat)
    if not shown_ok then notify({ "The feedback is in the chat, which could not be shown:", tostring(show_err) }) end
    return
  end

  local agent = target.agent
  local label = agent_label(agent)
  local buf = buf_of[path]
  if buf then M.hide(buf) end
  switch_tab(target)
  local answered = false
  local function consumed()
    if answered then return end
    answered = true
    delivered(path, snapshot)
  end
  local function expired()
    if answered then return end
    answered = true
    notify({ ("%s did not open its prompt editor (busy?)."):format(label), "Draft kept: deliver again." })
  end
  -- That agent's prompt editor is already open: the TUI is blocked on it and
  -- reads no key, so the text goes straight into it.
  if require("ai.editor").focus_open(text, agent) then return consumed() end
  require("ai").feed(agent, "edit_prompt", {
    seed = text,
    on_consumed = consumed,
    on_expired = expired,
    ttl_ms = require("ai.review.config").get().seed_ttl_ms,
  })
  enter_terminal(target.buf)
end

--- Deliver the draft shown in `buf`: write what is typed, check every entry
--- against its file, let rounds.resolve_sink pick and vet the target, send.
--- Anything refused or cancelled keeps the draft.
---@param buf integer
deliver = function(buf)
  local d = drafts[buf]
  if not d then return end
  if not save(buf) then return end
  local path = d.path
  local lines = split(read(path) or "")
  if message(lines) == "" then
    -- No feedback left (delivered elsewhere, or only its header and intro
    -- remain): no draft, and no longer one that spares its round (settled).
    if #lines > 0 then
      local ok, err = write(path, "")
      if not ok then notify({ "Could not empty the review draft:", tilde(path), tostring(err) }) end
    end
    reload(path)
    return notify("The draft is empty: nothing to deliver.")
  end
  local header = parse_header(lines[1])
  if not header then
    return notify({
      "This draft lost its first line (<!-- nvim-review ... -->),",
      "so where it belongs is unknown. Not delivered.",
    })
  end

  local function failed(err)
    notify("Delivering the review feedback failed; the draft is kept:\n" .. tostring(err))
  end
  -- Asynchronous from here on whenever something is asked: guarded at each
  -- step, since a callback's error would be a stack trace, not a warning.
  local function go()
    local roots = { header.root }
    if d.view_root then roots[2] = d.view_root end
    local ok, err = xpcall(rounds().resolve_sink, debug.traceback, header.conversation, roots, function(target)
      -- A refusal has been explained by resolve_sink; the draft stays.
      if not target then return end
      local sent, sink_err = xpcall(sink, debug.traceback, path, target)
      if not sent then failed(sink_err) end
    end)
    if not ok then failed(err) end
  end

  local stale = mark_stale(lines, header.root)
  if #stale == 0 then return go() end
  local ok, err = write(path, join(lines))
  if not ok then return notify({ "Could not mark the changed entries:", tostring(err) }) end
  reload(path)
  -- Which files, in a notice beside the question: the picker's prompt is one
  -- line.
  local why = vim.list_extend({ "Changed since you commented:" }, vim.list_slice(stale, 1, 3))
  if #stale > 3 then why[#why + 1] = ("and %d more"):format(#stale - 3) end
  why[#why + 1] = ("%s entries are marked %s."):format(#stale == 1 and "Its" or "Their", STALE)
  notify(why)
  local prompt = ("%s changed since you commented. Deliver anyway?"):format(
    #stale == 1 and "A file" or ("%d files"):format(#stale))
  vim.ui.select({ "Deliver anyway", "Edit first" }, { prompt = prompt, kind = "ai_review_stale" }, function(choice)
    if choice == "Deliver anyway" then return go() end
    local win = valid_buf(buf) and windows_here(buf)[1]
    if win then api.nvim_set_current_win(win) end
  end)
end

---Deliver the draft shown in `buf` (<C-d> in its float).
---@param buf integer
function M.deliver(buf)
  local ok, err = xpcall(deliver, debug.traceback, buf)
  if not ok then notify("Delivering the review feedback failed; the draft is kept:\n" .. tostring(err)) end
end

---The draft buffer this Nvim shows for `path`, if any. For the spec.
---@param path string
---@return integer?
function M._buf(path)
  local buf = buf_of[path]
  return valid_buf(buf) and buf or nil
end

M._parse_header = parse_header
M._message = message

return M
