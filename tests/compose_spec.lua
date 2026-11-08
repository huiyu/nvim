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

-- Close this one too: with a prompt open, compose() returns to it (UC-4 below)
-- instead of reaching the backend that UC-1 stubs next.
for _, w in ipairs(vim.api.nvim_list_wins()) do
  if vim.api.nvim_win_get_config(w).relative == "editor" then
    pcall(vim.api.nvim_win_close, w, true)
  end
end
vim.wait(200, function() return false end)

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

-- UC-4: with a prompt already open, <leader>ai goes back to it instead of
-- sending ctrl+g -- the TUI is blocked on the wrapper and would swallow the
-- key. A Visual selection made meanwhile lands in that prompt.
local open = vim.fn.tempname() .. ".md"
vim.fn.writefile({ "half written" }, open)
editor.open(open, open .. ".done")
vim.wait(200, function() return false end)
local prompt_win = vim.api.nvim_get_current_win()
-- Step out without WinLeave, the way a focus change the modal guard cannot see
-- would leave things.
vim.cmd("noautocmd wincmd w")
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one", "two" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.cmd("normal! Vj")
seen = {}
ai.compose()
t.eq(#seen, 0, "UC-4: compose does not reach the backend while a prompt is open")
t.eq(vim.api.nvim_get_current_win(), prompt_win, "UC-4: compose refocuses the open prompt")
local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(prompt_win), 0, -1, false)
t.ok(#lines > 1 and lines[1] == "half written", "UC-4: the selection is appended to the open prompt")

-- After a switch both agents can have a prompt open, and the active provider
-- is not necessarily the one that handed a prompt over. Ownership comes from
-- the temp path each CLI chooses (claude-prompt-*.md, $CODEX_HOME/editor/*.md).
local function close_floats()
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(w).relative == "editor" then pcall(vim.api.nvim_win_close, w, true) end
  end
  vim.wait(100, function() return false end)
end
local function float_titled(text)
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    local cfg = vim.api.nvim_win_get_config(w)
    local title = cfg.relative == "editor" and cfg.title
    if type(title) == "table" then title = (title[1] or {})[1] end
    if type(title) == "string" and title:find(text, 1, true) then return w end
  end
end
close_floats()

local saved_provider = config.provider
config.use_provider("claude")
local dir = vim.fn.tempname()
vim.fn.mkdir(dir .. "/editor", "p")
local codex_prompt = dir .. "/editor/0193.md"
local claude_prompt = dir .. "/claude-prompt-1a2b.md"
vim.fn.writefile({ "for codex" }, codex_prompt)
vim.fn.writefile({ "for claude" }, claude_prompt)

editor.open(codex_prompt, codex_prompt .. ".done")
vim.wait(200, function() return false end)
local codex_win = float_titled("Codex")
t.ok(codex_win ~= nil, "a Codex prompt is titled for Codex while Claude is the active provider")

-- <C-v> stages an image; :w returns the prompt; the image goes back to Codex.
local routed = {}
local backends = { claude = require("ai.backend.claude"), codex = require("ai.backend.codex") }
local real_attach = { claude = backends.claude.attach_images, codex = backends.codex.attach_images }
for name, b in pairs(backends) do
  b.attach_images = function(paths) routed[#routed + 1] = { name, paths } end
end
local clipboard = require("ai.clipboard")
local real_has, real_save = clipboard.has_image, clipboard.save_image
clipboard.has_image = function() return true end
clipboard.save_image = function(path) vim.fn.writefile({ "png" }, path) return true end

vim.api.nvim_set_current_win(codex_win)
vim.cmd("stopinsert")
vim.fn.maparg("<C-v>", "n", false, true).callback()
vim.cmd("silent write")
vim.cmd("close")
vim.wait(2000, function() return #routed > 0 end)
t.eq(#routed, 1, "the staged image is attached once")
t.eq(routed[1] and routed[1][1], "codex", "to the agent that owns the prompt, not to the active provider")

clipboard.has_image, clipboard.save_image = real_has, real_save
for name, b in pairs(backends) do b.attach_images = real_attach[name] end
for _, entry in ipairs(routed) do
  for _, png in ipairs(entry[2]) do vim.fn.delete(png) end
end

-- With one prompt open per agent, <leader>ai returns to the active provider's.
editor.open(codex_prompt, codex_prompt .. ".done")
editor.open(claude_prompt, claude_prompt .. ".done")
vim.wait(200, function() return false end)
local claude_win, codex_again = float_titled("Claude Code"), float_titled("Codex")
t.ok(claude_win and codex_again, "both agents' prompts are open at once")
vim.cmd("noautocmd wincmd t")
t.ok(editor.focus_open(), "a prompt is open to return to")
t.eq(vim.api.nvim_get_current_win(), claude_win, "the active provider's prompt wins (Claude)")
config.use_provider("codex")
vim.cmd("noautocmd wincmd t")
editor.focus_open()
t.eq(vim.api.nvim_get_current_win(), codex_again, "and follows a switch (Codex)")
close_floats()
config.use_provider(saved_provider)
vim.fn.delete(dir, "rf")

t.done()
