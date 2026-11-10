-- Baseline labels (lua/ai/review/labels.lua) and what they read: session names
-- and turn ends from the agents' own records (lua/ai/transcript/marks.lua,
-- through the claude and codex adapters), shown by the <leader>g pickers
-- (lua/plugin/vcs/codediff.lua).
--
-- Pinned here:
--   * ISO 8601 becomes epoch seconds by arithmetic, not through the local UTC
--     offset (ai.transcript.time.epoch); hhmm still reads local time;
--   * which records mark a session: Claude's ai-title / custom-title,
--     turn_duration and an interrupted turn's user record -- never a
--     subagent's, a tool result's or a quoted one; Codex's task_complete /
--     turn_aborted, and its thread index for the name;
--   * a session's name is the first it had; records are read incrementally
--     (appended lines, a partial last line, a replaced file), in slices, and
--     a line over MAX_LINE is skipped without losing the one after it;
--   * labels: "<name>: <Source> <start> - <end>", the end bounded by the
--     session's next round, "…" while it is at work, the start alone without
--     records; names cut at 40 columns; dates on other days, across midnight
--     and in other years; "<name>: Saved <time>";
--   * describe() waits at most its budget, then labels without the records,
--     and calls back once;
--   * <leader>gM and <leader>gk show the labels and label a view with the
--     start alone; <leader>gK offers the name of the session working here.
-- Records live in fixture directories under tempname() (CLAUDE_CONFIG_DIR,
-- CODEX_HOME), never ~/.claude or ~/.codex; repositories under tempname()
-- with a space in their path and an empty global git config.
local t = dofile("tests/helper.lua")
local uv = vim.uv

local saved_env = { CLAUDE_CONFIG_DIR = vim.env.CLAUDE_CONFIG_DIR, CODEX_HOME = vim.env.CODEX_HOME }
local records = vim.fn.tempname() .. " records"
local CLAUDE, CODEX = records .. "/claude", records .. "/codex"
vim.fn.mkdir(CLAUDE .. "/projects/-tmp-project", "p")
vim.fn.mkdir(CODEX .. "/sessions/2026/11/10", "p")
vim.env.CLAUDE_CONFIG_DIR, vim.env.CODEX_HOME = CLAUDE, CODEX

local time = require("ai.transcript.time")
local claude = require("ai.transcript.claude")
local codex = require("ai.transcript.codex")
local marks = require("ai.transcript.marks")
local labels = require("ai.review.labels")
local rounds = require("ai.review.rounds")
-- Files appear and vanish here faster than a remembered miss expires.
claude.MISS_TTL, codex.MISS_TTL = 0, 0
local function touch(path, when) assert(uv.fs_utime(path, when, when)) end

local function iso(epoch)
  local whole = math.floor(epoch)
  return os.date("!%Y-%m-%dT%H:%M:%S", whole) .. (".%03dZ"):format(math.floor((epoch - whole) * 1000 + 0.5))
end
local function line(record) return vim.json.encode(record) end
local function append(path, lines, newline)
  local fd = assert(io.open(path, "ab"))
  fd:write(table.concat(lines, "\n") .. (newline == false and "" or "\n"))
  fd:close()
end
local function read(agent, id, opts)
  local got, called = nil, 0
  marks.read(agent, id, function(m)
    got, called = m, called + 1
  end, opts)
  vim.wait(10000, function() return called > 0 end, 5)
  return got, called
end

---------------------------------------------------------------------------
-- Timestamps
---------------------------------------------------------------------------

t.eq(time.epoch("1970-01-01T00:00:00Z"), 0, "epoch: the epoch is 0")
t.ok(math.abs(time.epoch("2026-11-10T03:43:18.085Z") - 1794282198.085) < 1e-6, "epoch: keeps milliseconds")
t.eq(time.epoch("2024-02-29T12:00:00Z"), 1709208000, "epoch: a leap day")
t.eq(time.epoch("2026-11-10T11:43:18+08:00"), 1794282198, "epoch: an offset is applied")
t.eq(time.epoch("1999-12-31T23:59:59-05:30"), 946704599, "epoch: a negative offset with minutes")
t.eq(time.epoch("2026-03-29T01:30:00"), 1774747800, "epoch: no zone is UTC")
t.eq(time.epoch("2026-03-29T01:30:00.000000Z"), 1774747800, "epoch: microseconds")
for _, bad in ipairs({ "yesterday", "2026-13", "2026-11-10 03:43:18Z", "2026-11-10T03:43:18+8", 42, nil }) do
  t.eq(time.epoch(bad), nil, "epoch: nil for " .. tostring(bad))
end
t.eq(time.hhmm("2026-11-10T03:43:18Z"), os.date("%H:%M", 1794282198), "hhmm: local time of the moment")
local B = require("util.baseline")
t.eq(B.time_of({ time = 1794282198, id = "20261110T034318-c805" }), 1794282198.8,
  "time_of: a baseline's millisecond comes from its id (ms * 64 + pid bits)")
