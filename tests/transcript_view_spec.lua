-- Covers UC-11 (open at the end), UC-12 (picker), UC-13 (refresh),
-- UC-17 (no session), UC-R5 (read-only), UC-R6 (never writes).
local t = dofile("tests/helper.lua")
local view = require("ai.transcript")

local parse_calls = 0

-- Substitute the adapter so the test does not depend on which sessions happen
-- to exist on this machine. The indirection exists in the module for this.
local function stub(sessions, entries)
  view._adapter = function()
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

view.open_current()
local buf = vim.api.nvim_get_current_buf()

t.eq(vim.bo[buf].buftype, "nofile", "UC-R5: transcript buffer is nofile")
t.eq(vim.bo[buf].modifiable, false, "UC-R5: transcript buffer is read-only")
t.eq(vim.bo[buf].swapfile, false, "UC-R5: transcript buffer has no swapfile")
t.eq(vim.bo[buf].filetype, "ai-transcript", "uses its own filetype, not markdown")
t.eq(vim.wo.foldmethod, "expr", "UC-14: folding is expression driven")
t.eq(vim.wo.foldlevel, 0, "UC-14: opens with machinery folded")
t.ok(type(vim.b[buf].ai_transcript_folds) == "table", "fold levels are attached to the buffer")
t.eq(#vim.b[buf].ai_transcript_folds, vim.api.nvim_buf_line_count(buf),
  "fold levels cover every line")
t.eq(vim.fn.line("."), vim.fn.line("$"), "UC-11: cursor starts at the newest turn")

t.ok(vim.fn.maparg("R", "n", false, true).buffer == 1, "UC-13: R is mapped buffer-locally")
t.ok(vim.fn.maparg("q", "n", false, true).buffer == 1, "q is mapped buffer-locally")

-- The rendered content must actually be there.
local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
t.ok(text:find("hello back", 1, true) ~= nil, "renders the session content")
t.ok(text:find("Newest", 1, true) ~= nil, "header shows the session title")

-- UC-13: refresh re-reads rather than reusing a cached parse.
local before = parse_calls
view.refresh(buf)
t.eq(parse_calls, before + 1, "UC-13: refresh re-reads the transcript")
t.eq(vim.bo[buf].modifiable, false, "UC-R5: refresh leaves the buffer read-only")

vim.cmd("bwipeout!")

-- UC-12: the picker must actually build. This is the path most likely to break
-- silently on a Snacks upgrade, since it depends on the `items`, `format` and
-- `preview` presets existing.
stub({
  { id = "s1", path = "/tmp/fixture-a.jsonl", mtime = 2, title = "Newest" },
  { id = "s2", path = "/tmp/fixture-b.jsonl", mtime = 1 },
}, entries)
local picked_ok, picked_err = pcall(view.pick)
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
view.open_current()
t.eq(vim.api.nvim_get_current_buf(), current, "UC-17: no sessions opens no buffer")

-- pick() must also survive having nothing to offer.
local ok = pcall(view.pick)
t.ok(ok, "UC-12: pick() does not raise when there are no sessions")

t.done()
