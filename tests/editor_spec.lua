-- Host side of the agent TUI's ctrl+g handoff (local-plugin/agent-workbench.nvim/lua/agent_workbench/editor.lua).
--
-- The wrapper's own half -- $EDITOR is invoked, the file comes back edited --
-- is a shell/RPC concern and is not exercised here. What matters in-process is
-- that every exit path releases the blocked wrapper, because a missed release
-- does not just lose an edit: it hangs the agent TUI, which is sitting in a
-- blocking wait on $EDITOR.
--
-- Before it, ai.selection's draft; after it, <leader>ai through the facade
-- and the per-agent seeds.
local t = dofile("tests/helper.lua")
local editor = require("agent_workbench.editor")
local sel = require("agent_workbench.selection")

---------------------------------------------------------------------------
-- ai.selection.draft(): UC-3 (<leader>ai seeding), UC-R1 (<leader>as)
---------------------------------------------------------------------------

-- Outside Visual mode draft() has nothing to read. Checked first, while the
-- session is still cleanly in Normal mode: the guard being wrong is exactly
-- what would let <leader>ai seed a draft the user never selected.
do
  t.eq(vim.fn.mode(), "n", "spec starts in Normal mode")
  local none, err = sel.draft()
  t.ok(none == nil, "no visual selection returns nil")
  t.ok(type(err) == "string", "no visual selection returns a reason")
end

-- draft() reads the *live* visual selection, so it has to be called from inside
-- Visual mode. Driving it through an x-mode mapping is also the production path:
-- <leader>as is an x-mode mapping (M.send_selection in local-plugin/agent-workbench.nvim/lua/agent_workbench/init.lua's KEYS,
-- applied by apply_keymaps), which captures through ai.selection.capture.
-- An unsaved buffer has no path to @-mention, so the literal text must travel.
do
  local start = vim.api.nvim_get_current_buf()
  local draft
  vim.keymap.set("x", "<F13>", function() draft = sel.draft() end, {})
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "alpha", "beta" })
  vim.bo[buf].filetype = "lua"
  vim.api.nvim_feedkeys(vim.keycode("ggVG<F13>"), "x", false)
  t.ok(type(draft) == "string", "UC-6: draft() returns a string for an unsaved buffer")
  t.ok(draft and draft:find("alpha", 1, true) ~= nil, "UC-6: draft carries the selected text")
  t.ok(draft and draft:find("beta", 1, true) ~= nil, "UC-6: draft carries every selected line")
  t.ok(draft and draft:find("@", 1, true) == nil, "UC-6: unsaved buffer produces no @-mention")
  t.ok(draft and draft:find("````lua", 1, true) ~= nil, "UC-6: text is fenced with the filetype")
  -- Fed headless, the keys leave Visual mode on, and the prompt floats below
  -- would take <C-d> and <C-c> as Visual-mode keys. A buffer switch ends it, so
  -- this goes back to the startup buffer.
  vim.api.nvim_set_current_buf(start)
end

---------------------------------------------------------------------------
-- The prompt float
---------------------------------------------------------------------------

