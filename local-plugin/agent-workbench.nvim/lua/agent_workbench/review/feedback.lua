-- Review feedback UI and delivery: ,C captures a CodeDiff entry and opens
-- its draft in a float; <C-d> sends it through rounds.resolve_sink. Draft
-- parsing, atomic persistence and concurrent edits belong to review.draft.
-- Reaches plugin internals only through git_review.view and ai.companion.
local M = {}

local api, uv = vim.api, vim.uv
local draft = require("agent_workbench.review.draft")
local INFO, WARN = vim.log.levels.INFO, vim.log.levels.WARN

-- Lines of unchanged context around a hunk, as git diff shows them.
local CONTEXT = 3

-- Intro wording per round source, as rounds.lua names them in its subjects.
local SOURCES = { claude = "Claude", codex = "Codex", ["cc-acp"] = "Agent chat", ["cc-http"] = "API chat", manual = "Manual" }

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

local function rounds() return require("agent_workbench.review.rounds") end
local function codediff() return require("git_review.view") end

local function valid_buf(buf)
  return type(buf) == "number" and api.nvim_buf_is_valid(buf)
end

local function agent_label(agent)
  local p = require("agent_workbench.state").agents[agent]
  return p and p.label or tostring(agent)
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
---@field s table git_review.view.session()
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
  local ok, proc = pcall(vim.system, require("git_review.baseline").git_cmd({ "show", "-s", "--format=%ct", sha }),
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
---@field lines string[] its heading first, its "> " line last
---@field comment integer index of the "> " line in `lines`
---@field attrs { path: string, side: string, digest: string } what its marker carries

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
  local disk = draft.digest(view.root, path)
  if real_file(buf) and not vim.bo[buf].modified and disk ~= "none" then
    local on_disk, shown = vim.fn.readfile(view.root .. "/" .. path), buf_lines(buf)
    -- An empty file is no lines on disk and one empty line in a buffer.
    if #on_disk == 0 then on_disk = { "" } end
    if not vim.deep_equal(on_disk, shown) then
      return "sha256:" .. vim.fn.sha256(table.concat(shown, "\n") .. "\n")
    end
  end
  return disk
end

local function finish(heading, body, path, side, digest)
  local lines = { heading }
  vim.list_extend(lines, body)
  lines[#lines + 1] = "> "
  return { lines = lines, comment = #lines, attrs = { path = path, side = side, digest = digest } }
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
  local digest = side == "original" and draft.digest(view.root, path) or digest_for(view, path, buf)
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
  return finish(("## %s (%s)"):format(item.path, status), {}, item.path, "file", draft.digest(view.root, item.path))
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

---@class ai.review.DraftBuffer
---@field buf integer
---@field store ai.review.Draft
---@field view_root? string the root of the view that last added to it

---@type table<integer, ai.review.DraftBuffer>
local drafts = {}
---@type table<string, integer>
local buf_of = {}

--- Update the editor from persisted data without displacing its cursor.
local function show_lines(d, lines)
  if not vim.deep_equal(api.nvim_buf_get_lines(d.buf, 0, -1, false), lines) then
    local cursor = api.nvim_get_current_buf() == d.buf and api.nvim_win_get_cursor(0) or nil
    api.nvim_buf_set_lines(d.buf, 0, -1, false, lines)
    if cursor then pcall(api.nvim_win_set_cursor, 0, cursor) end
  end
  vim.bo[d.buf].modified = false
end

local function load(d)
  show_lines(d, draft.reload(d.store, api.nvim_buf_get_lines(d.buf, 0, -1, false)))
end

--- Present a storage conflict after the model has protected the local text.
local function conflict_notice(path, outcome)
  local why, where
  if outcome.clash and outcome.gone then
    why = { "Entries edited here were changed elsewhere", "in the same lines, or delivered or deleted,",
      "while the draft was open here:" }
    where = "It keeps what it has; what was typed here is in:"
  elseif outcome.clash then
    why = { "The draft was changed elsewhere in the same lines", "while it was open here:" }
    where = "It keeps that version; what was typed here is in:"
  else
    why = { "Entries edited here were delivered", "or deleted elsewhere meanwhile:" }
    where = "What was typed into them is in:"
  end
  if outcome.err then
    return notify(vim.list_extend(why, {
      tilde(path), "and what was typed here could not be written to:", tilde(outcome.path), tostring(outcome.err),
      "The draft was not saved.",
    }))
  end
  notify(vim.list_extend(why, { tilde(path), where, tilde(outcome.path) }))
end

--- Persist typed lines through the draft's three-way merge. A failed write
--- keeps this buffer modified; successful saves display the merged result.
---@return boolean ok
local function save(buf)
  local d = drafts[buf]
  if not d or not api.nvim_buf_is_loaded(buf) or not vim.bo[buf].modified then return true end
  local lines, outcome = draft.save(d.store, api.nvim_buf_get_lines(buf, 0, -1, false))
  local conflict = outcome and (outcome.conflict or (outcome.path and outcome))
  if conflict then conflict_notice(d.store.path, conflict) end
  if not lines then
    if not conflict or not conflict.err then
      notify({ "Could not save the review draft:", tilde(d.store.path), tostring(outcome and outcome.err) })
    end
    return false
  end
  show_lines(d, lines)
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
  local d = { buf = buf, store = draft.open(path) }
  drafts[buf] = d
  buf_of[path] = buf
  local ul = vim.bo[buf].undolevels
  vim.bo[buf].undolevels = -1
  load(d)
  vim.bo[buf].undolevels = ul
  vim.bo[buf].filetype = "markdown"
  -- @file completion (local-plugin/agent-workbench.nvim/lua/agent_workbench/mention.lua), as in the agent's prompt editor.
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
  local d = valid_buf(buf) and drafts[buf] or nil
  if not d then
    buf = create_buffer(path)
    d = drafts[buf]
  elseif not vim.bo[buf].modified then
    load(d)
  end
  d.view_root = info.root
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
  if d and api.nvim_buf_is_loaded(buf) and not vim.bo[buf].modified then load(d) end
end

---------------------------------------------------------------------------
-- ,C
---------------------------------------------------------------------------

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
  local known = valid_buf(open) and drafts[open] and drafts[open].store.head or nil
  local line, err = draft.append(path, header, intro_for(view, time), entry, known)
  if not line then return notify({ "Could not write the review draft:", tilde(path), tostring(err) }) end

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

--- Called only once the recipient has the text. Save typing made while it
--- was in flight before the store archives and removes unchanged sent blocks.
---@param known? ai.review.DraftHeader
local function delivered(path, snapshot, known)
  local open = buf_of[path]
  if open then save(open) end
  local status, copy, err = draft.acknowledge(path, snapshot, known)
  if status == "archive_failed" then
    return notify({ "Delivered, but the draft was kept:", "no copy could be written to", tilde(copy), tostring(err) })
  elseif status == "edited" then
    return notify({
      "Delivered. The draft was edited meanwhile,",
      "so it was kept as it is. What was sent is in:", tilde(copy),
    }, INFO)
  elseif status == "clear_failed" then
    notify({ "Delivered, but the draft could not be emptied:", tostring(err) })
  end
  reload(path)
end

--- Is a window showing `buf` on screen? A float parked with `hide` is not.
local function shown(win, buf)
  if api.nvim_win_get_buf(win) ~= buf then return false end
  return not api.nvim_win_get_config(win).hide
end

--- Go to the tabpage that shows the target's terminal or chat; else, from a
--- CodeDiff view, to the page it was opened from -- the rule the AI slot's
--- keys use too (editor_core.window.origin_tab). Only which tabpage is current
--- changes.
local function switch_tab(target)
  local current = api.nvim_get_current_tabpage()
  for _, tab in ipairs(api.nvim_list_tabpages()) do
    for _, win in ipairs(api.nvim_tabpage_list_wins(tab)) do
      if shown(win, target.buf) then
        if tab ~= current then api.nvim_set_current_tabpage(tab) end
        return
      end
    end
  end
  local origin = require("agent_workbench.context").origin_tab(current)
  if origin then api.nvim_set_current_tabpage(origin) end
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
---@param known ai.review.DraftHeader the header the draft was vetted with
local function sink(path, target, known)
  local doc, snapshot = draft.read(path, known)
  local text = draft.message(doc)
  if text == "" then return notify("The draft is empty: nothing to deliver.") end

  local companion = target.kind == "cc" and require("agent_workbench.companion") or nil
  if companion and companion.busy(target.chat) then
    return notify({ "The chat is replying.", "Draft kept: deliver again once it is done." })
  end
  local buf = buf_of[path]
  if buf then M.hide(buf) end
  switch_tab(target)

  if companion then
    local ok, why, err = companion.add_text(target.chat, "\n" .. text)
    if not ok then
      if why == "busy" then return notify({ "The chat is replying.", "Draft kept: deliver again once it is done." }) end
      if why == "gone" then return notify("That chat no longer exists. Draft kept.") end
      return notify({ "Could not add the feedback to the chat. Draft kept:", tostring(err or why) })
    end
    delivered(path, snapshot, known)
    local shown_ok, show_err = pcall(require("agent_workbench.slot").focus_chat_prompt, target.chat, true)
    if not shown_ok then notify({ "The feedback is in the chat, which could not be shown:", tostring(show_err) }) end
    return
  end

  local agent = target.agent
  local label = agent_label(agent)
  local answered = false
  local function consumed()
    if answered then return end
    answered = true
    delivered(path, snapshot, known)
  end
  local function expired()
    if answered then return end
    answered = true
    notify({ ("%s did not open its prompt editor (busy?)."):format(label), "Draft kept: deliver again." })
  end
  -- That agent's prompt editor is already open: the TUI is blocked on it and
  -- reads no key, so the text goes straight into it.
  if require("agent_workbench.editor").focus_open(text, agent) then return consumed() end
  require("agent_workbench").feed(agent, "edit_prompt", {
    seed = text,
    on_consumed = consumed,
    on_expired = expired,
    ttl_ms = require("agent_workbench.review.settings").get().seed_ttl_ms,
  })
  enter_terminal(target.buf)
end

--- Deliver the draft shown in `buf`: write what is typed, check every entry
--- against its file, let rounds.resolve_sink pick and vet the target, send.
--- Anything refused or cancelled keeps the draft.
---@param buf integer
local function deliver(buf)
  local d = drafts[buf]
  if not d then return end
  if not save(buf) then return end
  local path = d.store.path
  local doc, text = draft.read(path, d.store.head)
  if draft.message(doc) == "" then
    -- No feedback left (delivered elsewhere, or only its header and intro
    -- remain): no draft, and no longer one that spares its round.
    if text ~= "" then
      local ok, err = draft.store(path, doc)
      if not ok then notify({ "Could not empty the review draft:", tilde(path), tostring(err) }) end
    end
    reload(path)
    return notify("The draft is empty: nothing to deliver.")
  end
  -- The file's header, or the one this Nvim knows: only a draft that lost it
  -- and was never shown here has none.
  local header = doc.head
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
      local sent, sink_err = xpcall(sink, debug.traceback, path, target, header)
      if not sent then failed(sink_err) end
    end)
    if not ok then failed(err) end
  end

  local stale = draft.mark_stale(doc, header.root)
  if #stale == 0 then return go() end
  local ok, err = draft.store(path, doc)
  if not ok then return notify({ "Could not mark the changed entries:", tostring(err) }) end
  reload(path)
  -- Which files, in a notice beside the question: the picker's prompt is one
  -- line.
  local why = vim.list_extend({ "Changed since you commented:" }, vim.list_slice(stale, 1, 3))
  if #stale > 3 then why[#why + 1] = ("and %d more"):format(#stale - 3) end
  why[#why + 1] = ("%s entries are marked %s."):format(#stale == 1 and "Its" or "Their", draft.STALE)
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

---Where delivery goes before it reveals anything (see switch_tab). For the spec.
M._switch_tab = switch_tab

return M
