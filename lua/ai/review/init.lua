-- The review view behind <leader>av (design §5.5), and ,C in every CodeDiff
-- view (§5.8).
--
-- <leader>av shows what changed since a round's baseline: a CodeDiff view of
-- the round's sha against the working tree.
--
--   1. root: the current buffer's conversation root (an agent terminal or a
--      chat), else the current file's repository when it is in one -- in a
--      CodeDiff panel, the repository that view compares -- else the cwd's.
--      Outside a Git worktree it stops with git's reason.
--   2. round: rounds.select_round -- the buffer's conversation, the active
--      provider's session, the newest this process opened, the newest there.
--   3. one review tab per root: a tab already showing that round is focused
--      (its explorer); one showing another round is closed first, and the new
--      view opens from the tab <leader>av was pressed in, so the tab before a
--      review tab stays the one it was opened from. Other tabpages are read
--      (their vim.t.ai_review), never changed.
--   4. a clean tree (CodeDiff answers it with a bare "No changes to show",
--      #582), decided as the view's listing will list it
--      (util.codediff.listing): a tree that differs only in paths the
--      listing leaves out is clean, and the notice names them. The
--      conversation's previous round is shown instead when it has changes --
--      the next prompt went out, the agent has not written yet -- otherwise
--      it says so and opens nothing.
--   5. the view opens with vim.t.ai_review (the round: ,C files feedback for
--      its owner) and vim.t.codediff_baseline (for ,X), and says once what it
--      compares, when it has arrived. Roots open independently: another
--      root's view, or any other CodeDiff view, opening meanwhile takes
--      nothing of this one's (util.codediff.open); another press for a root
--      whose view is still on its way is refused.
--
-- A round only proves that a change came after its baseline. Whoever made it
-- -- the agent, the user, another agent in the same worktree -- it is listed,
-- so the messages say "changes since round HH:MM:SS", never "the agent's".
--
-- ,C is attach()'s, installed on every User CodeDiffKeys. It loads
-- ai.review.feedback, which owns the drafts, only when pressed; nothing here
-- knows what a draft is.
local M = {}

local api, uv = vim.api, vim.uv
local INFO, WARN = vim.log.levels.INFO, vim.log.levels.WARN

-- How long a view show() issued may take to arrive before another
-- <leader>av for that root is let through. util.codediff ends every open
-- within the same time (its done(nil) clears the slot); this only guards
-- against a callback that never came.
local PENDING_MS = 10000

-- How many skipped files a notice names before it counts the rest.
local NAMED = 5

-- Who a round's tab label names: the owner's kind, else the source's.
local SOURCES = { claude = "Claude", codex = "Codex", ["cc-acp"] = "Agent chat", ["cc-http"] = "API chat", manual = "Manual" }

-- Short lines, a clause each, with a path or git's own words on a line of
-- their own: the snacks notifier cuts a long line off instead of wrapping it
-- (as in rounds.lua).
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

local function codediff() return require("util.codediff") end

--- An async step that reports its own failure: it runs from a callback, where
--- an error is no notification of the facade's but a stack trace.
local function guarded(fn)
  return function(...)
    local ok, err = xpcall(fn, debug.traceback, ...)
    if not ok then notify("The review view failed:\n" .. tostring(err)) end
  end
end

--- When a round was taken: the time today, the date and time before.
local function when(time)
  time = time or os.time()
  if os.date("%Y-%m-%d", time) == os.date("%Y-%m-%d") then return os.date("%H:%M:%S", time) end
  return os.date("%Y-%m-%d %H:%M:%S", time)
end

--- The lines naming the paths a comparison left out, by reason, worded as
--- the view's listing words them: untracked files over max_file_size are in
--- neither tree, so a change to them shows nowhere, and a path the round has
--- that is still on disk is never listed as deleted.
---@param left_out? table<string, string[]>
---@return string[]
local function left_out_lines(left_out)
  return codediff().left_out_lines(left_out or {}, NAMED)
end

---------------------------------------------------------------------------
-- ,C: feedback on what the view shows
---------------------------------------------------------------------------

local function comment(opts)
  -- feedback.comment() warns about its own failures; this catches the module
  -- itself failing to load.
  local ok, err = pcall(function() require("ai.review.feedback").comment(opts) end)
  if not ok then notify("Review feedback failed: " .. tostring(err)) end
end

local function press_normal()
  comment({
    tab = api.nvim_get_current_tabpage(),
    win = api.nvim_get_current_win(),
    buf = api.nvim_get_current_buf(),
    mode = "n",
  })
end

--- Visual ,C: the selected lines, ordered, read before Visual mode is left.
local function press_visual()
  local a, b = vim.fn.line("v"), vim.fn.line(".")
  if vim.fn.mode():match("^[vV\22]") then vim.cmd.normal({ vim.keycode("<Esc>"), bang = true }) end
  comment({
    tab = api.nvim_get_current_tabpage(),
    win = api.nvim_get_current_win(),
    buf = api.nvim_get_current_buf(),
    mode = "v",
    range = { first = math.min(a, b), last = math.max(a, b) },
  })
end

local DESC = "Review feedback (hunk / selection / file)"

-- On every buffer of the view: both panes, a conflict result, the explorer or
-- history list. The handlers read the window they were pressed in, so one
-- table serves every view and every pass.
local KEYS = {
  { "n", "<localleader>C", press_normal, desc = DESC, on = "all" },
  { "x", "<localleader>C", press_visual, desc = DESC, on = "all" },
}

---Install ,C on the view in `tab` (0 or nil = current), in Normal and Visual
---mode, on every buffer it shows: every Git view kind -- status, staged,
---baseline or revision against the working tree, revision against revision,
---history -- and its explorer or history panel. A directory or file diff has
---no repository to file feedback under and gets none.
---
---Runs on every `User CodeDiffKeys` (each file switch or refresh fires it
---again), so it only hands the same two keys to util.codediff.set_keys under
---its own "review" scope, which leaves util.codediff_actions' "actions" scope
---alone on the same buffers.
---@param tab? integer
function M.attach(tab)
  tab = (tab == nil or tab == 0) and api.nvim_get_current_tabpage() or tab
  if type(tab) ~= "number" or not api.nvim_tabpage_is_valid(tab) then return end
  local s = codediff().session(tab)
  if not s then return end
  codediff().set_keys(tab, s.git_root and KEYS or {}, "review")
end

---------------------------------------------------------------------------
-- <leader>av
---------------------------------------------------------------------------

--- The directory whose worktree <leader>av reviews (step 1).
local function root_of(rounds, buf)
  local _, root, bound = rounds.conversation_of(buf)
  if bound and root then return root end
  local name = api.nvim_buf_get_name(buf)
  -- Only a file inside a worktree names one. Outside, rounds.toplevel would
  -- be the file's own directory, which is no repository; the steps below
  -- decide instead.
  if vim.bo[buf].buftype == "" and name ~= "" and not name:match("^%a[%w+.-]*://") and vim.fs.root(name, ".git") then
    return rounds.toplevel(name)
  end
  -- A CodeDiff panel or revision pane: the repository that view compares.
  -- Only once CodeDiff is loaded: asking util.codediff loads it.
  if package.loaded["codediff"] then
    local s = codediff().session(0)
    if s and type(s.git_root) == "string" then return s.git_root end
  end
  return rounds.toplevel()
end

--- The tabpages that show a review of `root`, in tab order: a view of a round
--- (vim.t.ai_review), whether <leader>av or <leader>gk opened it.
---@return { tab: integer, id: string }[]
local function review_tabs(root)
  local out = {}
  for _, tab in ipairs(api.nvim_list_tabpages()) do
    local vars = vim.t[tab].ai_review
    if type(vars) == "table" and type(vars.root) == "string" and real(vars.root) == root then
      out[#out + 1] = { tab = tab, id = vars.id }
    end
  end
  return out
end

--- A tab of `tabs` that still has its view and shows round `id`.
local function showing(tabs, id)
  for _, t in ipairs(tabs) do
    if t.id == id and api.nvim_tabpage_is_valid(t.tab) and codediff().session(t.tab) then return t.tab end
  end
end

local function focus(tab)
  api.nvim_set_current_tabpage(tab)
  local s = codediff().session(tab)
  if s and type(s.panel_win) == "number" and api.nvim_win_is_valid(s.panel_win) then
    api.nvim_set_current_win(s.panel_win)
  end
end

--- The nearest tabpage to `tab` that is not about to close, the one before
--- it first: where a view opened from a closing tab opens from instead.
local function neighbour(tab, closing)
  local tabs = api.nvim_list_tabpages()
  local at = api.nvim_tabpage_get_number(tab)
  for i = at - 1, 1, -1 do
    if not closing[tabs[i]] then return tabs[i] end
  end
  for i = at + 1, #tabs do
    if not closing[tabs[i]] then return tabs[i] end
  end
end

--- Who a tab label names for `entry`: the owner's kind (Claude, Codex, a
--- chat), else the source's.
local function owner_kind(entry)
  local trailers = entry.trailers or {}
  local agent = (trailers.Conversation or ""):match("^(%l+):")
  if agent == "claude" or agent == "codex" then return SOURCES[agent] end
  if agent == "cc" then
    return (trailers.Source == "cc-acp" or trailers.Source == "cc-http") and SOURCES[trailers.Source] or "Chat"
  end
  return SOURCES[trailers.Source] or "Round"
end

--- vim.t.codediff_label, which the statusline shows.
local function label(entry)
  return ("Review · %s · round %s → working tree"):format(owner_kind(entry), when(entry.time))
end

--- What the view compares, said once it has arrived. Short lines: the
--- notifier cuts a long one off rather than wrap it.
local function message(root, entry, vars, extra)
  local lines = {}
  if extra.note then lines[#lines + 1] = extra.note end
  lines[#lines + 1] = ("Changes since round %s (baseline → working tree)"):format(when(entry.time))
  lines[#lines + 1] = "Root: " .. tilde(root)
  lines[#lines + 1] = vars.conversation
    and ("Conversation: %s"):format(require("ai.review.rounds").label(vars.conversation))
    or "No conversation: delivering feedback asks where it goes"
  if vars.late then
    lines[#lines + 1] = "Late: the baseline landed after the prompt went out,"
    lines[#lines + 1] = "so the agent's first edits may be missing from this diff"
  end
  -- util.codediff's listing names the files left out for size as the view
  -- lists; only without it (a CodeDiff it was not written for) is it said here.
  if codediff().degraded() then vim.list_extend(lines, left_out_lines({ size = extra.skipped })) end
  return table.concat(lines, "\n")
end

-- Bumped by every <leader>av that starts on a root: an answer that arrives
-- for an older press there is dropped, so two quick presses open one view.
-- Per root, so a press elsewhere never drops this one.
local generation = {} ---@type table<string, integer>

-- The review views show() issued and has not seen arrive, by root.
local opening = {} ---@type table<string, { id: string, at: integer }>

--- Step 3 and 5: show `entry` in the one review tab of `root`.
---@param extra { note?: string, skipped?: string[] }
local function show(root, entry, extra, gen)
  if gen ~= generation[root] then return end
  local cd = codediff()
  local tabs = review_tabs(root)
  local there = showing(tabs, entry.id)
  if there then
    focus(there)
    if extra.note then notify(extra.note, INFO) end
    return
  end
  -- The new view opens from where <leader>av was pressed; from the tab
  -- before that one when it is one of the review tabs about to close.
  local closing = {}
  for _, t in ipairs(tabs) do closing[t.tab] = true end
  local from = api.nvim_get_current_tabpage()
  if closing[from] then from = neighbour(from, closing) end
  for _, t in ipairs(tabs) do
    if api.nvim_tabpage_is_valid(t.tab) then cd.close(t.tab) end
  end
  for _, t in ipairs(tabs) do
    -- CodeDiff asks before it drops unsaved merge results; kept is kept.
    if api.nvim_tabpage_is_valid(t.tab) and cd.session(t.tab) then
      return notify({ "The review view stays open, so no second one opens.", "Root: " .. tilde(root) })
    end
  end
  if from and api.nvim_tabpage_is_valid(from) and from ~= api.nvim_get_current_tabpage() then
    api.nvim_set_current_tabpage(from)
  end
  local vars = require("ai.review.rounds").review_vars(entry)
  if not vars then return notify("Not a review round: " .. tostring(entry.id)) end
  local text = message(root, entry, vars, extra)
  local mark = { id = entry.id, at = uv.now() }
  opening[root] = mark
  -- The view's own notice, once it has arrived; nothing when CodeDiff
  -- refused it (it says why itself) or it never came.
  local function arrived(tab)
    if opening[root] == mark then opening[root] = nil end
    if tab then notify(text, INFO) end
  end
  local ok, issued = pcall(cd.open, {
    root = root,
    -- The sha, never the ref: retention may delete the ref while the view is
    -- open. util.codediff.open adds `-C <root>`.
    args = { entry.sha },
    label = label(entry),
    tab_vars = { ai_review = vars, codediff_baseline = { sha = entry.sha, kind = "round" } },
    -- The notice above says what the view compares.
    quiet = true,
    done = arrived,
  })
  if not (ok and issued) then arrived(nil) end
  if not ok then error(issued, 0) end
end

--- Would a view of `sha` against the snapshot `tree` list anything? Asked
--- of the view's own listing rule (util.codediff.listing), so a tree whose
--- only differences are paths that listing leaves out counts as unchanged:
--- `cb(changed, left_out)`, or `cb(nil, nil, reason)` when git refused.
local function differs(root, sha, tree, info, cb)
  codediff().listing(root, sha, tree, info, nil, function(result, err)
    if not result then return cb(nil, nil, err) end
    cb(#result.listed > 0, result.left_out)
  end)
end

--- The round of `entry`'s conversation before it (one with no owner: the
--- unowned round before it): `cb(entry|nil)`.
local function previous(root, entry, cb)
  require("util.baseline").list(root, "round", function(entries)
    local owner = (entry.trailers or {}).Conversation
    local past = false
    for _, e in ipairs(entries or {}) do
      if past and (e.trailers or {}).Conversation == owner then return cb(e) end
      if e.id == entry.id then past = true end
    end
    cb(nil)
  end)
end

--- Step 4, then 5: snapshot the working tree and compare it with the round.
local function check(root, entry, gen)
  require("util.baseline").snapshot(root, guarded(function(tree, info)
    if gen ~= generation[root] then return end
    -- No snapshot, no verdict: the view opens and speaks for itself.
    if not tree then return show(root, entry, {}, gen) end
    local extra = { skipped = info.skipped }
    -- `left_out`: what the comparison with `entry` left out.
    local function nothing(left_out)
      local lines = { ("No changes since round %s in %s"):format(when(entry.time), tilde(root)) }
      vim.list_extend(lines, left_out_lines(left_out))
      notify(table.concat(lines, "\n"), INFO)
    end
    differs(root, entry.sha, tree, info, guarded(function(changed, left_out, why)
      if gen ~= generation[root] then return end
      if why then return notify(("Round %s cannot be compared: %s"):format(when(entry.time), why)) end
      if changed then return show(root, entry, extra, gen) end
      previous(root, entry, guarded(function(prev)
        if gen ~= generation[root] then return end
        if not prev then return nothing(left_out) end
        differs(root, prev.sha, tree, info, guarded(function(prev_changed)
          if gen ~= generation[root] then return end
          if not prev_changed then return nothing(left_out) end
          extra.note = ("Round %s has no changes yet; showing round %s"):format(when(entry.time), when(prev.time))
          show(root, prev, extra, gen)
        end))
      end))
    end))
  end))
end

---<leader>av: show the changes since a round's baseline (design §5.5; the
---steps are at the top of this file). Asynchronous: the snapshot and git run
---in the background, and the view opens when they are done.
function M.open()
  local buf = api.nvim_get_current_buf()
  local rounds = require("ai.review.rounds")
  local loc, err = require("util.baseline").locate(root_of(rounds, buf))
  if not loc then return notify({ "The review view needs a Git worktree:", tostring(err) }) end
  local root = loc.toplevel
  local o = opening[root]
  if o and uv.now() - o.at <= PENDING_MS then
    return notify(("The review view of %s is still opening"):format(tilde(root)), INFO)
  end
  generation[root] = (generation[root] or 0) + 1
  local gen = generation[root]
  rounds.select_round(root, guarded(function(entry, why)
    if gen ~= generation[root] then return end
    if not entry then
      if why then return notify({ "Could not list the review rounds:", "Root: " .. tilde(root), why }) end
      return notify(table.concat({
        ("%s has no review round yet."):format(tilde(root)),
        "Submit a prompt to Claude, Codex or a chat,",
        "or press <leader>aV to start one.",
        "Submitted one and no round came:",
        "see the hook checks in :checkhealth config.",
        "<leader>gv diffs against HEAD and the index.",
      }, "\n"))
    end
    -- Already on screen: nothing to snapshot.
    local there = showing(review_tabs(root), entry.id)
    if there then return focus(there) end
    check(root, entry, gen)
  end), { buf = buf })
end

return M
