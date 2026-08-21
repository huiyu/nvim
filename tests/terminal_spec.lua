-- Guards the terminal identity and position contracts.
--
-- Identity: `<leader>T1`..`T9` silently shared one terminal for a long time.
-- Snacks derives identity from cmd/cwd/env/count and never reads `opts.id`, so
-- passing name strings looked right and did nothing.
--
-- Position: chosen once by vim.g.terminal_position, never toggled at runtime.
-- edgy has to agree with that choice or it docks what should float.
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

-- Position is configuration, not a runtime toggle. Whatever it is set to, that
-- is the shape terminals open in -- and edgy must agree, or a float gets docked.
local floats = term.floats()
t.eq(floats, vim.g.terminal_position ~= "bottom", "floats() follows vim.g.terminal_position")

-- Terminal 1 is already showing from the check above; toggling again would
-- hide it.
vim.wait(400, function() return false end)
local win = vim.fn.bufwinid(one)
t.ok(win ~= -1, "terminal 1 is visible")
t.eq(relative_of(win) ~= "", floats,
  floats and "terminals open floating" or "terminals open docked")

-- An unnumbered toggle -- what <C-/> does -- must act on the terminal you are
-- sitting in. Defaulting to terminal 1 meant pressing it inside terminal 3
-- hid, or jumped to, a different terminal entirely.
term.toggle(3)
local three = vim.api.nvim_get_current_buf()
t.ok(three ~= one and three ~= two, "terminal 3 is its own shell")

local one_visible_before = vim.fn.bufwinid(one) ~= -1
term.toggle() -- <C-/> while sitting in terminal 3
t.eq(vim.fn.bufwinid(three), -1, "<C-/> hides the terminal you are in")
t.eq(vim.fn.bufwinid(one) ~= -1, one_visible_before,
  "<C-/> leaves other terminals exactly as they were")

-- From a normal buffer there is no "current terminal", so it falls back to 1.
if vim.fn.bufwinid(one) ~= -1 then term.toggle(1) end -- start from hidden
vim.cmd("topleft new")
t.eq(vim.bo.buftype, "", "sitting in a normal buffer")
term.toggle()
vim.wait(300, function() return false end)
t.ok(vim.fn.bufwinid(one) ~= -1, "from the editor, <C-/> still means terminal 1")

t.done()
