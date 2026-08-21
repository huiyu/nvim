-- Covers UC-15/UC-16 (session discovery), UC-18 (cap), UC-19 (malformed lines).
--
-- Fixtures are hand-written miniatures, not real transcripts: real ones carry
-- the whole conversation and must never enter the repository. Their record
-- shapes were taken field-by-field from real files on disk.
local t = dofile("tests/helper.lua")

local dir = vim.fn.fnamemodify("tests/fixtures", ":p")

local function index_by_kind(entries)
  local by = {}
  for _, e in ipairs(entries) do
    by[e.kind] = by[e.kind] or {}
    table.insert(by[e.kind], e)
  end
  return by
end

for _, name in ipairs({ "claude", "codex" }) do
  local adapter = require("ai.transcript." .. name)
  local path = dir .. name .. "-sample.jsonl"

  -- UC-19: the fixture ends with a deliberately truncated line.
  local entries, truncated = adapter.parse(path, 1000)
  t.ok(#entries > 0, name .. ": parses entries despite a malformed final line")
  t.eq(truncated, false, name .. ": a small fixture is not reported as truncated")

  local by = index_by_kind(entries)
  t.ok(by.text ~= nil, name .. ": recognises text")
  t.ok(by.tool_call ~= nil, name .. ": recognises tool calls")
  t.ok(by.tool_result ~= nil, name .. ": recognises tool results")
  t.ok(by.thinking ~= nil, name .. ": recognises thinking")

  local roles = {}
  for _, e in ipairs(entries) do
    roles[e.role] = true
    t.ok(type(e.text) == "string", name .. ": every entry carries text")
    t.ok(e.kind ~= nil, name .. ": every entry carries a kind")
  end
  t.ok(roles.user, name .. ": recognises user turns")
  t.ok(roles.assistant, name .. ": recognises assistant turns")

  -- Noise records must not leak through as entries.
  local joined = ""
  for _, e in ipairs(entries) do joined = joined .. e.text end
  t.ok(joined:find("skipped noise", 1, true) == nil, name .. ": skips known noise records")
  t.ok(joined:find("skipped instructions", 1, true) == nil, name .. ": skips developer/system records")

  -- Tool entries name the tool so the fold header can be useful.
  t.ok(by.tool_call[1].name ~= nil, name .. ": tool calls carry a tool name")

  -- UC-18: the cap keeps the tail and reports the truncation.
  local capped, was_truncated = adapter.parse(path, 2)
  t.ok(#capped <= 2, name .. ": cap bounds the retained entries")
  t.eq(was_truncated, true, name .. ": cap reports truncation")
  t.eq(capped[#capped], entries[#entries], name .. ": cap keeps the newest entries, not the oldest")

  -- A path that does not exist must not raise.
  local missing, missing_truncated = adapter.parse(dir .. "does-not-exist.jsonl", 10)
  t.eq(missing, {}, name .. ": a missing file yields no entries")
  t.eq(missing_truncated, false, name .. ": a missing file is not truncated")

  t.ok(type(adapter.sessions) == "function", name .. ": exposes sessions()")
  t.ok(type(adapter.sessions("/tmp/definitely-not-a-project")) == "table",
    name .. ": sessions() returns a table for an unknown root")
end

-- Claude exposes a session title; the picker uses it when present.
local claude_sessions = require("ai.transcript.claude")
t.ok(type(claude_sessions.sessions(vim.fn.getcwd())) == "table",
  "claude: sessions() resolves the cwd slug without raising")

t.done()
