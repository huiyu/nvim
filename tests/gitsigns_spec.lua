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

---------------------------------------------------------------------------
-- ]h / [h, the inline diff (<leader>gD) and the statusline's change counts,
-- on a second file with one change, one deletion and one addition.
---------------------------------------------------------------------------
local lines = {}
for i = 1, 10 do lines[i] = "line " .. i end
local other = dir .. "/b.txt"
vim.fn.writefile(lines, other)
git("add", "b.txt")
git("commit", "-q", "-m", "b")
local changed = vim.deepcopy(lines)
changed[2] = "LINE 2"            -- changed
table.remove(changed, 5)          -- "line 5" removed
table.insert(changed, 8, "added") -- after "line 8" (now line 7)
vim.fn.writefile(changed, other)
vim.cmd.edit(vim.fn.fnameescape(other))
t.ok(vim.wait(5000, function() return hunks() == 3 end, 50), "b.txt has three hunks")

for lhs, direction in pairs({ ["]h"] = "next", ["[h"] = "prev" }) do
  local rhs = vim.fn.maparg(lhs, "n", false, true).rhs or ""
  t.ok(rhs:find("nav_hunk " .. direction, 1, true) ~= nil,
    lhs .. " goes through nav_hunk, not the deprecated " .. direction .. "_hunk (" .. rhs .. ")")
end
local function step(keys, line, what)
  vim.api.nvim_feedkeys(vim.keycode(keys), "x", false)
  t.ok(vim.wait(2000, function() return vim.fn.line(".") == line end, 20),
    ("%s %s (line %d, got %d)"):format(keys, what, line, vim.fn.line(".")))
end
vim.api.nvim_win_set_cursor(0, { 1, 0 })
step("]h", 2, "lands on the changed line")
step("]h", 4, "lands above the removed line")
step("]h", 8, "lands on the added line")
step("[h", 4, "steps back")
vim.api.nvim_win_set_cursor(0, { 1, 0 })
step("2]h", 4, "takes a count")

-- The lualine diff component reads gitsigns' own counts instead of running git.
local lualine = require("lazy.core.config").plugins["lualine.nvim"]
local opts = require("lazy.core.plugin").values(lualine, "opts", false)
local diff
for _, component in ipairs(opts.sections.lualine_b) do
  if type(component) == "table" and component[1] == "diff" then diff = component end
end
t.ok(diff and type(diff.source) == "function", "the statusline has a diff component with a source")
if diff then
  t.ok(vim.wait(2000, function()
    local status = vim.b.gitsigns_status_dict
    return status and status.added == 1 and status.changed == 1 and status.removed == 1
  end, 20), "gitsigns counts the buffer's changes")
  t.eq(diff.source(), { added = 1, modified = 1, removed = 1 }, "the source hands those counts to lualine")
  -- lualine renders into 'statusline' on its own refresh, so ask for one.
  local text = ""
  vim.wait(3000, function()
    require("lualine").refresh({ place = { "statusline" }, force = true })
    text = vim.api.nvim_eval_statusline(vim.o.statusline, {}).str
    return text:find("+1 ~1 -1", 1, true) ~= nil
  end, 50)
  t.ok(text:find("+1 ~1 -1", 1, true) ~= nil, "the statusline shows them: " .. vim.trim(text))
  vim.cmd.enew()
  t.eq(diff.source(), nil, "a buffer gitsigns does not track shows no counts")
  vim.cmd.buffer(vim.fn.bufnr(other))
end

-- <leader>gD draws the index's removed lines inline as virtual lines, in this
-- window; a second press closes it.
local function inline_lines()
  local found = {}
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(0, -1, 0, -1, { details = true })) do
    for _, virt in ipairs(mark[4].virt_lines or {}) do
      local text = {}
      for _, chunk in ipairs(virt) do text[#text + 1] = chunk[1] end
      found[#found + 1] = table.concat(text)
    end
  end
  return table.concat(found, "\n")
end
local wins = #vim.api.nvim_tabpage_list_wins(0)
t.eq(inline_lines():find("line 5", 1, true), nil, "no inline diff before <leader>gD")
vim.api.nvim_feedkeys(vim.keycode("<leader>gD"), "x", false)
t.ok(vim.wait(5000, function()
  local text = inline_lines()
  return text:find("line 5", 1, true) ~= nil and text:find("line 2", 1, true) ~= nil
end, 50), "<leader>gD shows the removed and the replaced lines inline")
t.eq(#vim.api.nvim_tabpage_list_wins(0), wins, "in the same window, no split")
t.eq(vim.wo.diff, false, "and without diff mode")
vim.api.nvim_feedkeys(vim.keycode("<leader>gD"), "x", false)
t.ok(vim.wait(5000, function() return inline_lines():find("line 5", 1, true) == nil end, 50),
  "a second <leader>gD closes the inline diff")

vim.fn.delete(dir, "rf")
t.done()
