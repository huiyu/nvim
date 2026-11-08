-- The review loop end to end: a round opened through rounds.submit for a
-- native Claude terminal, <leader>av's view of it (ai.review.open), the real
-- ,C keys in Normal and Visual mode writing the draft and opening its float,
-- typing into it, and the float's real <C-d> going through the real
-- rounds.resolve_sink and ai.feed to Claude's backend. The pieces have specs
-- of their own (review_round, review_view, review_feedback); this one pins
-- that they are wired to each other.
--
-- A scratch repository under tempname(), with a space in its path, under an
-- empty global git config; drafts go to a scratch directory (rounds.draft_path
-- is redirected). No agent runs: "Claude" is a terminal running `cat` with the
-- Snacks record an agent panel carries, registered through the real TermOpen
-- path, and its session is reported through rounds.native_event as the hook
-- would report it. Claude's backend edit_prompt is the one stub on the way: it
-- records the seed and hands it over as the prompt editor would (on_consumed).
-- vim.ui.select and vim.ui.input are stubbed to record and refuse: nothing on
-- this path may ask, and a prompt nobody answers would hang the spec.
local t = dofile("tests/helper.lua")
local Config = require("lazy.core.config")
local api, uv = vim.api, vim.uv

t.eq(package.loaded["ai.review.feedback"], nil, "ai.review.feedback is not loaded at startup")
local plugin = Config.plugins["codediff.nvim"]
if #vim.fn.glob(plugin.dir .. "/libvscode_diff*", false, true) == 0 then
  t.ok(false, "CodeDiff's native library is installed in " .. plugin.dir .. " (see docs/DIAGNOSTICS.md)")
  t.done()
  return
end

local scratch = vim.fn.tempname() .. " review loop"
vim.fn.mkdir(scratch, "p")
scratch = uv.fs_realpath(scratch)
local saved_env = { GIT_CONFIG_NOSYSTEM = vim.env.GIT_CONFIG_NOSYSTEM, GIT_CONFIG_GLOBAL = vim.env.GIT_CONFIG_GLOBAL }
vim.env.GIT_CONFIG_NOSYSTEM = "1"
vim.env.GIT_CONFIG_GLOBAL = scratch .. "/gitconfig"
vim.fn.writefile({}, vim.env.GIT_CONFIG_GLOBAL)
local saved_review = vim.g.ai_review
vim.g.ai_review = nil
local spec_cwd = vim.fn.getcwd()

