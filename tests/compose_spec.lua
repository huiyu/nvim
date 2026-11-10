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
-- A temp name neither CLI uses belongs to the active provider, whose slot the
-- backends stage into.
editor.stage_seed("picked lines", { provider = config.provider })
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
--
-- Nothing is on the right, so <leader>ai asks which chat (lua/ai/slot.lua):
-- with none open, the new-chat picker, whose first entry is the active
-- provider's terminal. The answer is given here, and the agents on PATH are
-- stand-ins -- the stubbed edit_prompt below would start nothing anyway.
local stand_ins = vim.fn.tempname()
vim.fn.mkdir(stand_ins, "p")
for _, name in ipairs({ "claude", "codex" }) do
  vim.fn.writefile({ "#!/bin/sh", "exec cat" }, stand_ins .. "/" .. name)
  vim.fn.setfperm(stand_ins .. "/" .. name, "rwx------")
end
-- The stand-in select stays until the end: a question nothing answers would
-- otherwise reach the real one, which waits for input forever in a headless
-- run. Until UC-3 is done it answers with the first entry; after, it cancels.
local real_path, real_select = vim.env.PATH, vim.ui.select
vim.env.PATH = stand_ins .. ":" .. real_path
local asked, answering = {}, true
vim.ui.select = function(items, opts, on_choice)
  asked[#asked + 1] = { prompt = opts.prompt, first = opts.format_item(items[1]) }
  on_choice(answering and items[1] or nil)
end

local seen = {}
local real_edit_prompt = backend.edit_prompt
backend.edit_prompt = function(opts) seen[#seen + 1] = opts end

ai.compose()
t.eq(#seen, 1, "UC-1: compose reaches the backend once")
t.eq(seen[1] and seen[1].seed, nil, "UC-1: outside Visual mode there is no seed")
t.eq(#asked, 1, "with no chat on the right, it asks once")
t.ok(asked[1] and asked[1].first:find(config.label .. " · terminal", 1, true) == 1,
  "offering the active provider's terminal first (" .. tostring(asked[1] and asked[1].first) .. ")")

-- Drive a real Visual selection: ai.selection reads mode() and the `v` mark, so
-- a faked range would not exercise the path <leader>ai actually takes.
vim.cmd("enew")
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "alpha", "beta", "gamma" })
seen = {}
vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.cmd("normal! Vj")
ai.compose()
t.eq(#seen, 1, "UC-3: compose reaches the backend once from Visual mode")
answering = false
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
local asked_before = #asked
ai.compose()
t.eq(#seen, 0, "UC-4: compose does not reach the backend while a prompt is open")
t.eq(#asked, asked_before, "UC-4: nor asks where to go")
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

---------------------------------------------------------------------------
-- Seeds have an addressee: one slot per provider (review feedback)
---------------------------------------------------------------------------

local function settle(ms) vim.wait(ms or 150, function() return false end, 10) end
local function prompt_lines(path)
  local tail = "/" .. vim.fs.basename(path)
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    local b = vim.api.nvim_win_get_buf(w)
    if vim.api.nvim_win_get_config(w).relative == "editor" and vim.api.nvim_buf_get_name(b):sub(-#tail) == tail then
      return vim.api.nvim_buf_get_lines(b, 0, -1, false)
    end
  end
end
local function prompt_file(name, lines)
  local path = name == "codex" and (dir .. "/editor/" .. vim.fn.rand() .. ".md")
    or (dir .. "/claude-prompt-" .. vim.fn.rand() .. ".md")
  vim.fn.writefile(lines, path)
  return path
end

local calls = {}
local function stager(tag)
  return {
    on_consumed = function() calls[#calls + 1] = tag .. ":consumed" end,
    on_expired = function() calls[#calls + 1] = tag .. ":expired" end,
  }
end
local function staged(text, provider, tag, ttl)
  local opts = stager(tag)
  opts.provider, opts.ttl_ms = provider, ttl
  editor.stage_seed(text, opts)
end

-- Staged for Claude, the active provider being Codex: a Codex prompt opening
-- first does not take it, and Claude's next one does.
config.use_provider("codex")
calls = {}
local claude_file = prompt_file("claude", { "typed first" })
-- on_consumed runs once the text is in the buffer.
local seen_in_buffer
editor.stage_seed("for claude only", {
  provider = "claude",
  on_consumed = function()
    seen_in_buffer = prompt_lines(claude_file)
    calls[#calls + 1] = "a:consumed"
  end,
  on_expired = function() calls[#calls + 1] = "a:expired" end,
})
local codex_file = prompt_file("codex", { "codex box" })
editor.open(codex_file, codex_file .. ".done")
settle()
t.eq(prompt_lines(codex_file), { "codex box" }, "a seed staged for Claude stays out of a prompt Codex opens")
t.eq(calls, {}, "and nobody is told anything")
t.ok(editor._seed_pending("claude"), "the Claude seed is still waiting")
close_floats()
editor.open(claude_file, claude_file .. ".done")
settle()
t.eq(prompt_lines(claude_file), { "typed first", "for claude only" }, "Claude's prompt gets it, after what was typed")
t.eq(calls, { "a:consumed" }, "on_consumed fires once, on_expired never")
t.eq(seen_in_buffer, { "typed first", "for claude only" }, "on_consumed runs with the text already in the buffer")
t.eq(editor._seed_pending("claude"), false, "the slot is empty afterwards")
close_floats()

-- A newer seed replaces an older one: the older one hears on_expired only.
calls = {}
staged("first", "claude", "old")
staged("second", "claude", "new")
t.eq(calls, { "old:expired" }, "a replaced seed fires its on_expired, never on_consumed")
-- Clearing one slot leaves the other.
staged("codex text", "codex", "cx")
editor.stage_seed(nil, { provider = "claude" })
t.eq(calls, { "old:expired", "new:expired" }, "stage_seed(nil) clears that slot, with its on_expired")
t.ok(editor._seed_pending("codex") and not editor._seed_pending("claude"), "and only that slot")
editor.stage_seed(nil, { provider = "codex" })

-- A TTL drops a seed nobody took in time.
calls = {}
staged("in time?", "claude", "ttl", 100)
vim.wait(1000, function() return #calls > 0 end, 10)
t.eq(calls, { "ttl:expired" }, "a seed not taken within ttl_ms expires")
t.eq(editor._seed_pending("claude"), false, "and is no longer staged")
local late = prompt_file("claude", { "" })
editor.open(late, late .. ".done")
settle()
t.eq(prompt_lines(late), { "" }, "a prompt opened after the TTL gets nothing")
close_floats()
-- Without a TTL a seed waits, as a <leader>ai selection always has.
calls = {}
staged("no rush", "claude", "wait")
settle(300)
t.ok(editor._seed_pending("claude") and #calls == 0, "a seed without ttl_ms keeps waiting")
editor.stage_seed(nil, { provider = "claude" })

-- focus_open with a provider takes only that agent's prompt.
config.use_provider("claude")
local codex_open = prompt_file("codex", { "codex prompt" })
editor.open(codex_open, codex_open .. ".done")
settle()
vim.cmd("noautocmd wincmd t")
t.eq(editor.focus_open("feedback", "claude"), false, "focus_open(text, \"claude\") ignores Codex's open prompt")
t.eq(prompt_lines(codex_open), { "codex prompt" }, "and leaves it untouched")
t.eq(editor.focus_open("feedback", "codex"), true, "focus_open(text, \"codex\") uses it")
t.eq(prompt_lines(codex_open), { "codex prompt", "feedback" }, "appending the text")
close_floats()

-- The backends stage into their own slot, passing the callbacks along. The
-- Claude backend runs for real against a stand-in terminal module: a `cat`
-- job takes the edit key.
backend.edit_prompt = real_edit_prompt
local term_buf = vim.api.nvim_create_buf(false, true)
local cat
vim.api.nvim_buf_call(term_buf, function() cat = vim.fn.jobstart({ "cat" }, { term = true }) end)
local saved_terminal = package.loaded["claudecode.terminal"]
package.loaded["claudecode.terminal"] = {
  get_active_terminal_bufnr = function() return term_buf end,
  ensure_visible = function() end,
}
calls = {}
local opts = stager("backend")
opts.seed, opts.ttl_ms = "from the backend", 5000
require("ai.backend.claude").edit_prompt(opts)
package.loaded["claudecode.terminal"] = saved_terminal
t.ok(editor._seed_pending("claude") and not editor._seed_pending("codex"), "Claude's edit_prompt stages into Claude's slot")
local via_backend = prompt_file("claude", { "" })
editor.open(via_backend, via_backend .. ".done")
settle()
t.eq({ prompt_lines(via_backend), calls }, { { "from the backend" }, { "backend:consumed" } },
  "with the stager's callbacks attached")
close_floats()
pcall(vim.fn.jobstop, cat)
-- Codex's backend starts a real terminal, so its line is checked as written.
for _, name in ipairs({ "claude", "codex" }) do
  local source = table.concat(vim.fn.readfile("lua/ai/backend/" .. name .. ".lua"), "\n")
  local body = source:match("function M%.edit_prompt%(opts%)(.-)\nend\n") or ""
  local call = body:match("editor%.stage_seed%((.-)%)\n") or ""
  t.ok(call:find(('provider = "%s"'):format(name), 1, true) ~= nil and call:find("on_consumed = opts.on_consumed", 1, true) ~= nil
    and call:find("on_expired = opts.on_expired", 1, true) ~= nil and call:find("ttl_ms = opts.ttl_ms", 1, true) ~= nil,
    name .. "'s edit_prompt stages its seed for itself, with the callbacks and the TTL")
end

config.use_provider(saved_provider)
vim.fn.delete(dir, "rf")
vim.ui.select, vim.env.PATH = real_select, real_path
vim.fn.delete(stand_ins, "rf")

t.done()
