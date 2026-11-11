-- Covers UC-1/UC-11/UC-12 (prompt editor and transcript keys) and UC-R1 (nothing moved).
local t = dofile("tests/helper.lua")

local function mapped(lhs, mode)
  return next(vim.fn.maparg(lhs, mode or "n", false, true)) ~= nil
end

-- The prompt editor and transcript keys.
t.ok(mapped(" ai"), "UC-1: <leader>ai opens the agent's prompt editor")
t.ok(mapped(" ai", "x"), "UC-3: <leader>ai also works from Visual mode, to seed from a selection")
t.ok(mapped(" at"), "UC-11: <leader>at opens the transcript")
t.ok(mapped(" aT"), "UC-12: <leader>aT opens the session picker")

-- UC-R1: every pre-existing mapping keeps its key and mode.
for _, lhs in ipairs({ " ac", " af", " ar", " aR", " am", " ab" }) do
  t.ok(mapped(lhs), "UC-R1: <leader>" .. lhs:sub(2) .. " is unchanged")
end
t.ok(mapped(" as", "x"), "UC-R1: <leader>as still lives in Visual mode")

-- No key names an agent: the chat keys reach whatever the tabpage shows on
-- its right (lua/ai/slot.lua), the native keys the native agent there, else
-- the one asked for. n/l open a picker, from Visual mode taking the selection
-- along; both are leaves. "…" marks a key that asks something of its own
-- before it acts (a choice, typed input): not aR, whose only question is the
-- shared which-agent one, nor aT/ao, whose list is where they go.
local FIXED = {
  [" an"] = "New AI chat…", [" al"] = "Switch AI chat…", [" ac"] = "Toggle AI chat", [" af"] = "Focus AI chat",
  [" ab"] = "Add file to AI chat", [" ai"] = "Compose prompt for AI chat",
  [" ar"] = "Resume native agent…", [" aR"] = "Continue native agent", [" am"] = "Select native agent model…",
  [" at"] = "Read native agent transcript", [" aT"] = "Browse native agent transcripts",
  [" ax"] = "Switch API key profile…",
  [" av"] = "Review changes since round baseline", [" aV"] = "Start review round",
  [" ap"] = "Companion actions…", [" ao"] = "Browse saved Companion chats",
}
local function desc(lhs, mode) return vim.fn.maparg(lhs, mode or "n", false, true).desc or "" end
for lhs, want in pairs(FIXED) do
  t.eq(desc(lhs), want, "<leader>" .. lhs:sub(2) .. " is " .. want)
end
t.eq(desc(" as", "x"), "Add selection to AI chat", "<leader>as is Add selection to AI chat")
for _, lhs in ipairs({ " an", " al", " ai" }) do
  t.ok(mapped(lhs, "x"), "<leader>" .. lhs:sub(2) .. " also works from Visual mode")
end
for _, mode in ipairs({ "n", "x" }) do
  local longer = {}
  for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do
    local keys = vim.fn.keytrans(vim.keycode(m.lhs))
    if keys:find("^<Space>a[nl].") then longer[#longer + 1] = keys end
  end
  t.eq(longer, {}, "no <leader>an* / <leader>al* mapping in " .. mode .. " mode")
end

-- <leader>ax picks the API key profile, Normal mode only.
for _, mode in ipairs({ "x", "o", "i", "t" }) do
  t.ok(not mapped(" ax", mode), "<leader>ax is Normal-mode only (" .. mode .. ")")
end

-- The per-kind chat keys are gone: a new chat of any kind comes from
-- <leader>an, whose entries name their billing, and Visual <leader>as adds to
-- the one on the right.
for _, lhs in ipairs({ " ag", " aG", " ah", " aH" }) do
  for _, mode in ipairs({ "n", "x" }) do
    t.ok(not mapped(lhs, mode), "<leader>" .. lhs:sub(2) .. " is gone (" .. mode .. ")")
  end
end

-- CodeCompanion keys sit directly under <leader>a, owned by the facade: e
-- inline, p actions, o saved chats. Visual mode takes the selection along.
for _, lhs in ipairs({ " ae", " ap", " ao", " ax" }) do
  t.ok(mapped(lhs), "<leader>" .. lhs:sub(2) .. " exists in Normal mode")
end
for _, lhs in ipairs({ " ae", " ap" }) do
  t.ok(mapped(lhs, "x"), "<leader>" .. lhs:sub(2) .. " exists in Visual mode")
end
t.ok(not mapped(" ao", "x"), "<leader>ao is Normal-mode only")
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
-- mode only: a round belongs to a conversation.
for _, lhs in ipairs({ " av", " aV" }) do
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

-- <leader>ae alone names something that changes: the key profile it bills,
-- relabelled by :AI key. Nothing else moves with it.
local c = require("ai.config")
t.eq(desc(" ae", "x"), ("Inline edit · %s (HTTP)…"):format(c.key.label), "<leader>ae names the key profile")
local real_notify = vim.notify
vim.notify = function() end
local was = c.key_setting()
local other = c.key.name == "anthropic" and "openai" or "anthropic"
require("ai.switch").key(other)
t.eq(desc(" ae"), ("Inline edit · %s (HTTP)…"):format(c.key_profiles[other].label),
  "after :AI key " .. other .. ", <leader>ae names " .. c.key_profiles[other].label)
for lhs, want in pairs(FIXED) do
  t.eq(desc(lhs), want, "after :AI key <leader>" .. lhs:sub(2) .. " is still " .. want)
end
require("ai.switch").key(was)
vim.notify = real_notify

-- The facade must expose the methods those mappings call.
local ai = require("ai")
for _, method in ipairs({ "compose", "transcript", "transcript_pick", "review", "new_round", "feed", "new_chat",
  "switch_chat", "tree_add" }) do
  t.ok(type(ai[method]) == "function", "facade exposes " .. method .. "()")
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