local notes = {}
local real_notify = vim.notify
vim.notify = function(msg, level, opts)
  notes[#notes + 1] = { msg = tostring(msg), level = level, title = opts and opts.title }
end
local function heard() return vim.inspect(vim.tbl_map(function(n) return n.msg end, notes)) end

local asked = {}
local real_select, real_input = vim.ui.select, vim.ui.input
vim.ui.select = function(_, opts, on_choice)
  asked[#asked + 1] = opts and opts.prompt or "select"
  on_choice(nil)
end
vim.ui.input = function(opts, on_confirm)
  asked[#asked + 1] = opts and opts.prompt or "input"
  on_confirm(nil)
end

local function settle(ms) vim.wait(ms or 100, function() return false end, 10) end
local function map(buf, lhs, mode)
  return api.nvim_buf_call(buf, function() return vim.fn.maparg(lhs, mode or "n", false, true) end)
end

local rounds = require("ai.review.rounds")
local cd = require("util.codediff")
local real_draft_path = rounds.draft_path
rounds.draft_path = function(root, id)
  return ("%s/drafts/%s/%s.md"):format(scratch, vim.fn.sha256(uv.fs_realpath(root) or root):sub(1, 12), id)
end

---------------------------------------------------------------------------
-- A repository, Claude's terminal in it, and a round it owns
---------------------------------------------------------------------------

local root = scratch .. "/proj loop"
vim.fn.mkdir(root, "p")
local function git(...)
  local r = vim.system(vim.list_extend({ "git", "-C", root, "-c", "user.name=Fixture",
    "-c", "user.email=fixture@example.invalid", "-c", "commit.gpgsign=false" }, { ... }), { text = true }):wait()
  assert(r.code == 0, r.stderr)
  return r.stdout
end
git("init", "-q", "-b", "main")
local rows = {}
for i = 1, 12 do rows[i] = "line " .. i end
vim.fn.writefile(rows, root .. "/f.txt")
git("add", ".")
git("commit", "-qm", "fixture")

vim.o.lines, vim.o.columns = 50, 200
vim.cmd.cd(vim.fn.fnameescape(root))
vim.cmd.edit(vim.fn.fnameescape(root .. "/f.txt"))
local editor_tab = api.nvim_get_current_tabpage()
local file_win = api.nvim_get_current_win()
vim.cmd("vsplit")
vim.cmd.enew()
local term_buf = api.nvim_get_current_buf()
local term_job = vim.fn.jobstart({ "cat" }, { term = true, cwd = root })
vim.b[term_buf].snacks_terminal = { cmd = { "claude", "--settings", "{}" }, cwd = root }
local native = rounds._state().native
t.ok(vim.wait(2000, function() return native.claude ~= nil and native.claude.buf == term_buf end, 10),
  "TermOpen registers the stand-in Claude terminal")
rounds.native_event({
  agent = "claude", event = "session", payload = { session_id = "loop-1", source = "startup" }, done = function() end,
})
t.eq(native.claude and native.claude.session, "loop-1", "its session is reported as the hook reports it")
api.nvim_set_current_win(file_win)

local round
rounds.submit({
  source = "manual",
  conversation = "claude:loop-1",
  root = root,
  force = true,
  on_round = function(r) round = r end,
})
t.ok(vim.wait(10000, function() return round ~= nil end, 20), "rounds.submit opens a round")
round = round or {}
t.eq({ round.conversation, round.root }, { "claude:loop-1", root }, "owned by Claude's session, in the repository")

-- What the agent did since.
rows[4] = "line 4 CHANGED"
vim.fn.writefile(rows, root .. "/f.txt")
vim.cmd("checktime")

---------------------------------------------------------------------------
-- <leader>av, then the real ,C
---------------------------------------------------------------------------

require("ai.review").open()
local tab
t.ok(vim.wait(20000, function()
  for _, tp in ipairs(api.nvim_list_tabpages()) do
    local v = vim.t[tp].ai_review
    local s = type(v) == "table" and v.id == round.id and cd.session(tp)
    local raw = s and require("codediff.ui.lifecycle").get_session(tp)
    if raw and raw.refresh and raw.refresh.loading == false and type(s.modified_bufnr) == "number"
      and api.nvim_buf_is_valid(s.modified_bufnr) and api.nvim_buf_get_name(s.modified_bufnr):match("/f%.txt$")
      and api.nvim_buf_line_count(s.modified_bufnr) >= 12 and map(s.modified_bufnr, ",C").callback then
      tab = tp
      return true
    end
  end
  return false
end, 20), "ai.review.open() shows the round, with ,C in its panes " .. heard())
if not tab then
  vim.notify = real_notify
  t.done()
  return
end
local s = cd.session(tab)
t.eq(package.loaded["ai.review.feedback"], nil, "the view does not load ai.review.feedback; ,C will")

local draft = rounds.draft_path(root, round.id)
local function draft_lines() return vim.fn.filereadable(draft) == 1 and vim.fn.readfile(draft) or {} end
local function floats()
  local out = {}
  for _, tp in ipairs(api.nvim_list_tabpages()) do
    for _, w in ipairs(api.nvim_tabpage_list_wins(tp)) do
      if api.nvim_win_get_config(w).relative ~= "" and api.nvim_buf_get_name(api.nvim_win_get_buf(w)):match("/drafts/") then
        out[#out + 1] = w
      end
    end
  end
  return out
end

api.nvim_set_current_tabpage(tab)
api.nvim_set_current_win(s.modified_win)
api.nvim_win_set_cursor(s.modified_win, { 4, 0 })
local inserted
api.nvim_create_autocmd("InsertEnter", {
  once = true,
  callback = function(ev)
    inserted = { buf = ev.buf, float = api.nvim_win_get_config(0).relative == "editor", tab = api.nvim_get_current_tabpage() }
  end,
})
-- The key, and then typing into the float it opens: one typeahead.
api.nvim_feedkeys(vim.keycode(",Cmy comment<Esc>"), "xt", false)
t.ok(package.loaded["ai.review.feedback"] ~= nil, ",C loads ai.review.feedback")
local lines = draft_lines()
t.eq(lines[1], ("<!-- nvim-review round=%s sha=%s conversation=claude:loop-1 root=%s -->")
  :format(round.id, round.sha, vim.json.encode(root)), "the draft starts with the round's header")
t.ok(lines[2] and lines[2]:match("^Review of changes since baseline .+ %(Manual round%) in .+:$") ~= nil,
  "then the round's intro: " .. tostring(lines[2]))
t.ok(vim.list_contains(lines, "## f.txt:4 (working tree) · was 4 at the baseline"), "then the hunk under the cursor")
local fwin = api.nvim_get_current_win()
local fbuf = api.nvim_win_get_buf(fwin)
t.eq({ api.nvim_win_get_config(fwin).relative, api.nvim_win_get_tabpage(fwin) }, { "editor", tab },
  "the draft opens in a float in the review tab")
t.eq(inserted, { buf = fbuf, float = true, tab = tab }, "in Insert mode")
t.ok(vim.list_contains(draft_lines(), "> my comment"), "what is typed there is in the draft file once Insert mode is left")

-- q hides it; Visual ,C in the pane appends a selection, typed into the same way.
api.nvim_feedkeys("q", "xt", false)
t.eq(#floats(), 0, "q hides the float")
api.nvim_set_current_win(s.modified_win)
api.nvim_feedkeys(vim.keycode("6GVj,Csecond comment<Esc>"), "xt", false)
lines = draft_lines()
t.ok(vim.list_contains(lines, "## f.txt:6-7 (working tree)") and vim.list_contains(lines, "> second comment"),
  "Visual ,C appends the selection, and its comment is typed in")
t.ok(vim.list_contains(lines, "> my comment"), "the first entry stays")
t.eq(#vim.tbl_filter(function(l) return l:match("^Review of changes") ~= nil end, lines), 1, "under one intro")
fwin = api.nvim_get_current_win()
fbuf = api.nvim_win_get_buf(fwin)
t.eq(api.nvim_win_get_config(fwin).relative, "editor", "the float is back, focused")
local delivered_text = table.concat(lines, "\n") .. "\n"

---------------------------------------------------------------------------
-- The float's <C-d>: the real resolve_sink, ai.feed, Claude's backend
---------------------------------------------------------------------------

local resolved = {}
local real_resolve = rounds.resolve_sink
rounds.resolve_sink = function(conversation, roots, cb)
  resolved[#resolved + 1] = { conversation = conversation, roots = roots }
  return real_resolve(conversation, roots, function(target, reason)
    resolved[#resolved].target, resolved[#resolved].reason = target, reason
    return cb(target, reason)
  end)
end
local claude = require("ai.backend.claude")
local real_edit_prompt = claude.edit_prompt
local fed = {}
claude.edit_prompt = function(opts)
  fed[#fed + 1] = { opts = opts, tab = api.nvim_get_current_tabpage() }
  -- The prompt editor opens and takes the seed.
  vim.schedule(function() opts.on_consumed() end)
end
-- Feedback for Claude never reaches Codex. Were it to, Codex's real
-- edit_prompt would start a Codex terminal in this Nvim: it is stubbed to
-- record and do nothing.
local codex = require("ai.backend.codex")
local real_codex_edit_prompt = codex.edit_prompt
local codex_fed = 0
codex.edit_prompt = function() codex_fed = codex_fed + 1 end
-- startinsert takes effect once the main loop runs a Normal-mode command,
-- which a headless spec never does: what is asked for, and where, is what
-- the spec can see.
local real_cmd = vim.cmd
local inserts = {}
vim.cmd = setmetatable({}, {
  __index = real_cmd,
  __call = function(_, c, ...)
    if c == "startinsert" then inserts[#inserts + 1] = api.nvim_get_current_buf() end
    return real_cmd(c, ...)
  end,
})
local ok, err = pcall(function()
  api.nvim_feedkeys(vim.keycode("<C-d>"), "xt", false)
  vim.wait(5000, function() return #fed > 0 and vim.fn.getfsize(draft) == 0 end, 20)
  settle(100)
end)
vim.cmd = real_cmd
claude.edit_prompt = real_edit_prompt
codex.edit_prompt = real_codex_edit_prompt
rounds.resolve_sink = real_resolve
t.ok(ok, "<C-d> runs: " .. tostring(err))
t.eq(codex_fed, 0, "nothing goes to Codex")

t.eq(#resolved, 1, "<C-d> asks rounds.resolve_sink once")
t.eq(resolved[1] and { resolved[1].conversation, resolved[1].roots }, { "claude:loop-1", { root, root } },
  "for the header's conversation, against the header's root and the view's")
t.eq(resolved[1] and resolved[1].target and { resolved[1].target.kind, resolved[1].target.agent, resolved[1].target.buf },
  { "native", "claude", term_buf }, "which finds Claude's terminal, running that session")
t.eq(asked, {}, "nothing asks along the way")
t.eq(#fed, 1, "ai.feed reaches Claude's edit_prompt once " .. heard())
local seed = fed[1] and fed[1].opts.seed or ""
t.ok(seed:match("^Review of changes since baseline") ~= nil, "the seed starts with the intro")
t.ok(not seed:find("nvim-review", 1, true) and not seed:find("review-item", 1, true),
  "without the header or the review-item lines")
t.ok(seed:find("> my comment", 1, true) ~= nil and seed:find("> second comment", 1, true) ~= nil, "with both comments")
t.eq(fed[1] and fed[1].opts.ttl_ms, require("ai.review.config").get().seed_ttl_ms, "given seed_ttl_ms to arrive in")
t.eq(fed[1] and fed[1].tab, editor_tab, "fed from the tabpage that shows Claude's terminal")
t.eq(vim.fn.getfsize(draft), 0, "on_consumed empties the draft")
local last_sent = (draft:gsub("%.md$", "")) .. ".last-sent.md"
t.eq(vim.fn.filereadable(last_sent) == 1 and table.concat(vim.fn.readfile(last_sent), "\n") .. "\n", delivered_text,
  "after keeping what was delivered as <id>.last-sent.md")
t.eq({ api.nvim_get_current_tabpage(), api.nvim_get_current_buf() }, { editor_tab, term_buf },
  "the focus ends in Claude's terminal")
t.eq(inserts, { term_buf }, "in Terminal mode")
t.eq(#floats(), 0, "the draft's float is gone")
t.ok(cd.session(tab) ~= nil, "and the review view is still there")
vim.cmd("stopinsert")

---------------------------------------------------------------------------
-- Cleanup
---------------------------------------------------------------------------

rounds.draft_path = real_draft_path
pcall(vim.fn.jobstop, term_job)
for _, tp in ipairs(api.nvim_list_tabpages()) do
  if cd.session(tp) then cd.close(tp) end
end
vim.wait(3000, function()
  for _, tp in ipairs(api.nvim_list_tabpages()) do
    if cd.session(tp) then return false end
  end
  return true
end, 20)
-- Anything this Nvim started (the cat job, a CodeDiff watcher) goes with it.
t.process_cleanup()()
vim.ui.select, vim.ui.input = real_select, real_input
vim.notify = real_notify
vim.fn.chdir(spec_cwd)
vim.g.ai_review = saved_review
for k, v in pairs(saved_env) do vim.env[k] = v end
vim.fn.delete(scratch, "rf")
t.done()
