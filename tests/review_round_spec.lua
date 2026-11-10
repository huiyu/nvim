-- Review rounds (lua/ai/review/rounds.lua): the registry of native terminals
-- and CodeCompanion chats, the round rules every source goes through
-- (submit), the CodeCompanion source, the delivery checks (resolve_sink), the
-- <leader>av/aV facade keys, ai.feed's make_room, and CodeCompanion's own
-- code review being off.
--
-- Every repository is a scratch one under tempname(), with a space in its
-- path. No agent is started: the "agent terminals" run `cat` and carry the
-- Snacks record an agent panel would. Hook events go through the real
-- receiver (ai.review.hook) with payload files written here. The CodeCompanion
-- source runs on stubbed chat objects, plus one real API chat whose curl layer
-- is stubbed and which is never submitted -- its on_before_submit is
-- dispatched directly -- so nothing is sent and no ACP bridge is spawned.
local t = dofile("tests/helper.lua")

t.eq(package.loaded["ai.review.rounds"], nil, "the round registry is not loaded at startup")

local rounds = require("ai.review.rounds")
local hook = require("ai.review.hook")
local baseline = require("util.baseline")
local config = require("ai.config")
local uv = vim.uv
local INFO, WARN = vim.log.levels.INFO, vim.log.levels.WARN

-- `notes` is reset by each case; everything rounds itself shows is also kept
-- for the readability check at the end.
local notes, every_note, every_prompt = {}, {}, {}
local function from_rounds()
  local caller = debug.getinfo(3, "S")
  return caller ~= nil and caller.source:find("ai/review/rounds.lua", 1, true) ~= nil
