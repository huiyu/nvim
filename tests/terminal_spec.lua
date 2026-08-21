-- Guards the terminal identity and shape contracts.
--
-- Identity: `<leader>T1`..`T9` silently shared one terminal for a long time.
-- Snacks derives identity from cmd/cwd/env/count and never reads `opts.id`, so
-- passing name strings looked right and did nothing.
--
-- Shape: floating is a property of a terminal, not a separate terminal. The
-- same shell, buffer and window handle survive the switch.
local t = dofile("tests/helper.lua")
local term = require("util.terminal")

-- edgy claims every non-agent snacks_terminal for its bottom edge, so it must
-- be loaded before any float is judged. It normally arrives on VeryLazy, which
-- never fires headless -- which is exactly why an earlier version of this spec
-- passed while the float still docked itself in a real session.
vim.cmd("Lazy! load edgy.nvim")
t.ok(package.loaded["edgy"] ~= nil, "edgy is loaded, so its layout rules apply")

local function relative_of(win)
  return vim.api.nvim_win_get_config(win).relative
end

-- Numbered terminals must actually be distinct.
term.toggle(1)
local one = vim.api.nvim_get_current_buf()
term.toggle(1) -- hide
term.toggle(2)
local two = vim.api.nvim_get_current_buf()
t.ok(one ~= two, "<leader>T1 and <leader>T2 are different terminals")
t.eq(vim.bo[one].buftype, "terminal", "terminal 1 is a real terminal")
term.toggle(2) -- hide

-- Re-toggling a number returns to the same shell rather than spawning another.
term.toggle(1)
t.eq(vim.api.nvim_get_current_buf(), one, "toggling a number reuses its shell")

-- Floating acts on the terminal you are in, and changes only its shape.
local before_win = vim.api.nvim_get_current_win()
t.eq(relative_of(before_win), "", "terminal 1 starts docked")

term.toggle_float()
local float_win = vim.api.nvim_get_current_win()
t.eq(relative_of(float_win), "editor", "toggle_float floats the terminal")
t.eq(float_win, before_win, "floating reuses the same window, not a new one")
t.eq(vim.api.nvim_win_get_buf(float_win), one, "floating keeps the same shell")
t.ok(term.is_float_buf(one), "the floating terminal is marked for edgy")

-- edgy docks asynchronously; it must leave a marked float alone.
vim.wait(300, function() return false end)
t.ok(vim.api.nvim_win_is_valid(float_win), "the float survives edgy's layout pass")
t.eq(relative_of(float_win), "editor", "edgy does not dock the float")

-- And back again.
term.toggle_float()
t.eq(relative_of(vim.api.nvim_get_current_win()), "", "toggling again re-docks it")
t.eq(vim.api.nvim_get_current_buf(), one, "re-docking keeps the same shell")
t.ok(not term.is_float_buf(one), "the mark is cleared once docked")

-- Hiding a floated terminal with <C-/> and bringing it back must not leave a
-- stale mark: Snacks restores its own docked config, so the mark would tell
-- edgy to skip a window that is no longer a float.
term.toggle_float()
t.eq(relative_of(vim.api.nvim_get_current_win()), "editor", "floated again")
term.toggle(1) -- hide
term.toggle(1) -- show
vim.wait(300, function() return false end)
t.ok(not term.is_float_buf(one), "reshowing through Snacks clears the float mark")
local reshown = vim.fn.bufwinid(one)
t.ok(reshown ~= -1, "the terminal is visible again")
t.eq(relative_of(reshown), "", "and it came back docked, matching the cleared mark")

-- From the editor, the count decides which terminal is acted on.
-- A fresh window is needed, not `enew`: edgy owns the terminal's window and
-- keeps a terminal in it, so swapping the buffer in place does not get us out.
vim.cmd("topleft new")
t.eq(vim.bo.buftype, "", "now sitting in a normal buffer, not a terminal")
term.toggle_float(2)
t.eq(vim.api.nvim_get_current_buf(), two, "a count targets that terminal from the editor")
t.eq(relative_of(vim.api.nvim_get_current_win()), "editor", "and floats it")
term.toggle_float(2)

t.done()