local released = {}
editor._release = function(sentinel)
  released[#released + 1] = sentinel
end

local function tmpfile(lines)
  local path = vim.fn.tempname() .. ".md"
  vim.fn.writefile(lines, path)
  return path
end

-- A prompt file named the way Codex names it, which is how a prompt
-- float knows whose it is; tmpfile's names belong to no agent.
local owned_dir = vim.fn.tempname()
vim.fn.mkdir(owned_dir .. "/editor", "p")
local owned_n = 0
local function owned(lines)
  owned_n = owned_n + 1
  local path = ("%s/editor/%d.md"):format(owned_dir, owned_n)
  vim.fn.writefile(lines, path)
  return path
end

-- vim.schedule defers the window work off the RPC handler, so the callbacks
-- have to be drained before the float can be observed.
local function settle(ms)
  vim.wait(ms or 200, function() return false end)
end

local function float_win()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(win).relative ~= "" then return win end
  end
end

-- UC-1: a readable file opens in a float carrying the prompt's exact bytes.
local exact = { "alpha line one", "", "beta line two" }
local path = tmpfile(exact)
t.eq(editor.open(path, path .. ".done"), "opened", "UC-1: open() reports success")
settle()
local win = float_win()
t.ok(win ~= nil, "UC-1: prompt opens in a float")
local buf = vim.api.nvim_win_get_buf(win)
t.eq(vim.api.nvim_buf_get_lines(buf, 0, -1, false), exact, "UC-1: content arrives byte for byte")
-- The agent hands over a real .md file, so conform's markdown -> prettier rule
-- would run on the :w that hands it back and reflow the prompt first.
t.eq(vim.b[buf].autoformat, false, "UC-1: opts out of format-on-save")
t.eq(vim.bo[buf].bufhidden, "wipe", "UC-1: buffer goes when the window does")
-- The mark is what turns on @file completion (local-plugin/agent-workbench.nvim/lua/agent_workbench/mention.lua); without it
-- the blink provider stays disabled and the prompt loses the TUI's @ habit.
t.eq(vim.b[buf].ai_prompt, true, "UC-1: the buffer is marked as an agent prompt")

-- UC-2: closing the float releases the wrapper.
released = {}
vim.api.nvim_win_close(win, true)
settle()
t.eq(released, { path .. ".done" }, "UC-2: closing releases the wrapper exactly once")

-- UC-3: <C-d> writes the edit back to the file the agent will re-read.
local path2 = tmpfile({ "before" })
editor.open(path2, path2 .. ".done")
settle()
local win2 = float_win()
vim.api.nvim_set_current_win(win2)
vim.api.nvim_buf_set_lines(vim.api.nvim_win_get_buf(win2), 0, -1, false, { "after one", "after two" })
released = {}
vim.api.nvim_feedkeys(vim.keycode("<C-d>"), "x", false)
settle()
t.eq(vim.fn.readfile(path2), { "after one", "after two" }, "UC-3: <C-d> writes the edit back")
t.eq(released, { path2 .. ".done" }, "UC-3: <C-d> releases the wrapper")

-- UC-4: cancelling leaves the file alone, so the TUI's box keeps what it had.
local path3 = tmpfile({ "keep me" })
editor.open(path3, path3 .. ".done")
settle()
local win3 = float_win()
vim.api.nvim_set_current_win(win3)
vim.api.nvim_buf_set_lines(vim.api.nvim_win_get_buf(win3), 0, -1, false, { "thrown away" })
released = {}
vim.api.nvim_feedkeys(vim.keycode("<C-c>"), "x", false)
settle()
t.eq(vim.fn.readfile(path3), { "keep me" }, "UC-4: <C-c> leaves the file untouched")
t.eq(released, { path3 .. ".done" }, "UC-4: <C-c> still releases the wrapper")

-- UC-5: a refusal must release too, or the agent waits on an editor that never
-- opened. This is the failure mode that hangs the TUI rather than losing text.
released = {}
t.eq(editor.open("/nonexistent/prompt.md", "/tmp/never.done"), "error: not readable",
  "UC-5: an unreadable path is refused")
t.eq(released, { "/tmp/never.done" }, "UC-5: a refusal still releases the wrapper")

released = {}
t.eq(editor.open("", "/tmp/never2.done"), "error: no path", "UC-5: an empty path is refused")
t.eq(released, { "/tmp/never2.done" }, "UC-5: an empty path still releases the wrapper")

-- UC-7: a duplicate request for a prompt already on screen must not stack a
-- second window on the same buffer -- and must let its own wrapper go, or the
-- agent behind it blocks forever.
local path4 = tmpfile({ "only once" })
editor.open(path4, path4 .. ".a")
settle()
-- Compare buffer handles, not names: on macOS the tempdir resolves through a
-- symlink, so the buffer's name is not the string that was handed in.
local win4 = float_win()
local buf4 = vim.api.nvim_win_get_buf(win4)
released = {}
t.eq(editor.open(path4, path4 .. ".b"), "focused", "UC-7: a duplicate open is refused")
settle()
t.eq(released, { path4 .. ".b" }, "UC-7: the duplicate's wrapper is released at once")
local showing = 0
for _, w in ipairs(vim.api.nvim_list_wins()) do
  if vim.api.nvim_win_get_buf(w) == buf4 then showing = showing + 1 end
end
t.eq(showing, 1, "UC-7: the prompt is still in exactly one window")
released = {}
vim.api.nvim_win_close(win4, true)
settle()
t.eq(released, { path4 .. ".a" }, "UC-7: closing still releases the original wrapper")

-- UC-8: images. The clipboard is stubbed because the real one is shared with
-- whatever the machine is doing, and ai.attach_images because it drives a live
-- agent pty.
local clipboard = require("agent_workbench.clipboard")
local has_image = true
-- Every file <C-v> wrote, so the assertions below look at this spec's images
-- only and never glob the directory.
local saved = {}
clipboard.has_image = function() return has_image end
clipboard.save_image = function(target)
  vim.fn.writefile({ "not really a png" }, target)
  saved[#saved + 1] = target
  return true
end

-- The staging directory is named after the pid, and pids are reused: a new
-- Nvim must not start out with what a dead one left there. Planted before this
-- process's first staging_dir() call, the way that earlier Nvim would have.
local staging = ("%s/nvim-ai-images-%d"):format(vim.fn.stdpath("cache"), vim.fn.getpid())
vim.fn.mkdir(staging, "p")
vim.fn.writefile({ "left by a dead Nvim" }, staging .. "/19-1.png")
t.eq(clipboard.staging_dir(), staging, "UC-8: images are staged in this pid's directory")
t.eq(vim.fn.readdir(staging), {}, "UC-8: a reused pid's directory starts out empty")

local ai = require("agent_workbench")
local attached
local real_attach_images = ai.attach_images
ai.attach_images = function(paths) attached = paths end

local function press_ctrl_v()
  vim.api.nvim_feedkeys(vim.keycode("<C-v>"), "x", false)
end

-- An empty clipboard stages nothing rather than creating a junk file.
local path5 = owned({ "prompt" })
editor.open(path5, path5 .. ".done")
settle()
vim.api.nvim_set_current_win(float_win())
has_image = false
press_ctrl_v()
attached = nil
vim.api.nvim_feedkeys(vim.keycode("<C-d>"), "x", false)
vim.wait(1200, function() return attached ~= nil end)
t.eq(saved, {}, "UC-8: an empty clipboard stages no file")
t.eq(attached, nil, "UC-8: nothing is attached when the clipboard holds no image")

-- Cancelling must drop staged images: the box keeps its old text, so attaching
-- would bolt them onto a prompt that was just thrown away.
has_image = true
local path6 = owned({ "prompt" })
editor.open(path6, path6 .. ".done")
settle()
vim.api.nvim_set_current_win(float_win())
press_ctrl_v()
local staged = saved
t.ok(#staged == 1 and vim.fn.filereadable(staged[1]) == 1, "UC-8: <C-v> stages the clipboard image to a file")
t.ok(#staged == 1 and vim.startswith(staged[1], staging .. "/"), "UC-8: the image is staged in this pid's directory")
-- Staging has to be visible, but as virtual text: real text would be sent to
-- the agent alongside the CLI's own [Image #N] marker.
local imgbuf = vim.api.nvim_get_current_buf()
local marks = vim.api.nvim_buf_get_extmarks(imgbuf, -1, 0, -1, { details = true })
local virt = 0
for _, m in ipairs(marks) do
  if m[4] and m[4].virt_lines then virt = virt + #m[4].virt_lines end
end
t.eq(virt, 1, "UC-8: a staged image shows as one virtual line")
t.eq(vim.api.nvim_buf_get_lines(imgbuf, 0, -1, false), { "prompt" },
  "UC-8: the buffer text itself is untouched, so nothing extra is sent")
attached = nil
vim.api.nvim_feedkeys(vim.keycode("<C-c>"), "x", false)
vim.wait(1200, function() return attached ~= nil end)
t.eq(attached, nil, "UC-8: cancelling attaches nothing")
t.eq(vim.tbl_filter(function(png) return vim.fn.filereadable(png) == 1 end, staged), {},
  "UC-8: cancelling deletes the staged file")

-- A prompt whose path names no agent (a `git commit` run in an agent's pane)
-- stages no image: it could only go to an agent guessed at. Its title names
-- no agent either.
local nobody = tmpfile({ "prompt" })
editor.open(nobody, nobody .. ".done")
settle()
local nobody_win = float_win()
local nobody_title = vim.api.nvim_win_get_config(nobody_win).title
if type(nobody_title) == "table" then nobody_title = (nobody_title[1] or {})[1] end
t.eq(nobody_title, " Prompt ", "UC-8: a prompt that names no agent is titled for none")
vim.api.nvim_set_current_win(nobody_win)
saved = {}
press_ctrl_v()
t.eq(saved, {}, "UC-8: <C-v> there stages nothing")
attached = nil
vim.api.nvim_feedkeys(vim.keycode("<C-d>"), "x", false)
vim.wait(1200, function() return attached ~= nil end)
t.eq(attached, nil, "UC-8: and returning it attaches nothing")
local owned_title = (function()
  local p = owned({ "prompt" })
  editor.open(p, p .. ".done")
  settle()
  local w = float_win()
  local title = vim.api.nvim_win_get_config(w).title
  vim.api.nvim_win_close(w, true)
  settle()
  if type(title) == "table" then title = (title[1] or {})[1] end
  return title
end)()
t.eq(owned_title, " Prompt · Codex ", "UC-8: Claude's prompt is titled for Codex")

-- Returning the prompt hands the staged images over.
local path7 = owned({ "prompt" })
editor.open(path7, path7 .. ".done")
settle()
vim.api.nvim_set_current_win(float_win())
saved = {}
press_ctrl_v()
press_ctrl_v()
attached = nil
vim.api.nvim_feedkeys(vim.keycode("<C-d>"), "x", false)
vim.wait(2000, function() return attached ~= nil end)
t.ok(#saved == 2 and vim.deep_equal(attached, saved), "UC-8: returning the prompt attaches both staged images")
-- A backend deletes what it attached; the stub above does not, and a later
-- Nvim given this pid would inherit the files.
vim.fn.delete(staging, "rf")
-- The <leader>ai cases below route images through the real one.
ai.attach_images = real_attach_images

-- UC-9: readiness detection. This is the one place the rendered screen is
-- read, and only as a trigger -- see the note on tui_ready.
local function scratch(lines)
  local b = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(b, 0, -1, false, lines)
  return b
end
t.eq(editor.tui_ready(scratch({ "", "Loading...", "" })), false,
  "UC-9: a booting TUI is not ready")
t.eq(editor.tui_ready(scratch({ "❯ " })), true, "UC-9: Claude's prompt marker counts as ready")
-- An empty box is the marker on its own, which is the state a cold start lands
-- in. Requiring whitespace after it meant readiness never fired there.
t.eq(editor.tui_ready(scratch({ "❯" })), true, "UC-9: an empty Claude box is ready")
t.eq(editor.tui_ready(scratch({ "›" })), true, "UC-9: an empty Codex box is ready")
t.eq(editor.tui_ready(scratch({ "› Ask Codex to do anything" })), true,
  "UC-9: Codex's prompt marker counts as ready")
-- The trust gate draws the same marker in front of a numbered choice; sending
-- the edit key there would do nothing useful.
t.eq(editor.tui_ready(scratch({ "❯ 1. Yes, I trust this folder", "  2. No, exit" })), false,
  "UC-9: a numbered choice list is not an input box")
t.eq(editor.tui_ready(nil), false, "UC-9: a missing buffer is not ready")

-- A prompt may blink during the final settle period. The wait must resume,
-- then either deliver exactly once or reach its original timeout.
do
  local defer, now = vim.defer_fn, vim.uv.now
  local clock, queue, actions, timeouts = 0, {}, 0, 0
  vim.uv.now = function() return clock end
  vim.defer_fn = function(fn, delay) queue[#queue + 1] = { fn = fn, at = clock + delay } end
  local function step()
    local task = table.remove(queue, 1)
    if not task then return false end
    clock = task.at
    task.fn()
    return true
  end
  local prompt = scratch({ "›" })
  local function wait()
    editor.when_ready(function() return prompt end,
      function() actions = actions + 1 end, function() timeouts = timeouts + 1 end)
  end
  wait()
  step()
  step()
  vim.api.nvim_buf_set_lines(prompt, 0, -1, false, { "Loading..." })
  step()
  t.eq(actions, 0, "a prompt lost during settling triggers no premature action")
  t.ok(#queue > 0, "losing the prompt during settling keeps the wait alive")
  vim.api.nvim_buf_set_lines(prompt, 0, -1, false, { "›" })
  for _ = 1, 8 do if not step() then break end end
  t.eq({ actions, timeouts, #queue }, { 1, 0, 0 }, "a returning prompt delivers once and stops polling")
  wait()
  step()
  step()
  vim.api.nvim_buf_set_lines(prompt, 0, -1, false, { "Loading..." })
  for _ = 1, 240 do if not step() then break end end
  t.eq({ actions, timeouts, #queue }, { 1, 1, 0 }, "a prompt that never returns still times out once")
  vim.defer_fn, vim.uv.now = defer, now
  vim.api.nvim_buf_delete(prompt, { force = true })
end

-- UC-6: the wrapper the terminals are launched with has to exist and be
-- runnable, or ctrl+g silently falls back to a nested nvim.
local wrapper = require("agent_workbench.backend.launch").wrapper()
t.eq(vim.fn.executable(wrapper), 1, "UC-6: the $EDITOR wrapper is executable")

-- UC-10: the float is modal. The global <C-h/j/k/l> window keys work from a
-- float too, and once focus is in the dashboard or the agent panel there is no
-- way back: the TUI is blocked on the wrapper and drops the ctrl+g <leader>ai
-- would send. So a slip out of the float is undone.
vim.cmd("vsplit")
local path10 = tmpfile({ "modal" })
editor.open(path10, path10 .. ".done")
settle()
local win10 = float_win()
for _, key in ipairs({ "<C-h>", "<C-l>", "<C-w>w", "<C-,>" }) do
  vim.api.nvim_set_current_win(win10)
  vim.api.nvim_feedkeys(vim.keycode(key), "tx", false)
  settle()
  t.eq(vim.api.nvim_get_current_win(), win10, "UC-10: " .. key .. " does not leave the prompt")
end
t.ok(editor.is_prompt_win(win10), "UC-10: the float is known as a prompt window")

-- A second prompt (the other agent's) may take focus: bouncing between two
-- modal floats would never settle.
local path10b = tmpfile({ "other agent" })
editor.open(path10b, path10b .. ".done")
settle()
local win10b = vim.api.nvim_get_current_win()
t.ok(win10b ~= win10 and editor.is_prompt_win(win10b), "UC-10: a second prompt opens and keeps focus")
settle()
t.eq(vim.api.nvim_get_current_win(), win10b, "UC-10: the first prompt does not steal focus back")

-- focus_open is the explicit way back, and carries a selection made meanwhile.
vim.api.nvim_win_close(win10b, true)
settle()
-- Force focus elsewhere despite the guard, as a plugin-driven focus change would.
for _, w in ipairs(vim.api.nvim_list_wins()) do
  if not editor.is_prompt_win(w) then vim.api.nvim_set_current_win(w) end
end
settle()
t.eq(vim.api.nvim_get_current_win(), win10, "UC-10: the guard also undoes a programmatic leave")
t.eq(editor.focus_open("picked"), true, "UC-10: focus_open reports an open prompt")
t.eq(vim.api.nvim_get_current_win(), win10, "UC-10: focus_open lands in the prompt")
t.eq(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win10), 0, -1, false), { "modal", "picked" },
  "UC-10: focus_open appends the selection to the prompt")
released = {}
vim.api.nvim_feedkeys(vim.keycode("<C-c>"), "x", false)
settle()
t.eq(released, { path10 .. ".done" }, "UC-10: the modal prompt still releases on cancel")
t.eq(editor.focus_open(), false, "UC-10: focus_open reports nothing once the prompt is closed")
vim.cmd("only")

---------------------------------------------------------------------------
-- <leader>ai: the agent TUI's own prompt editor (ctrl+g), routed into this Nvim
---------------------------------------------------------------------------

-- It opens no buffer of our own. It asks the agent's TUI to open the
-- prompt editor both CLIs already have on ctrl+g, which local-plugin/agent-workbench.nvim/scripts/agent-editor
-- routes back into this Nvim (local-plugin/agent-workbench.nvim/lua/agent_workbench/editor.lua). So what is under test here is
-- the keystroke payload and the facade wiring, not a buffer.
--
-- It runs on what the cases above left: editor._release still only records
-- (no sentinel is written), the clipboard is still UC-8's stub, and
-- ai.attach_images is the real one again.
local config = require("agent_workbench.state")
local backend = require("agent_workbench.backend." .. config.agent_names()[1])

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
local function prompt_lines(path)
  local tail = "/" .. vim.fs.basename(path)
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    local b = vim.api.nvim_win_get_buf(w)
    if vim.api.nvim_win_get_config(w).relative == "editor" and vim.api.nvim_buf_get_name(b):sub(-#tail) == tail then
      return vim.api.nvim_buf_get_lines(b, 0, -1, false)
    end
  end
end

-- UC-1: the key sent to the pty is exactly what both TUIs bind to "edit this
-- prompt in $EDITOR". Verified against both CLIs: a bare 0x07 opens it.
t.eq(editor.EDIT_KEY, "\7", "UC-1: the edit key is 0x07 (ctrl+g)")

-- Prompt files named the way each CLI names them: that name is how a prompt
-- float knows whose it is (claude-prompt-*.md, $CODEX_HOME/editor/*.md).
local dir = vim.fn.tempname()
vim.fn.mkdir(dir .. "/editor", "p")

-- A seed is for one agent: the agent is not optional.
t.ok(not pcall(editor.stage_seed, "for nobody"), "stage_seed without an agent is refused")
t.ok(not pcall(editor.stage_seed, "for nobody", { agent = "nope" }), "and so is one that is no agent")

-- UC-3: the selection reaches the prompt through the buffer, not through a
-- paste racing the key. A staged seed lands in the file the agent hands over.
local seeded = dir .. "/editor/seeded.md"
vim.fn.writefile({ "" }, seeded)
editor.stage_seed("picked lines", { agent = "codex" })
editor.open(seeded, seeded .. ".done")
settle()
t.eq(prompt_lines(seeded), { "picked lines" }, "UC-3: a staged seed fills an empty prompt")

-- Close it, or the next assertion reads the float that is still on screen.
close_floats()

-- A prompt whose path names no agent (a `git commit` run in an agent's pane)
-- has no owner: a seed waiting for an agent stays out of it.
editor.stage_seed("for claude", { agent = "codex" })
local nobody = vim.fn.tempname() .. ".md"
vim.fn.writefile({ "commit message" }, nobody)
editor.open(nobody, nobody .. ".done")
settle()
local nobody_win = float_win()
t.eq(prompt_lines(nobody), { "commit message" }, "a prompt that names no agent takes no seed")
t.ok(editor._seed_pending("codex"), "which still waits for Claude's next prompt")
local title = nobody_win and vim.api.nvim_win_get_config(nobody_win).title
if type(title) == "table" then title = (title[1] or {})[1] end
t.eq(title, " Prompt ", "and is titled for no agent")
t.eq({ editor.open_here() }, { true, nil }, "open_here: a prompt is open here, owned by nobody")
editor.stage_seed(nil, { agent = "codex" })

-- Close this one too: with a prompt open, compose() returns to it (UC-4 below)
-- instead of reaching the backend that UC-1 stubs next.
close_floats()

-- UC-1/UC-3: the facade hands the backend a seed only when there is a selection.
--
-- Nothing is on the right, so <leader>ai asks which chat (local-plugin/agent-workbench.nvim/lua/agent_workbench/slot.lua):
-- with none open, the new-chat picker, whose first entry is the first listed
-- provider's terminal (lua/config/ai.lua). The answer is given here, and the
-- agents on PATH are stand-ins -- the stubbed edit_prompt below would start
-- nothing anyway.
local stand_ins = vim.fn.tempname()
vim.fn.mkdir(stand_ins, "p")
for _, name in ipairs({ "codex", "codex" }) do
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
t.ok(asked[1] and asked[1].first:find(config.agents[config.agent_names()[1]].label .. " · terminal", 1, true) == 1,
  "offering the first provider's terminal first (" .. tostring(asked[1] and asked[1].first) .. ")")

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
-- Sending bytes to a terminal does not leave Visual mode, so the mode has to be
-- dropped explicitly.
t.eq(vim.fn.mode():sub(1, 1), "n", "UC-3: Visual mode is left behind")

-- UC-4: with a prompt already open, <leader>ai goes back to it instead of
-- sending ctrl+g -- the TUI is blocked on the wrapper and would swallow the
-- key. A Visual selection made meanwhile lands in that prompt.
local open = vim.fn.tempname() .. ".md"
vim.fn.writefile({ "half written" }, open)
editor.open(open, open .. ".done")
settle()
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

-- Codex owns its prompts and images; an unrelated $EDITOR request has no owner.
close_floats()
local codex_prompt = dir .. "/editor/image.md"
vim.fn.writefile({ "for codex" }, codex_prompt)
editor.open(codex_prompt, codex_prompt .. ".done")
settle()
local codex_win = float_titled("Codex")
t.ok(codex_win ~= nil, "Codex's prompt has its own title")
local codex = require("agent_workbench.backend.codex")
local attach = codex.attach_images
local routed = {}
codex.attach_images = function(paths) routed[#routed + 1] = paths end
has_image = true
vim.api.nvim_set_current_win(codex_win)
vim.cmd.stopinsert()
vim.fn.maparg("<C-v>", "n", false, true).callback()
vim.cmd("silent write")
vim.cmd.close()
vim.wait(2000, function() return #routed == 1 end, 10)
t.eq(#routed, 1, "returning the Codex prompt attaches its images once")
codex.attach_images = attach
local unowned = dir .. "/commit-message.md"
vim.fn.writefile({ "external editor" }, unowned)
editor.open(unowned, unowned .. ".done")
settle()
local previous_images = #saved
vim.fn.maparg("<C-v>", "n", false, true).callback()
t.eq(#saved, previous_images, "an unowned prompt cannot stage images for a guessed agent")
close_floats()

-- One seed address (Codex), with replacement, cancellation and expiry.
local calls = {}
local function stage(text, tag, ttl)
  editor.stage_seed(text, { agent = "codex", ttl_ms = ttl,
    on_consumed = function() calls[#calls + 1] = tag .. ":consumed" end,
    on_expired = function() calls[#calls + 1] = tag .. ":expired" end })
end
stage("feedback", "first")
editor.open(unowned, unowned .. ".done")
settle()
t.ok(editor._seed_pending("codex"), "an unrelated prompt cannot consume Codex feedback")
t.eq(prompt_lines(unowned), { "external editor" }, "unowned contents remain intact")
close_floats()
local addressed = dir .. "/editor/addressed.md"
vim.fn.writefile({ "typed first" }, addressed)
editor.open(addressed, addressed .. ".done")
settle()
t.eq(prompt_lines(addressed), { "typed first", "feedback" }, "feedback appends to the user's existing draft")
t.eq(calls, { "first:consumed" }, "consumption is acknowledged exactly once")
t.ok(not editor._seed_pending("codex"), "consumption empties the seed slot")
close_floats()
calls = {}
stage("old", "old")
stage("new", "new")
t.eq(calls, { "old:expired" }, "replacement expires the old seed")
editor.stage_seed(nil, { agent = "codex" })
t.eq(calls, { "old:expired", "new:expired" }, "cancellation expires the pending seed")
calls = {}
stage("expired", "ttl", 100)
vim.wait(1000, function() return #calls > 0 end, 10)
t.eq(calls, { "ttl:expired" }, "TTL expiry is acknowledged")
t.ok(not editor._seed_pending("codex"), "expired feedback cannot land in a later prompt")
t.ok(not pcall(editor.stage_seed, "later", { agent = "claude" }), "an unimplemented native agent has no seed slot")

-- Multiple editor requests route by tab/window, without sending another ctrl+g.
editor.open(addressed, addressed .. ".done")
settle()
local first_win = float_titled("Codex")
local first_tab = vim.api.nvim_get_current_tabpage()
vim.cmd("noautocmd tabnew")
local second_tab = vim.api.nvim_get_current_tabpage()
local second = dir .. "/editor/second.md"
vim.fn.writefile({ "second" }, second)
editor.open(second, second .. ".done")
settle()
vim.cmd("noautocmd tabnext " .. vim.api.nvim_tabpage_get_number(first_tab))
t.ok(editor.focus_open(), "an open prompt is refocused")
t.eq(vim.api.nvim_get_current_win(), first_win, "the current tab's prompt wins")
close_floats()
vim.api.nvim_set_current_tabpage(second_tab)
close_floats()
vim.cmd.tabclose()

-- Real backend staging and ctrl+g, backed only by the offline PTY fixture.
backend.edit_prompt = real_edit_prompt
vim.cmd.enew()
local session, cleanup_agent = t.start_codex(dir)
local sent = {}
local chan_send = vim.api.nvim_chan_send
vim.api.nvim_chan_send = function(channel, bytes)
  if channel == vim.bo[session.buf].channel then sent[#sent + 1] = bytes end
  return chan_send(channel, bytes)
end
calls = {}
codex.edit_prompt({ seed = "from the backend", ttl_ms = 5000,
  on_consumed = function() calls[#calls + 1] = "consumed" end,
  on_expired = function() calls[#calls + 1] = "expired" end })
vim.api.nvim_chan_send = chan_send
t.eq(sent, { editor.EDIT_KEY }, "the backend sends ctrl+g without Enter")
t.ok(editor._seed_pending("codex"), "real backend stages feedback for Codex")
local from_backend = dir .. "/editor/backend.md"
vim.fn.writefile({ "" }, from_backend)
editor.open(from_backend, from_backend .. ".done")
settle()
t.eq({ prompt_lines(from_backend), calls }, { { "from the backend" }, { "consumed" } },
  "the editor consumes the real backend's seed and callback")
close_floats()
cleanup_agent()
vim.fn.delete(dir, "rf")
vim.ui.select, vim.env.PATH = real_select, real_path
vim.fn.delete(stand_ins, "rf")
t.done()
