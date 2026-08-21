-- <leader>ai after the composer was retired.
--
-- It no longer opens a buffer of our own. It asks the agent's TUI to open the
-- prompt editor both CLIs already have on ctrl+g, which scripts/agent-editor
-- routes back into this Nvim (lua/ai/editor.lua). So what is under test here is
-- the keystroke payload and the facade wiring, not a buffer.
local t = dofile("tests/helper.lua")
local ai = require("ai")
local config = require("ai.config")
local editor = require("ai.editor")
local backend = require("ai.backend." .. config.provider)

-- UC-1: the key sent to the pty is exactly what both TUIs bind to "edit this
-- prompt in $EDITOR". Verified against both CLIs: a bare 0x07 opens it.
t.eq(editor.EDIT_KEY, "\7", "UC-1: the edit key is 0x07 (ctrl+g)")

-- UC-3: the selection reaches the prompt through the buffer, not through a
-- paste racing the key. A staged seed lands in the file the agent hands over.
local seeded = vim.fn.tempname() .. ".md"
vim.fn.writefile({ "" }, seeded)
editor.stage_seed("picked lines")
editor.open(seeded, seeded .. ".done")
vim.wait(200, function() return false end)
local shown
for _, w in ipairs(vim.api.nvim_list_wins()) do
  if vim.api.nvim_win_get_config(w).relative == "editor" then
    shown = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(w), 0, -1, false)
  end
end
t.eq(shown, { "picked lines" }, "UC-3: a staged seed fills an empty prompt")

-- Close it, or the next assertion reads the float that is still on screen.
for _, w in ipairs(vim.api.nvim_list_wins()) do
  if vim.api.nvim_win_get_config(w).relative == "editor" then
    pcall(vim.api.nvim_win_close, w, true)
  end
end
vim.wait(200, function() return false end)

-- An unconsumed seed must not leak into an unrelated ctrl+g later on.
local plain = vim.fn.tempname() .. ".md"
vim.fn.writefile({ "typed in the box" }, plain)
editor.open(plain, plain .. ".done")
vim.wait(200, function() return false end)
for _, w in ipairs(vim.api.nvim_list_wins()) do
  if vim.api.nvim_win_get_config(w).relative == "editor" then
    shown = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(w), 0, -1, false)
  end
end
t.eq(shown, { "typed in the box" }, "UC-3: the seed is consumed once, not reused")

-- UC-1/UC-3: the facade hands the backend a seed only when there is a selection.
local seen = {}
backend.edit_prompt = function(opts) seen[#seen + 1] = opts end

ai.compose()
t.eq(#seen, 1, "UC-1: compose reaches the backend once")
t.eq(seen[1].seed, nil, "UC-1: outside Visual mode there is no seed")

-- Drive a real Visual selection: ai.selection reads mode() and the `v` mark, so
-- a faked range would not exercise the path <leader>ai actually takes.
vim.cmd("enew")
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "alpha", "beta", "gamma" })
seen = {}
vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.cmd("normal! Vj")
ai.compose()
t.eq(#seen, 1, "UC-3: compose reaches the backend once from Visual mode")
t.ok(seen[1].seed ~= nil and seen[1].seed ~= "", "UC-3: a Visual selection seeds the prompt")
-- The composer this replaced left Visual by opening a buffer; sending bytes to a
-- terminal does not, so the mode has to be dropped explicitly.
t.eq(vim.fn.mode():sub(1, 1), "n", "UC-3: Visual mode is left behind")

-- UC-2 lives in the backends: with no terminal running they must start one
-- rather than fire 0x07 into a process that is not listening yet.
t.eq(type(require("ai.backend.claude").edit_prompt), "function",
  "UC-2: the Claude backend exposes edit_prompt")
t.eq(type(require("ai.backend.codex").edit_prompt), "function",
  "UC-2: the Codex backend exposes edit_prompt")

-- UC-R1: <leader>as keeps its own path; retiring the composer must not take
-- ai.selection with it.
t.eq(type(require("ai.selection").draft), "function", "UC-R1: ai.selection survives")

-- The retired modules are gone, not merely unreferenced.
t.eq(pcall(require, "ai.composer"), false, "ai.composer is removed")
-- ai.clipboard survived the composer: <C-v> in the prompt editor still stages
-- images through it, and the agent's own ctrl+v is still how they get attached.
t.eq(pcall(require, "ai.clipboard"), true, "ai.clipboard is still in use")

t.done()
