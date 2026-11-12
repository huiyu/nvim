-- Covers UC-11 (open at the end), UC-12 (picker), UC-13 (refresh),
-- UC-17 (no session), UC-R5 (read-only), UC-R6 (never writes).
local t = dofile("tests/helper.lua")
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

-- q in the only layout window, with floats around. ui2 (lua/config/options.lua) keeps
-- hidden cmd/msg/pager/dialog floats in the current tabpage, so counting every
-- window made q try to close the last real one and fail with E444. Headless
-- never enables ui2, so a hidden float stands in for its windows.
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
