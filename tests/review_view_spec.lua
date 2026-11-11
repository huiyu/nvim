-- The review view (lua/ai/review/init.lua): <leader>av and the ,C keys it
-- installs in every CodeDiff view.
--
-- Real CodeDiff views of scratch repositories, so the native library is
-- needed. Rounds are real baselines: saved through util.baseline with the
-- trailers a source writes, or opened through rounds.submit / rounds.start.
-- The "agent terminals" run `cat` and carry the Snacks record an agent panel
-- would, so rounds.select_round sees them; no agent starts. ai.review.feedback
-- is stubbed through package.loaded, so ,C records what it would hand over.
-- Pinned here:
--   * the round <leader>av picks, through the real select_round: the current
--     buffer's conversation, the chat on the right's session, this process's
--     newest, the newest there at all;
--   * one review tab per root: the same round is focused (its explorer),
--     another round replaces it -- three rounds in a row leave one tab -- and
--     no other tabpage's windows change; the new tab opens where the old one
--     was;
--   * a clean tree: the conversation's previous round with a notice (never
--     another conversation's round in between), or just "no changes" and
--     nothing opened -- also when the only differences are paths the view's
--     listing leaves out, which the notice names with their reasons; nothing
--     is left waiting for a view CodeDiff would refuse;
--   * the view's tab variables and label; one notice on open, with Late and
--     the files left out for size, and no CodeDiff "Comparing" line beside it;
--   * the no-round and non-Git notices; a file outside any repository falls
--     back to the cwd's;
--   * two roots opening at once, with a status view opened meanwhile: each
--     view gets its own tab variables and notice, the status view none, and
--     a second press for the root still opening is refused;
--   * util.codediff.open on its own: an open CodeDiff refuses ends with
--     done(nil), and no open's label or tab variables land on a view that
--     is not the one it asked for;
--   * ,C in Normal and Visual mode on every buffer of a round view, a status
--     view, a rev-vs-rev view and a history view, handing comment() the
--     window, buffer, mode and ordered line range; repeated CodeDiffKeys
--     passes keep exactly one ,C and leave ,u ,U ,X alone.
-- Every repository lives under tempname() with a space in its path, with
-- git's system and global config shut out.
local t = dofile("tests/helper.lua")
local Config = require("lazy.core.config")
local uv = vim.uv

t.eq(package.loaded["ai.review"], nil, "the review view is not loaded at startup")
local plugin = Config.plugins["codediff.nvim"]
local libs = vim.fn.glob(plugin.dir .. "/libvscode_diff*", false, true)
if #libs == 0 then
  t.ok(false, "CodeDiff's native library is installed in " .. plugin.dir .. " (see docs/DIAGNOSTICS.md)")
  t.done()
  return
end

local gitconfig = vim.fn.tempname()
vim.fn.writefile({ "[init]", "\tdefaultBranch = main", "[gc]", "\tauto = 0" }, gitconfig)
local saved_env = { GIT_CONFIG_NOSYSTEM = vim.env.GIT_CONFIG_NOSYSTEM, GIT_CONFIG_GLOBAL = vim.env.GIT_CONFIG_GLOBAL }
vim.env.GIT_CONFIG_GLOBAL = gitconfig
vim.env.GIT_CONFIG_NOSYSTEM = "1"
local saved_g = vim.g.ai_review
vim.g.ai_review = nil

local notices = {}
local real_notify = vim.notify
vim.notify = function(msg, level, opts)
  notices[#notices + 1] = { msg = tostring(msg), level = level or vim.log.levels.INFO, title = opts and opts.title }
end
local function said(text)
  for _, n in ipairs(notices) do
    if n.msg:find(text, 1, true) then return n end
  end
end
local function count(text)
  local n = 0
  for _, m in ipairs(notices) do
    if m.msg:find(text, 1, true) then n = n + 1 end
  end
  return n
end
local function heard() return vim.inspect(vim.tbl_map(function(n) return n.msg end, notices)) end
local function settle(ms) vim.wait(ms or 100, function() return false end, 10) end

local DESC = "[AI] Review feedback (hunk / selection / file)"
local function map(buf, lhs, mode)
  return vim.api.nvim_buf_call(buf, function() return vim.fn.maparg(lhs, mode or "n", false, true) end)
end
local function desc(buf, lhs, mode) return map(buf, lhs, mode).desc end
--- How many buffer-local mappings `buf` has for `lhs` in `mode`.
local function mappings(buf, lhs, mode)
  local n = 0
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, mode)) do
    if m.lhs == lhs then n = n + 1 end
  end
  return n
end

