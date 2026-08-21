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

t.done()
