-- Host side of the agent TUI's ctrl+g handoff (lua/ai/editor.lua).
--
-- The wrapper's own half -- $EDITOR is invoked, the file comes back edited --
-- is a shell/RPC concern and is not exercised here. What matters in-process is
-- that every exit path releases the blocked wrapper, because a missed release
-- does not just lose an edit: it hangs the agent TUI, which is sitting in a
-- blocking wait on $EDITOR.
local t = dofile("tests/helper.lua")
local editor = require("ai.editor")

local released = {}
editor._release = function(sentinel)
  released[#released + 1] = sentinel
end

local function tmpfile(lines)
  local path = vim.fn.tempname() .. ".md"
  vim.fn.writefile(lines, path)
  return path
end

-- vim.schedule defers the window work off the RPC handler, so the callbacks
-- have to be drained before the float can be observed.
local function settle()
  vim.wait(200, function() return false end)
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
-- The mark is what turns on @file completion (lua/ai/mention.lua); without it
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
local clipboard = require("ai.clipboard")
local has_image = true
clipboard.has_image = function() return has_image end
clipboard.save_image = function(target)
  vim.fn.writefile({ "not really a png" }, target)
  return true
end

local ai = require("ai")
local attached
ai.attach_images = function(paths) attached = paths end

local function press_ctrl_v()
  vim.api.nvim_feedkeys(vim.keycode("<C-v>"), "x", false)
end

-- An empty clipboard stages nothing rather than creating a junk file.
local path5 = tmpfile({ "prompt" })
editor.open(path5, path5 .. ".done")
settle()
vim.api.nvim_set_current_win(float_win())
has_image = false
press_ctrl_v()
attached = nil
vim.api.nvim_feedkeys(vim.keycode("<C-d>"), "x", false)
vim.wait(1200, function() return attached ~= nil end)
t.eq(attached, nil, "UC-8: nothing is attached when the clipboard holds no image")

-- Cancelling must drop staged images: the box keeps its old text, so attaching
-- would bolt them onto a prompt that was just thrown away.
has_image = true
local path6 = tmpfile({ "prompt" })
editor.open(path6, path6 .. ".done")
settle()
vim.api.nvim_set_current_win(float_win())
press_ctrl_v()
local staged = vim.fn.glob(require("ai.clipboard").staging_dir() .. "/*.png", false, true)
t.ok(#staged > 0, "UC-8: <C-v> stages the clipboard image to a file")
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
for _, png in ipairs(staged) do
  t.eq(vim.fn.filereadable(png), 0, "UC-8: cancelling deletes the staged file")
end

-- Returning the prompt hands the staged images over.
local path7 = tmpfile({ "prompt" })
editor.open(path7, path7 .. ".done")
settle()
vim.api.nvim_set_current_win(float_win())
press_ctrl_v()
press_ctrl_v()
attached = nil
vim.api.nvim_feedkeys(vim.keycode("<C-d>"), "x", false)
vim.wait(2000, function() return attached ~= nil end)
t.ok(attached ~= nil and #attached == 2, "UC-8: returning the prompt attaches both staged images")

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

-- UC-6: the wrapper the terminals are launched with has to exist and be
-- runnable, or ctrl+g silently falls back to a nested nvim.
local wrapper = editor.wrapper()
t.eq(vim.fn.executable(wrapper), 1, "UC-6: the $EDITOR wrapper is executable")

t.done()
