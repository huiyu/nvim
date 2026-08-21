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

-- UC-1: with nothing to seed, the payload is exactly the key both TUIs bind to
-- "edit this prompt in $EDITOR". Verified against both CLIs: a bare 0x07 on the
-- pty opens the external editor.
t.eq(editor.EDIT_KEY, "\7", "UC-1: the edit key is 0x07 (ctrl+g)")
t.eq(editor.keys(), "\7", "UC-1: no seed sends the key alone")
t.eq(editor.keys(""), "\7", "UC-1: an empty seed sends the key alone")

-- UC-3: a seed is pasted first, then the editor is asked for -- in ONE payload,
-- so the pty cannot interleave them. Bracketed paste is what keeps an embedded
-- newline from submitting the prompt early.
local seeded = editor.keys("line one\nline two")
t.eq(seeded, "\27[200~line one\nline two\27[201~\7",
  "UC-3: a seed is bracketed-pasted, then the key follows in the same write")
t.ok(seeded:sub(-1) == "\7", "UC-3: the key is last, so the paste lands first")
t.ok(not seeded:find("\r"), "UC-3: no carriage return, so the prompt is not submitted")

-- A stray ESC in a selection would terminate the paste early and let the rest
-- be read as control sequences.
t.eq(editor.keys("a\27[200~b"), "\27[200~a[200~b\27[201~\7",
  "UC-3: ESC is stripped out of the seed")
t.eq(editor.keys("crlf\r\nend"), "\27[200~crlf\nend\27[201~\7",
  "UC-3: CRLF is normalised so it cannot submit")

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