t.eq(B.time_of({ time = 1794282198, id = "20261110T034318-0000" }), 1794282198, "time_of: millisecond 0")
t.eq(B.time_of({ time = 1794282198, id = "something else" }), 1794282198, "time_of: an id that is not ours: the second")
t.eq(B.time_of({ time = 1794282198, id = "20261110T034318-ffff" }), 1794282198, "time_of: no millisecond past 999")

---------------------------------------------------------------------------
-- What marks a session
---------------------------------------------------------------------------

local T0 = 1794282198 -- 2026-11-10T03:43:18Z
local function user(content, extra)
  return vim.tbl_extend("force", { type = "user", timestamp = iso(T0), message = { role = "user", content = content } },
    extra or {})
end
t.eq(claude.mark({ type = "ai-title", aiTitle = "Scanner", sessionId = "s" }), { title = "Scanner" }, "claude: ai-title")
t.eq(claude.mark({ type = "custom-title", customTitle = "Mine" }), { title = "Mine" }, "claude: custom-title (/rename)")
t.eq(claude.mark({ type = "system", subtype = "turn_duration", durationMs = 5, timestamp = iso(T0) }), { ended = T0 },
  "claude: turn_duration ends a turn")
t.eq(claude.mark(user({ { type = "text", text = "[Request interrupted by user]" } })), { ended = T0 },
  "claude: an interrupted turn's user record ends it")
t.eq(claude.mark(user("[Request interrupted by user for tool use]")), { ended = T0 }, "claude: as a bare string too")
t.eq(claude.mark(user({ { type = "tool_result", content = "[Request interrupted by user]" } })), nil,
  "claude: not a tool result quoting it")
t.eq(claude.mark(user({ { type = "text", text = "why did [Request interrupted by user] appear?" } })), nil,
  "claude: not a prompt mentioning it")
t.eq(claude.mark({ type = "system", subtype = "turn_duration", timestamp = iso(T0), isSidechain = true }), nil,
  "claude: not a subagent's turn")
t.eq(claude.mark({ type = "system", subtype = "turn_duration" }), nil, "claude: not without a time")
t.eq(claude.mark({ type = "assistant", timestamp = iso(T0) }), nil, "claude: nothing else")
t.eq(codex.mark({ type = "event_msg", timestamp = iso(T0), payload = { type = "task_complete" } }), { ended = T0 },
  "codex: task_complete ends a turn")
t.eq(codex.mark({ type = "event_msg", timestamp = iso(T0), payload = { type = "turn_aborted", reason = "interrupted" } }),
  { ended = T0 }, "codex: so does turn_aborted")
t.eq(codex.mark({ type = "event_msg", timestamp = iso(T0), payload = { type = "task_started" } }), nil,
  "codex: not task_started")
t.eq(codex.mark({ type = "response_item", timestamp = iso(T0), payload = { type = "task_complete" } }), nil,
  "codex: not a response item")
t.eq(codex.index_mark({ id = "c1", thread_name = "Name", updated_at = iso(T0) }), { id = "c1", title = "Name" },
  "codex: an index record names its thread")
t.eq(claude.sources("../../etc/passwd"), {}, "claude: no lookup for an id that is not one")
t.eq(codex.sources("a*b"), {}, "codex: nor here")

---------------------------------------------------------------------------
-- Reading a Claude transcript
---------------------------------------------------------------------------

local CID = "11111111-2222-4333-8444-555555555555"
local transcript = CLAUDE .. "/projects/-tmp-project/" .. CID .. ".jsonl"
local E = { T0 + 100, T0 + 200, T0 + 300, T0 + 400, T0 + 500 }
marks.MAX_LINE = 4096
append(transcript, {
  line(user("first prompt")),
  -- A record quoted by a tool: its quotes are escaped, so it never matches.
  line({ type = "assistant", timestamp = iso(T0),
    message = { content = { { type = "text", text = '{"type":"ai-title","aiTitle":"Quoted"}' } } } }),
  line(user({ { type = "tool_result", content = "[Request interrupted by user]" } })),
  line({ type = "ai-title", aiTitle = "First title", sessionId = CID }),
  line({ type = "system", subtype = "turn_duration", timestamp = iso(E[1]) }),
  line({ type = "custom-title", customTitle = "Renamed later", sessionId = CID }),
  line({ type = "ai-title", aiTitle = "Second title", sessionId = CID }),
  line(user({ { type = "text", text = "[Request interrupted by user]" } }, { timestamp = iso(E[2]) })),
  line({ type = "system", subtype = "turn_duration", timestamp = iso(E[1] + 50), isSidechain = true }),
  -- Longer than MAX_LINE: skipped whole, though it is a turn_duration record.
  line({ type = "system", subtype = "turn_duration", timestamp = iso(E[1] + 60), pad = string.rep("x", 9000) }),
  line({ type = "system", subtype = "turn_duration", timestamp = iso(E[3]) }),
})
local m, called = read("claude", CID)
t.eq(called, 1, "marks.read calls back once")
t.eq(m and m.title, "First title", "the session's name is its first title, not a later ai-title or /rename")
t.eq(m and m.ends, { E[1], E[2], E[3] }, "its ends: turn_duration and the interrupt; not a subagent's or an over-long line")
t.eq(m and m.turns, true, "and it says turns were read")
local st = marks._state(transcript)
local size = uv.fs_stat(transcript).size
t.eq(st and st.offset, size, "the whole file was consumed")

