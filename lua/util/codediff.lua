-- The one module that reads CodeDiff's internals.
--
-- codediff.nvim's README calls everything under codediff.core and codediff.ui
-- internal, and it has no API for the session, the hunks or its keymaps
-- (upstream #577). What this config needs from there goes through this file,
-- like which-key's View.sort in lua/plugin/editor/whichkey.lua. Every access
-- is guarded -- pcall around the require, a type check before each call -- and
-- setup() compares the plugin's VERSION with the one these hooks were written
-- against. A mismatch warns once and leaves the patches below off. That
-- fallback is safe: the upstream keys that would be dangerous here are already
-- disabled in lua/plugin/vcs/codediff.lua, so what remains is plain CodeDiff.
-- tests/codediff_spec.lua pins every internal named here.
--
--   codediff.version                VERSION
--   codediff.ui.lifecycle           get_session, set_buf_keymap,
--                                   begin/end_keymap_scope, close,
--                                   update_buffers (wrapped)
--   session fields                  git_root, original/modified ({ relative,
--                                   absolute }), *_revision, *_bufnr, *_win,
--                                   result_bufnr/_win, layout, single_side,
--                                   merge, source_revisions,
--                                   stored_diff_result.changes,
--                                   panel { name, data, view { bufnr, winid, tree } }
--   panel tree                      get_node(line) and its node.data, and a
--                                   history's data.opts (panel_item)
--   codediff.ui.explorer.actions    toggle_stage_entry, stage_all,
--                                   unstage_all, restore_entry
--   codediff.ui.view.actions.hunk   unstage_hunk
--   codediff.ui.refresh             request
--   codediff.core.diff              compute_diff
--   codediff.ui.view.render         diff_options
--   codediff.ui.layout              arrange
--   codediff.core.git.runner        run_async
--   codediff.core.git               get_commit_list, get_diff_revision
--   codediff.core.git.changes       get_diff_revision (the listing patch)
--
-- Besides them, the public codediff module's next_hunk/prev_hunk (]h [h).
--
-- Keys go through the session's own keymap registry (set_keys): it snapshots
-- whatever a buffer had before, suspends the claims on real file buffers on
-- TabLeave, and hands every key back when the view closes.
local M = {}

--- The CodeDiff release the hooks below were written and tested against.
M.VERSION = "4.0.6"

-- Filetypes of CodeDiff's own panels. lua/util/window.lua names the same two
-- for its first-tabpage guard; it runs at startup, so it cannot require this.
M.PANEL_FILETYPES = { "codediff-explorer", "codediff-history" }

-- How long an open() waits for its view. CodeDiff refuses some opens with a
-- notice of its own and no event (an unknown revision, a git error), and
-- what an open carries must not outlive it.
local PENDING_MS = 10000

---@class util.codediff.Pending an open() whose view has not arrived
---@field label? string
---@field tab_vars? table<string, any>
---@field quiet? boolean
---@field done? fun(tab?: integer, why?: string)
---@field root? string realpath the view's git_root must have
---@field mode? string the view's mode, where the arguments name one
---@field base? string the view's base revision, where given as a full sha
---@field target? string its target revision, likewise
---@field at integer

local degraded = false
local pending = {} ---@type util.codediff.Pending[] oldest first
local tab_vars = {} ---@type table<integer, string[]> views on_open set up, with their extra tab vars
local queued = {} ---@type table<integer, true>

local warned = {}
local function warn_once(key, msg)
  if warned[key] then return end
  warned[key] = true
  vim.schedule(function() vim.notify(msg, vim.log.levels.WARN, { title = "CodeDiff" }) end)
end

---@param name string module name below `codediff.`
local function internal(name)
  local ok, mod = pcall(require, "codediff." .. name)
  return ok and type(mod) == "table" and mod or nil
end

local function tabpage(tab)
  if tab == nil or tab == 0 then return vim.api.nvim_get_current_tabpage() end
  return tab
end

local function raw_session(tab)
  local lifecycle = internal("ui.lifecycle")
  if not lifecycle or type(lifecycle.get_session) ~= "function" then return nil end
  local ok, session = pcall(lifecycle.get_session, tabpage(tab))
  return ok and type(session) == "table" and session or nil
end

local function valid_buf(buf)
  return type(buf) == "number" and vim.api.nvim_buf_is_valid(buf) and buf or nil
end

local function panel_view(s)
  return type(s.panel) == "table" and type(s.panel.view) == "table" and s.panel.view or nil
end

--- The session's buffers by role. "panel" is the explorer or history list.
local function session_buffers(s)
  local view = panel_view(s)
  return {
    original = valid_buf(s.original_bufnr),
    modified = valid_buf(s.modified_bufnr),
    result = valid_buf(s.result_bufnr),
    panel = view and valid_buf(view.bufnr) or nil,
  }
end

---@param s table raw session
---@return "status"|"staged"|"revision"|"revisions"|"history"|"dir"|"file"
local function mode_of(s)
  local panel = type(s.panel) == "table" and s.panel or nil
  if not panel then return "file" end
  if panel.name == "history" then return "history" end
  if not s.git_root then return "dir" end
  local data = type(panel.data) == "table" and panel.data or {}
  if not data.base_revision and not data.target_revision then return "status" end
  if data.target_revision == ":0" then return "staged" end
  if data.target_revision and data.target_revision ~= "WORKING" then return "revisions" end
  return "revision"
end

--- A copy of the session for `tab` (0 = current), or nil when it has no view.
---
--- `mode`: "status" (`:CodeDiff`, Staged/Changes/Conflicts groups),
--- "revision" (rev vs working tree), "revisions" (rev vs rev), "staged"
--- (`--staged`, rev vs index), "history", "dir" or "file" (no panel).
--- original/modified are `{ relative, absolute }` real paths even when that
--- side is a codediff:// buffer, and `""` on the missing side of an added or
--- deleted file. A nil revision is the working tree, ":0" the index.
---@param tab? integer
---@return table?
function M.session(tab)
  tab = tabpage(tab)
  local s = raw_session(tab)
  if not s then return nil end
  local view = panel_view(s)
  local data = type(s.panel) == "table" and type(s.panel.data) == "table" and s.panel.data or {}
  return {
    tabpage = tab,
    mode = mode_of(s),
    git_root = s.git_root,
    original = vim.deepcopy(s.original),
    modified = vim.deepcopy(s.modified),
    original_revision = s.original_revision,
    modified_revision = s.modified_revision,
    source_revisions = vim.deepcopy(s.source_revisions),
    base_revision = data.base_revision,
    target_revision = data.target_revision,
    selection = vim.deepcopy(data.current_selection),
    original_bufnr = s.original_bufnr,
    modified_bufnr = s.modified_bufnr,
    result_bufnr = s.result_bufnr,
    original_win = s.original_win,
    modified_win = s.modified_win,
    result_win = s.result_win,
    layout = s.layout,
    single_side = s.single_side,
    conflict = s.merge == true,
    panel = type(s.panel) == "table" and s.panel.name or nil,
    panel_bufnr = view and view.bufnr or nil,
    panel_win = view and view.winid or nil,
  }
end

local function range_copy(r)
  return { start_line = r.start_line, end_line = r.end_line }
end

--- The displayed hunk under the cursor of `win` (default: current window).
---
--- Same rule as CodeDiff's own find_hunk_at_cursor: lines are 1-based and
--- end_line is exclusive; an empty range (one side has no lines) matches at
--- its start line. `side` is the pane the cursor is in; the inline layout
--- only has the modified one.
---@param tab? integer
---@param win? integer
---@return { index: integer, side: "original"|"modified", original: table, modified: table }?
function M.hunk_at_cursor(tab, win)
  local s = raw_session(tab)
  local result = s and type(s.stored_diff_result) == "table" and s.stored_diff_result or nil
  if not result or type(result.changes) ~= "table" then return nil end
  win = (win == nil or win == 0) and vim.api.nvim_get_current_win() or win
  if not vim.api.nvim_win_is_valid(win) then return nil end
  local buf = vim.api.nvim_win_get_buf(win)
  local side
  if s.layout ~= "inline" and buf == s.original_bufnr then
    side = "original"
  elseif buf == s.modified_bufnr then
    side = "modified"
  else
    return nil
  end
  local line = vim.api.nvim_win_get_cursor(win)[1]
  for i, change in ipairs(result.changes) do
    local r = change[side]
    if type(r) == "table" and ((line >= r.start_line and line < r.end_line)
        or (r.start_line == r.end_line and line == r.start_line)) then
      return { index = i, side = side, original = range_copy(change.original), modified = range_copy(change.modified) }
    end
  end
  return nil
end

local function same_range(a, b)
  return a.start_line == b.start_line and a.end_line == b.end_line
end

--- The hunk under the cursor, only if it is still what both buffers hold.
---
--- Recomputes the diff from the two buffers' current text with CodeDiff's
--- own engine and options, and returns the displayed hunk when the fresh
--- result has the same ranges. A view that has not caught up with an edit or
--- an external write yet answers nil, so nothing acts on stale ranges.
---@param tab? integer
---@param win? integer
---@return table? hunk, string? reason
function M.fresh_hunk(tab, win)
  local shown = M.hunk_at_cursor(tab, win)
  if not shown then return nil, "no hunk under the cursor" end
  local s = raw_session(tab)
  local diff, render = internal("core.diff"), internal("ui.view.render")
  local original, modified = valid_buf(s.original_bufnr), valid_buf(s.modified_bufnr)
  if not diff or type(diff.compute_diff) ~= "function" or not original or not modified then
    return nil, "CodeDiff's diff engine is unavailable"
  end
  local options = render and type(render.diff_options) == "function" and render.diff_options() or {}
  local ok, result = pcall(diff.compute_diff,
    vim.api.nvim_buf_get_lines(original, 0, -1, false),
    vim.api.nvim_buf_get_lines(modified, 0, -1, false),
    options)
  if not ok or type(result) ~= "table" then return nil, "the diff could not be recomputed" end
  for _, change in ipairs(result.changes or {}) do
    if same_range(change.original, shown.original) and same_range(change.modified, shown.modified) then
      return shown
    end
  end
  return nil, "the hunk changed since it was displayed"
end

---------------------------------------------------------------------------
-- The panel entry under the cursor
---------------------------------------------------------------------------

local function str(v) return type(v) == "string" and v ~= "" and v or nil end

--- The file a commit row of a history panel stands for. A single file's
--- history follows one file (opts.file_path), and each of its rows is that
--- file as the working tree names it, which a digest can hash. CodeDiff's own
--- name for the commit, from `git log --follow --numstat`
--- (core/git/history.lua), is no use there: for the commit that renamed the
--- file it is `old => new` verbatim, or the old name alone where git printed
--- `dir/{old => new}`. Any other history gives the file CodeDiff listed for
--- the commit, a verbatim `old => new` reduced to the new name.
local function commit_file(s, data)
  local opts = type(s.panel.data) == "table" and type(s.panel.data.opts) == "table" and s.panel.data.opts or {}
  local followed = str(opts.file_path)
  if followed and not (type(s.git_root) == "string" and vim.fn.isdirectory(s.git_root .. "/" .. followed) == 1) then
    return followed
  end
  local listed = str(data.file_path)
  return listed and (listed:match("^.- => (.+)$") or listed) or followed
end

--- The explorer or history entry on the cursor line of `win` (default: the
--- panel's own window), as plain data, for review feedback on a file rather
--- than a hunk (lua/ai/review/feedback.lua). Read from the panel's tree
--- (panel.view.tree:get_node(line)), as CodeDiff's own explorer keys do.
---
--- `type` is "file", "directory", "group" (a status group), "commit" or
--- "title" (history). A file has `path` (relative to the repository),
--- `status` (M, A, D, R, ?? ...), `old_path` for a rename and, in the status
--- view, `group` ("staged", "unstaged", "conflicts"); in history `commit` is
--- the commit it belongs to. A history commit has `commit`, `short_hash`,
--- `subject` and, in a single file's history, that file as `path`, as the
--- working tree names it (commit_file). nil when `win` does not show the
--- panel or its line holds no entry.
---@param tab? integer
---@param win? integer
---@return { panel: "explorer"|"history", type: string, path?: string, old_path?: string, status?: string, group?: string, commit?: string, short_hash?: string, subject?: string }?
function M.panel_item(tab, win)
  local s = raw_session(tab)
  local view = s and panel_view(s)
  local tree = view and view.tree
  if type(tree) ~= "table" or type(tree.get_node) ~= "function" or not valid_buf(view.bufnr) then return nil end
  if win == nil or win == 0 then win = view.winid end
  if type(win) ~= "number" or not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_buf(win) ~= view.bufnr then
    return nil
  end
  local line = vim.api.nvim_win_get_cursor(win)[1]
  local ok, node = pcall(tree.get_node, tree, line)
  local data = ok and type(node) == "table" and type(node.data) == "table" and node.data or nil
  if not data then return nil end
  -- Explorer files carry no type; every other node names its own.
  local kind = str(data.type) or (str(data.path) and "file") or nil
  if not kind then return nil end
  local path = str(data.path)
  if kind == "commit" and not path then path = commit_file(s, data) end
  return {
    panel = s.panel.name,
    type = kind,
    path = path,
    old_path = str(data.old_path),
    status = str(data.status),
    group = str(data.group),
    commit = str(data.commit_hash) or (kind == "commit" and str(data.hash)) or nil,
    short_hash = str(data.short_hash),
    subject = str(data.subject),
  }
end

--- Unstage the hunk under the cursor through CodeDiff itself.
---
--- Only correct where upstream allows it: the right side is the index (":0"),
--- i.e. the status view's Staged group, where the left side is HEAD.
---@param tab? integer
---@return boolean ran
function M.unstage_hunk(tab)
  tab = tabpage(tab)
  local s, hunk = raw_session(tab), internal("ui.view.actions.hunk")
  if not s or not hunk or type(hunk.unstage_hunk) ~= "function" then return false end
  hunk.unstage_hunk({
    tabpage = tab,
    original_bufnr = s.original_bufnr,
    modified_bufnr = s.modified_bufnr,
    is_inline = s.layout == "inline",
  })
  return true
end

--- Have CodeDiff recompute the view in `tab` (0 = current) the way its file
--- watcher does: list, read and diff again. For a guard that refused because
--- the view is behind the files (util.codediff_actions), so that the view
--- catches up instead of waiting for the next file event.
---@param tab? integer
---@return boolean requested false when `tab` has no view or CodeDiff has no refresh
function M.refresh(tab)
  tab = tabpage(tab)
  local refresh = internal("ui.refresh")
  if not raw_session(tab) or not refresh or type(refresh.request) ~= "function" then return false end
  return (pcall(refresh.request, tab, { full = true }))
end

local TARGETS = {
  all = { "original", "modified", "result", "panel" },
  panes = { "original", "modified", "result" },
  panel = { "panel" },
  original = { "original" },
  modified = { "modified" },
  result = { "result" },
}

---@class util.codediff.Key
---@field [1] string|string[] mode(s)
---@field [2] string lhs
---@field [3] function rhs
---@field desc string
---@field on? "all"|"panes"|"panel"|"original"|"modified"|"result" which buffers (default "all")
---@field opts? table more vim.keymap.set options (nowait, expr, ...)

--- Map keys on the view in `tab` through CodeDiff's keymap registry.
---
--- The registry is what makes these safe on the real file buffers a view
--- borrows: it snapshots any buffer-local mapping there, suspends the claim
--- while another tabpage is current, and hands the key back when the file
--- leaves the view or the view closes. Panel keys stay installed throughout,
--- as CodeDiff's own do.
---
--- Call it again after every `User CodeDiffKeys`: a file switch or a refresh
--- swaps the pane buffers, and the new ones start without these keys. With a
--- `scope`, a claim the previous pass of that scope made and this one does
--- not repeat is released, so a key that no longer applies goes away.
---@param tab? integer
---@param specs util.codediff.Key[]
---@param scope? string
---@return boolean installed false when `tab` has no view
function M.set_keys(tab, specs, scope)
  tab = tabpage(tab)
  local s, lifecycle = raw_session(tab), internal("ui.lifecycle")
  if not s or not lifecycle or type(lifecycle.set_buf_keymap) ~= "function" then return false end
  local scoped = scope and type(lifecycle.begin_keymap_scope) == "function"
    and type(lifecycle.end_keymap_scope) == "function"
  if scoped then lifecycle.begin_keymap_scope(tab, scope) end
  local buffers = session_buffers(s)
  for _, spec in ipairs(specs) do
    for _, role in ipairs(TARGETS[spec.on or "all"] or {}) do
      local buf = buffers[role]
      if buf then
        local opts = vim.tbl_extend("force", { silent = true, desc = spec.desc }, spec.opts or {})
        pcall(lifecycle.set_buf_keymap, tab, buf, spec[1], spec[2], spec[3], opts, { suspendable = role ~= "panel" })
      end
    end
  end
  if scoped then lifecycle.end_keymap_scope(tab, scope) end
  return true
end

local function has_panel_window(tab)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
    if vim.list_contains(M.PANEL_FILETYPES, vim.bo[vim.api.nvim_win_get_buf(win)].filetype) then
      return true
    end
  end
  return false
end

--- A tabpage CodeDiff has let go of while its panel is still on screen. `:e`
--- in a revision pane, closing a diff pane, or a pane's buffer wiped while
--- the tabpage was hidden all end the session and leave the tabpage behind,
--- and nothing in it responds any more.
local function is_orphan(tab)
  return vim.api.nvim_tabpage_is_valid(tab) and raw_session(tab) == nil and has_panel_window(tab)
end

local function close_tab(tab)
  if #vim.api.nvim_list_tabpages() == 1 then vim.cmd("tabnew") end
  pcall(vim.cmd, vim.api.nvim_tabpage_get_number(tab) .. "tabclose")
end

--- Close the view in `tab` (0 = current), and only that tabpage.
---
--- A tabpage CodeDiff abandoned (see is_orphan) is closed as well. Anything
--- else is left alone: false means there was no view to close.
---@param tab? integer
---@return boolean
function M.close(tab)
  tab = tabpage(tab)
  if not vim.api.nvim_tabpage_is_valid(tab) then return false end
  local lifecycle = internal("ui.lifecycle")
  if raw_session(tab) and lifecycle and type(lifecycle.close) == "function" then
    -- CodeDiff's own close, which `:CodeDiff` without arguments runs for the
    -- current tabpage; it asks first about unsaved conflict results.
    lifecycle.close(tab)
    return true
  end
  if is_orphan(tab) then
    close_tab(tab)
    return true
  end
  return false
end

local function real(path)
  return type(path) == "string" and (vim.uv.fs_realpath(path) or path) or nil
end

local function full_sha(rev)
  return type(rev) == "string" and (#rev == 40 or #rev == 64) and rev:match("^%x+$") and rev or nil
end

-- :CodeDiff's subcommands; its first argument is a revision otherwise.
local SUBCOMMANDS = { history = true, file = true, dir = true, merge = true, pr = true, install = true }

--- What the view an open() asks for will be, as far as `spec` and `args`
--- say: the root it names; a status, staged or history view; the revisions
--- given as full shas, which is what CodeDiff keeps once rev-parse has
--- resolved them. A `-C` in `args` (no `root`) leaves the root open.
---@return util.codediff.Pending
local function expectation(spec, args)
  local want = { root = real(spec.root) }
  local positional, staged, i = {}, false, 1
  while i <= #args and args[i] ~= "--" do
    local a = args[i]
    if a == "-C" or a == "--repo" then
      i = i + 1
    elseif a == "--staged" or a == "--cached" then
      staged = true
    elseif a:sub(1, 1) ~= "-" then
      positional[#positional + 1] = a
    end
    i = i + 1
  end
  if positional[1] == "history" then
    want.mode = "history"
  elseif staged then
    want.mode, want.base = "staged", full_sha(positional[1])
  elseif #positional == 0 then
    want.mode = "status"
  elseif not SUBCOMMANDS[positional[1]] then
    want.base, want.target = full_sha(positional[1]), full_sha(positional[2])
  end
  return want
end

--- Does the view `s` (M.session) fit what open `p` asked for?
local function fits(p, s)
  return (not p.root or real(s.git_root) == p.root)
    and (not p.mode or s.mode == p.mode)
    and (not p.base or s.base_revision == p.base)
    and (not p.target or s.target_revision == p.target)
end

local function specificity(p)
  return (p.root and 1 or 0) + (p.mode and 1 or 0) + (p.base and 1 or 0) + (p.target and 1 or 0)
end

local function unqueue(p)
  for i, q in ipairs(pending) do
    if q == p then
      table.remove(pending, i)
      return true
    end
  end
  return false
end

--- End the open `p`, still pending: its view is `tab`, or nil and `why`.
local function settle(p, tab, why)
  if not unqueue(p) or not p.done then return end
  local ok, err = pcall(p.done, tab, why)
  if not ok then
    vim.notify("CodeDiff: an open's callback failed: " .. tostring(err), vim.log.levels.WARN, { title = "CodeDiff" })
  end
end

--- The pending open the view in `tab` answers: the one that asks for the
--- most of what it is, the oldest of those.
local function claim(tab)
  local s = M.session(tab)
  if not s then return nil end
  local best, rank
  local now = vim.uv.now()
  for _, p in ipairs(pending) do
    if now - p.at <= PENDING_MS and fits(p, s) and (not best or specificity(p) > rank) then
      best, rank = p, specificity(p)
    end
  end
  return best
end

--- CodeDiff answers an empty revision listing with "No changes to show" and
--- no view (commands/handlers/explorer.lua): the opens waiting for a view of
--- that root and revision end there. Not while a view of them is open: the
--- listing may be its refresh.
local function refused(git_root, revision)
  local root = real(git_root)
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    local s = M.session(tab)
    if s and s.base_revision == revision and real(s.git_root) == root then return end
  end
  local ended = vim.tbl_filter(function(p)
    return p.base == revision and not p.mode and not p.target and (not p.root or p.root == root)
  end, pending)
  for _, p in ipairs(ended) do settle(p, nil, "CodeDiff found no changes to show") end
end

--- Open a CodeDiff view.
---
--- `args` are `:CodeDiff`'s arguments, passed as a list so a path with
--- spaces stays one argument. `root` adds `-C <root>` unless `args` has it,
--- escaped for the expand() CodeDiff runs on that value; a `-C` value in
--- `args` is passed as given. Revisions are best passed as shas: CodeDiff
--- reads a name like `history` as its subcommand.
--- `label` (vim.t.codediff_label, shown in the statusline) and `tab_vars`
--- land on the view's tabpage when it opens; CodeDiff opens asynchronously,
--- after its git commands return. They land only on a view that fits the
--- spec -- the `root` it names, a status or history view where `args` ask
--- for one, the revisions `args` give as full shas -- so another view that
--- opens meanwhile, from another open() or a typed :CodeDiff, never takes
--- them. `quiet` leaves out the "Comparing <label>" notice, for a caller
--- that says what the view compares itself.
---
--- `done(tab)` runs once the view has opened with them; `done(nil, why)`
--- when it will not: CodeDiff refused it for an empty listing, or it did not
--- open within PENDING_MS (CodeDiff refuses some opens with a notice of its
--- own and no event). Exactly once for an open() that returned true.
---
--- An empty `args` in a tabpage that already has a view is refused: a bare
--- `:CodeDiff` there closes the view instead of opening one.
---@param spec { args?: string[], root?: string, label?: string, tab_vars?: table<string, any>, quiet?: boolean, done?: fun(tab?: integer, why?: string) }
---@return boolean issued
function M.open(spec)
  spec = spec or {}
  local args = vim.deepcopy(spec.args or {})
  if spec.root and not vim.list_contains(args, "-C") and not vim.list_contains(args, "--repo") then
    -- CodeDiff passes -C through vim.fn.expand() (commands/parse.lua,
    -- to_global_opts), which reads `$app` in a root as a variable and `*`,
    -- `[` or `{` as a glob. Escaped, expand() returns the path as it was.
    table.insert(args, 1, vim.fn.fnameescape(spec.root))
    table.insert(args, 1, "-C")
  end
  if #args == 0 and raw_session(0) then
    vim.notify("This tab already shows a CodeDiff view; <leader>gq closes it", vim.log.levels.WARN, { title = "CodeDiff" })
    return false
  end
  local p = expectation(spec, args)
  p.label, p.tab_vars, p.quiet, p.done, p.at = spec.label, spec.tab_vars, spec.quiet, spec.done, vim.uv.now()
  pending[#pending + 1] = p
  vim.defer_fn(function() settle(p, nil, "the view did not open") end, PENDING_MS)
  local ok, err = pcall(vim.cmd.CodeDiff, { args = args })
  if not ok then
    -- The caller gets the error; nothing waits for a view.
    unqueue(p)
    error(err, 0)
  end
  return true
end

local function short(rev)
  if type(rev) ~= "string" then return nil end
  return rev:match("^%x+$") and #rev > 12 and rev:sub(1, 8) or rev
end

--- A label for a view CodeDiff opened without open(), e.g. a typed command.
local function default_label(s)
  local mode = mode_of(s)
  if mode == "status" then return "index/HEAD ↔ working tree" end
  if mode == "history" then return "history" end
  if mode == "dir" then return "directory diff" end
  if mode == "file" then return "file diff" end
  local data = s.panel.data
  local requested = type(data.source_revisions) == "table" and data.source_revisions or {}
  local from = short(requested.original) or short(data.base_revision) or "?"
  if mode == "staged" then return from .. " → index" end
  if mode == "revision" then return from .. " → working tree" end
  return from .. " → " .. (short(requested.modified) or short(data.target_revision) or "?")
end

-- The two global prefixes a view cannot survive: a `;` picker lands its file
-- in the working-tree pane, which desynchronises the view, and the `s` window
-- keys close or reshape panes, and closing one tears the session down. On
-- every buffer of the view, nowait so a fast `;f` cannot slip past to the
-- global mapping.
--
-- nowait alone only stops the prefix key: the one after it then ran as a
-- command of its own, so `so` opened a line in Insert mode and `;f` started a
-- flash jump. Swallow it too, when it comes within 'timeoutlen' -- the time
-- the real prefix would have waited for it. Keys that arrive together (a
-- macro, `:normal ;f`) still reach the global mapping: Vim prefers the
-- longer match for keys already typed (:help map-nowait).
---@param prefix? boolean swallow the key that follows, as above
local function blocked(key, hint, prefix)
  return function()
    vim.notify(("%s is disabled in CodeDiff\n%s"):format(key, hint), vim.log.levels.WARN, { title = "CodeDiff" })
    if prefix and vim.wait(vim.o.timeoutlen, function() return vim.fn.getchar(1) ~= 0 end, 10) then
      vim.fn.getcharstr()
    end
  end
end
local LEAVE = "gf opens this file in the previous tab\n<leader>gq closes the view"
local BLOCKS = {
  { "n", ";", blocked(";", LEAVE, true), desc = "Disabled in CodeDiff", opts = { nowait = true } },
  { "n", "s", blocked("s", "<C-w> still moves between windows\n<leader>gq closes the view", true),
    desc = "Disabled in CodeDiff", opts = { nowait = true } },
}
-- The keys off `;` that put another buffer in the current window do the same
-- as a `;` picker: bufferline's H/L, [b/]b and [B/]B (first/last), and the
-- alternate buffer (<C-^>, and <C-6> through it; `;a` is already under `;`).
-- Neither the panes nor the nofile panels are 'winfixbuf', so each swapped the
-- window's buffer under a session that stayed alive. Oil's `-` is the same,
-- and own_keys blocks it where it is not the status explorer's stage key.
-- Whole keys rather than prefixes, so the key after one is the user's next
-- command and is left alone.
for _, key in ipairs({ "H", "L", "[b", "]b", "[B", "]B", "<C-^>" }) do
  BLOCKS[#BLOCKS + 1] = { "n", key, blocked(key, LEAVE), desc = "Disabled in CodeDiff", opts = { nowait = true } }
end

--- Native wheel scrolling leaves the other pane behind: measured, neither a
--- wheel over an unfocused pane nor one over the focused pane moves its
--- scrollbind partner. Running the wheel key inside nvim_win_call on the
--- hovered pane -- focused or not -- does; win_call restores focus, and Nvim
--- still handles filler, folds and 'mousescroll'. The panel scrolls on its
--- own, as it always did.
local function wheel(tab, key)
  return function()
    local function scroll() vim.cmd.normal({ args = { vim.keycode(key) }, bang = true }) end
    local target = vim.fn.getmousepos().winid
    local s = raw_session(tab)
    if s and vim.api.nvim_win_is_valid(target)
      and (target == s.original_win or target == s.modified_win or target == s.result_win) then
      vim.api.nvim_win_call(target, scroll)
      return
    end
    scroll()
  end
end

local function panel_action(tab, fn)
  return function()
    local s = raw_session(tab)
    local view = s and panel_view(s)
    if view then fn(view, view.tree) end
  end
end

local function own_keys(tab, s)
  local keys = vim.deepcopy(BLOCKS)
  for _, direction in ipairs({ "Up", "Down" }) do
    local key = "<ScrollWheel" .. direction .. ">"
    keys[#keys + 1] = { { "n", "x" }, key, wheel(tab, key), desc = "Scroll " .. direction:lower() .. " (sync diff panes)" }
  end
  -- ]h/[h are this config's hunk keys (gitsigns' everywhere else). In the
  -- panes they would walk gitsigns' index hunks of the working-tree file, not
  -- the hunks on screen, and nothing in a revision pane; here they are
  -- CodeDiff's own ]c/[c, through its public API, in every buffer of the view
  -- as ]c is: from the explorer or history panel they jump into the right pane.
  for _, k in ipairs({ { "]h", "next_hunk", "Next hunk" }, { "[h", "prev_hunk", "Prev hunk" } }) do
    keys[#keys + 1] = { "n", k[1], function()
      local ok, codediff = pcall(require, "codediff")
      if ok and type(codediff) == "table" and type(codediff[k[2]]) == "function" then codediff[k[2]]() end
    end, desc = k[3] }
  end
  -- q leaves the diff panes to macro recording.
  keys[#keys + 1] = { "n", "q", function() M.close(tab) end, desc = "Close diff view",
    on = "panel", opts = { nowait = true } }
  -- The explorer's file-level index keys, in the status view only: in a
  -- revision view CodeDiff's X runs `git clean` on any file the index does
  -- not track, including ones the revision merely contains.
  local actions = internal("ui.explorer.actions")
  local stages = false
  if mode_of(s) == "status" and actions then
    for _, k in ipairs({
      { "-", "toggle_stage_entry", "Stage/unstage file" },
      { "S", "stage_all",          "Stage all files" },
      { "U", "unstage_all",        "Unstage all files" },
      { "X", "restore_entry",      "Discard file changes…" },
    }) do
      if type(actions[k[2]]) == "function" then
        keys[#keys + 1] = { "n", k[1], panel_action(tab, actions[k[2]]), desc = k[3], on = "panel", opts = { nowait = true } }
        stages = stages or k[1] == "-"
      end
    end
  end
  -- Everywhere else in the view `-` would be oil's parent directory, opened
  -- in place of the pane or panel (see BLOCKS).
  keys[#keys + 1] = { "n", "-", blocked("-", LEAVE), desc = "Disabled in CodeDiff",
    on = stages and "panes" or "all", opts = { nowait = true } }
  return keys
end

--- Give the <localleader>g prefix a "Conflict" which-key group label where
--- conflict maps actually exist (it would otherwise show as an unnamed
--- prefix). pcall: cosmetic only, must not break the view if which-key is
--- absent.
local function label_conflict_group(s)
  -- nvim_buf_get_keymap reports lhs with the leader already expanded.
  local probe = (vim.g.maplocalleader or "\\") .. "go"
  for _, buf in pairs(session_buffers(s)) do
    for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
      if m.lhs == probe then
        pcall(function()
          require("which-key").add({ { "<localleader>g", group = "Conflict", mode = "n", buffer = buf } })
        end)
        break
      end
    end
  end
end

local function install(tab)
  local s = raw_session(tab)
  if not s then return end
  M.set_keys(tab, own_keys(tab, s), "config")
  label_conflict_group(s)
  vim.api.nvim_exec_autocmds("User", { pattern = "CodeDiffKeys", modeline = false, data = { tabpage = tab } })
end

--- Install the view's keys once the current event has settled: CodeDiff
--- builds a view and swaps pane buffers from scheduled callbacks, and maps
--- its own keys on the new buffers right after the swap.
local function schedule_install(tab)
  if queued[tab] then return end
  queued[tab] = true
  vim.schedule(function()
    queued[tab] = nil
    install(tab)
  end)
end

local function on_open(tab)
  if type(tab) ~= "number" or not vim.api.nvim_tabpage_is_valid(tab) then return end
  local p = claim(tab)
  local s = raw_session(tab)
  local label = p and p.label or (s and default_label(s))
  vim.t[tab].blocks_global_prefixes = true
  vim.t[tab].codediff_label = label
  local names = {}
  for name, value in pairs(p and p.tab_vars or {}) do
    vim.t[tab][name] = value
    names[#names + 1] = name
  end
  tab_vars[tab] = names
  if label and not (p and p.quiet) then vim.notify("Comparing " .. label, vim.log.levels.INFO, { title = "CodeDiff" }) end
  schedule_install(tab)
  if p then settle(p, tab) end
end

local function clear_vars(tab)
  local names = tab_vars[tab] or {}
  tab_vars[tab] = nil
  if not vim.api.nvim_tabpage_is_valid(tab) then return end
  vim.t[tab].blocks_global_prefixes = nil
  vim.t[tab].codediff_label = nil
  for _, name in ipairs(names) do vim.t[tab][name] = nil end
end

--- Tidy a tabpage whose view is gone: drop the variables on_open set (only
--- those -- another view may set blocks_global_prefixes too) and close the
--- tabpage if CodeDiff left its panel behind (is_orphan).
local function sweep(tab)
  if not vim.api.nvim_tabpage_is_valid(tab) or raw_session(tab) then return end
  if tab_vars[tab] then clear_vars(tab) end
  if has_panel_window(tab) then
    close_tab(tab)
    vim.notify("The diff view lost a pane, so its tab was closed", vim.log.levels.INFO, { title = "CodeDiff" })
  end
end

local function on_close(tab)
  if type(tab) ~= "number" then return end
  clear_vars(tab)
  -- CodeDiffClose fires inside the teardown, before the session is gone;
  -- look once it has finished.
  vim.schedule(function() sweep(tab) end)
end

--- Pass `-c core.quotePath=false` to every git command CodeDiff runs.
---
--- Its revision and history modes parse `--name-status` without -z, and its
--- unquoting skips octal escapes, so `中文.txt` became `344270255346226207.txt`.
--- Not GIT_CONFIG_* in the environment: the agent terminals would inherit it.
--- Has to run before codediff.core.git.* load -- each takes the function into
--- a local -- which is why setup() does it before CodeDiff's own setup.
local function patch_runner()
  local runner = internal("core.git.runner")
  if not runner or type(runner.run_async) ~= "function" or runner.nvim_config_patched then return end
  for _, name in ipairs({ "changes", "history", "statistics", "content", "worktree", "refs", "repository", "revision" }) do
    if package.loaded["codediff.core.git." .. name] then
      warn_once("runner", "codediff.core.git." .. name .. " loaded before util.codediff could patch its runner;"
        .. " non-ASCII paths may be garbled in revision views")
      break
    end
  end
  local run_async = runner.run_async
  runner.run_async = function(args, opts, callback)
    local argv = { "-c", "core.quotePath=false" }
    vim.list_extend(argv, args or {})
    return run_async(argv, opts, callback)
  end
  runner.nvim_config_patched = true
end

--- Apply `limit_of()` where CodeDiff caps a history listing at 100.
---
--- `:CodeDiff history` without a range is the one call that sets a limit,
--- and both the first listing (commands/handlers/history.lua) and every
--- refresh (ui/refresh/panel.lua) reach get_commit_list through the
--- codediff.core.git table at call time. `false` lifts the cap. A history
--- with a range never had one.
---@param limit_of fun(): integer|false
local function patch_history(limit_of)
  local git = internal("core.git")
  if not git or type(git.get_commit_list) ~= "function" or git.nvim_config_patched then return end
  local get_commit_list = git.get_commit_list
  git.get_commit_list = function(range, root, opts, callback)
    if (range == nil or range == "") and type(opts) == "table" and opts.limit == 100 then
      local ok, limit = pcall(limit_of)
      if ok and (limit == false or type(limit) == "number") then
        opts = vim.deepcopy(opts)
        opts.limit = limit or nil
      end
    end
    return get_commit_list(range, root, opts, callback)
  end
  git.nvim_config_patched = true
end

---------------------------------------------------------------------------
-- The listing patch: what a revision-vs-working-tree view lists
---------------------------------------------------------------------------

-- Upstream lists `:CodeDiff <rev>` with `git diff --name-status <rev>` plus
-- `ls-files --others` (core/git/changes.lua, get_diff_revision). Both read
-- the real index, so a path the revision has and the index does not -- an
-- untracked file a baseline captured, or one a branch tracks and this
-- checkout leaves untracked -- was listed twice, as a D and a ??, and a plain
-- `mv` as D + ?? instead of R. The replacement lists what the two trees
-- differ in: util.baseline snapshots the working tree into a tree of its own
-- (a temporary index, never the real one; untracked files included, ignored
-- ones not, whatever explorer.untracked says) and `diff-tree -M <rev> <tree>`
-- compares them. The right pane is still the real, editable file.
--
-- It replaces the function for every caller: statistics.lua looks it up on
-- the changes table at call time, for the first listing and every refresh.
-- That holds while explorer.line_stats is off (lua/plugin/vcs/codediff.lua);
-- with line stats on, their numbers would still come from upstream's
-- `git diff <rev>` (core/git.lua, get_diff_revision_with_line_stats).
--
-- The snapshot is the cost: one per refresh, coalesced in util.baseline's
-- queue behind any prompt's baseline. Its temporary index lives in the
-- gitdir, where CodeDiff's watcher does not look, so it never triggers the
-- refresh that would take the next one.

-- buf -> mtime of its file when the buffer last matched it: read, written,
-- or a change on disk that :checktime handled. Recorded from the first
-- CodeDiff use on; first_unsaved_change() stands in for older buffers.
local synced = {}
local unsaved_noticed = {} ---@type table<string, true> "buf:mtime" told about
local skipped_noticed = {} ---@type table<string, table<string, true>> view key -> paths told about

local function file_mtime(path)
  local st = path and vim.uv.fs_stat(path)
  if not st then return nil end
  return st.mtime.sec + st.mtime.nsec / 1e9, ("%d.%09d"):format(st.mtime.sec, st.mtime.nsec)
end

--- Stands in for when a buffer read before the records began last matched
--- its file: the time of its first change since it was last written (or
--- read). That is no earlier than the match, so a file changed after it has
--- really changed; one changed in between is missed. nil when the undo tree
--- cannot say.
local function first_unsaved_change(buf)
  local ok, tree = pcall(vim.fn.undotree, buf)
  if not ok or type(tree) ~= "table" then return nil end
  local function walk(entries, visit)
    for _, e in ipairs(entries or {}) do
      visit(e)
      walk(e.alt, visit)
    end
  end
  local saved_at, first = 0, nil
  walk(tree.entries, function(e)
    if e.save and e.save == tree.save_last then saved_at = e.seq end
  end)
  walk(tree.entries, function(e)
    if e.seq > saved_at and (not first or e.time < first) then first = e.time end
  end)
  return first
end

--- CodeDiff never reloads a modified buffer, so a file changed on disk under
--- unsaved edits shows the buffer's text without a word (measured). Say it
--- once per buffer and disk mtime, for the files this listing shows, and
--- leave the choice to the user.
local function notice_unsaved(git_root, entries)
  local top = vim.uv.fs_realpath(git_root) or git_root
  local listed = {}
  for _, e in ipairs(entries) do
    if e.status ~= "D" then listed[e.path] = true end
  end
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].modified and vim.bo[buf].buftype == "" then
      local name = vim.api.nvim_buf_get_name(buf)
      local real = name ~= "" and not name:match("^%w+://") and vim.uv.fs_realpath(name) or nil
      local rel = real and vim.fs.relpath(top, real)
      if rel and listed[rel] then
        local mtime, stamp = file_mtime(real)
        local since = synced[buf] or first_unsaved_change(buf)
        local key = ("%d:%s"):format(buf, tostring(stamp))
        if mtime and since and mtime > since and not unsaved_noticed[key] then
          unsaved_noticed[key] = true
          vim.notify(("%s: unsaved changes here, and the file changed on disk since\n"
            .. ":e! takes the disk's version; :w keeps yours and overwrites the disk's"):format(rel),
            vim.log.levels.WARN, { title = "CodeDiff" })
        end
      end
    end
  end
end

local function view_key(git_root, revision)
  return tostring(git_root) .. "\0" .. tostring(revision)
end

local function size_text(bytes)
  local mib = 1024 * 1024
  if bytes >= mib and bytes % mib == 0 then return ("%d MiB"):format(bytes / mib) end
  return ("%d bytes"):format(bytes)
end

local function size_reason()
  local ok, settings = pcall(function() return require("ai.review.config").get() end)
  local limit = ok and settings.max_file_size and size_text(settings.max_file_size) or "the size limit"
  return ("untracked, over %s; vim.g.ai_review.max_file_size"):format(limit)
end

-- Why a path is not compared, in the order every notice names them.
local LEFT_OUT = {
  { "size", size_reason },
  { "ignored", function() return "ignored, still on disk" end },
  { "other", function() return "still on disk, so not listed as deleted" end },
}

---The lines that name `left_out` (M.listing's), one per reason, in the order
---a view's own notice gives them: "Not compared (<why>): a, b". With
---`limit`, a line names that many paths and counts the rest.
---@param left_out table<string, string[]>
---@param limit? integer
---@return string[]
function M.left_out_lines(left_out, limit)
  local lines = {}
  for _, reason in ipairs(LEFT_OUT) do
    local paths = left_out[reason[1]] or {}
    if #paths > 0 then
      local named = limit and vim.list_slice(paths, 1, limit) or paths
      local more = #paths > #named and (" and %d more"):format(#paths - #named) or ""
      lines[#lines + 1] = ("Not compared (%s): %s%s"):format(reason[2](), table.concat(named, ", "), more)
    end
  end
  return lines
end

--- Say which paths a view cannot compare (M.listing's left_out), once per
--- path per view, in one notice with a line per reason.
---@param left_out table<string, string[]>
local function notice_left_out(key, left_out)
  local seen = skipped_noticed[key] or {}
  skipped_noticed[key] = seen
  local fresh = {}
  for reason, paths in pairs(left_out) do
    fresh[reason] = {}
    for _, path in ipairs(paths) do
      if not seen[path] then
        seen[path] = true
        table.insert(fresh[reason], path)
      end
    end
  end
  local lines = M.left_out_lines(fresh)
  if #lines == 0 then return end
  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "CodeDiff" })
end

--- `diff-tree -z --name-status` output as CodeDiff's status entries.
local function parse_name_status(out)
  local fields = vim.split(out, "\0", { plain = true })
  local entries, i = {}, 1
  while i <= #fields and fields[i] ~= "" do
    local letter = fields[i]:sub(1, 1)
    if letter == "R" or letter == "C" then
      assert(fields[i + 2], "truncated diff-tree output")
      entries[#entries + 1] = { status = letter, old_path = fields[i + 1], path = fields[i + 2] }
      i = i + 3
    else
      assert(fields[i + 1], "truncated diff-tree output")
      -- A type change (file <-> symlink) is shown as a modification.
      entries[#entries + 1] = { status = letter == "T" and "M" or letter, path = fields[i + 1] }
      i = i + 2
    end
  end
  return entries
end

--- Which of `paths` (relative to `toplevel`) git ignores: `cb(set)`, empty
--- when git cannot say. One batch, NUL-separated on stdin.
local function ignored_of(toplevel, paths, cb)
  local function answer(r)
    local set = {}
    if r.code == 0 then
      for _, path in ipairs(vim.split(r.stdout or "", "\0", { plain = true, trimempty = true })) do
        set[path] = true
      end
    end
    cb(set)
  end
  local ok, err = pcall(vim.system, require("util.baseline").git_cmd({ "check-ignore", "-z", "--stdin" }), {
    cwd = toplevel,
    stdin = table.concat(paths, "\0") .. "\0",
  }, function(r) vim.schedule(function() answer(r) end) end)
  if not ok then
    warn_once("check-ignore", "CodeDiff: git check-ignore failed: " .. tostring(err))
    vim.schedule(function() answer({ code = -1 }) end)
  end
end

--- `out`'s entries split into the listed ones, the D entries still on disk
--- that the snapshot skipped for size, and the other D entries still on disk.
local function sort_out(out, info)
  local skipped = {}
  for _, path in ipairs(info.skipped or {}) do skipped[path] = true end
  local listed, size, present = {}, {}, {}
  for _, e in ipairs(parse_name_status(out)) do
    if e.status == "D" and vim.uv.fs_lstat(info.toplevel .. "/" .. e.path) then
      table.insert(skipped[e.path] and size or present, e.path)
    else
      listed[#listed + 1] = e
    end
  end
  return listed, size, present
end

---What a view of `revision` against the working tree lists: the listing
---patch below, which every such view goes through, and a caller that has to
---know before it opens one whether CodeDiff will show anything -- it answers
---an empty listing with a bare "No changes to show" and no view (#582).
---`tree` and `info` are a util.baseline.snapshot() of the worktree at
---`root`; `diff-tree -M <revision> <tree>` compares them.
---
---`done({ listed, left_out })`: `listed` is CodeDiff's status entries
---({ status, path, old_path? }); `left_out` the paths not compared, by
---reason: "size" (untracked over max_file_size: every file the snapshot
---skipped, or under a pathspec the ones dropped below), "ignored" and
---"other" (dropped below). `done(nil, err)` when git failed. Says nothing
---itself; left_out_lines() words `left_out`.
---
---A D whose path is still on disk is not listed: the snapshot left the file
---out -- over max_file_size, ignored now (a .env a baseline captured before
---.gitignore named it), unreadable -- or something else is there. It is
---named instead, so it never reaches the one-sided "deleted since baseline"
---hint (util.codediff_actions), whose `git restore` overwrites whatever is
---at the path. Measured: it replaced a directory, untracked work in it
---included, with the old file, and on a case-insensitive file system (macOS
---by default) it wrote a file renamed in case only back over the new one.
---@param root string
---@param revision string
---@param tree string
---@param info { toplevel: string, skipped?: string[] }
---@param pathspec? string[]
---@param done fun(result?: { listed: table[], left_out: table<string, string[]> }, err?: string)
function M.listing(root, revision, tree, info, pathspec, done)
  local baseline = require("util.baseline")
  local args = { "-c", "core.quotePath=false", "diff-tree", "-r", "-M", "-z", "--name-status", revision, tree, "--" }
  vim.list_extend(args, pathspec or {})
  local spawned, err = pcall(vim.system, baseline.git_cmd(args), {
    cwd = root,
    -- A missing object must never become a fetch from a promisor remote.
    env = { GIT_NO_LAZY_FETCH = "1" },
  }, function(r)
    vim.schedule(function()
      if r.code ~= 0 then
        local why = (vim.split(vim.trim(r.stderr or ""), "\n")[1] or ""):gsub("^fatal: ", "")
        return done(nil, "git diff-tree: " .. (why ~= "" and why or ("exit " .. r.code)))
      end
      local ok, listed, size, present = pcall(sort_out, r.stdout or "", info)
      if not ok then return done(nil, tostring(listed)) end
      local function finish(ignored)
        local left_out = { size = size, ignored = {}, other = {} }
        for _, path in ipairs(present) do
          table.insert(ignored[path] and left_out.ignored or left_out.other, path)
        end
        -- Scoped to a pathspec, only the dropped paths are known to be in scope.
        if not (pathspec and #pathspec > 0) then left_out.size = vim.list_slice(info.skipped or {}) end
        done({ listed = listed, left_out = left_out })
      end
      if #present == 0 then return finish({}) end
      ignored_of(info.toplevel, present, finish)
    end)
  end)
  if not spawned then vim.schedule(function() done(nil, tostring(err)) end) end
end

---@param original function upstream's get_diff_revision
local function patched_listing(original)
  return function(revision, git_root, callback, pathspec)
    if type(revision) ~= "string" or type(git_root) ~= "string" then
      return original(revision, git_root, callback, pathspec)
    end
    local answered = false
    local function fallback(reason)
      if answered then return end
      answered = true
      warn_once("listing", ("CodeDiff's revision listing fell back to upstream's, which can show a path as"
        .. " both D and ?? (%s)"):format(reason))
      original(revision, git_root, callback, pathspec)
    end
    local function answer(result)
      if answered then return end
      answered = true
      for _, step in ipairs({
        { "left-out", "naming the files not compared", function()
          notice_left_out(view_key(git_root, revision), result.left_out)
        end },
        { "unsaved", "the unsaved-buffer check", function() notice_unsaved(git_root, result.listed) end },
        -- Before the callback, which is where CodeDiff gives up on the view.
        { "refused", "ending a refused open", function()
          if #result.listed == 0 then refused(git_root, revision) end
        end },
      }) do
        local ok, err = pcall(step[3])
        if not ok then warn_once(step[1], ("CodeDiff: %s failed: %s"):format(step[2], tostring(err))) end
      end
      -- Outside the pcall: an error in CodeDiff's callback is its own.
      vim.schedule(function() callback(nil, { unstaged = result.listed, staged = {} }) end)
    end
    local ok, err = pcall(function()
      require("util.baseline").snapshot(git_root, function(tree, info)
        if not tree then return fallback(tostring(info)) end
        M.listing(git_root, revision, tree, info, pathspec, function(result, why)
          if not result then return fallback(why) end
          answer(result)
        end)
      end)
    end)
    if not ok then fallback(tostring(err)) end
  end
end

--- Install the listing patch, and what keeps its notices honest: the buffer
--- records notice_unsaved() compares against, and a view's skipped-file
--- notices starting over once no view of that revision is open.
local function patch_listing()
  local changes = internal("core.git.changes")
  if not changes or type(changes.get_diff_revision) ~= "function" or changes.nvim_config_patched then return end
  local original = changes.get_diff_revision
  local patched = patched_listing(original)
  changes.get_diff_revision = patched
  -- core/git.lua keeps a copy on its facade; nothing calls it today.
  local git = internal("core.git")
  if git and git.get_diff_revision == original then git.get_diff_revision = patched end
  changes.nvim_config_patched = true

  local group = vim.api.nvim_create_augroup("util_codediff_listing", { clear = true })
  vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost", "FileChangedShellPost" }, {
    group = group,
    callback = function(ev)
      local name = vim.api.nvim_buf_get_name(ev.buf)
      synced[ev.buf] = name ~= "" and file_mtime(name) or nil
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    callback = function(ev) synced[ev.buf] = nil end,
  })
  local function key_of(s)
    local data = type(s.panel) == "table" and type(s.panel.data) == "table" and s.panel.data or {}
    return data.base_revision and view_key(s.git_root, data.base_revision) or nil
  end
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "CodeDiffClose",
    callback = function(ev)
      -- Still there: CodeDiffClose fires inside the teardown.
      local s = ev.data and type(ev.data.tabpage) == "number" and raw_session(ev.data.tabpage)
      local key = s and key_of(s)
      if not key then return end
      vim.schedule(function()
        for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
          local other = raw_session(tab)
          if other and key_of(other) == key then return end
        end
        skipped_noticed[key] = nil
      end)
    end,
  })
end

--- Re-install the view's keys whenever CodeDiff swaps a pane's buffer.
---
--- Every path that does -- a file picked in the explorer, a refresh, the
--- welcome page of an emptied list, a layout toggle -- goes through
--- lifecycle.update_buffers, looked up on the module table at call time, and
--- drops this view's claims on the buffers that leave. Neither
--- CodeDiffFileSelect (it fires before the swap) nor BufWinEnter (it never
--- fires for a file already shown in another tabpage) catches all of them.
local function hook_buffer_swaps()
  local lifecycle = internal("ui.lifecycle")
  if not lifecycle or type(lifecycle.update_buffers) ~= "function" or lifecycle.nvim_config_patched then return end
  local update_buffers = lifecycle.update_buffers
  lifecycle.update_buffers = function(tab, ...)
    local result = update_buffers(tab, ...)
    if type(tab) == "number" then schedule_install(tab) end
    return result
  end
  lifecycle.nvim_config_patched = true
end

--- Even out the two diff panes after a window appears or goes in the view's
--- tabpage. An agent panel opened beside a view (edgy's right bar) took all
--- its width from the neighbouring pane -- measured, 52 and 15 columns --
--- and closing it handed the space back to that pane alone. CodeDiff's own
--- layout.arrange re-splits the panes' combined width and re-pins the
--- explorer; it only runs for two side-by-side panes, since its single-pane
--- branch would take the whole width back from the agent panel.
---
--- Keyed on the number of windows, not on every resize, so a pane resized by
--- hand with <C-w> stays the size it was given.
local window_counts = {}
local function rebalance_on_resize()
  local tab = vim.api.nvim_get_current_tabpage()
  local s = raw_session(tab)
  if not s then
    window_counts[tab] = nil
    return
  end
  local count = #vim.tbl_filter(function(win) return vim.api.nvim_win_get_config(win).relative == "" end,
    vim.api.nvim_tabpage_list_wins(tab))
  if window_counts[tab] == count then return end
  window_counts[tab] = count
  vim.schedule(function()
    s = raw_session(tab)
    local layout = internal("ui.layout")
    if not s or not layout or type(layout.arrange) ~= "function" or s.layout == "inline" or s.single_side then return end
    for _, win in ipairs({ s.original_win, s.modified_win }) do
      if type(win) ~= "number" or not vim.api.nvim_win_is_valid(win) then return end
    end
    if s.original_win ~= s.modified_win then pcall(layout.arrange, tab) end
  end)
end

--- Set CodeDiff up: version check, the git patches, CodeDiff's own setup,
--- then the hooks that keep each view's tab variables and keys.
---
--- CodeDiff's setup loads its native library (and downloads it when it is
--- missing and VSCODE_DIFF_NO_AUTO_INSTALL is unset), so this runs from the
--- lazy spec's config, at first use, never at startup.
---@param opts table CodeDiff's options
---@param hooks? { history_limit?: fun(): integer|false }
function M.setup(opts, hooks)
  hooks = hooks or {}
  local version = internal("version")
  local found = version and version.VERSION
  degraded = found ~= M.VERSION
  if degraded then
    warn_once("version", ("CodeDiff %s is not the %s this config was written against; its path fix,"
      .. " revision listing and history limit are off (lua/util/codediff.lua)"):format(tostring(found), M.VERSION))
  else
    patch_runner()
    -- After the runner: loading core.git.changes captures its run_async.
    patch_listing()
    if hooks.history_limit then patch_history(hooks.history_limit) end
  end

  require("codediff").setup(opts)
  -- Not version-gated: without it the key blocks (BLOCKS) miss every file
  -- after the first, and the hook only adds a scheduled call.
  hook_buffer_swaps()

  local group = vim.api.nvim_create_augroup("util_codediff", { clear = true })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "CodeDiffOpen",
    callback = function(ev) on_open(ev.data and ev.data.tabpage) end,
  })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "CodeDiffClose",
    callback = function(ev) on_close(ev.data and ev.data.tabpage) end,
  })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "CodeDiffFileSelect",
    callback = function(ev)
      if ev.data and ev.data.tabpage then schedule_install(ev.data.tabpage) end
    end,
  })
  -- Not every teardown says CodeDiffClose: when a pane's buffer was wiped
  -- while its tabpage was hidden, CodeDiff's resume (scheduled from its own
  -- TabEnter) drops the session silently (lifecycle/state.lua resume_diff).
  -- Sweep after that has run, and after any revision buffer is wiped.
  local function sweep_later(tab)
    vim.schedule(function() vim.schedule(function() sweep(tab) end) end)
  end
  vim.api.nvim_create_autocmd("TabEnter", {
    group = group,
    callback = function() sweep_later(vim.api.nvim_get_current_tabpage()) end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    pattern = "codediff://*",
    callback = function() sweep_later(vim.api.nvim_get_current_tabpage()) end,
  })
  vim.api.nvim_create_autocmd("WinResized", { group = group, callback = rebalance_on_resize })
  -- CodeDiff lists its revision buffers; they would crowd the bufferline and
  -- buffer pickers with codediff:// entries that vanish on the next file.
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = group,
    pattern = "codediff://*",
    callback = function(ev)
      if vim.bo[ev.buf].buflisted then vim.bo[ev.buf].buflisted = false end
    end,
  })
end

---@return boolean degraded true when the installed CodeDiff is not M.VERSION
function M.degraded() return degraded end

return M
