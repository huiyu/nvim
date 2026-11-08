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

-- <leader>ax opens :AI's switcher, Normal mode only.
t.eq(vim.fn.maparg(" ax", "n", false, true).desc, "Switch AI provider / API key", "<leader>ax switches provider / key")
for _, mode in ipairs({ "x", "o", "i", "t" }) do
  t.ok(not mapped(" ax", mode), "<leader>ax is Normal-mode only (" .. mode .. ")")
end

-- CodeCompanion keys sit directly under <leader>a, owned by the facade so a
-- switch can relabel them: g/G agent chat (ACP), h/H API chat (HTTP), e inline,
-- p actions, o saved chats. Visual mode takes the selection along.
for _, lhs in ipairs({ " ag", " aG", " ah", " aH", " ae", " ap", " ao", " ax" }) do
  t.ok(mapped(lhs), "<leader>" .. lhs:sub(2) .. " exists in Normal mode")
end
for _, lhs in ipairs({ " ag", " ah", " ae", " ap" }) do
  t.ok(mapped(lhs, "x"), "<leader>" .. lhs:sub(2) .. " exists in Visual mode")
end
for _, lhs in ipairs({ " aG", " aH", " ao" }) do
  t.ok(not mapped(lhs, "x"), "<leader>" .. lhs:sub(2) .. " is Normal-mode only")
end
-- <leader>ap is a leaf now: the old two-level keys are gone, and nothing longer
-- may make <leader>ap wait out 'timeoutlen'.
for _, lhs in ipairs({ " apc", " apt", " apa", " api", " apb", " aph" }) do
  t.ok(not mapped(lhs) and not mapped(lhs, "x"), "<leader>" .. lhs:sub(2) .. " is gone")
end
for _, mode in ipairs({ "n", "x" }) do
  local longer = {}
  for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do
    local keys = vim.fn.keytrans(vim.keycode(m.lhs))
    if keys:find("^<Space>ap.") then longer[#longer + 1] = keys end
  end
  t.eq(longer, {}, "no <leader>ap* mapping in " .. mode .. " mode")
end
t.ok(require("lazy.core.config").plugins["codecompanion.nvim"]._.loaded == nil,
  "defining them loaded no CodeCompanion")

-- Review rounds: <leader>av opens the review, <leader>aV starts a round. Normal
-- mode only, and named for no agent: a round belongs to a conversation.
local REVIEW = { [" av"] = "Review changes since round baseline", [" aV"] = "Start a review round" }
for lhs, want in pairs(REVIEW) do
  t.eq(vim.fn.maparg(lhs, "n", false, true).desc, want, "<leader>" .. lhs:sub(2) .. " is " .. want)
  for _, mode in ipairs({ "x", "o", "i", "t" }) do
    t.ok(not mapped(lhs, mode), "<leader>" .. lhs:sub(2) .. " is Normal-mode only (" .. mode .. ")")
  end
end
for _, module in ipairs({ "ai.review", "ai.review.rounds", "util.baseline" }) do
  t.eq(package.loaded[module], nil, "defining them loaded no " .. module)
end
-- The handlers require their module when pressed, not before. Stand-ins
-- record the call, so no view opens and no git runs here.
local review_calls = {}
package.loaded["ai.review"] = { open = function() review_calls[#review_calls + 1] = "open" end }
package.loaded["ai.review.rounds"] = { start = function() review_calls[#review_calls + 1] = "start" end }
vim.fn.maparg(" av", "n", false, true).callback()
vim.fn.maparg(" aV", "n", false, true).callback()
package.loaded["ai.review"], package.loaded["ai.review.rounds"] = nil, nil
t.eq(review_calls, { "open", "start" }, "<leader>av reaches ai.review.open, <leader>aV ai.review.rounds.start")

-- The descriptions name what each key reaches, and follow a switch: the agent
-- for g/G, the key profile for h/H/e.
local c = require("ai.config")
local function desc(lhs, mode) return vim.fn.maparg(lhs, mode or "n", false, true).desc or "" end
t.eq(desc(" ag"), ("Agent chat · %s (ACP)"):format(c.label), "<leader>ag names the agent")
t.eq(desc(" ah"), ("API chat · %s (HTTP)"):format(c.key.label), "<leader>ah names the key profile")
t.eq(desc(" ae", "x"), ("Inline edit · %s (HTTP)"):format(c.key.label), "<leader>ae names the key profile")
local real_notify = vim.notify
vim.notify = function() end
local start = c.provider
local other = start == "claude" and "codex" or "claude"
local was_auto = c.key.auto
require("ai.switch").provider(other)
for _, lhs in ipairs({ " ag", " aG", " ai", " at", " aT" }) do
  t.ok(desc(lhs):find(c.providers[other].label, 1, true) ~= nil, "after a switch " .. lhs .. " names " .. c.label)
end
t.ok(desc(" ag", "x"):find(c.providers[other].label, 1, true) ~= nil, "and so does Visual <leader>ag")
for lhs, want in pairs(REVIEW) do
  t.eq(desc(lhs), want, "after a switch <leader>" .. lhs:sub(2) .. " keeps its description")
end
if was_auto then
  t.ok(desc(" ah"):find(c.key.label, 1, true) ~= nil and desc(" aH"):find(c.key.label, 1, true) ~= nil,
    "an auto key takes <leader>ah/aH along to " .. c.key.label)
end
require("ai.switch").provider(start)
vim.notify = real_notify

-- The facade must expose the methods those mappings call.
local ai = require("ai")
for _, method in ipairs({ "compose", "transcript", "transcript_pick", "review", "new_round", "feed" }) do
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