local dirs = {}
local function repo(name)
  local root = vim.fn.tempname() .. " " .. name
  vim.fn.mkdir(root, "p")
  root = uv.fs_realpath(root)
  dirs[#dirs + 1] = root
  local function git(...)
    local command = { "git", "-C", root, "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid" }
    local result = vim.system(vim.list_extend(command, { ... }), { text = true }):wait()
    assert(result.code == 0, table.concat({ ... }, " ") .. ": " .. (result.stderr or ""))
    return vim.trim(result.stdout or "")
  end
  git("init", "-q", "-b", "main")
  vim.fn.writefile({ "one", "two", "three", "four", "five" }, root .. "/a.txt")
  git("add", ".")
  git("commit", "-qm", "one")
  return root, git
end
local writes = 0
local function edit(root)
  writes = writes + 1
  vim.fn.writefile({ "one", "two " .. writes, "three", "four " .. writes, "five" }, root .. "/a.txt")
end

local B = require("util.baseline")
local rounds = require("ai.review.rounds")
local cd = require("util.codediff")
local config = require("ai.config")

---A round as a source would save it: `trailers` are Source, Conversation,
---Late; Root is the repository.
local function save_round(root, trailers)
  local entry
  B.save(root, "round", vim.tbl_extend("force", { subject = "spec round", Root = root }, trailers),
    function(e, info) entry = e or info or false end)
  vim.wait(10000, function() return entry ~= nil end, 20)
  assert(type(entry) == "table", "saving a round failed: " .. tostring(entry))
  return entry
end
local function when(time) return os.date("%H:%M:%S", time) end

---Every tabpage showing a review of `root`.
local function review_tabs(root)
  local out = {}
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    local v = vim.t[tab].ai_review
    if type(v) == "table" and v.root == root then out[#out + 1] = tab end
  end
  return out
end

--- The view in `tab` has listed its files and carries this config's keys.
local function view_ready(tab)
  local s = cd.session(tab)
  if not (s and s.panel_bufnr and vim.api.nvim_buf_is_valid(s.panel_bufnr)) then return false end
  local raw = require("codediff.ui.lifecycle").get_session(tab)
  return raw ~= nil and raw.refresh ~= nil and raw.refresh.loading == false and desc(s.panel_bufnr, ",C") == DESC
end

---Press <leader>av and wait for the view of round `id` and its notice.
---@return integer? tab
local function review(id)
  notices = {}
  require("ai.review").open()
  local tab
  vim.wait(20000, function()
    for _, tb in ipairs(vim.api.nvim_list_tabpages()) do
      local v = vim.t[tb].ai_review
      if type(v) == "table" and v.id == id and view_ready(tb) then
        tab = tb
        return said("Changes since round") ~= nil
      end
    end
    return false
  end, 20)
  return tab
end

---Press <leader>av where nothing should open: wait for `text`.
local function review_nothing(text)
  notices = {}
  local tabs = #vim.api.nvim_list_tabpages()
  require("ai.review").open()
  local ok = vim.wait(10000, function() return said(text) ~= nil end, 20)
  settle(300)
  return ok and #vim.api.nvim_list_tabpages() == tabs
end

---What a tabpage's windows hold: compared before and after a review opens
---elsewhere. Its own windows only: floats (a notification, ui2's) come and go
---and resize on their own, which is no change to the tab's layout.
local function layout(tab)
  local out = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
    if vim.api.nvim_win_get_config(win).relative == "" then
      out[#out + 1] = {
        win = win,
        buf = vim.api.nvim_win_get_buf(win),
        cursor = vim.api.nvim_win_get_cursor(win),
        size = { vim.api.nvim_win_get_width(win), vim.api.nvim_win_get_height(win) },
      }
    end
  end
  return out
end

vim.o.lines, vim.o.columns = 50, 200
local cwd = vim.fn.getcwd()
local editor_tab = vim.api.nvim_get_current_tabpage()

---------------------------------------------------------------------------
-- Outside Git, and a repository with no round
---------------------------------------------------------------------------

local plain = vim.fn.tempname() .. " plain dir"
vim.fn.mkdir(plain, "p")
dirs[#dirs + 1] = plain
vim.cmd.cd(vim.fn.fnameescape(plain))
vim.cmd.enew()
t.ok(review_nothing("The review view needs a Git worktree:"), "<leader>av outside Git says so and opens nothing")
local outside = vim.split((said("Git worktree") or { msg = "" }).msg, "\n")
t.ok(#outside == 2 and outside[2]:find("^not a git repository") ~= nil,
  "with git's reason on a line of its own: the notifier cuts a long line " .. heard())
t.eq(said("Git worktree").title, "AI review", "titled AI review")

local empty = repo("no rounds")
vim.cmd.cd(vim.fn.fnameescape(empty))
vim.cmd.edit(vim.fn.fnameescape(empty .. "/a.txt"))
t.ok(review_nothing("has no review round yet"), "<leader>av with no round says so and opens nothing")
local none = said("has no review round yet")
t.ok(none ~= nil and none.msg:find(vim.fn.fnamemodify(empty, ":~"), 1, true) ~= nil
  and none.msg:find("<leader>aV", 1, true) ~= nil and none.msg:find(":checkhealth config", 1, true) ~= nil
  and none.msg:find("<leader>gv", 1, true) ~= nil,
  "naming the root, <leader>aV, :checkhealth config and <leader>gv " .. heard())

-- The rounds cannot be listed: what failed, the root and the reason, each
-- on a line of its own.
do
  local real_select = rounds.select_round
  rounds.select_round = function(_, cb) cb(nil, "spec: no listing") end
  local refused = review_nothing("Could not list the review rounds")
  rounds.select_round = real_select
  t.ok(refused, "<leader>av whose rounds cannot be listed opens nothing")
  t.eq((said("Could not list") or {}).msg,
    ("Could not list the review rounds:\nRoot: %s\nspec: no listing"):format(vim.fn.fnamemodify(empty, ":~")),
    "and says why, a clause a line")
end

---------------------------------------------------------------------------
-- The repository under review, and a bystander tabpage
---------------------------------------------------------------------------

local R, git = repo("review view")
vim.fn.writefile({ "b one" }, R .. "/b.txt")
git("add", "b.txt")
git("commit", "-qm", "two")
-- The last commit changes a.txt only, so a rev-vs-rev view shows a file on
-- both sides.
vim.fn.writefile({ "one", "two", "three v2", "four", "five" }, R .. "/a.txt")
git("commit", "-qam", "three")
local head1, head2 = git("rev-parse", "HEAD~1"), git("rev-parse", "HEAD")
vim.cmd.cd(vim.fn.fnameescape(R))

vim.cmd.tabnew()
local bystander = vim.api.nvim_get_current_tabpage()
vim.cmd.edit(vim.fn.fnameescape(R .. "/b.txt"))
vim.cmd.vsplit(vim.fn.fnameescape(R .. "/a.txt"))
vim.api.nvim_win_set_cursor(0, { 3, 1 })
local bystander_layout = layout(bystander)
vim.api.nvim_set_current_tabpage(editor_tab)
vim.cmd.edit(vim.fn.fnameescape(R .. "/a.txt"))
local file_buf = vim.api.nvim_get_current_buf()
t.eq(map(file_buf, ",C"), {}, "a plain file has no ,C")

---------------------------------------------------------------------------
-- Which round: the newest there at all
---------------------------------------------------------------------------

local L = save_round(R, { Source = "claude", Conversation = "claude:gone-session" })
edit(R)
local before = layout(editor_tab)
local tab = review(L.id)
t.ok(tab ~= nil, "<leader>av opens the newest round when nothing else claims one " .. heard())
t.eq(vim.t[tab].ai_review, rounds.review_vars(L), "vim.t.ai_review is the round's review_vars")
t.eq(vim.t[tab].codediff_baseline, { sha = L.sha, kind = "round" }, "vim.t.codediff_baseline marks a round baseline")
t.eq(vim.t[tab].codediff_label, ("Review · Claude · round %s → working tree"):format(when(L.time)),
  "the label names the owner's kind, the round and the range")
local s = cd.session(tab)
t.eq({ s.mode, s.original_revision, s.git_root }, { "revision", L.sha, R },
  "the view compares the round's sha with the working tree, in the root")
local note = said("Changes since round")
t.ok(note.msg:find(("Changes since round %s (baseline → working tree)\nRoot: %s\n"):format(when(L.time),
  vim.fn.fnamemodify(R, ":~")), 1, true) ~= nil, "the notice names the round, the range and the root " .. heard())
t.ok(note.msg:find("Conversation: " .. rounds.label("claude:gone-session"), 1, true) ~= nil, "and the conversation")
t.ok(note.msg:find("Late", 1, true) == nil and note.msg:find("Not compared", 1, true) == nil, "no Late, nothing left out")
t.eq(note.title, "AI review", "titled AI review")
settle(500)
t.eq(count("Changes since round"), 1, "said once")
t.eq(count("Comparing "), 0, "with no CodeDiff 'Comparing' line beside it " .. heard())
t.eq(vim.api.nvim_tabpage_get_number(tab), vim.api.nvim_tabpage_get_number(editor_tab) + 1,
  "the review tab opens right after the tab it was asked from")
t.eq(layout(editor_tab), before, "the tab it was asked from keeps its windows")
t.eq(layout(bystander), bystander_layout, "another tabpage keeps its windows")
t.eq(package.loaded["ai.review.feedback"], nil, "installing ,C does not load ai.review.feedback")

-- A file outside any repository names none: the cwd's repository is
-- reviewed, and its round is on screen.
vim.fn.writefile({ "notes" }, plain .. "/notes.md")
vim.api.nvim_set_current_tabpage(editor_tab)
vim.cmd.edit(vim.fn.fnameescape(plain .. "/notes.md"))
notices = {}
require("ai.review").open()
vim.wait(5000, function() return vim.api.nvim_get_current_tabpage() == tab end, 20)
settle(200)
t.eq(vim.api.nvim_get_current_tabpage(), tab, "<leader>av from a file outside any repository reviews the cwd's " .. heard())
t.eq(said("Git worktree"), nil, "instead of refusing")
vim.api.nvim_set_current_tabpage(editor_tab)
vim.api.nvim_set_current_buf(file_buf)

-- The same round again: focused, not reopened.
local tabs = #vim.api.nvim_list_tabpages()
vim.api.nvim_set_current_tabpage(editor_tab)
notices = {}
require("ai.review").open()
vim.wait(5000, function() return vim.api.nvim_get_current_tabpage() == tab end, 20)
settle(200)
t.eq(vim.api.nvim_get_current_tabpage(), tab, "<leader>av for the round on screen goes to its tab")
t.eq(vim.api.nvim_get_current_win(), cd.session(tab).panel_win, "and focuses its explorer")
t.eq(#vim.api.nvim_list_tabpages(), tabs, "opening nothing new")
t.eq(count("Changes since round"), 0, "and saying nothing")

---------------------------------------------------------------------------
-- ... this process's newest round; replaced in the same place
---------------------------------------------------------------------------

local P
rounds.submit({ source = "manual", root = R, force = true, on_round = function(round) P = round end })
vim.wait(10000, function() return P ~= nil end, 20)
t.ok(P ~= nil and P.id ~= L.id, "a round this process opened")
edit(R)
-- Asked from the review tab itself, its explorer focused: the root is the
-- view's, and the new view opens where the old one was.
local old = tab
before = layout(editor_tab)
tab = review(P.id)
t.ok(tab ~= nil and tab ~= old, "<leader>av prefers the newest round this process opened " .. heard())
t.ok(not vim.api.nvim_tabpage_is_valid(old), "the other round's view is closed")
t.eq(review_tabs(R), { tab }, "one review tab for the root")
t.eq(vim.api.nvim_tabpage_get_number(tab), vim.api.nvim_tabpage_get_number(editor_tab) + 1,
  "in the place of the old one")
t.eq(layout(editor_tab), before, "the tab before it keeps its windows")
t.eq(layout(bystander), bystander_layout, "another tabpage keeps its windows")
t.eq(vim.t[tab].codediff_label, ("Review · Manual · round %s → working tree"):format(when(P.time)),
  "a round with no owner is labelled by its source")
t.ok(said("No conversation: delivering feedback asks where it goes") ~= nil, "and says it has no owner " .. heard())

---------------------------------------------------------------------------
-- ... the session on the right; the current buffer's conversation
---------------------------------------------------------------------------

local terminals = {}
---A stand-in agent panel in the editor tabpage, registered through the real
---TermOpen path, reporting `session`.
local function agent_terminal(agent, session)
  vim.api.nvim_set_current_tabpage(editor_tab)
  vim.cmd.enew()
  local buf = vim.api.nvim_get_current_buf()
  local job = vim.fn.jobstart({ "cat" }, { term = true, cwd = R })
  vim.b[buf].snacks_terminal = { cmd = agent == "claude" and { "claude", "--settings", "{}" } or { "codex", "--yolo" }, cwd = R }
  terminals[#terminals + 1] = { buf = buf, job = job }
  vim.wait(2000, function()
    local e = rounds._state().native[agent]
    return e ~= nil and e.buf == buf
  end, 10)
  rounds._state().native[agent].session = session
  return buf
end
-- Either agent can be the one on the right: the first listed here, and the
-- other is registered beside it.
local right = config.agent_names()[1]
local other = config.agent_names()[2]
local right_term = agent_terminal(right, "s-right")
local other_term = agent_terminal(other, "s-other")
t.ok(rounds.conversation_of(other_term) == other .. ":s-other", "the stand-in terminals are registered")

local O = save_round(R, { Source = other, Conversation = other .. ":s-other" })
local A = save_round(R, { Source = right, Conversation = right .. ":s-right" })
local P2
rounds.submit({ source = "manual", root = R, force = true, on_round = function(round) P2 = round end })
vim.wait(10000, function() return P2 ~= nil end, 20)
edit(R)

-- ai.slot reads the chat on the right off the windows, and knows a native
-- agent by its backend: the stand-in is that backend's terminal here.
local right_backend = require("ai.backend." .. right)
local backend_saved = { running = right_backend.running, buf = right_backend.buf }
right_backend.running = function() return vim.api.nvim_buf_is_valid(right_term) end
right_backend.buf = function() return right_term end
vim.api.nvim_set_current_tabpage(editor_tab)
vim.api.nvim_set_current_buf(file_buf)
vim.cmd("botright vsplit")
local right_win = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_buf(right_win, right_term)
vim.cmd("stopinsert")
vim.cmd("wincmd p")
tab = review(A.id)
t.ok(tab ~= nil, "from a file, the newest round of the session on the right, over a newer one of this process " .. heard())
t.eq(review_tabs(R), { tab }, "still one review tab")

vim.api.nvim_set_current_tabpage(editor_tab)
vim.api.nvim_set_current_buf(other_term)
tab = review(O.id)
t.ok(tab ~= nil, "from an agent terminal, its own session's newest round, over the one on the right's " .. heard())
t.eq(review_tabs(R), { tab }, "still one review tab")
t.eq(vim.t[tab].codediff_label, ("Review · %s · round %s → working tree"):format(
  other == "claude" and "Claude" or "Codex", when(O.time)), "labelled by the owner's agent")
t.eq(layout(bystander), bystander_layout, "another tabpage keeps its windows throughout")
local round_tab = tab
pcall(vim.api.nvim_win_close, right_win, true)
for k, fn in pairs(backend_saved) do right_backend[k] = fn end

---------------------------------------------------------------------------
-- ,C on a round view
---------------------------------------------------------------------------

t.eq(package.loaded["ai.review.feedback"], nil, "ai.review.feedback is still not loaded")
local calls = {}
package.loaded["ai.review.feedback"] = { comment = function(opts) calls[#calls + 1] = opts end }

s = cd.session(round_tab)
local panes = { modified = s.modified_bufnr, original = s.original_bufnr, explorer = s.panel_bufnr }
for where, buf in pairs(panes) do
  t.eq({ desc(buf, ",C"), desc(buf, ",C", "x") }, { DESC, DESC }, ",C in Normal and Visual mode on the " .. where)
end
for _, lhs in ipairs({ ",u", ",U", ",X" }) do
  t.ok(desc(s.modified_bufnr, lhs) ~= nil, lhs .. " from util.codediff_actions is there too")
end

--- Press ,C in Normal mode in `win`, at `line`.
local function press(win, line)
  vim.api.nvim_set_current_win(win)
  if line then vim.api.nvim_win_set_cursor(win, { line, 0 }) end
  local m = map(vim.api.nvim_win_get_buf(win), ",C")
  assert(m.callback, ",C is mapped here")
  m.callback()
  return calls[#calls]
end
--- Type `keys` ending in ,C in `win`, in Visual mode.
local function visual(win, keys)
  vim.api.nvim_set_current_win(win)
  vim.api.nvim_feedkeys(keys, "x", false)
  return calls[#calls]
end

vim.api.nvim_set_current_tabpage(round_tab)
t.eq(press(s.modified_win, 2), { tab = round_tab, win = s.modified_win, buf = s.modified_bufnr, mode = "n" },
  "Normal ,C hands comment() the tab, window, buffer and mode")
t.eq(press(s.original_win, 2), { tab = round_tab, win = s.original_win, buf = s.original_bufnr, mode = "n" },
  "on the baseline side too")
t.eq(press(s.panel_win), { tab = round_tab, win = s.panel_win, buf = s.panel_bufnr, mode = "n" },
  "and in the explorer")
local n = #calls
t.eq(visual(s.modified_win, "2GVj,C"),
  { tab = round_tab, win = s.modified_win, buf = s.modified_bufnr, mode = "v", range = { first = 2, last = 3 } },
  "Visual ,C adds the selected line range")
t.eq(#calls, n + 1, "once")
t.eq(vim.fn.mode(), "n", "and leaves Visual mode")
t.eq(visual(s.original_win, "4GVkk,C").range, { first = 2, last = 4 }, "a selection made upwards is ordered")
t.eq(visual(s.modified_win, "3Gv,C").range, { first = 3, last = 3 }, "a characterwise one gives its lines")

-- Every CodeDiffKeys pass runs attach() again.
local view = require("ai.review")
for _ = 1, 3 do view.attach(round_tab) end
for _ = 1, 2 do
  vim.api.nvim_exec_autocmds("User", { pattern = "CodeDiffKeys", modeline = false, data = { tabpage = round_tab } })
end
settle(200)
require("util.codediff_actions").attach(round_tab)
for where, buf in pairs(panes) do
  t.eq({ mappings(buf, ",C", "n"), mappings(buf, ",C", "x") }, { 1, 1 },
    "repeated passes keep exactly one ,C per mode on the " .. where)
end
t.eq(desc(s.modified_bufnr, ",u"), "Stage hunk", ",u is untouched by them")
t.ok((desc(s.modified_bufnr, ",X") or ""):match("^Discard hunk back to baseline ") ~= nil, ",X too")
t.eq(press(s.modified_win, 2).mode, "n", ",C still reaches comment()")
t.ok(pcall(view.attach, 99999) and pcall(view.attach, editor_tab), "attach() on no view is a no-op")
-- The working-tree pane is a.txt's own buffer: its ,C is suspended while
-- another tabpage is current, like every key the view lends a real file.
t.eq(s.modified_bufnr, file_buf, "the working-tree pane is the file's own buffer")
vim.api.nvim_set_current_tabpage(editor_tab)
t.eq(map(file_buf, ",C"), {}, "it has no ,C while another tabpage is current")
vim.api.nvim_set_current_tabpage(round_tab)
-- CodeDiff resumes a tabpage's claims from a callback its TabEnter schedules.
vim.wait(3000, function() return desc(file_buf, ",C") == DESC end, 20)
t.eq(desc(file_buf, ",C"), DESC, "and gets it back in the view")

package.loaded["ai.review.feedback"] = { comment = function() error("boom") end }
notices = {}
t.ok(pcall(map(s.modified_bufnr, ",C").callback), "a failing comment() does not escape the key")
t.ok(said("Review feedback failed") ~= nil and said("Review feedback failed").level == vim.log.levels.WARN,
  "it warns instead " .. heard())
package.loaded["ai.review.feedback"] = { comment = function(opts) calls[#calls + 1] = opts end }

---------------------------------------------------------------------------
-- ,C on a status view, a rev-vs-rev view and a history view
---------------------------------------------------------------------------

local function other_view(args, mode, root)
  vim.api.nvim_set_current_tabpage(editor_tab)
  vim.api.nvim_set_current_buf(file_buf)
  cd.open({ args = args, root = root, label = "spec view" })
  local found
  vim.wait(15000, function()
    local tb = vim.api.nvim_get_current_tabpage()
    local v = cd.session(tb)
    if v and v.mode == mode and view_ready(tb) and v.modified_bufnr and vim.api.nvim_buf_is_valid(v.modified_bufnr)
      and desc(v.modified_bufnr, ",C") == DESC then
      found = tb
      return true
    end
    return false
  end, 20)
  t.ok(found ~= nil, ("a %s view opens"):format(mode))
  return found
end

for _, case in ipairs({
  { args = {}, mode = "status" },
  { args = { head1, head2 }, mode = "revisions", root = R },
  { args = { "history" }, mode = "history" },
}) do
  local tb = other_view(case.args, case.mode, case.root)
  if tb then
    local v = cd.session(tb)
    for where, buf in pairs({ modified = v.modified_bufnr, original = v.original_bufnr, panel = v.panel_bufnr }) do
      if buf and vim.api.nvim_buf_is_valid(buf) then
        t.eq({ desc(buf, ",C"), desc(buf, ",C", "x") }, { DESC, DESC },
          (",C in Normal and Visual mode on the %s of a %s view"):format(where, case.mode))
      end
    end
    t.eq(vim.t[tb].ai_review, nil, "a " .. case.mode .. " view is no review of a round")
    t.eq(press(v.modified_win, 1), { tab = tb, win = v.modified_win, buf = v.modified_bufnr, mode = "n" },
      "Normal ,C in a " .. case.mode .. " view")
    if vim.api.nvim_buf_line_count(v.modified_bufnr) >= 2 then
      t.eq(visual(v.modified_win, "1GVj,C").range, { first = 1, last = 2 }, "Visual ,C in a " .. case.mode .. " view")
    end
    t.eq(press(v.panel_win), { tab = tb, win = v.panel_win, buf = v.panel_bufnr, mode = "n" },
      "Normal ,C in its " .. (case.mode == "history" and "history list" or "explorer"))
    cd.close(tb)
    vim.wait(3000, function() return not vim.api.nvim_tabpage_is_valid(tb) end, 20)
  end
end
t.eq(review_tabs(R), { round_tab }, "the review tab is untouched by other views")

---------------------------------------------------------------------------
-- Three rounds in a row leave one review tab (U8)
---------------------------------------------------------------------------

local R2 = repo("three rounds")
vim.api.nvim_set_current_tabpage(editor_tab)
vim.cmd.edit(vim.fn.fnameescape(R2 .. "/a.txt"))
local r2_buf = vim.api.nvim_get_current_buf()
local first_r2
local ids = {}
for i = 1, 3 do
  edit(R2)
  notices = {}
  rounds.start({ buf = r2_buf })
  t.ok(vim.wait(10000, function() return said("Review round ") ~= nil and said(" started\nRoot: ") ~= nil end, 20),
    ("round %d starts " .. heard()):format(i))
  local newest = rounds._state().newest_here[R2]
  ids[i] = newest and newest.id
  edit(R2) -- the agent writes
  vim.api.nvim_set_current_tabpage(editor_tab)
  vim.api.nvim_set_current_buf(r2_buf)
  before = layout(editor_tab)
  local tb = review(ids[i])
  first_r2 = first_r2 or tb
  t.ok(tb ~= nil, ("round %d opens its review " .. heard()):format(i))
  t.eq(#review_tabs(R2), 1, ("after round %d, one review tab for that root"):format(i))
  t.eq(layout(editor_tab), before, ("round %d leaves the tab it was asked from alone"):format(i))
  t.eq(layout(bystander), bystander_layout, ("round %d leaves another tabpage alone"):format(i))
end
t.ok(ids[1] and ids[2] and ids[3] and ids[1] ~= ids[2] and ids[2] ~= ids[3], "three distinct rounds")
t.eq(review_tabs(R), { round_tab }, "the other root's review tab stays")

---------------------------------------------------------------------------
-- A clean tree
---------------------------------------------------------------------------

-- The next prompt went out and nothing is written yet: the round before it.
local R3 = repo("clean tree")
local C1 = save_round(R3, { Source = "claude", Conversation = "claude:prev-test" })
edit(R3)
-- Another conversation's round in between, which differs from the tree as
-- well: the fallback is the conversation's own previous round, never merely
-- the one before.
local X = save_round(R3, { Source = "codex", Conversation = "codex:bystander" })
edit(R3)
local C2 = save_round(R3, { Source = "claude", Conversation = "claude:prev-test" })
t.ok(X.id ~= C1.id and X.id ~= C2.id, "a round of another conversation sits between the two")
vim.api.nvim_set_current_tabpage(editor_tab)
vim.cmd.edit(vim.fn.fnameescape(R3 .. "/a.txt"))
tab = review(C1.id)
t.ok(tab ~= nil, "a round with no changes yet shows the conversation's previous round " .. heard())
t.ok(said(("Round %s has no changes yet; showing round %s"):format(when(C2.time), when(C1.time))) ~= nil,
  "and says so " .. heard())
t.eq(count("Changes since round"), 1, "in the one notice")
t.eq(tab and vim.t[tab].ai_review.id, C1.id, "the view is the previous round's, not the other conversation's")

-- Nothing changed, and no earlier round of that conversation that differs.
local R4 = repo("no changes")
save_round(R4, { Source = "manual" })
local D2 = save_round(R4, { Source = "manual" })
vim.api.nvim_set_current_tabpage(editor_tab)
vim.cmd.edit(vim.fn.fnameescape(R4 .. "/a.txt"))
t.ok(review_nothing("No changes since round"), "no change since the round opens nothing " .. heard())
t.ok(said(("No changes since round %s in %s"):format(when(D2.time), vim.fn.fnamemodify(R4, ":~"))) ~= nil,
  "naming the round and the root " .. heard())
t.eq(review_tabs(R4), {}, "and no review tab")

---------------------------------------------------------------------------
-- Late, and files left out for size
---------------------------------------------------------------------------

vim.g.ai_review = { max_file_size = 1024 }
local R5 = repo("late round")
local E = save_round(R5, { Source = "codex", Conversation = "codex:late-session", Late = true })
vim.fn.writefile({ ("x"):rep(4096) }, R5 .. "/big.bin")
edit(R5)
vim.api.nvim_set_current_tabpage(editor_tab)
vim.cmd.edit(vim.fn.fnameescape(R5 .. "/a.txt"))
tab = review(E.id)
t.ok(tab ~= nil, "a Late round opens " .. heard())
t.eq(vim.t[tab].ai_review.late, true, "vim.t.ai_review says it is Late")
note = said("Changes since round") or { msg = "" }
t.ok(note.msg:find("\nLate: ", 1, true) ~= nil, "the notice says Late " .. heard())
-- util.codediff's listing names it as the view lists; the review's notice
-- would only repeat it.
t.ok(said("Not compared (untracked, over 1024 bytes; vim.g.ai_review.max_file_size): big.bin") ~= nil,
  "the untracked file left out for size is named " .. heard())
t.eq(count("big.bin"), 1, "once")

-- Nothing to review but files left out for size: they are named there.
local R6 = repo("skipped only")
save_round(R6, { Source = "manual" })
vim.fn.writefile({ ("y"):rep(4096) }, R6 .. "/huge.bin")
vim.api.nvim_set_current_tabpage(editor_tab)
vim.cmd.edit(vim.fn.fnameescape(R6 .. "/a.txt"))
t.ok(review_nothing("No changes since round"), "a tree that differs only in a skipped file has no changes " .. heard())
t.ok((said("No changes since round") or { msg = "" }).msg:find(
  "\nNot compared (untracked, over 1024 bytes; vim.g.ai_review.max_file_size): huge.bin", 1, true) ~= nil,
  "and the notice names the file it could not compare " .. heard())
t.eq(vim.t[tab].codediff_label, ("Review · Codex · round %s → working tree"):format(when(E.time)), "labelled Codex")

---------------------------------------------------------------------------
-- Differences the view's listing leaves out
---------------------------------------------------------------------------

--- The tabpage showing a CodeDiff view of `root` in `mode`, once it is there.
local function view_of(root, mode)
  local found
  vim.wait(15000, function()
    for _, tb in ipairs(vim.api.nvim_list_tabpages()) do
      local v = cd.session(tb)
      if v and v.mode == mode and v.git_root and uv.fs_realpath(v.git_root) == root and view_ready(tb) then
        found = tb
        return true
      end
    end
    return false
  end, 20)
  return found
end
local function close_view(tb)
  if tb and vim.api.nvim_tabpage_is_valid(tb) then
    cd.close(tb)
    vim.wait(3000, function() return not vim.api.nvim_tabpage_is_valid(tb) end, 20)
  end
  vim.api.nvim_set_current_tabpage(editor_tab)
end

-- The round captured an untracked log and a .env. The log has grown past
-- max_file_size since, and the .env is ignored now: both are still on disk,
-- so the view's listing lists neither as deleted, nothing else changed, and
-- CodeDiff would answer the view with a bare "No changes to show".
local R7 = repo("left out")
vim.fn.writefile({ "small" }, R7 .. "/grow.log")
vim.fn.writefile({ "TOKEN=1" }, R7 .. "/.env")
local G = save_round(R7, { Source = "claude", Conversation = "claude:left-out" })
vim.fn.writefile({ ("z"):rep(4096) }, R7 .. "/grow.log")
vim.fn.mkdir(R7 .. "/.git/info", "p")
vim.fn.writefile({ ".env" }, R7 .. "/.git/info/exclude")
vim.api.nvim_set_current_tabpage(editor_tab)
vim.cmd.edit(vim.fn.fnameescape(R7 .. "/a.txt"))
local r7_tabs = #vim.api.nvim_list_tabpages()
notices = {}
require("ai.review").open()
vim.wait(5000, function() return said("No changes since round") ~= nil or said("No changes to show") ~= nil end, 20)
settle(300)
local quiet = said("No changes since round") or { msg = "" }
t.ok(quiet.msg:find(("No changes since round %s in %s"):format(when(G.time), vim.fn.fnamemodify(R7, ":~")), 1, true) ~= nil,
  "a tree whose only differences the listing leaves out has no changes " .. heard())
t.ok(quiet.msg:find("\nNot compared (untracked, over 1024 bytes; vim.g.ai_review.max_file_size): grow.log", 1, true) ~= nil
  and quiet.msg:find("\nNot compared (ignored, still on disk): .env", 1, true) ~= nil,
  "naming each path left out with its reason " .. heard())
t.eq(said("No changes to show"), nil, "CodeDiff is not asked for a view it would refuse")
t.eq(#vim.api.nvim_list_tabpages(), r7_tabs, "nothing opens")
-- Nothing is left waiting: the next press answers the same at once.
notices = {}
require("ai.review").open()
vim.wait(5000, function() return said("No changes since round") ~= nil or said("still opening") ~= nil end, 20)
t.eq(said("still opening"), nil, "a second press is not told the view is still opening " .. heard())
t.ok(said("No changes since round") ~= nil, "it answers no changes again " .. heard())
-- A view opened next is a plain status view.
vim.cmd.CodeDiff()
local typed = view_of(R7, "status")
t.ok(typed ~= nil, "a typed :CodeDiff opens a status view")
if typed then
  t.eq({ vim.t[typed].ai_review, vim.t[typed].codediff_baseline, vim.t[typed].codediff_label },
    { nil, nil, "index/HEAD ↔ working tree" }, "with nothing of the review's")
end
close_view(typed)

-- util.codediff.open on its own. An open CodeDiff refuses for an empty
-- listing ends with done(nil); one it refuses with an error of its own
-- (an unknown revision) waits out its time. Neither one's label or tab
-- variables land on the view opened next.
local outcome
notices = {}
cd.open({ root = R7, args = { G.sha }, label = "spec refused", tab_vars = { spec_var = "refused" },
  done = function(tb, why) outcome = { tab = tb, why = why } end })
vim.wait(5000, function() return outcome ~= nil end, 20)
t.ok(outcome ~= nil and outcome.tab == nil and type(outcome.why) == "string",
  "an open CodeDiff answers with no changes ends with done(nil, why) " .. vim.inspect(outcome) .. heard())
t.ok(cd.open({ root = R7, args = { ("0"):rep(40) }, label = "spec unknown", tab_vars = { spec_var = "unknown" } }),
  "an open of an unknown revision is issued")
vim.wait(5000, function() return said("Invalid revision") ~= nil end, 20)
vim.api.nvim_set_current_tabpage(editor_tab)
vim.cmd.CodeDiff()
typed = view_of(R7, "status")
t.ok(typed ~= nil, "a typed :CodeDiff opens a status view after them")
if typed then
  t.eq({ vim.t[typed].spec_var, vim.t[typed].codediff_label }, { nil, "index/HEAD ↔ working tree" },
    "and gets neither open's label or tab variables")
end
close_view(typed)
vim.g.ai_review = nil

---------------------------------------------------------------------------
-- Two roots opening at once, and a status view meanwhile
---------------------------------------------------------------------------

local RA = repo("slow root")
local RB = repo("fast root")
local RG = repo("status root")
local GA = save_round(RA, { Source = "claude", Conversation = "claude:slow" })
local GB = save_round(RB, { Source = "codex", Conversation = "codex:fast" })
edit(RA)
edit(RB)
edit(RG)
-- RA's listing answers only when the spec lets it, so RB's review view and
-- a status view of RG are issued, and arrive, while RA's is on its way.
local changes = require("codediff.core.git.changes")
local real_listing = changes.get_diff_revision
local hold, held = true, {}
changes.get_diff_revision = function(revision, git_root, callback, pathspec)
  if not hold or (uv.fs_realpath(git_root) or git_root) ~= RA then
    return real_listing(revision, git_root, callback, pathspec)
  end
  return real_listing(revision, git_root, function(err, result)
    held[#held + 1] = function() callback(err, result) end
  end, pathspec)
end
local function release()
  hold = false
  for _, answer in ipairs(held) do answer() end
  held = {}
end
local issued = {}
local real_open = cd.open
cd.open = function(spec)
  issued[#issued + 1] = spec
  return real_open(spec)
end
local function tilde(path) return vim.fn.fnamemodify(path, ":~") end
local function review_of(round)
  for _, tb in ipairs(vim.api.nvim_list_tabpages()) do
    local v = vim.t[tb].ai_review
    if type(v) == "table" and v.id == round.id and view_ready(tb) then return tb end
  end
end

notices = {}
vim.api.nvim_set_current_tabpage(editor_tab)
vim.cmd.edit(vim.fn.fnameescape(RA .. "/a.txt"))
require("ai.review").open()
vim.wait(10000, function() return #issued >= 1 end, 10)
t.eq(issued[1] and issued[1].root, RA, "RA's review view is issued")
vim.cmd.edit(vim.fn.fnameescape(RG .. "/a.txt"))
cd.open({ args = {}, label = "spec status" })
local status_tab = view_of(RG, "status")
t.ok(status_tab ~= nil, "a status view opens while RA's review view is on its way")
vim.api.nvim_set_current_tabpage(editor_tab)
vim.cmd.edit(vim.fn.fnameescape(RB .. "/a.txt"))
require("ai.review").open()
local tb_b
vim.wait(10000, function()
  tb_b = review_of(GB)
  return tb_b ~= nil and said("Root: " .. tilde(RB)) ~= nil
end, 20)
t.ok(tb_b ~= nil, "RB's review view opens while RA's is on its way " .. heard())
t.eq(review_tabs(RA), {}, "RA's has not arrived yet")
t.eq(said("Root: " .. tilde(RA)), nil, "and its notice waits for it")
vim.wait(5000, function() return #held > 0 end, 20)
t.eq(#held, 1, "RA's listing has answered and is held")
release()
local tb_a
vim.wait(15000, function()
  tb_a = review_of(GA)
  return tb_a ~= nil and said("Root: " .. tilde(RA)) ~= nil
end, 20)
t.ok(tb_a ~= nil, "RA's review view arrives last " .. heard())
local function vars(tb)
  return tb and { vim.t[tb].ai_review, vim.t[tb].codediff_baseline, vim.t[tb].codediff_label } or {}
end
t.eq(vars(tb_a), { rounds.review_vars(GA), { sha = GA.sha, kind = "round" },
  ("Review · Claude · round %s → working tree"):format(when(GA.time)) }, "with its own tab variables and label")
t.eq(vars(tb_b), { rounds.review_vars(GB), { sha = GB.sha, kind = "round" },
  ("Review · Codex · round %s → working tree"):format(when(GB.time)) }, "RB's view with its own")
t.eq(vars(status_tab), { nil, nil, "spec status" }, "the status view with none of theirs")
t.eq({ count("Root: " .. tilde(RA)), count("Root: " .. tilde(RB)) }, { 1, 1 }, "each review view says its notice once")
t.ok(said("Comparing spec status") ~= nil and count("Comparing Review") == 0,
  "the status view says what it compares, the review views leave it to their own notice " .. heard())
for _, tb in ipairs({ tb_a, tb_b, status_tab }) do close_view(tb) end

-- Another press for a root whose view is still on its way is refused, and
-- says which; it issues nothing.
edit(RA)
notices = {}
issued = {}
hold = true
vim.cmd.edit(vim.fn.fnameescape(RA .. "/a.txt"))
require("ai.review").open()
vim.wait(10000, function() return #issued >= 1 end, 10)
require("ai.review").open()
vim.wait(2000, function() return said("still opening") ~= nil end, 20)
t.ok(said(("The review view of %s is still opening"):format(tilde(RA))) ~= nil,
  "a second press for RA while its view is on its way waits for it " .. heard())
vim.wait(5000, function() return #held > 0 end, 20)
release()
vim.wait(15000, function()
  tb_a = review_of(GA)
  return tb_a ~= nil and said("Root: " .. tilde(RA)) ~= nil
end, 20)
t.ok(tb_a ~= nil, "and the view arrives " .. heard())
t.eq(#issued, 1, "only once")
changes.get_diff_revision = real_listing
cd.open = real_open
close_view(tb_a)

---------------------------------------------------------------------------
-- Closing hands the keys back
---------------------------------------------------------------------------

for _, tb in ipairs(vim.api.nvim_list_tabpages()) do
  if cd.session(tb) then cd.close(tb) end
end
vim.wait(3000, function()
  for _, tb in ipairs(vim.api.nvim_list_tabpages()) do
    if cd.session(tb) then return false end
  end
  return true
end, 20)
t.eq({ map(file_buf, ",C"), map(file_buf, ",C", "x") }, { {}, {} }, "a file the view showed has no ,C once it closes")
t.eq(layout(bystander), bystander_layout, "and the bystander tabpage is as it was")

---------------------------------------------------------------------------
-- Cleanup
---------------------------------------------------------------------------

package.loaded["ai.review.feedback"] = nil
for _, term in ipairs(terminals) do pcall(vim.fn.jobstop, term.job) end
settle(100)
for _, term in ipairs(terminals) do pcall(vim.api.nvim_buf_delete, term.buf, { force = true }) end
vim.notify = real_notify
local cleanup = t.process_cleanup()
cleanup()
vim.cmd.cd(vim.fn.fnameescape(cwd))
vim.g.ai_review = saved_g
for k, v in pairs(saved_env) do vim.env[k] = v end
for _, dir in ipairs(dirs) do vim.fn.delete(dir, "rf") end
vim.fn.delete(gitconfig)
t.done()
