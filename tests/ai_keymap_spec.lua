-- Covers UC-1/UC-11/UC-12 (new entry points) and UC-R1 (nothing moved).
local t = dofile("tests/helper.lua")

local function mapped(lhs, mode)
  return next(vim.fn.maparg(lhs, mode or "n", false, true)) ~= nil
end

-- New entry points.
t.ok(mapped(" ai"), "UC-1: <leader>ai opens the composer")
t.ok(mapped(" ai", "x"), "UC-6: <leader>ai also works from Visual mode, to seed from a selection")
t.ok(mapped(" at"), "UC-11: <leader>at opens the transcript")
t.ok(mapped(" aT"), "UC-12: <leader>aT opens the session picker")

-- UC-R1: every pre-existing mapping keeps its key and mode.
for _, lhs in ipairs({ " ac", " af", " ar", " aR", " am", " ab" }) do
  t.ok(mapped(lhs), "UC-R1: <leader>" .. lhs:sub(2) .. " is unchanged")
end
t.ok(mapped(" as", "x"), "UC-R1: <leader>as still lives in Visual mode")

-- The facade must expose the methods those mappings call.
local ai = require("ai")
for _, method in ipairs({ "compose", "transcript", "transcript_pick", "send_text" }) do
  t.ok(type(ai[method]) == "function", "facade exposes " .. method .. "()")
end

-- Descriptions carry the provider label so which-key stays truthful about which
-- agent a key talks to.
local label = require("ai.config").label
for _, lhs in ipairs({ " ai", " at", " aT" }) do
  local desc = vim.fn.maparg(lhs, "n", false, true).desc or ""
  t.ok(desc:find(label, 1, true) ~= nil, lhs .. " describes the active provider")
end

-- UC-R9 is deferred with issue #14, so lua/mappings.lua must be untouched: the
-- pre-existing terminal-mode maps are all still present and no <C-S-e>/<C-S-t>
-- was added.
for _, lhs in ipairs({ "<C-\\>", "<C-q>", "<C-h>", "<C-l>", "<C-S-l>" }) do
  t.ok(mapped(lhs, "t"), "UC-R3: terminal-mode " .. lhs .. " is unchanged")
end
t.ok(not mapped("<C-S-e>", "t"), "issue #14: no <C-S-e> chord was added this round")
t.ok(not mapped("<C-S-t>", "t"), "issue #14: no <C-S-t> chord was added this round")

t.done()