end
local real_notify = vim.notify
vim.notify = function(msg, level, opts)
  notes[#notes + 1] = { msg = tostring(msg), level = level or INFO, title = opts and opts.title }
  if from_rounds() then every_note[#every_note + 1] = notes[#notes] end
end
local function noted(pattern)
  for _, n in ipairs(notes) do
    if n.msg:find(pattern, 1, true) then return n end
  end
end
local function pause(ms) vim.wait(ms or 50, function() return false end, 10) end

local spec_cwd = uv.cwd()
local saved_review = vim.g.ai_review
vim.g.ai_review = nil

---------------------------------------------------------------------------
-- Scratch repositories, under an isolated git config
---------------------------------------------------------------------------

local scratch = vim.fn.tempname() .. " review rounds"
vim.fn.mkdir(scratch, "p")
local saved_env = { GIT_CONFIG_NOSYSTEM = vim.env.GIT_CONFIG_NOSYSTEM, GIT_CONFIG_GLOBAL = vim.env.GIT_CONFIG_GLOBAL }
vim.env.GIT_CONFIG_NOSYSTEM = "1"
vim.env.GIT_CONFIG_GLOBAL = scratch .. "/gitconfig"
vim.fn.writefile({}, vim.env.GIT_CONFIG_GLOBAL)

local function git(dir, ...)
  return vim.system({ "git", "-C", dir, "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
    "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null", ... }, { text = true }):wait()
end
local function repo(name)
  local dir = scratch .. "/" .. name
  vim.fn.mkdir(dir .. "/sub dir", "p")
  git(dir, "init", "-q")
  vim.fn.writefile({ "one" }, dir .. "/a.txt")
  git(dir, "add", "a.txt")
  git(dir, "commit", "-qm", "fixture")
  return uv.fs_realpath(dir)
end
local R1, R2 = repo("first repo"), repo("second repo")
local PLAIN = scratch .. "/plain dir"
vim.fn.mkdir(PLAIN, "p")
PLAIN = uv.fs_realpath(PLAIN)

local edits = 0
local function edit(root)
  edits = edits + 1
  vim.fn.writefile({ ("edit %d %s"):format(edits, ("x"):rep(edits)) }, (root or R1) .. "/a.txt")
end

---Every round baseline in `root`, newest first.
local function rounds_in(root)
  local got
  baseline.list(root, "round", function(entries) got = entries end)
  vim.wait(5000, function() return got ~= nil end, 10)
  return got or {}
end
local function find_round(root, id)
  for _, e in ipairs(rounds_in(root)) do
    if e.id == id then return e end
  end
end

---------------------------------------------------------------------------
-- Watching submit(): what each event became, in order
---------------------------------------------------------------------------

local real_submit = rounds.submit
local submits, seq = {}, 0
rounds.submit = function(ev)
  local rec = { ev = ev }
  submits[#submits + 1] = rec
  local inner_done, inner_round = ev.done, ev.on_round
  ev.done = function()
    seq = seq + 1
    rec.done, rec.done_seq = true, seq
    if inner_done then inner_done() end
  end
  ev.on_round = function(round, reused)
    seq = seq + 1
    rec.round, rec.reused, rec.round_seq = round, reused, seq
    if inner_round then inner_round(round, reused) end
  end
  return real_submit(ev)
end

---Wait for submit number `n` to finish: released, and its round opened or
---kept when `want_round`; otherwise a moment for anything that should not
---happen.
local function settled(n, want_round)
  vim.wait(3000, function() return submits[n] ~= nil end, 10)
  local rec = submits[n]
  if not rec then return {} end
  vim.wait(8000, function() return rec.done and (not want_round or rec.round ~= nil) end, 10)
  if not want_round then pause(150) end
  return rec
end

local function payload_file(payload)
  local path = vim.fn.tempname() .. "-payload.json"
  vim.fn.writefile({ vim.json.encode(payload) }, path)
  return path, path .. ".done"
end

---Deliver a hook event through the real receiver. `give_up` deletes the
---payload at once, as the script does when its wait runs out.
local function hook_event(agent, event, payload, give_up)
  local path, done = payload_file(payload)
  local status = hook.event(agent, event, path, done)
  if give_up then os.remove(path) end
  return status, path, done
end

-- Most checks are not about the one-second repeat guard.
rounds._DEDUPE_MS = 0

---------------------------------------------------------------------------
-- Paths and tab variables
---------------------------------------------------------------------------

t.eq(rounds.toplevel(R1 .. "/sub dir"), R1, "toplevel: a subdirectory belongs to its worktree")
t.eq(rounds.toplevel(R1 .. "/a.txt"), R1, "toplevel: so does a file")
t.eq(rounds.toplevel(PLAIN), PLAIN, "toplevel: outside Git, the directory itself")
t.eq(rounds.draft_path(R1, "20261108T112233-0a0b"),
  ("%s/ai-review/%s/20261108T112233-0a0b.md"):format(vim.fn.stdpath("state"), vim.fn.sha256(R1):sub(1, 12)),
  "draft_path: state/ai-review/<sha256(realpath(root)):12>/<id>.md")
t.ok(rounds.nonce():match("^%d+%-%d+$") ~= nil, "the process nonce is <pid>-<hrtime>")

local fake_round = {
  kind = "round", id = "R-1", sha = "abc", root = R1, tree = "def",
  trailers = { Source = "claude", Conversation = "claude:s", Root = R1, Late = "1" },
}
t.eq(rounds.review_vars(fake_round),
  { id = "R-1", sha = "abc", conversation = "claude:s", source = "claude", root = R1, late = true },
  "review_vars: a round's metadata, Late as a boolean")
t.eq(rounds.review_vars(vim.tbl_extend("force", fake_round, { trailers = { Source = "manual", Root = R1 } })),
  { id = "R-1", sha = "abc", source = "manual", root = R1, late = false }, "review_vars: no owner, not late")
t.eq(rounds.review_vars(vim.tbl_extend("force", fake_round, { kind = "saved" })), nil, "review_vars: nil for a saved baseline")
t.eq(rounds.review_vars(nil), nil, "review_vars: nil for nothing")

---------------------------------------------------------------------------
-- The native registry
---------------------------------------------------------------------------

local terminals = {}
---A stand-in agent panel: a terminal running `cat`, recorded the way Snacks
---records an agent's command. Registered through the real TermOpen path.
local function agent_terminal(agent, cwd)
  vim.cmd.enew()
  local buf = vim.api.nvim_get_current_buf()
  local job = vim.fn.jobstart({ "cat" }, { term = true, cwd = cwd })
  vim.b[buf].snacks_terminal = { cmd = agent == "claude" and { "claude", "--settings", "{}" } or { "codex", "--yolo" }, cwd = cwd }
  terminals[#terminals + 1] = { buf = buf, job = job }
  vim.wait(1000, function()
    local e = rounds._state().native[agent]
    return e ~= nil and e.buf == buf
  end, 10)
  return buf, job
end
local native = rounds._state().native

local claude_buf = agent_terminal("claude", R1)
t.ok(native.claude ~= nil and native.claude.buf == claude_buf, "TermOpen registers a Claude panel")
t.eq(native.claude.root, R1, "its root is the Git toplevel of its cwd")
t.eq({ native.claude.session, native.claude.dirty }, { nil, false }, "with no session yet, and clean")
local codex_buf = agent_terminal("codex", R1 .. "/sub dir")
t.eq(native.codex and native.codex.root, R1, "a Codex panel started in a subdirectory belongs to the toplevel")

vim.cmd.enew()
local shell_job = vim.fn.jobstart({ "cat" }, { term = true })
pause(50)
t.ok(native.claude.buf == claude_buf and native.codex.buf == codex_buf, "a plain terminal registers nothing")
vim.fn.jobstop(shell_job)

-- Claude's SessionStart reports the foreground session, except a fork.
t.eq(hook_event("claude", "session", { session_id = "s1", source = "startup", cwd = R1 }), "ok", "SessionStart is accepted")
vim.wait(1000, function() return native.claude.session == "s1" end, 10)
t.eq(native.claude.session, "s1", "SessionStart(startup) sets the session")

-- dirty: typed input in Terminal-mode on a registered agent panel.
local real_mode = vim.api.nvim_get_mode
local function in_mode(mode, fn)
  vim.api.nvim_get_mode = function() return { mode = mode, blocking = false } end
  local ok, err = pcall(fn)
  vim.api.nvim_get_mode = real_mode
  assert(ok, err)
end
vim.api.nvim_set_current_buf(claude_buf)
in_mode("t", function()
  rounds._on_key("j", "j")
  rounds._on_key("\128\253K", vim.keycode("<ScrollWheelUp>"))
  rounds._on_key("x", "")
end)
t.eq(native.claude.dirty, false, "dirty: the config's own Terminal-mode keys (jk), the wheel and untyped keys do not count")
in_mode("n", function() rounds._on_key("a", "a") end)
t.eq(native.claude.dirty, false, "dirty: nothing outside Terminal-mode")
vim.api.nvim_set_current_buf(codex_buf)
in_mode("t", function() rounds._on_key("a", "a") end)
t.eq(native.claude.dirty, false, "dirty: input to another panel leaves this one alone")
t.eq(native.codex.dirty, true, "dirty: ... and marks that one")
native.codex.dirty = false
vim.api.nvim_set_current_buf(claude_buf)
in_mode("t", function() rounds._on_key("/", "/") end)
t.eq(native.claude.dirty, true, "dirty: typing into the agent's own panel marks it")

hook_event("claude", "session", { session_id = "s-fork", source = "fork", cwd = R1 })
pause(100)
t.eq({ native.claude.session, native.claude.dirty }, { "s1", true }, "SessionStart(fork) changes nothing")
hook_event("claude", "session", { session_id = "s1", source = "resume", cwd = R1 })
vim.wait(1000, function() return native.claude.dirty == false end, 10)
t.eq({ native.claude.session, native.claude.dirty }, { "s1", false }, "SessionStart(resume) reports the session and clears dirty")

---------------------------------------------------------------------------
-- The round rules, through the hook receiver
---------------------------------------------------------------------------

local function claude_submit(extra, give_up)
  local n = #submits + 1
  local _, path, done = hook_event("claude", "submit",
    vim.tbl_extend("force", { session_id = "s1", cwd = R1, prompt = "x" }, extra or {}), give_up)
  return n, path, done
end

-- A Claude prompt opens a round, owned by its session.
edit()
local n, _, done_path = claude_submit()
local rec = settled(n, true)
t.ok(rec.round ~= nil and rec.reused == false, "Claude UserPromptSubmit opens a round")
t.ok(rec.done_seq < rec.round_seq, "the hook is released when the tree is written, before the round is saved")
t.ok(uv.fs_stat(done_path) ~= nil, "the waiting script is told through its done file")
local first = find_round(R1, rec.round.id)
t.ok(first ~= nil, "the round is a baseline under refs/nvim-review/")
t.eq(first and first.trailers, { Source = "claude", Conversation = "claude:s1", Root = R1 },
  "with Source, Conversation and Root trailers, and no Late")
t.ok(first and first.subject:match("^nvim review: Claude round %d%d:%d%d:%d%d$") ~= nil,
  "and a subject for pickers (" .. tostring(first and first.subject) .. ")")
local count = #rounds_in(R1)

-- Nothing changed: the round is kept.
n = claude_submit()
rec = settled(n, true)
t.ok(rec.reused == true and rec.round.id == first.id, "an unchanged tree keeps the conversation's last round")
t.eq(#rounds_in(R1), count, "and saves nothing")

-- Every Claude prompt with changes opens one: there is no turn to dedupe by.
edit()
n = claude_submit()
rec = settled(n, true)
t.ok(rec.reused == false and rec.round.id ~= first.id, "the next Claude prompt with changes opens another round")
count = count + 1

-- A hook that fires twice within the window opens nothing the second time.
rounds._DEDUPE_MS = 60000
edit()
n = claude_submit()
rec = settled(n, false)
t.ok(rec.done and rec.round == nil, "a repeat within a second is released and opens nothing")
t.eq(#rounds_in(R1), count, "no round for the repeat")
rounds._DEDUPE_MS = 0

-- Codex: a steer repeats its turn id.
local function codex_submit(turn, extra)
  local m = #submits + 1
  hook_event("codex", "submit", vim.tbl_extend("force", { session_id = "c1", turn_id = turn, cwd = R1 }, extra or {}))
  return m
end
edit()
rec = settled(codex_submit("t1"), true)
t.ok(rec.round ~= nil and not rec.reused, "Codex UserPromptSubmit opens a round")
t.eq(find_round(R1, rec.round.id).trailers.Conversation, "codex:c1", "owned by codex:<session_id>")
t.eq(native.codex.session, "c1", "and reports the Codex session")
edit()
rec = settled(codex_submit("t1"), false)
t.ok(rec.done and rec.round == nil, "a steer (same turn_id) opens no new round")
rec = settled(codex_submit("t2"), true)
t.ok(rec.round ~= nil and not rec.reused, "the next turn does")

-- Subagents and teammates belong to the parent's turn.
local before = #submits
t.eq(hook_event("codex", "submit", { session_id = "c-child", turn_id = "t9", agent_id = "sub", cwd = R1 }), "ignored",
  "an event with agent_id is dropped by the receiver")
local released = false
rounds.native_event({ agent = "claude", event = "submit", payload = { session_id = "s-sub", agent_id = "x" },
  done = function() released = true end, gave_up = function() return false end })
pause(150)
t.ok(released and #submits == before, "and by native_event: released, no submit")
t.eq({ native.claude.session, native.codex.session }, { "s1", "c1" }, "neither changed a session")

-- Claude waking itself when a background task finishes goes on with the turn.
local NOTIFICATION = "<task-notification>\n<task-id>b1</task-id>\n<status>completed</status>\n</task-notification>"
before = #submits
local rounds_before = #rounds_in(R1)
edit()
local asked_before = os.time()
-- Only the notification can set these back.
rounds._state().prompted["claude:s1"] = nil
native.claude.session, native.claude.dirty = "s-other", true
local _, _, notify_done = hook_event("claude", "submit", { session_id = "s1", cwd = R1, prompt = NOTIFICATION })
vim.wait(3000, function() return uv.fs_stat(notify_done) ~= nil end, 10)
pause(150)
t.ok(uv.fs_stat(notify_done) ~= nil, "a background task's notification releases the hook at once")
t.eq({ #submits, #rounds_in(R1) }, { before, rounds_before }, "and opens no round, though the tree changed")
t.ok((rounds.prompted_at("claude:s1") or 0) >= asked_before, "but marks the session prompted")
t.eq({ native.claude.session, native.claude.dirty }, { "s1", false }, "and still reports its session")
-- A background agent's hand-back, idle (framed) or queued during a turn (bare).
local HANDBACK = '<agent-message from="a51adc1b9a1fa2e89">\n[Subagent hand-back] The text below is the final report.'
for _, prompt in ipairs({
  "Another Claude session sent a message:\n" .. HANDBACK,
  "Another Claude session sent a message while you were working:\n" .. HANDBACK,
  HANDBACK,
}) do
  n = claude_submit({ prompt = prompt })
  pause(150)
  t.eq(#submits, before, "a background agent's hand-back opens no round: " .. prompt:sub(1, 40):gsub("\n", " "))
end
for _, prompt in ipairs({
  'Another Claude session sent a message:\n<agent-message from="teammate">\nPlease review the parser.',
  '<cross-session-message from="x">\n[Subagent hand-back] quoted</cross-session-message>',
  'please explain [Subagent hand-back] and <agent-message>',
}) do
  edit()
  rec = settled(claude_submit({ prompt = prompt }), true)
  t.ok(rec.round ~= nil and not rec.reused, "a request opens its round: " .. prompt:sub(1, 40):gsub("\n", " "))
  before = #submits
end
n = claude_submit({ prompt = "  " .. NOTIFICATION })
pause(150)
t.eq(#submits, before, "leading blanks do not hide one")
t.eq({ rounds._continues_turn(nil), rounds._continues_turn(42) }, { false, false }, "no prompt is no wake-up")
edit()
n = claude_submit({ prompt = "explain <task-notification> to me" })
rec = settled(n, true)
t.ok(rec.round ~= nil and not rec.reused, "a prompt that only mentions it opens a round as any other")
count = #rounds_in(R1)
edit()
rec = settled(codex_submit("t-notify", { prompt = NOTIFICATION }), true)
t.ok(rec.round ~= nil and not rec.reused, "Codex has no such prompt: its submits open rounds whatever they say")

-- Late: the script stopped waiting before the tree was written.
edit()
n = claude_submit(nil, true)
rec = settled(n, true)
local late = rec.round and find_round(R1, rec.round.id)
t.eq(late and late.trailers.Late, "1", "a baseline that lands after the script gave up is Late")
t.eq(late and rounds.review_vars(late).late, true, "and review_vars says so")

-- Claude's Bash can leave the repository; the session's root stays.
notes = {}
edit()
n = claude_submit({ cwd = R2 })
rec = settled(n, true)
t.eq(rec.round and find_round(R1, rec.round.id).trailers.Root, R1, "a prompt from another cwd still rounds the session's root")
local drift = noted("still recorded for")
t.ok(drift ~= nil and drift.msg:find(vim.fn.fnamemodify(R2, ":~"), 1, true) ~= nil, "and says where the agent is, once")
notes = {}
edit()
settled(claude_submit({ cwd = R2 }), true)
t.eq(noted("still recorded for"), nil, "only once")

-- Outside Git: the registry is updated, nothing else.
local plain_buf, plain_job = agent_terminal("codex", PLAIN)
t.eq(native.codex.root, PLAIN, "a Codex panel outside Git registers with its directory")
rec = settled(codex_submit("p1", { session_id = "c-plain", cwd = PLAIN }), false)
t.ok(rec.done and rec.round == nil, "a prompt there is released and opens no round")
t.eq(native.codex.session, "c-plain", "but its session is recorded")
notes = {}
n = #submits + 1
rounds.submit({ source = "claude", conversation = "claude:z", root = PLAIN })
rec = settled(n, false)
t.ok(rec.done and rec.round == nil and #notes == 0, "submit outside Git: released, silent, no round")

-- A failure says what failed, and git's (or Lua's) words on a line of their own.
do
  local real_snapshot, real_save, real_locate = baseline.snapshot, baseline.save, baseline.locate
  local function failing(what, field, stub)
    baseline[field] = stub
    notes = {}
    n = #submits + 1
    rounds.submit({ source = "claude", conversation = "claude:failing", root = R1 })
    rec = settled(n, false)
    baseline.snapshot, baseline.save, baseline.locate = real_snapshot, real_save, real_locate
    t.ok(rec.done and rec.round == nil, what .. ": the source is released, no round")
    return notes[1] and notes[1].level == WARN and notes[1].msg or ""
  end
  local said = failing("no snapshot", "snapshot", function(_, cb) cb(nil, "spec: no snapshot") end)
  t.ok(said:find("^No review baseline for this Claude prompt:\nspec: no snapshot$") ~= nil, "and says why: " .. vim.inspect(said))
  edit()
  said = failing("the round not saved", "save", function(_, _, _, cb) cb(nil, "spec: not saved") end)
  t.ok(said:find("^Could not save the review round:\nspec: not saved$") ~= nil, "and says why: " .. vim.inspect(said))
  said = failing("an error", "locate", function() error("spec: locate threw", 0) end)
  t.ok(said:find("^Review round failed:\nspec: locate threw$") ~= nil, "and says what: " .. vim.inspect(said))
end

-- TermClose forgets the panel.
vim.fn.jobstop(plain_job)
vim.wait(2000, function() return native.codex == nil end, 10)
t.eq(native.codex, nil, "TermClose removes the panel from the registry")
pcall(vim.api.nvim_buf_delete, plain_buf, { force = true })
rounds.track_terminal(codex_buf)
t.eq(native.codex and native.codex.buf, codex_buf, "the R1 Codex panel registers again")
settled(codex_submit("t3"), true)
t.eq(native.codex.session, "c1", "and learns its session from the next prompt")

---------------------------------------------------------------------------
-- Retention spares a round with a draft
---------------------------------------------------------------------------

local drafts = scratch .. "/drafts"
local real_draft_path = rounds.draft_path
rounds.draft_path = function(root, id) return ("%s/%s/%s.md"):format(drafts, vim.fn.sha256(root):sub(1, 12), id) end
local probe = { kind = "round", root = R1, id = "probe" }
t.eq(rounds._exempt(probe), false, "exempt: no draft")
vim.fn.mkdir(vim.fs.dirname(rounds.draft_path(R1, "probe")), "p")
vim.fn.writefile({}, rounds.draft_path(R1, "probe"), "b")
t.eq(rounds._exempt(probe), false, "exempt: an empty draft does not count")
vim.fn.writefile({ "> keep this" }, rounds.draft_path(R1, "probe"))
t.eq(rounds._exempt(probe), true, "exempt: a non-empty draft does")
t.eq(rounds._exempt(vim.tbl_extend("force", probe, { kind = "saved" })), false, "exempt: rounds only")

local all = rounds_in(R1)
local oldest = all[#all]
vim.fn.writefile({ "> feedback in progress" }, rounds.draft_path(R1, oldest.id))
vim.g.ai_review = { retention = { rounds = 1 } }
edit()
local newest = settled(claude_submit(), true).round
vim.wait(5000, function() return #rounds_in(R1) == 2 end, 50)
local kept = vim.tbl_map(function(e) return e.id end, rounds_in(R1))
t.eq(kept, { newest.id, oldest.id }, "retention keeps the newest round and the one with a draft, nothing else")
vim.g.ai_review = nil
rounds.draft_path = real_draft_path

---------------------------------------------------------------------------
-- CodeCompanion: stubbed chats
---------------------------------------------------------------------------

rounds.chat_created({ bufnr = 1, id = 1 })
t.eq(next(rounds._state().chats), nil, "ChatCreated with CodeCompanion unloaded does nothing")

local function fake_chat(id, adapter_type, cwd)
  local chat = {
    id = id,
    bufnr = vim.api.nvim_create_buf(false, true),
    adapter = { type = adapter_type, name = adapter_type == "acp" and "claude_code" or "anthropic",
      formatted_name = adapter_type == "acp" and "Claude Code" or "Anthropic" },
    callbacks = {},
  }
  function chat:add_callback(event, fn)
    self.callbacks[event] = self.callbacks[event] or {}
    table.insert(self.callbacks[event], fn)
    return self
  end
  vim.fn.chdir(cwd)
  local entry = rounds.attach_chat(chat)
  vim.fn.chdir(spec_cwd)
  return chat, entry
end
local function before_submit(chat)
  local cb = (chat.callbacks.on_before_submit or {})[1]
  return cb and cb(chat, { adapter = chat.adapter })
end

local http, http_entry = fake_chat(4242, "http", R1 .. "/sub dir")
local http_conv = ("cc:%s:4242"):format(rounds.nonce())
t.eq(http_entry and http_entry.conversation, http_conv, "a chat's conversation is cc:<nonce>:<chat.id>")
t.eq({ http_entry.kind, http_entry.root }, { "cc-http", R1 }, "an API chat is cc-http, rooted at the cwd's toplevel")
t.eq(#(http.callbacks.on_before_submit or {}), 1, "on_before_submit is hooked")

edit()
n = #submits + 1
local ret = before_submit(http)
t.ok(ret ~= false, "the callback never cancels the submit")
t.ok(submits[n] and submits[n].done == true, "the baseline's tree is written before the callback returns")
rec = settled(n, true)
local cc_round = rec.round and find_round(R1, rec.round.id)
t.eq(cc_round and cc_round.trailers, { Source = "cc-http", Conversation = http_conv, Root = R1 },
  "the round belongs to the chat, and is not Late")

vim.g.ai_review = { hook_wait_ms = 0 }
edit()
n = #submits + 1
before_submit(http)
t.ok(submits[n] and not submits[n].done, "with hook_wait_ms = 0 the submit goes ahead at once")
rec = settled(n, true)
t.eq(rec.round and find_round(R1, rec.round.id).trailers.Late, "1", "and its baseline is Late")

vim.g.ai_review = { sources = { codecompanion_http = false } }
before = #submits
edit()
t.ok(before_submit(http) ~= false and #submits == before, "sources.codecompanion_http = false: a hooked chat opens nothing")
local gated = fake_chat(4343, "http", R1)
t.eq(gated.callbacks.on_before_submit, nil, "and a chat created meanwhile is not hooked")
vim.g.ai_review = nil

local acp, acp_entry = fake_chat(5151, "acp", R1)
t.eq(acp_entry.kind, "cc-acp", "an agent chat is cc-acp")
edit()
n = #submits + 1
before_submit(acp)
rec = settled(n, true)
t.eq(rec.round and find_round(R1, rec.round.id).trailers.Source, "cc-acp", "and its rounds say so")

do
  local real_before = rounds._before_submit
  rounds._before_submit = function() error("spec: before_submit threw", 0) end
  notes = {}
  local ok = before_submit(acp) ~= false
  rounds._before_submit = real_before
  t.ok(ok and notes[1] and notes[1].msg == "Review round for a chat failed:\nspec: before_submit threw",
    "a round that fails never cancels the submit, and says why: " .. vim.inspect(notes[1] and notes[1].msg))
end

vim.api.nvim_exec_autocmds("User", { pattern = "CodeCompanionChatClosed", data = { bufnr = gated.bufnr, id = gated.id } })
t.eq(rounds._state().chats[("cc:%s:4343"):format(rounds.nonce())], nil, "ChatClosed forgets the chat")

---------------------------------------------------------------------------
-- Delivery checks
---------------------------------------------------------------------------

local real_select = vim.ui.select
local selects, answers = {}, {}
vim.ui.select = function(items, opts, on_choice)
  selects[#selects + 1] = { items = items, prompt = opts.prompt, kind = opts.kind,
    labels = vim.tbl_map(function(i) return opts.format_item and opts.format_item(i) or i end, items) }
  if from_rounds() then every_prompt[#every_prompt + 1] = selects[#selects] end
  local answer = table.remove(answers, 1)
  on_choice(answer and answer(items) or nil)
end
local function choose(want)
  return function(items)
    for _, item in ipairs(items) do
      local text = type(item) == "table" and item.label or item
      if text:find(want, 1, true) then return item end
    end
  end
end
local function resolve(conversation, root, ...)
  selects, answers, notes = {}, { ... }, {}
  local target, reason, finished
  rounds.resolve_sink(conversation, root, function(tg, why) target, reason, finished = tg, why, true end)
  vim.wait(500, function() return finished end, 10)
  return target, reason
end
local function kinds() return vim.tbl_map(function(s) return s.kind end, selects) end

local r2_chat = fake_chat(6161, "http", R2)
local r2_conv = ("cc:%s:6161"):format(rounds.nonce())

local target, reason = resolve("claude:s1", R1)
t.ok(target and target.kind == "native" and target.agent == "claude" and target.conversation == "claude:s1",
  "owner running the round's session, clean: delivered to it")
t.eq(#selects, 0, "without asking")
t.ok(target and target.redirected == false and target.owner == "claude:s1", "not redirected")

native.claude.dirty = true
target = resolve("claude:s1", R1, choose("Deliver"))
t.eq(kinds(), { "ai_review_confirm" }, "dirty: asks first")
t.ok(noted("/new, /resume or /fork") ~= nil, "saying why")
t.ok(selects[1] and selects[1].prompt:find("Deliver anyway?", 1, true) ~= nil, "in a notice beside the question")
t.ok(target and target.agent == "claude", "and delivers once confirmed")
target, reason = resolve("claude:s1", R1, choose("Cancel"))
t.ok(target == nil and reason == "cancelled", "cancelling refuses")
vim.g.ai_review = { unknown_session = "refuse" }
target, reason = resolve("claude:s1", R1)
t.ok(target == nil and reason == "unknown-session" and #selects == 0, "unknown_session = refuse: refused without asking")
vim.g.ai_review = nil
native.claude.dirty = false

native.codex.session = nil
target = resolve("codex:c1", R1, choose("Deliver"))
t.eq(kinds(), { "ai_review_confirm" }, "a session not reported yet: asks first")
t.ok(noted("first prompt") ~= nil, "explaining Codex reports it at the first prompt")
t.ok(target and target.agent == "codex", "and delivers once confirmed")
native.codex.session = "c1"
native.claude.session = nil
target = resolve("claude:s1", R1, choose("Deliver"))
t.ok(kinds()[1] == "ai_review_confirm" and noted("Claude Code has not reported its session") ~= nil and target ~= nil,
  "a Claude panel that has not reported its session asks the same way")
native.claude.session = "s1"

vim.g.ai_review = { always_confirm = { "claude" } }
target = resolve("claude:s1", R1, choose("Deliver"))
t.ok(#selects == 1 and target ~= nil, "always_confirm: asks even when the session is known")
target = resolve("codex:c1", R1)
t.ok(#selects == 0 and target ~= nil, "but only for the agents it names")
vim.g.ai_review = nil

-- Rule 1, which nothing bypasses.
target, reason = resolve("claude:s1", R2)
t.ok(target == nil and reason == "root" and #selects == 0, "another root: refused, nothing asked")
t.ok(#notes == 1 and notes[1].level == WARN and notes[1].title == "AI review", "with a warning")
target, reason = resolve(r2_conv, R1)
t.ok(target == nil and reason == "root" and #selects == 0, "a chat in another root: refused the same way")
target, reason = resolve("claude:s1", { R1, R2 })
t.ok(target == nil and reason == "root" and #selects == 0, "view and draft disagreeing about the root: refused")
target = resolve("claude:s1", { R1 .. "/sub dir/..", R1 })
t.ok(target ~= nil, "roots are compared as realpaths")

-- Rule 4: the owner is gone.
target, reason = resolve("claude:other", R1, choose("Keep the draft"))
t.ok(target == nil and reason == "owner-gone", "another session in the owner's terminal: refused")
t.eq(kinds(), { "ai_review_redirect" }, "offering to send it to a current session")
t.ok(notes[1] and notes[1].msg:find("/resume", 1, true) ~= nil, "and saying how to get the owner back")
t.ok(selects[1] and notes[1] and selects[1].prompt == vim.split(notes[1].msg, "\n")[1],
  "the offer is headed by the notice's first line (" .. tostring(selects[1] and selects[1].prompt) .. ")")
target = resolve("claude:other", R1, choose("current session"), choose("Codex"), choose("Send"))
t.eq(kinds(), { "ai_review_redirect", "ai_review_target", "ai_review_confirm" }, "redirect: offer, pick, confirm")
local labels = selects[2] and table.concat(selects[2].labels, " | ") or ""
t.ok(labels:find("Claude Code · session s1", 1, true) and labels:find("Codex · session c1", 1, true)
  and labels:find("#" .. http.bufnr, 1, true) and not labels:find("#" .. r2_chat.bufnr, 1, true),
  "of this root only: both panels and the chats (" .. labels .. ")")
t.ok(selects[3] and selects[3].prompt:find("belongs to Claude Code session other", 1, true)
  and selects[3].labels[1]:find("Codex · session c1", 1, true), "the confirmation names the owner and the new target")
t.ok(target and target.agent == "codex" and target.redirected == true and target.owner == "claude:other",
  "confirmed: delivered to the new target, marked redirected")

vim.g.ai_review = { redirect = false }
target, reason = resolve("claude:other", R1)
t.ok(target == nil and reason == "owner-gone" and #selects == 0, "redirect = false: refused, nothing offered")
vim.g.ai_review = nil

local saved_codex = native.codex
native.codex = nil
target, reason = resolve("codex:c1", R1, choose("Keep"))
t.ok(target == nil and reason == "owner-gone" and kinds()[1] == "ai_review_redirect",
  "owner's agent not running: refused, with the offer")
t.ok(notes[1] and notes[1].msg:find("not running", 1, true) and notes[1].msg:find("codex resume", 1, true),
  "telling how to resume Codex")
native.codex = saved_codex
local saved_claude = native.claude
native.claude = nil
target, reason = resolve("claude:s1", R1, choose("Keep"))
t.ok(target == nil and reason == "owner-gone" and notes[1]
  and notes[1].msg:find("resume session s1 with <leader>ar", 1, true) ~= nil,
  "a Claude owner not running: refused, telling which session to resume")
native.claude = saved_claude

-- The owner's agent relaunched in another root. Whether that terminal still
-- runs the owner is asked first: another session there, or one not reported
-- yet, is the owner gone (with the same-root offer); only the owner's own
-- session there is a root refusal.
local function not_listed(agent)
  for _, item in ipairs(selects[2] and selects[2].items or {}) do
    if item.agent == agent then return false end
  end
  return selects[2] ~= nil
end
local claude_was = { root = native.claude.root, session = native.claude.session }
native.claude.root, native.claude.session = R2, "b2"
target, reason = resolve("claude:s1", R1, choose("Keep the draft"))
t.ok(target == nil and reason == "owner-gone", "owner's agent now in another root and another session: the owner is gone")
t.eq(kinds(), { "ai_review_redirect" }, "so the redirect is offered, not a root refusal")
t.ok(notes[1] and notes[1].msg:find(vim.fn.fnamemodify(R2, ":~"), 1, true) ~= nil
  and notes[1].msg:find("session b2", 1, true) ~= nil and notes[1].msg:find("<leader>ar", 1, true) ~= nil,
  "saying where and in which session the agent runs now, and how to get the owner back")
target = resolve("claude:s1", R1, choose("current session"), choose("Codex"), choose("Send"))
t.eq(kinds(), { "ai_review_redirect", "ai_review_target", "ai_review_confirm" }, "redirect: offer, pick, confirm")
t.ok(not_listed("claude"), "the picker lists this root's sessions, not the panel in the other root")
t.ok(target and target.agent == "codex" and target.root == R1 and target.redirected == true,
  "confirmed: delivered to this root's Codex, marked redirected")
native.claude.session = nil
target, reason = resolve("claude:s1", R1, choose("Keep the draft"))
t.ok(target == nil and reason == "owner-gone" and kinds()[1] == "ai_review_redirect",
  "in another root with its session not reported yet: the owner is gone too, with the offer")
t.ok(notes[1] and notes[1].msg:find("has not reported its session", 1, true) ~= nil, "saying so")
native.claude.session = "s1"
target, reason = resolve("claude:s1", R1)
t.ok(target == nil and reason == "root" and #selects == 0, "the owner's own session in another root: refused, nothing offered")
native.claude.dirty = true
target, reason = resolve("claude:s1", R1)
t.ok(target == nil and reason == "root" and #selects == 0, "also when it was typed into since it said so")
native.claude.dirty = false
native.claude.root, native.claude.session = claude_was.root, claude_was.session

local codex_was = { root = native.codex.root, session = native.codex.session }
native.codex.root, native.codex.session = R2, nil
target, reason = resolve("codex:c1", R1, choose("current session"), choose("Claude Code · session"), choose("Send"))
t.ok(selects[1] and selects[1].kind == "ai_review_redirect" and not_listed("codex"),
  "a Codex panel relaunched in another root before its first prompt: the owner is gone, with the offer")
t.ok(target and target.agent == "claude" and target.redirected == true, "and the redirect delivers to this root's Claude")
native.codex.root, native.codex.session = codex_was.root, codex_was.session

-- Chats.
target = resolve(http_conv, R1)
t.ok(target and target.kind == "cc" and target.chat == http and #selects == 0, "an open chat of this process: delivered")
http.current_request = {}
target, reason = resolve(http_conv, R1)
t.ok(target == nil and reason == "busy" and #selects == 0, "a chat with a request in flight: refused")
http.current_request = nil
http._turn_in_progress = true
target, reason = resolve(http_conv, R1)
t.ok(target == nil and reason == "busy", "a chat between two steps of its tool loop: refused too")
http._turn_in_progress = nil
target, reason = resolve("cc:1-2:4242", R1, choose("Keep"))
t.ok(target == nil and reason == "owner-gone" and kinds()[1] == "ai_review_redirect",
  "a chat id from another Nvim (other nonce): refused, with the offer")
http.current_request = {}
target, reason = resolve("claude:gone", R1, choose("current session"), choose("API chat"), choose("Send"))
t.ok(target == nil and reason == "busy", "a redirect to a busy chat is still refused")
http.current_request = nil

-- No owner.
target = resolve(nil, R1, choose("Agent chat"))
t.eq(kinds(), { "ai_review_target" }, "no owner: the picker opens at once, with no second confirmation")
t.ok(target and target.chat == acp and target.redirected == false, "and delivers to the pick")
target = resolve(nil, R2, choose("API chat"))
t.ok(selects[1] and #selects[1].items == 1 and target and target.chat == r2_chat, "it lists the sessions of that root only")
target, reason = resolve(nil, PLAIN)
t.ok(target == nil and reason == "no-session" and #selects == 0, "no session there: refused")
t.ok(notes[1] and notes[1].msg:find("No session to deliver to", 1, true) ~= nil, "saying so")
target, reason = resolve("nonsense", R1)
t.ok(target == nil and reason == "unknown", "an unknown conversation id is refused")

vim.ui.select = real_select

---------------------------------------------------------------------------
-- <leader>aV: who owns a manual round
---------------------------------------------------------------------------

local function start(buf, no_round)
  n = #submits + 1
  notes = {}
  vim.api.nvim_set_current_buf(buf)
  rounds.start()
  return settled(n, not no_round)
end
local function owner_of(rec_)
  local e = rec_.round and rec_.round.id and find_round(rec_.round.root or R1, rec_.round.id)
  return e and e.trailers.Conversation, e
end

edit()
rec = start(claude_buf)
local owner, entry = owner_of(rec)
t.eq({ owner, entry and entry.trailers.Source }, { "claude:s1", "manual" }, "aV in an agent panel: owned by its session")
t.ok(noted("started") ~= nil, "and says it started")
rec = start(claude_buf)
t.ok(rec.reused == true and noted("already the current state") ~= nil, "aV again with nothing changed only says so")

vim.cmd.edit(vim.fn.fnameescape(R1 .. "/a.txt"))
local file_buf = vim.api.nvim_get_current_buf()
vim.cmd("silent AI provider claude")
edit()
t.eq((owner_of(start(file_buf))), "claude:s1", "aV in a file: the active provider's panel in this root owns it")
vim.cmd("silent AI provider codex")
edit()
t.eq((owner_of(start(file_buf))), "codex:c1", "after a switch, the other agent's")
vim.cmd("silent AI provider " .. config.startup.provider)

vim.cmd.edit(vim.fn.fnameescape(R2 .. "/a.txt"))
edit(R2)
rec = start(vim.api.nvim_get_current_buf())
owner, entry = owner_of(rec)
t.ok(entry ~= nil and owner == nil and entry.root == R2, "aV where no panel runs: a round without an owner")
t.ok(noted("No conversation yet") ~= nil, "saying feedback will ask where to go")

edit()
t.eq((owner_of(start(acp.bufnr))), ("cc:%s:5151"):format(rounds.nonce()), "aV in a chat buffer: owned by the chat")

native.codex.session = nil
edit()
owner, entry = owner_of(start(codex_buf))
t.ok(entry ~= nil and owner == nil, "aV in a panel that has not reported its session: no owner")
native.codex.session = "c1"

vim.cmd.edit(vim.fn.fnameescape(PLAIN .. "/x.txt"))
rec = start(vim.api.nvim_get_current_buf(), true)
t.ok(rec.done and rec.round == nil and noted("not a git repository") ~= nil, "aV outside Git says so")

---------------------------------------------------------------------------
-- Which round <leader>av shows
---------------------------------------------------------------------------

local function select_round(root, buf)
  local got, why, finished
  rounds.select_round(root, function(e, w) got, why, finished = e, w, true end, { buf = buf })
  vim.wait(5000, function() return finished end, 10)
  return got, why
end
local function newest_of(root, conversation)
  for _, e in ipairs(rounds_in(root)) do
    if e.trailers.Conversation == conversation then return e end
  end
end
local scratch_buf = vim.api.nvim_create_buf(false, true)
local picked, why = select_round(R1, claude_buf)
t.ok(picked and why == "buffer" and picked.id == newest_of(R1, "claude:s1").id,
  "select_round: from an agent panel, that session's newest round")
local active_conv = config.provider .. ":" .. native[config.provider].session
picked, why = select_round(R1, scratch_buf)
t.ok(picked and why == "active" and picked.id == newest_of(R1, active_conv).id,
  "select_round: elsewhere, the active provider's session's newest round (" .. active_conv .. ")")
picked, why = select_round(R2, scratch_buf)
local r2_newest = rounds_in(R2)[1]
t.ok(picked and why == "process" and picked.id == r2_newest.id, "select_round: else the newest this process opened there")
rounds._state().newest_here[R2] = nil
picked, why = select_round(R2, scratch_buf)
t.ok(picked and why == "latest" and picked.id == r2_newest.id, "select_round: else the newest there at all")
picked, why = select_round(PLAIN, scratch_buf)
t.ok(picked == nil and type(why) == "string", "select_round: nothing outside Git, with the reason")

---------------------------------------------------------------------------
-- A real API chat: ChatCreated hooks it, and the callback never cancels
---------------------------------------------------------------------------

local function store_listing()
  local listing = {}
  for _, dir in ipairs({ vim.fn.stdpath("data") .. "/codecompanion-history", vim.fn.stdpath("data") .. "/codecompanion/sessions" }) do
    if vim.fn.isdirectory(dir) == 1 then
      for name, kind in vim.fs.dir(dir, { depth = 3 }) do
        local stat = kind == "file" and uv.fs_stat(dir .. "/" .. name)
        listing[dir .. "/" .. name] = stat and (stat.mtime.sec .. "." .. stat.mtime.nsec) or kind
      end
    end
  end
  return listing
end
local VARS = { "NVIM_ANTHROPIC_API_KEY", "NVIM_OPENAI_API_KEY" }
local saved_keys = {}
for _, var in ipairs(VARS) do saved_keys[var] = vim.env[var] end
vim.env.NVIM_ANTHROPIC_API_KEY = "sk-ant-spec-not-a-key"
vim.env.NVIM_OPENAI_API_KEY = "sk-spec-not-a-key"
local stores_before = store_listing()

require("lazy").load({ plugins = { "codecompanion.nvim" } })
local Curl = require("codecompanion.utils.curl")
local requests = {}
Curl.request = function(opts)
  requests[#requests + 1] = (opts.method or "GET"):upper()
  return {}
end
Curl.request_sync = function(opts)
  requests[#requests + 1] = (opts.method or "GET"):upper()
  return nil, { message = "stubbed by review_round_spec" }
end

t.eq(vim.fn.exists(":CodeCompanionCodeReview"), 0, ":CodeCompanionCodeReview is gone")
t.eq(require("codecompanion.config").interactions.code_review.enabled, false, "CodeCompanion's code review is off")

vim.fn.chdir(R1)
vim.cmd.edit(vim.fn.fnameescape(R1 .. "/a.txt"))
local chat = require("codecompanion").chat({ params = { adapter = config.codecompanion.http_adapter } })
vim.fn.chdir(spec_cwd)
local real_conv = chat and ("cc:%s:%s"):format(rounds.nonce(), chat.id)
local real_entry = real_conv and rounds._state().chats[real_conv]
t.ok(real_entry ~= nil and real_entry.root == R1 and real_entry.kind == "cc-http", "ChatCreated registers a real API chat")
local ours = 0
for _ in ipairs(chat and chat.callbacks.on_before_submit or {}) do ours = ours + 1 end
t.ok(ours >= 1, "and hooks its on_before_submit")
edit()
n = #submits + 1
local cancelled = chat and chat:dispatch_cancellable("on_before_submit",
  { adapter = require("codecompanion.adapters").make_safe(chat.adapter) })
t.eq(cancelled, false, "dispatching on_before_submit does not cancel the submit")
rec = settled(n, true)
t.eq(rec.round and find_round(R1, rec.round.id).trailers.Conversation, real_conv, "and opens the chat's round")
if chat then chat:close() end
t.eq(rounds._state().chats[real_conv], nil, "closing the chat forgets it")
pause(100)
t.eq(vim.tbl_filter(function(m) return m ~= "GET" end, requests), {}, "nothing was sent")
t.eq(store_listing(), stores_before, "no chat history or session was written")
for _, var in ipairs(VARS) do vim.env[var] = saved_keys[var] end

---------------------------------------------------------------------------
-- ai.feed makes room for the agent it feeds
---------------------------------------------------------------------------

local ai = require("ai")
local backends = { claude = require("ai.backend.claude"), codex = require("ai.backend.codex") }
local saved_fns, shown, hidden, fed = {}, {}, {}, {}
for name, b in pairs(backends) do
  saved_fns[name] = { window = b.window, visible = b.visible, hide = b.hide, edit_prompt = b.edit_prompt }
  -- A window id no tabpage has: 1000 is Nvim's first window, which the slot
  -- would rightly refuse to hide as the tabpage's last one.
  b.window = function() return shown[name] and 999999 or nil end
  b.visible = function() return shown[name] == "here" end
  b.hide = function() hidden[#hidden + 1] = name; shown[name] = nil end
  b.edit_prompt = function(opts) fed[#fed + 1] = { name, opts and opts.seed } end
end
local function feed_case(active, state, target)
  vim.cmd("silent AI provider " .. active)
  shown, hidden, fed = vim.deepcopy(state), {}, {}
  ai.feed(target, "edit_prompt", { seed = "feedback" })
  return hidden, fed
end
local h, f = feed_case("claude", { claude = "here" }, "codex")
t.eq({ h, f }, { { "claude" }, { { "codex", "feedback" } } },
  "feeding Codex while Claude is active hides Claude's panel here, and feeds Codex")
h, f = feed_case("codex", { codex = "here" }, "claude")
t.eq({ h, f }, { { "codex" }, { { "claude", "feedback" } } }, "and the other way round")
h = feed_case("claude", { claude = "here", codex = "elsewhere" }, "codex")
t.eq(h, {}, "a target already shown in another tabpage makes nothing yield")
h = feed_case("codex", { claude = "here" }, "codex")
t.eq(h, { "claude" }, "feeding the active agent makes room as its keys do")
vim.cmd("silent AI provider claude")
shown, hidden = { claude = "here" }, {}
ai.feed("codex", "running")
t.eq(hidden, {}, "a method that reveals nothing hides nothing")
notes, fed = {}, {}
ai.feed("nope", "edit_prompt")
t.ok(#notes == 1 and notes[1].level == WARN and #fed == 0, "an unknown provider is refused")
for name, b in pairs(backends) do
  for k, fn in pairs(saved_fns[name]) do b[k] = fn end
end
vim.cmd("silent AI provider " .. config.startup.provider)

---------------------------------------------------------------------------
-- <leader>av / <leader>aV
---------------------------------------------------------------------------

local function keymap(lhs, mode) return vim.fn.maparg(lhs, mode or "n", false, true) end
local DESCS = { [" av"] = "Review changes since round baseline", [" aV"] = "Start a review round" }
for _, provider in ipairs({ config.startup.provider, config.startup.provider == "claude" and "codex" or "claude" }) do
  vim.cmd("silent AI provider " .. provider)
  for lhs, desc in pairs(DESCS) do
    t.eq(keymap(lhs).desc, desc, ("%s under %s: %q"):format(lhs, provider, desc))
    t.eq(keymap(lhs, "x"), {}, lhs .. " is Normal-mode only")
  end
end
vim.cmd("silent AI provider " .. config.startup.provider)
local calls = {}
local real_view, real_start = package.loaded["ai.review"], rounds.start
package.loaded["ai.review"] = { open = function() calls[#calls + 1] = "open" end }
rounds.start = function() calls[#calls + 1] = "start" end
keymap(" av").callback()
keymap(" aV").callback()
package.loaded["ai.review"], rounds.start = real_view, real_start
t.eq(calls, { "open", "start" }, "<leader>av opens the review, <leader>aV starts a round")

---------------------------------------------------------------------------
-- Everything rounds showed above stays readable
---------------------------------------------------------------------------

-- The snacks notifier cuts a line off at its width.max, 0.4 x 'columns' (62
-- cells of text at 160), instead of wrapping it; vim.ui.select is the snacks
-- picker, whose prompt is a one-line title of a window at least 80 columns
-- wide. This spec's scratch paths are long, so each counts as a typical one.
do
  local function typical(text)
    for _, path in ipairs({ R1, R2, PLAIN }) do
      for _, form in ipairs({ vim.fn.fnamemodify(path, ":~"), path }) do
        text = text:gsub(vim.pesc(form), "~/src/project")
      end
    end
    return text
  end
  local too_long = {}
  for _, note in ipairs(every_note) do
    for _, line in ipairs(vim.split(typical(note.msg), "\n", { plain = true })) do
      if vim.fn.strdisplaywidth(line) > 60 then too_long[#too_long + 1] = line end
    end
  end
  t.ok(#every_note >= 30, ("the cases above showed rounds' notices (%d)"):format(#every_note))
  t.eq(too_long, {}, "every line of every notice is at most 60 cells")
  too_long = {}
  for _, s in ipairs(every_prompt) do
    for _, text in ipairs(vim.list_extend({ s.prompt }, s.labels)) do
      text = typical(text)
      if text:find("\n", 1, true) or vim.fn.strdisplaywidth(text) > 70 then too_long[#too_long + 1] = text end
    end
  end
  t.ok(#every_prompt >= 15, ("and asked its questions (%d)"):format(#every_prompt))
  t.eq(too_long, {}, "every prompt and choice is one line of at most 70 cells")
end

---------------------------------------------------------------------------
-- Cleanup
---------------------------------------------------------------------------

rounds.submit = real_submit
for _, term in ipairs(terminals) do
  pcall(vim.fn.jobstop, term.job)
end
pause(100)
for _, term in ipairs(terminals) do
  pcall(vim.api.nvim_buf_delete, term.buf, { force = true })
end
vim.fn.chdir(spec_cwd)
vim.g.ai_review = saved_review
for k, v in pairs(saved_env) do vim.env[k] = v end
vim.notify = real_notify
vim.fn.delete(scratch, "rf")
t.done()