-- A partial last line waits for its newline.
append(transcript, { line({ type = "system", subtype = "turn_duration", timestamp = iso(E[4]) }) }, false)
m = read("claude", CID)
t.eq(m and m.ends, { E[1], E[2], E[3] }, "a line still being written is not read yet")
t.eq(marks._state(transcript).offset, size, "nor consumed")
append(transcript, { "", line({ type = "ai-title", aiTitle = "Third title" }) })
m = read("claude", CID)
t.eq(m and m.ends, { E[1], E[2], E[3], E[4] }, "once complete it is, from where the last read stopped")
t.eq(m and m.title, "First title", "the name stays the first one")

-- An over-long line split across reads: still skipped, and the next line read.
local big = line({ type = "system", subtype = "turn_duration", timestamp = iso(E[4] + 1), pad = string.rep("y", 9000) })
append(transcript, { big:sub(1, 5000) }, false)
read("claude", CID)
t.eq(marks._state(transcript).skipping, true, "a partial line already over MAX_LINE is dropped, and skipped on")
append(transcript, { big:sub(5001), line({ type = "system", subtype = "turn_duration", timestamp = iso(E[5]) }) })
m = read("claude", CID)
t.eq(m and m.ends, { E[1], E[2], E[3], E[4], E[5] }, "an over-long line arriving in parts is skipped, the next one read")

