-- Visual `<leader>gS` / `<leader>gr` act on the selected lines only. They were
-- `<Cmd>Gitsigns stage_hunk<CR>` mappings, which hand the command no range, so
-- a selection inside a hunk staged -- or discarded -- the whole hunk.
local t = dofile("tests/helper.lua")

local dir = vim.fn.tempname()
vim.fn.mkdir(dir, "p")
local function git(...)
  return vim.system({ "git", "-C", dir, ... }, { text = true }):wait()
end
git("init", "-q")
git("config", "user.email", "spec@example.com")
git("config", "user.name", "spec")
local file = dir .. "/a.txt"
vim.fn.writefile({ "one", "two", "three", "four", "five" }, file)
git("add", "a.txt")
git("commit", "-q", "-m", "init")
-- One hunk of four changed lines.
vim.fn.writefile({ "ONE", "TWO", "THREE", "FOUR", "five" }, file)

vim.cmd.edit(vim.fn.fnameescape(file))
local gs = require("gitsigns")
local function hunks()
  return #(gs.get_hunks(0) or {})
end
t.ok(vim.wait(5000, function() return hunks() == 1 end, 50), "the four changed lines form one hunk")

-- `motion` runs after `V`, so the cursor ends at the other end of the range.
local function visual(line, motion, keys)
  vim.api.nvim_win_set_cursor(0, { line, 0 })
  vim.api.nvim_feedkeys(vim.keycode("V" .. motion .. keys .. "<Esc>"), "x", false)
end

-- Selected bottom-up: the cursor (line 2) sits above the 'v' end (line 3).
visual(3, "k", "<leader>gS")
local cached = ""
t.ok(vim.wait(5000, function()
  cached = git("diff", "--cached", "--", "a.txt").stdout
  return cached:find("+TWO", 1, true) ~= nil and cached:find("+THREE", 1, true) ~= nil
end, 50), "visual <leader>gS stages both selected lines")
t.ok(not cached:find("+ONE", 1, true) and not cached:find("+FOUR", 1, true),
  "lines outside the selection stay unstaged")
t.ok(vim.wait(5000, function() return hunks() == 2 end, 50), "the staged lines split the hunk around them")

-- Lines 1-2: only ONE still differs from the index, TWO is staged.
visual(1, "j", "<leader>gr")
t.ok(vim.wait(5000, function()
  return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == "one"
end, 50), "visual <leader>gr resets the selected lines")
t.eq(vim.api.nvim_buf_get_lines(0, 1, 4, false), { "TWO", "THREE", "FOUR" },
  "lines outside the selection are kept")

vim.fn.delete(dir, "rf")
t.done()
