-- Covers UC-1/UC-11/UC-12 (new entry points) and UC-R1 (nothing moved).
local t = dofile("tests/helper.lua")

local function mapped(lhs, mode)
  return next(vim.fn.maparg(lhs, mode or "n", false, true)) ~= nil
end

-- New entry points.
t.ok(mapped(" ai"), "UC-1: <leader>ai opens the agent's prompt editor")
t.ok(mapped(" ai", "x"), "UC-3: <leader>ai also works from Visual mode, to seed from a selection")
t.ok(mapped(" at"), "UC-11: <leader>at opens the transcript")
t.ok(mapped(" aT"), "UC-12: <leader>aT opens the session picker")

-- UC-R1: every pre-existing mapping keeps its key and mode.
for _, lhs in ipairs({ " ac", " af", " ar", " aR", " am", " ab" }) do
  t.ok(mapped(lhs), "UC-R1: <leader>" .. lhs:sub(2) .. " is unchanged")
end
t.ok(mapped(" as", "x"), "UC-R1: <leader>as still lives in Visual mode")

-- The facade must expose the methods those mappings call.
local ai = require("ai")
for _, method in ipairs({ "compose", "transcript", "transcript_pick" }) do
  t.ok(type(ai[method]) == "function", "facade exposes " .. method .. "()")
end

-- Descriptions carry the provider label so which-key stays truthful about which
-- agent a key talks to.
local label = require("ai.config").label
for _, lhs in ipairs({ " ai", " at", " aT" }) do
  local desc = vim.fn.maparg(lhs, "n", false, true).desc or ""
  t.ok(desc:find(label, 1, true) ~= nil, lhs .. " describes the active provider")
end

-- UC-R9 is deferred with issue #14: the unrelated terminal-mode maps remain
-- present and no <C-S-e>/<C-S-t> chord was added.
--
-- <C-q> is no longer in this list. It used to close the terminal, and was
-- removed deliberately: `exit`, <C-/> and :bd! already cover it, so the chord
-- only offered a way to force-delete a buffer. What replaced the guard is the
-- assertion below -- <C-c> must stay unmapped in Terminal-mode, because it is
-- SIGINT and shadowing it would make a runaway process unkillable.
for _, lhs in ipairs({ "<C-h>", "<C-l>", "<C-S-l>" }) do
  t.ok(mapped(lhs, "t"), "UC-R3: terminal-mode " .. lhs .. " is unchanged")
end
t.ok(not mapped("<C-q>", "t"), "close-terminal chord stays removed")
t.ok(not mapped("<C-c>", "t"), "terminal-mode <C-c> stays unmapped (SIGINT)")
t.ok(not mapped("<C-S-e>", "t"), "issue #14: no <C-S-e> chord was added this round")
t.ok(not mapped("<C-S-t>", "t"), "issue #14: no <C-S-t> chord was added this round")

t.done()
