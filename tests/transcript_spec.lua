-- ai.transcript, the read-only view of a native agent's own session records:
-- its adapters, its renderer and the view, in that order. Only the view stubs
-- view._adapter; the adapters are required directly, and read tests/fixtures
-- through a path relative to the cwd.
local t = dofile("tests/helper.lua")

-- Adapters. Covers UC-15/UC-16 (session discovery), UC-18 (cap), UC-19
-- (malformed lines).
--
-- Fixtures are hand-written miniatures, not real transcripts: real ones carry
-- the whole conversation and must never enter the repository. Their record
-- shapes were taken field-by-field from real files on disk.
do
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
end

-- Rendering. Covers UC-14 (prose visible, machinery folded) and UC-18
-- (truncation stated).
do
  local render = require("ai.transcript.render")

  local entries = {
    { role = "user",      kind = "text",        text = "有哪些Open issue",  time = "00:02" },
    { role = "assistant", kind = "thinking",    text = "weighing options",  time = "00:02" },
    { role = "assistant", kind = "tool_call",   text = "gh issue list",     name = "Bash", time = "00:02" },
    { role = "assistant", kind = "tool_result", text = "13\tOPEN",          name = "result", time = "00:02" },
    { role = "assistant", kind = "text",        text = "8 open issues",     time = "00:03" },
  }

  local meta = { provider = "claude", label = "Claude Code", id = "abcd1234",
    root = "/tmp/p", title = "Fixture", truncated = false }

  local lines, folds = render.build(entries, meta)

  t.eq(#lines, #folds, "UC-14: every line carries a fold level")
  t.ok(lines[1]:match("^# ") ~= nil, "starts with a level-1 markdown heading")

  local joined = table.concat(lines, "\n")
  t.ok(joined:find("有哪些Open issue", 1, true) ~= nil, "renders user text, CJK intact")
  t.ok(joined:find("8 open issues", 1, true) ~= nil, "renders assistant text")
  t.ok(joined:find("weighing options", 1, true) ~= nil, "renders thinking rather than dropping it")
  t.ok(joined:find("gh issue list", 1, true) ~= nil, "renders the tool call")
  t.ok(joined:find("Bash", 1, true) ~= nil, "names the tool")
  t.ok(joined:find(meta.root, 1, true) ~= nil, "header states the project root")

  -- Fold levels decide what a reader sees first.
  local function level_of(needle)
    for i, line in ipairs(lines) do
      if line:find(needle, 1, true) then return folds[i] end
    end
  end
  t.eq(level_of("有哪些Open issue"), 0, "UC-14: user text sits at fold level 0")
  t.eq(level_of("8 open issues"), 0, "UC-14: assistant text sits at fold level 0")
  t.ok(level_of("weighing options") >= 1, "UC-14: thinking is foldable")
  t.ok(level_of("gh issue list") >= 1, "UC-14: tool calls are foldable")
  t.ok(level_of("13\tOPEN") >= 1, "UC-14: tool results are foldable")

  -- Turn headings must stay at level 0 or the whole turn folds away with its
  -- machinery and the transcript reads as empty.
  local heading_level
  for i, line in ipairs(lines) do
    if line:match("^## ") then heading_level = folds[i] break end
  end
  t.eq(heading_level, 0, "UC-14: turn headings stay visible")

  -- UC-18: truncation is stated, never silent.
  local truncated_lines = render.build(entries, vim.tbl_extend("force", meta, {
    truncated = true, dropped = 42,
  }))
  t.ok(table.concat(truncated_lines, "\n"):find("42", 1, true) ~= nil,
    "UC-18: truncation states how many entries were dropped")

  -- An empty session must still produce a readable buffer, not an error.
  local empty_lines, empty_folds = render.build({}, meta)
  t.ok(#empty_lines > 0, "an empty session still renders a header")
  t.eq(#empty_lines, #empty_folds, "an empty session keeps lines and folds aligned")

  -- foldexpr must survive being called with no buffer state attached.
  t.eq(render.foldexpr(), 0, "foldexpr defaults to 0 when no fold table is attached")

  -- A long session folds in linear time. foldexpr runs once per line; reading
  -- the levels out of a buffer variable copied the whole table on every call,
  -- and a 42k-line transcript took 13 s to open. 30k lines took about 6.5 s
  -- that way and take well under a tenth of a second now: the bound is loose
  -- for a slow CI runner and still far below the quadratic time.
  local big = vim.api.nvim_create_buf(false, true)
  local n = 30000
  local big_lines, big_levels = {}, {}
  for i = 1, n do
    big_lines[i] = "line " .. i
    big_levels[i] = i % 10 == 0 and 0 or 1
  end
  vim.api.nvim_buf_set_lines(big, 0, -1, false, big_lines)
  render.set_folds(big, big_levels)
  vim.cmd("tabnew")
  vim.api.nvim_win_set_buf(0, big)
  vim.wo.foldmethod = "expr"
  vim.wo.foldexpr = "v:lua.require'ai.transcript.render'.foldexpr()"
  local started = vim.uv.hrtime()
  vim.cmd("normal! zx")
  local took = (vim.uv.hrtime() - started) / 1e6
  t.ok(took < 2000, ("folding %d lines takes linear time (%d ms)"):format(n, took))
  t.eq({ vim.fn.foldlevel(1), vim.fn.foldlevel(10) }, { 1, 0 }, "and reads each line's own level")
  vim.cmd("tabclose")
  vim.api.nvim_buf_delete(big, { force = true })
  t.eq(render.folds(big), nil, "a wiped buffer's levels are dropped")
end

-- The view. Covers UC-11 (open at the end), UC-12 (picker), UC-13 (refresh),
-- UC-17 (no session), UC-R5 (read-only), UC-R6 (never writes).
local view = require("ai.transcript")

local parse_calls = 0
local adapter_for = {}

-- Substitute the adapter so the test does not depend on which sessions happen
-- to exist on this machine. The indirection exists in the module for this.
local function stub(sessions, entries)
  view._adapter = function(agent)
    adapter_for[#adapter_for + 1] = agent
    return {
      sessions = function() return sessions end,
      parse = function()
        parse_calls = parse_calls + 1
        return entries, false
      end,
    }
  end
end

local entries = {
  { role = "user",      kind = "text",      text = "hi",        time = "00:01" },
  { role = "assistant", kind = "tool_call", text = "ls", name = "Bash", time = "00:01" },
  { role = "assistant", kind = "text",      text = "hello back", time = "00:02" },
}

stub({ { id = "s1", path = "/tmp/fixture-a.jsonl", mtime = 2, title = "Newest" } }, entries)

-- A transcript is one native agent's: the caller names it (the agent on the
-- right, or the one asked for), and nothing falls back to a default.
local function refusal(fn, ...)
  local ok, err = pcall(fn, ...)
  return not ok and tostring(err):find("a transcript belongs to a native agent", 1, true) ~= nil
end
t.ok(refusal(view.open_current), "open_current without an agent is refused, saying why")
t.ok(refusal(view.pick, "nope"), "and pick with something that is no agent")
adapter_for = {}
view.open_current("codex")
local buf = vim.api.nvim_get_current_buf()
local function only(agent)
  return #adapter_for > 0 and vim.iter(adapter_for):all(function(a) return a == agent end)
end
t.ok(only("codex"), "the named agent's records are read, and only those")
t.ok(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"):find("Codex", 1, true) ~= nil,
  "and the view names that agent")
t.eq(vim.b[buf].ai_transcript_agent, "codex", "the buffer remembers whose it is, for R")

t.eq(vim.bo[buf].buftype, "nofile", "UC-R5: transcript buffer is nofile")
t.eq(vim.bo[buf].modifiable, false, "UC-R5: transcript buffer is read-only")
t.eq(vim.bo[buf].swapfile, false, "UC-R5: transcript buffer has no swapfile")
t.eq(vim.bo[buf].filetype, "ai-transcript", "uses its own filetype, not markdown")
t.eq(vim.wo.foldmethod, "expr", "UC-14: folding is expression driven")
t.eq(vim.wo.foldlevel, 0, "UC-14: opens with machinery folded")
local folds = require("ai.transcript.render").folds(buf)
t.ok(type(folds) == "table", "fold levels are attached to the buffer")
t.eq(folds and #folds, vim.api.nvim_buf_line_count(buf), "fold levels cover every line")
t.eq(vim.b[buf].ai_transcript_folds, nil,
  "and kept on the Lua side: a buffer variable is copied on every foldexpr call")
t.eq(vim.fn.line("."), vim.fn.line("$"), "UC-11: cursor starts at the newest turn")

t.ok(vim.fn.maparg("R", "n", false, true).buffer == 1, "UC-13: R is mapped buffer-locally")
t.ok(vim.fn.maparg("q", "n", false, true).buffer == 1, "q is mapped buffer-locally")

-- The rendered content must actually be there.
local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
t.ok(text:find("hello back", 1, true) ~= nil, "renders the session content")
t.ok(text:find("Newest", 1, true) ~= nil, "header shows the session title")

-- UC-13: refresh re-reads rather than reusing a cached parse.
local before = parse_calls
adapter_for = {}
view.refresh(buf)
t.eq(parse_calls, before + 1, "UC-13: refresh re-reads the transcript")
t.ok(only("codex"), "UC-13: through the same agent's adapter")
t.eq(vim.bo[buf].modifiable, false, "UC-R5: refresh leaves the buffer read-only")

vim.cmd("bwipeout!")

-- UC-12: the picker must actually build. This is the path most likely to break
-- silently on a Snacks upgrade, since it depends on the `items`, `format` and
-- `preview` presets existing.
stub({
  { id = "s1", path = "/tmp/fixture-a.jsonl", mtime = 2, title = "Newest" },
  { id = "s2", path = "/tmp/fixture-b.jsonl", mtime = 1 },
}, entries)
local picked_ok, picked_err = pcall(view.pick, "claude")
t.ok(picked_ok, "UC-12: pick() builds a picker" .. (picked_ok and "" or (": " .. tostring(picked_err))))
local picker = Snacks.picker.get({ source = "ai_transcripts" })[1]
t.ok(picker ~= nil, "UC-12: the picker instance exists")
if picker then
  t.eq(#(picker:items() or {}), 2, "UC-12: every session reaches the picker")
  picker:close()
end

-- UC-17: no session must notify and open nothing.
stub({}, {})
local current = vim.api.nvim_get_current_buf()
view.open_current("claude")
t.eq(vim.api.nvim_get_current_buf(), current, "UC-17: no sessions opens no buffer")

-- pick() must also survive having nothing to offer.
local ok = pcall(view.pick, "claude")
t.ok(ok, "UC-12: pick() does not raise when there are no sessions")

-- q in the only layout window, with floats around (a notification, a noice
-- popup, incline's label). Counting every window made q try to close the last
-- real one and fail with E444. Headless shows none of them, so a hidden float
-- stands in.
stub({ { id = "s1", path = "/tmp/fixture-a.jsonl", mtime = 2, title = "Newest" } }, entries)
view.open_current("claude")
local transcript = vim.api.nvim_get_current_buf()
vim.cmd("silent! tabonly")
local float = vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), false, {
  relative = "editor", row = 0, col = 0, width = 1, height = 1, hide = true, focusable = false,
})
local closed, close_err = pcall(vim.fn.maparg("q", "n", false, true).callback)
t.ok(closed, "q in the only real window does not raise" .. (closed and "" or (": " .. tostring(close_err))))
t.eq(vim.api.nvim_buf_is_valid(transcript), false, "q wipes the transcript when no other layout window is left")
t.eq(vim.api.nvim_win_is_valid(float), true, "q leaves floats alone")
vim.api.nvim_win_close(float, true)

t.done()