-- Unchanged: answered from what is known, without reading again.
local gen, offset = marks._state(transcript).gen, marks._state(transcript).offset
local jobs = marks._jobs
m = read("claude", CID)
t.eq(marks._jobs, jobs, "an unchanged file queues no job")
t.eq({ marks._state(transcript).gen, marks._state(transcript).offset }, { gen, offset }, "an unchanged file is not read again")
t.eq(m and #m.ends, 5, "and gives the same marks")

-- Rewritten in place (same inode, longer, other first bytes): read again.
do
  local before = uv.fs_stat(transcript)
  local fd = assert(io.open(transcript, "wb"))
  fd:write(table.concat({
    line({ type = "custom-title", customTitle = "Renamed first", sessionId = CID }),
    line({ type = "ai-title", aiTitle = "Generated after", sessionId = CID }),
    line({ type = "system", subtype = "turn_duration", timestamp = iso(E[2]) }),
    line(user("padding " .. string.rep("p", before.size))),
  }, "\n") .. "\n")
  fd:close()
  local after = uv.fs_stat(transcript)
  t.ok(after.ino == before.ino and after.size > before.size, "(the rewrite keeps the inode and grows the file)")
end
m = read("claude", CID)
t.eq({ m and m.title, m and m.ends }, { "Renamed first", { E[2] } },
  "a transcript rewritten in place is read again; a /rename before the first ai-title is the name")

-- A replaced file (another inode) is read from its start.
os.remove(transcript)
append(transcript, {
  line({ type = "ai-title", aiTitle = "Rewritten", sessionId = CID }),
  line({ type = "system", subtype = "turn_duration", timestamp = iso(E[1]) }),
})
m = read("claude", CID)
t.eq({ m and m.title, m and m.ends }, { "Rewritten", { E[1] } }, "a replaced transcript is read again from the start")
os.remove(transcript)
m = read("claude", CID)
t.eq(m, nil, "a session with no transcript has no marks")
t.eq(read("claude", "99999999-0000-4000-8000-000000000000"), nil, "nor does an unknown one")

-- Slices and blocks: a file read in many thread-pool jobs, in blocks that cut
-- lines and patterns apart, gives the same answer.
marks.SLICE, marks.CHUNK = 8192, 1000
local many = {}
local want_ends = {}
for i = 1, 400 do
  many[#many + 1] = line(user("prompt " .. i .. string.rep(" ", 60)))
  many[#many + 1] = line({ type = "system", subtype = "turn_duration", timestamp = iso(T0 + i) })
  want_ends[#want_ends + 1] = T0 + i
end
append(transcript, many)
m = read("claude", CID)
t.ok(uv.fs_stat(transcript).size > 8 * 8192, "the transcript spans many slices")
t.eq(m and m.ends, want_ends, "read in slices, every end is found, in order")
local st_many = marks._state(transcript)
t.eq(st_many and st_many.offset, uv.fs_stat(transcript).size, "and stops at the end of the file")
marks.SLICE, marks.CHUNK = 64 * 1048576, 4 * 1048576
os.remove(transcript)

---------------------------------------------------------------------------
-- Reading Codex's records
---------------------------------------------------------------------------

local XID = "01a1c0c1-5e52-7fc1-bb0f-a50d34636ba3"
local OTHER = "01a1c0c1-0000-7000-8000-000000000000"
local index = CODEX .. "/session_index.jsonl"
append(index, {
  line({ id = XID, thread_name = "Codex first", updated_at = iso(T0) }),
  line({ id = OTHER, thread_name = "Other thread", updated_at = iso(T0) }),
  line({ id = XID, thread_name = "Codex renamed", updated_at = iso(T0 + 9) }),
})
local rollout = CODEX .. "/sessions/2026/11/10/rollout-2026-11-10T10-00-00-" .. XID .. ".jsonl"
append(rollout, {
  line({ timestamp = iso(T0), type = "session_meta", payload = { id = XID, cwd = "/tmp/project" } }),
  line({ timestamp = iso(T0 + 1), type = "event_msg", payload = { type = "task_started" } }),
  line({ timestamp = iso(T0 + 2), type = "response_item",
    payload = { type = "message", content = { { text = '"type":"task_complete"' } } } }),
  line({ timestamp = iso(E[1]), type = "event_msg", payload = { type = "task_complete", last_agent_message = "done" } }),
  line({ timestamp = iso(E[2]), type = "event_msg", payload = { type = "turn_aborted", reason = "interrupted" } }),
})
m = read("codex", XID)
t.eq(m and m.title, "Codex first", "codex: the thread's first name, not its rename")
t.eq(m and m.ends, { E[1], E[2] }, "codex: completed and aborted turns end; nothing quoted does")
t.eq(m and m.turns, true, "codex: with its rollout read")
m = read("codex", OTHER)
t.eq({ m and m.title, m and m.ends, m and m.turns }, { "Other thread", {}, false },
  "codex: a thread with no rollout here has its name and no turns")
t.eq(read("codex", "01a1c0c1-ffff-7fff-bfff-ffffffffffff"), nil, "codex: an unknown thread has no marks")

-- A read for the name alone leaves the rollout unread.
marks._reset()
m = read("codex", XID, { titles = true })
t.eq(m and m.title, "Codex first", "codex: a read for the name gives it")
t.eq(marks._state(rollout), nil, "without reading the rollout")
t.ok(marks._state(index) ~= nil, "only the index")

-- Finding a rollout: its UUIDv7 day first, remembered, the whole tree last.
local globs = {}
local real_globpath = vim.fn.globpath
local function spy()
  globs = {}
  vim.fn.globpath = function(dir, pat, ...)
    globs[#globs + 1] = pat
    return real_globpath(dir, pat, ...)
  end
end
local function unspy() vim.fn.globpath = real_globpath end
local VID = "01a1c347-475d-7241-98cd-01717ec3828c" -- created 0x01a1c347475d ms after the epoch
local vday = os.date("%Y/%m/%d", math.floor(0x01a1c347475d / 1000))
vim.fn.mkdir(CODEX .. "/sessions/" .. vday, "p")
local vpath = CODEX .. "/sessions/" .. vday .. "/rollout-2026-11-10T10-26-32-" .. VID .. ".jsonl"
append(vpath, { line({ timestamp = iso(E[3]), type = "event_msg", payload = { type = "task_complete" } }) })
codex._forget()
spy()
local srcs = codex.sources(VID)
unspy()
t.eq(srcs[2] and srcs[2].path, vpath, "codex: a rollout is found under its thread's day")
t.ok(#globs >= 1 and globs[1]:find(vday, 1, true) == 1 and not vim.tbl_contains(globs, "*/*/*/rollout-*-" .. VID .. ".jsonl"),
  "looking there first, not through the whole tree (" .. table.concat(globs, ", ") .. ")")
spy()
srcs = codex.sources(VID)
unspy()
t.eq({ #globs, srcs[2] and srcs[2].path }, { 0, vpath }, "codex: then remembered: no glob at all")
vim.fn.mkdir(CODEX .. "/sessions/2020/01/01", "p")
local moved = CODEX .. "/sessions/2020/01/01/rollout-2020-01-01T00-00-00-" .. VID .. ".jsonl"
assert(os.rename(vpath, moved))
srcs = codex.sources(VID)
t.eq(srcs[2] and srcs[2].path, moved, "codex: a rollout no longer where it was is looked for again, in the whole tree")
codex.MISS_TTL = 60
local GONE = "01a1c347-0000-7000-8000-000000000000"
codex.sources(GONE)
spy()
codex.sources(GONE)
unspy()
t.eq(#globs, 0, "codex: a miss is remembered for MISS_TTL")
codex.MISS_TTL = 0
os.remove(moved)

-- A cold rollout compressed in place is read through zstd.
if vim.fn.executable("zstd") == 1 then
  local ZID = "01a18fe7-bf36-7ee2-a3e8-8fc53ca4326b"
  local zday = os.date("%Y/%m/%d", math.floor(0x01a18fe7bf36 / 1000))
  vim.fn.mkdir(CODEX .. "/sessions/" .. zday, "p")
  local plain = CODEX .. "/sessions/" .. zday .. "/rollout-2026-10-31T11-01-32-" .. ZID .. ".jsonl"
  append(plain, {
    line({ timestamp = iso(E[1]), type = "event_msg", payload = { type = "task_complete" } }),
    line({ timestamp = iso(E[4]), type = "event_msg", payload = { type = "turn_aborted" } }),
  })
  local z = vim.system({ "zstd", "-q", "--rm", plain }):wait()
  t.ok(z.code == 0 and uv.fs_stat(plain .. ".zst") ~= nil and uv.fs_stat(plain) == nil, "(the rollout is compressed)")
  m = read("codex", ZID)
  t.eq({ m and m.ends, m and m.turns }, { { E[1], E[4] }, true }, "codex: a compressed rollout's turns are read")
  local zjobs = marks._jobs
  m = read("codex", ZID)
  t.eq({ marks._jobs, m and #m.ends }, { zjobs, 2 }, "and not again while it is unchanged")
else
  t.ok(true, "codex: zstd is not installed here, so compressed rollouts are not read (skipped)")
end

---------------------------------------------------------------------------
-- Formatting
---------------------------------------------------------------------------

local function at(y, mo, d, h, mi, s) return os.time({ year = y, month = mo, day = d, hour = h, min = mi, sec = s }) end
local NOW = at(2026, 11, 10, 12, 0, 0)
t.eq(labels.stamp(at(2026, 11, 10, 11, 16, 38), NOW), "11:16:38", "stamp: today, to the second")
t.eq(labels.stamp(at(2026, 11, 9, 23, 8, 5), NOW), "11-09 23:08", "stamp: another day, with its date")
t.eq(labels.stamp(at(2025, 12, 31, 23, 50, 0), NOW), "2025-12-31 23:50", "stamp: another year, with it")
t.eq(labels.span(at(2026, 11, 10, 11, 16, 38), at(2026, 11, 10, 11, 43, 18), false, NOW), "11:16:38 - 11:43:18",
  "span: today")
t.eq(labels.span(at(2026, 11, 9, 21, 43, 5), at(2026, 11, 9, 22, 12, 40), false, NOW), "11-09 21:43 - 22:12",
  "span: another day, its date once")
t.eq(labels.span(at(2026, 11, 9, 23, 50, 0), at(2026, 11, 10, 0, 20, 0), false, NOW), "11-09 23:50 - 11-10 00:20",
  "span: across midnight, both dated")
t.eq(labels.span(at(2026, 11, 10, 11, 39, 25), nil, true, NOW), "11:39:25 - …", "span: still at work")
t.eq(labels.span(at(2026, 11, 10, 11, 39, 25), at(2026, 11, 10, 11, 43, 0), true, NOW), "11:39:25 - …",
  "span: at work again after an earlier end")
t.eq(labels.span(at(2026, 11, 10, 11, 39, 25), nil, false, NOW), "11:39:25", "span: the start alone when the end is unknown")
t.eq(labels.shorten("扫描器 status"), "扫描器 status", "shorten: a short name stays")
local long = string.rep("a", 41)
t.eq(labels.shorten(long), string.rep("a", 39) .. "…", "shorten: 41 columns become 40 with …")
t.eq(vim.fn.strdisplaywidth(labels.shorten(string.rep("中", 25))), 39, "shorten: double-width characters are counted as two")
t.eq(labels.shorten(string.rep("中", 25)), string.rep("中", 19) .. "…", "shorten: and never split")
t.eq(labels.shorten("two\nlines\t here "), "two lines here", "shorten: one line, trimmed")

---------------------------------------------------------------------------
-- describe()
---------------------------------------------------------------------------

-- Session A (Claude, with records): rounds R1 < R2 < R3. Session X (Codex).
local AID = "aaaaaaaa-1111-4111-8111-111111111111"
local A, X = "claude:" .. AID, "codex:" .. XID
local a_path = CLAUDE .. "/projects/-tmp-project/" .. AID .. ".jsonl"
local R = { at(2026, 11, 10, 9, 0, 0), at(2026, 11, 10, 10, 0, 0), at(2026, 11, 10, 11, 0, 0) }
append(a_path, {
  line({ type = "ai-title", aiTitle = string.rep("长", 30), sessionId = AID }),
  line({ type = "system", subtype = "turn_duration", timestamp = iso(R[1] + 600) }),
  line({ type = "system", subtype = "turn_duration", timestamp = iso(R[1] + 1200) }),
  -- R2 runs past R3's start: its turn ended after the next round began.
  line({ type = "system", subtype = "turn_duration", timestamp = iso(R[3] + 30) }),
})
local function entry(kind, id, when, trailers, subject)
  return { kind = kind, id = id, sha = id .. "sha", time = when, subject = subject or ("nvim review: x round " .. id),
    trailers = trailers or {} }
end
-- Waits past the budget too, so a second answer would be counted.
local function describe(entries, opts)
  local got, calls = nil, 0
  opts = vim.tbl_extend("force", { now = NOW }, opts or {})
  labels.describe(entries, function(l)
    got, calls = l, calls + 1
  end, opts)
  vim.wait(5000, function() return calls > 0 end, 5)
  vim.wait((opts.budget_ms or labels.BUDGET_MS) + 100, function() return false end, 5)
  return got, calls
end
local ENTRIES = {
  entry("round", "r3", R[3], { Source = "claude", Conversation = A }),
  -- After X's last recorded end, whatever the local time zone.
  entry("round", "x1", E[2] + 60, { Source = "codex", Conversation = X }),
  entry("round", "r2", R[2], { Source = "claude", Conversation = A }),
  entry("round", "m1", R[1] + 300, { Source = "manual" }),
  entry("round", "c1", R[1] + 200, { Source = "cc-acp", Conversation = "cc:nonce:3" }),
  entry("round", "z1", R[1] + 100, { Source = "claude", Conversation = "claude:bbbbbbbb-0000-4000-8000-000000000000" }),
  entry("round", "r1", R[1], { Source = "claude", Conversation = A }),
  entry("round", "o1", R[1] - 60, {}, "nvim review: an old round"),
  entry("saved", "s1", at(2026, 11, 9, 23, 8, 0), { Label = "temp" }, "saved · temp"),
  entry("saved", "s2", R[1], {}, "saved · from the subject"),
  entry("saved", "s3", R[1], { Label = "the Label" }, "saved · not the subject"),
}
local NAME = string.rep("长", 19) .. "…"
-- Both sessions wrote their records a minute ago: alive.
touch(a_path, NOW - 60)
touch(rollout, NOW - 60)
local got, calls = describe(ENTRIES)
t.eq(calls, 1, "describe calls back once")
local function shown(i) return got and got[i] and got[i].display end
local function label(i) return got and got[i] and got[i].label end
t.eq(shown(7), NAME .. ": Claude 09:00:00 - 09:20:00",
  "a round: its session's name, cut to 40 columns, its start and the last end before the session's next round")
t.eq(label(7), NAME .. ": Claude 09:00:00", "and the view's label names the start alone")
t.eq(shown(3), NAME .. ": Claude 10:00:00", "a round whose turn outlasted the next round's start: no end")
t.eq(shown(1), NAME .. ": Claude 11:00:00 - 11:00:30", "the session's newest round ends at its last turn")
t.eq(shown(2), "Codex first: Codex " .. labels.stamp(E[2] + 60, NOW) .. " - …",
  "a Codex round with no end since its start is at work")
t.eq(shown(4), "Manual 09:05:00", "a manual round with no owner: its source and start")
t.eq(shown(5), "Agent chat 09:03:20", "a chat's round: no records to read")
t.eq(shown(6), "Claude 09:01:40", "a Claude round whose transcript is not here: no name, no end")
t.eq(got and got[8], nil, "a round with no Source keeps the caller's label")
t.eq({ shown(9), label(9) }, { "temp: Saved 11-09 23:08", "temp: Saved 11-09 23:08" }, "a saved baseline: its Label")
t.eq(shown(10), "from the subject: Saved 09:00:00", "or the name in its subject")
t.eq(shown(11), "the Label: Saved 09:00:00", "its Label first")

-- At work again: a prompt after the last end keeps the round (nothing changed).
rounds._state().prompted[A] = R[3] + 60
got = describe(ENTRIES)
t.eq(shown(1), NAME .. ": Claude 11:00:00 - …", "a prompt after the session's last end: at work again")
t.eq(shown(7), NAME .. ": Claude 09:00:00 - 09:20:00", "older rounds keep their ends")
rounds._state().prompted[A] = R[3] + 10
got = describe(ENTRIES)
t.eq(shown(1), NAME .. ": Claude 11:00:00 - 11:00:30", "a prompt before the last end changes nothing")

-- At work only while alive: a session killed mid-turn writes no end.
rounds._state().prompted[A] = R[3] + 60
touch(a_path, NOW - labels.LIVE_SECONDS - 60)
touch(rollout, NOW - labels.LIVE_SECONDS - 60)
got = describe(ENTRIES)
t.eq(shown(1), NAME .. ": Claude 11:00:00 - 11:00:30", "records untouched for LIVE_SECONDS: no …, the last end")
t.eq(shown(2), "Codex first: Codex " .. labels.stamp(E[2] + 60, NOW), "and a round with no end shows its start alone")
local real_running = rounds.running
rounds.running = function(conversation) return conversation == A end
got = describe(ENTRIES)
t.eq(shown(1), NAME .. ": Claude 11:00:00 - …", "a session running in this Nvim is alive, however old its records")
rounds.running = real_running
rounds._state().prompted[A] = nil
touch(a_path, NOW - 60)
touch(rollout, NOW - 60)

-- A manual round owned by a session is no prompt of it.
local OWNED = {
  entry("round", "m2", R[3] + 600, { Source = "manual", Conversation = A }),
  entry("round", "r3", R[3], { Source = "claude", Conversation = A }),
}
got = describe(OWNED)
t.eq(shown(1), NAME .. ": Manual 11:10:00", "a manual round of an idle session: not at work")
t.eq(shown(2), NAME .. ": Claude 11:00:00 - 11:00:30", "and the round before it keeps its end")
rounds._state().prompted[A] = R[3] + 700
got = describe(OWNED)
t.eq(shown(1), NAME .. ": Manual 11:10:00 - …", "prompted since: at work")
rounds._state().prompted[A] = nil
-- A Late round's baseline may postdate the turn it belongs to.
got = describe({
  entry("round", "l1", R[3] + 900, { Source = "claude", Conversation = A, Late = "1" }),
  entry("round", "r3", R[3], { Source = "claude", Conversation = A }),
})
t.eq(shown(1), NAME .. ": Claude 11:15:00", "a Late round with no end after it is not taken for work in progress")

-- Milliseconds: a prompt sent in the second a turn ended.
local QID = "dddddddd-3333-4333-8333-333333333333"
local Q = "claude:" .. QID
local q_path = CLAUDE .. "/projects/-tmp-project/" .. QID .. ".jsonl"
append(q_path, {
  line({ type = "ai-title", aiTitle = "Queued", sessionId = QID }),
  line({ type = "system", subtype = "turn_duration", timestamp = iso(R[1] + 14.3) }),
})
touch(q_path, NOW - 60)
local function id_at(when, ms) return os.date("!%Y%m%dT%H%M%S", when) .. ("-%04x"):format(ms * 64 + 5) end
local SAME = {
  entry("round", id_at(R[1] + 14, 800), R[1] + 14, { Source = "claude", Conversation = Q }),
  entry("round", id_at(R[1], 0), R[1], { Source = "claude", Conversation = Q }),
}
got = describe(SAME)
t.eq(shown(2), "Queued: Claude 09:00:00 - 09:00:14", "a turn ending at .300 belongs to the round before one taken at .800")
t.eq(shown(1), "Queued: Claude 09:00:14 - …", "which is at work, not finished at that end")
SAME[1].id = id_at(R[1] + 14, 200)
got = describe(SAME)
t.eq({ shown(2), shown(1) }, { "Queued: Claude 09:00:00", "Queued: Claude 09:00:14 - 09:00:14" },
  "taken at .200, before that end, the round owns it")

-- The budget: records not read by then are left out, and the answer comes once.
local real_marks = package.loaded["ai.transcript.marks"]
local late = {}
-- Names come at once, turns never.
package.loaded["ai.transcript.marks"] = {
  read = function(_, _, cb, opts)
    if opts and opts.titles then return vim.schedule(function() cb({ title = "Named", ends = {}, turns = false }) end) end
    late[#late + 1] = cb
  end,
}
local t0 = uv.hrtime()
got, calls = describe(ENTRIES, { budget_ms = 100 })
local waited = (uv.hrtime() - t0) / 1e6
t.ok(waited >= 90 and waited < 2000, ("describe answers after its budget when records are slow (%d ms)"):format(waited))
t.eq(shown(7), "Named: Claude 09:00:00", "turns not read in time: the name, read on its own, and the start")
for _, cb in ipairs(late) do cb({ title = "Too late", ends = {}, turns = true }) end
vim.wait(50, function() return false end, 5)
t.eq(calls, 1, "records arriving after the budget do not call back again")
package.loaded["ai.transcript.marks"] = real_marks

---------------------------------------------------------------------------
-- The pickers and <leader>gK
---------------------------------------------------------------------------

local Config = require("lazy.core.config")
local plugin = Config.plugins["codediff.nvim"]
local function key(lhs)
  for _, spec in ipairs(plugin.keys) do
    if spec[1] == lhs then return spec[2] end
  end
end
local gitconfig = vim.fn.tempname()
vim.fn.writefile({ "[init]", "\tdefaultBranch = main", "[gc]", "\tauto = 0" }, gitconfig)
vim.env.GIT_CONFIG_GLOBAL = gitconfig
vim.env.GIT_CONFIG_NOSYSTEM = "1"
local root = vim.fn.tempname() .. " labels repo"
vim.fn.mkdir(root, "p")
root = uv.fs_realpath(root)
local function git(...)
  local r = vim.system(vim.list_extend({ "git", "-C", root, "-c", "user.name=F", "-c", "user.email=f@example.invalid" },
    { ... }), { text = true }):wait()
  assert(r.code == 0, table.concat({ ... }, " ") .. ": " .. (r.stderr or ""))
end
git("init", "-q", "-b", "main")
vim.fn.writefile({ "one" }, root .. "/a.txt")
git("add", ".")
git("commit", "-qm", "one")

-- A session of its own, whose records hold nothing but this test's turn.
local PID = "cccccccc-2222-4222-8222-222222222222"
local P = "claude:" .. PID
local p_path = CLAUDE .. "/projects/-tmp-project/" .. PID .. ".jsonl"
append(p_path, { line({ type = "ai-title", aiTitle = string.rep("长", 30), sessionId = PID }) })
local round
B.save(root, "round", { subject = "nvim review: Claude round 00:00:00", Source = "claude", Conversation = P, Root = root },
  function(e) round = e end)
vim.wait(5000, function() return round ~= nil end, 10)
t.ok(round ~= nil, "a round is saved")
-- The session's turn ends two seconds after the round.
append(p_path, { line({ type = "system", subtype = "turn_duration", timestamp = iso(round.time + 2) }) })
vim.fn.writefile({ "two" }, root .. "/a.txt")

local CODEDIFF = rawget(vim.cmd, "CodeDiff")
local cd = require("util.codediff")
local real_open, real_select, real_input, real_notify = cd.open, vim.ui.select, vim.ui.input, vim.notify
local specs, offered, inputs, script = {}, {}, {}, {}
vim.cmd.CodeDiff = function() end
cd.open = function(spec) specs[#specs + 1] = vim.deepcopy(spec) end
vim.ui.select = function(items, _, on_choice)
  offered[#offered + 1] = items
  local want = table.remove(script, 1)
  for _, item in ipairs(items) do
    if type(want) == "function" and want(item) then return on_choice(item) end
  end
  on_choice(nil)
end
vim.ui.input = function(opts, on_confirm)
  inputs[#inputs + 1] = opts
  on_confirm(table.remove(script, 1))
end
vim.notify = function() end
vim.cmd.cd(vim.fn.fnameescape(root))
vim.cmd.enew()

local stamp = function(at_time) return labels.stamp(at_time) end
local WANT = NAME .. ": Claude " .. labels.span(round.time, round.time + 2)
local function is_round(item) return item.rev == round.sha end
script = { is_round }
key("<leader>gM")()
vim.wait(5000, function() return #specs > 0 end, 10)
local item = offered[1] and vim.iter(offered[1]):find(is_round)
t.eq(item and item.display, " " .. WANT, "<leader>gM shows a round as <session>: <Source> <start> - <end>")
t.eq(specs[1] and specs[1].label, NAME .. ": Claude " .. stamp(round.time) .. " → working tree",
  "and labels its view with the start alone")

specs, offered = {}, {}
script = { is_round, function(i) return i.kind == "working" end }
key("<leader>gk")()
vim.wait(5000, function() return #specs > 0 end, 10)
item = offered[1] and vim.iter(offered[1]):find(is_round)
t.eq(item and item.display, " " .. WANT, "<leader>gk shows the same label")
t.eq(specs[1] and specs[1].label, NAME .. ": Claude " .. stamp(round.time) .. " → working tree", "and the same view label")

-- <leader>gK: no agent here offers nothing; Claude working here offers its name.
local function press_gK(name)
  inputs, script = {}, { name }
  local before = #specs
  key("<leader>gK")()
  vim.wait(5000, function() return #inputs > 0 end, 10)
  return inputs[1], before
end
local asked = press_gK(nil)
t.ok(asked ~= nil and asked.default == nil, "<leader>gK with no agent session here offers no name")

vim.cmd.enew()
local term = vim.api.nvim_get_current_buf()
local job = vim.fn.jobstart({ "cat" }, { term = true, cwd = root })
vim.b[term].snacks_terminal = { cmd = { "claude", "--settings", "{}" }, cwd = root }
vim.wait(1000, function()
  local e = rounds._state().native.claude
  return e ~= nil and e.buf == term
end, 10)
rounds.native_event({ agent = "claude", event = "session", payload = { session_id = PID, source = "startup", cwd = root } })
t.eq({ rounds.running(P), rounds.running(A), rounds.running(nil) }, { true, false, false },
  "running: the session an agent terminal here runs")
vim.cmd.enew()
asked = press_gK(nil)
t.eq(asked and asked.default, string.rep("长", 30), "<leader>gK offers the name of the Claude session working here, uncut")
asked = press_gK("kept")
local saved
vim.wait(5000, function()
  B.list(root, "saved", function(es) saved = es end)
  return saved ~= nil and #saved > 0
end, 50)
t.eq(saved and saved[1] and saved[1].trailers.Label, "kept", "and saves under the name typed")

-- A submit is remembered for "at work".
local before = os.time()
local released = false
rounds.native_event({ agent = "claude", event = "submit", payload = { session_id = PID, cwd = root },
  done = function() released = true end })
vim.wait(5000, function() return released end, 10)
t.ok((rounds.prompted_at(P) or 0) >= before, "a native submit records when the session was prompted")
t.eq(rounds.prompted_at("claude:never"), nil, "a session never prompted has no time")
t.eq(rounds.source_label("codex"), "Codex", "source_label: the word for a Source")
t.eq(rounds.source_label(nil), nil, "source_label: nil for none")

vim.fn.jobstop(job)
vim.wait(2000, function() return not rounds.running(P) end, 10)
t.eq(rounds.running(P), false, "running: not once its terminal stopped")
vim.cmd.CodeDiff = CODEDIFF
cd.open, vim.ui.select, vim.ui.input, vim.notify = real_open, real_select, real_input, real_notify
vim.env.CLAUDE_CONFIG_DIR, vim.env.CODEX_HOME = saved_env.CLAUDE_CONFIG_DIR, saved_env.CODEX_HOME
vim.cmd.cd(vim.fn.fnameescape(vim.fn.stdpath("config")))
vim.fn.delete(records, "rf")
vim.fn.delete(root, "rf")
vim.fn.delete(gitconfig)

t.done()
