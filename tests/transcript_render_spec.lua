-- Covers UC-14 (prose visible, machinery folded) and UC-18 (truncation stated).
local t = dofile("tests/helper.lua")
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

t.done()
