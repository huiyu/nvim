-- Guards the terminal identity contract.
--
-- This exists because `<leader>T1`..`T9` silently shared one terminal for a
-- long time: Snacks derives identity from cmd/cwd/env/count and never reads
-- `opts.id`, so passing name strings looked right and did nothing.
local t = dofile("tests/helper.lua")
local term = require("util.terminal")

local function buf_of(x) return x and x.buf end

-- Numbered terminals must actually be distinct.
term.toggle(1)
local one = vim.api.nvim_get_current_buf()
term.toggle(1) -- hide
term.toggle(2)
local two = vim.api.nvim_get_current_buf()
t.ok(one ~= two, "<leader>T1 and <leader>T2 are different terminals")
t.eq(vim.bo[one].buftype, "terminal", "terminal 1 is a real terminal")
t.eq(vim.bo[two].buftype, "terminal", "terminal 2 is a real terminal")
term.toggle(2) -- hide

-- Re-toggling a number returns to the same shell rather than spawning another.
term.toggle(1)
t.eq(vim.api.nvim_get_current_buf(), one, "toggling a number reuses its shell")
term.toggle(1)

-- The float must be a float, and must not resolve to any bottom terminal.
local float = term.toggle_float()
t.ok(float ~= nil, "toggle_float returns a terminal")
local win = vim.api.nvim_get_current_win()
local cfg = vim.api.nvim_win_get_config(win)
t.eq(cfg.relative, "editor", "the floating terminal really floats")
t.ok(buf_of(float) ~= one and buf_of(float) ~= two,
  "the float is not one of the numbered bottom terminals")
t.eq(vim.bo[buf_of(float)].buftype, "terminal", "the float holds a real terminal")

-- <C-/> must be shadowed inside the float, or it would toggle the bottom one.
for _, lhs in ipairs({ "<C-/>", "<C-_>" }) do
  t.eq(vim.fn.maparg(lhs, "t", false, true).buffer, 1,
    lhs .. " is buffer-local inside the float")
end

-- Hiding then reopening keeps the same shell.
term.toggle_float()
t.ok(not vim.api.nvim_win_is_valid(win), "toggling the float hides it")
local again = term.toggle_float()
t.eq(buf_of(again), buf_of(float), "reopening the float reuses its shell")

t.done()
