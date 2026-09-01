-- Moving lines lives on <leader>m because Alt belongs to tmux here (#12), and
-- repeats on bare j/k so a multi-line move is not one <leader> press per line.
local t = dofile("tests/helper.lua")
local move = require("util.move")

local function buffer(lines)
  local b = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(b)
  vim.api.nvim_buf_set_lines(b, 0, -1, false, lines)
  return b
end
local function body() return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "") end

---Drive the repeat loop with a fixed key sequence.
local function feed(keys)
  local i = 0
  move._getchar = function()
    i = i + 1
    return keys[i] or "\27" -- ESC ends the run
  end
end

-- One move, no repeats.
buffer({ "a", "b", "c", "d" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
feed({})
move.run("down")
t.eq(body(), "bacd", "one move swaps the line with the one below")

-- Repeating on bare j: three presses walk it three lines down.
buffer({ "a", "b", "c", "d" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
feed({ "j", "j" })
move.run("down")
t.eq(body(), "bcda", "bare j keeps moving without another <leader>")

-- k reverses inside the same run.
buffer({ "a", "b", "c", "d" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
feed({ "j", "k" })
move.run("down")
t.eq(body(), "bacd", "k moves back up in the same run")

-- A key that is not j/k ends the run and is handed back, not swallowed.
buffer({ "a", "b", "c" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
local handed_back = nil
feed({ "w" })
local real_feedkeys = vim.api.nvim_feedkeys
vim.api.nvim_feedkeys = function(keys, ...) handed_back = keys return real_feedkeys(keys, ...) end
move.run("down")
vim.api.nvim_feedkeys = real_feedkeys
t.eq(handed_back, "w", "a non-move key is fed back rather than eaten")

-- A count applies to the first move only; repeats are one line each.
buffer({ "a", "b", "c", "d", "e" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
feed({})
vim.cmd("normal! 2")  -- no-op; v:count1 is read inside run()
move.run("down")
t.ok(body():find("a") ~= nil, "the line is still present after a counted move")

-- Hitting the last line reports instead of raising.
buffer({ "a", "b" })
vim.api.nvim_win_set_cursor(0, { 2, 0 })
feed({})
local ok = pcall(move.run, "down")
t.ok(ok, "moving past the last line does not raise")

-- Horizontal is the same idea applied to indentation: also something done
-- several times in a row, also driven by the hjkl vocabulary.
local function indented(lines)
  local b = buffer(lines)
  vim.bo[b].shiftwidth = 2
  vim.bo[b].expandtab = true
  return b
end

indented({ "a", "b" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
feed({})
move.run("right")
t.eq(vim.api.nvim_buf_get_lines(0, 0, 1, false)[1], "  a", ",l indents once")

indented({ "a", "b" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
feed({ "l", "l" })
move.run("right")
t.eq(vim.api.nvim_buf_get_lines(0, 0, 1, false)[1], "      a", "bare l keeps indenting")

indented({ "      a", "b" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
feed({ "h" })
move.run("left")
t.eq(vim.api.nvim_buf_get_lines(0, 0, 1, false)[1], "  a", "h dedents, and repeats")

-- Directions mix freely inside one run.
indented({ "a", "b", "c" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
feed({ "l" })
move.run("down")
local after = vim.api.nvim_buf_get_lines(0, 0, -1, false)
t.eq(table.concat(after, "|"), "b|  a|c", "a run can move then indent")

move._getchar = vim.fn.getcharstr
t.done()
