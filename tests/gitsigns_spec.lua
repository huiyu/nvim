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

---------------------------------------------------------------------------
-- <leader>gd: the same comparison in a split. gitsigns has no key that
-- closes it, and <leader>gq answered "No diff view in this tab" over it;
-- now <leader>gq and a second <leader>gd close it (util.diffsplit).
---------------------------------------------------------------------------
local notices = {}
local notify = vim.notify
vim.notify = function(msg, level) notices[#notices + 1] = { msg = tostring(msg), level = level } end
local function said(text)
  for _, n in ipairs(notices) do
    if n.msg:find(text, 1, true) then return n end
  end
end
local function press(keys) vim.api.nvim_feedkeys(vim.keycode(keys), "x", false) end
-- Notifications and noice's popups are floats in a tabpage; the split is what counts.
local function layout()
  return vim.tbl_filter(function(w) return vim.api.nvim_win_get_config(w).relative == "" end,
    vim.api.nvim_tabpage_list_wins(0))
end
local function revisions()
  return vim.tbl_filter(function(w)
    return vim.wo[w].diff and vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(w)):match("^gitsigns://") ~= nil
  end, layout())
end
local function revision_bufs()
  return vim.tbl_filter(function(b)
    return vim.api.nvim_buf_is_loaded(b) and vim.api.nvim_buf_get_name(b):match("^gitsigns://") ~= nil
  end, vim.api.nvim_list_bufs())
end
local file_win = vim.api.nvim_get_current_win()
local fdm = vim.wo.foldmethod
local function open(n)
  press("<leader>gd")
  return vim.wait(5000, function() return #revisions() == (n or 1) end, 20)
end
local function closed(what)
  t.eq(revisions(), {}, what .. ": no revision window is left")
  t.eq(layout(), { file_win }, what .. ": the file's window is the only split")
  t.eq({ vim.wo[file_win].diff, vim.wo[file_win].foldmethod, vim.wo[file_win].scrollbind },
    { false, fdm, false }, what .. ": its diff mode is off, folds and scrolling as before")
  t.eq(revision_bufs(), {}, what .. ": gitsigns wiped the revision buffer")
  t.eq(said("No diff view"), nil, what .. ": and no claim that there was no view")
end

t.ok(open(), "<leader>gd opens the index in a split")
t.eq(#layout(), 2, "beside the file's window")
t.eq(vim.wo[file_win].diff, true, "both in diff mode")

-- From the revision window, where the cursor was in the report.
vim.api.nvim_set_current_win(revisions()[1])
notices = {}
press("<leader>gq")
closed("<leader>gq from the index side")
t.eq(vim.api.nvim_get_current_win(), file_win, "the cursor is back in the file")

t.ok(open(), "<leader>gd opens it again")
notices = {}
press("<leader>gd")
closed("a second <leader>gd")

-- Unsaved edits on the index side (:w there stages them) are not thrown
-- away: nothing closes, and the notice says what to do.
t.ok(open(), "<leader>gd for the edit case")
local index_buf = vim.api.nvim_win_get_buf(revisions()[1])
vim.api.nvim_buf_set_lines(index_buf, 0, 1, false, { "edited in the index" })
notices = {}
press("<leader>gq")
local refused = said("unsaved changes")
t.ok(refused ~= nil and refused.level == vim.log.levels.WARN, "<leader>gq refuses over unsaved index edits")
t.eq(#revisions(), 1, "and leaves the split as it was")
t.eq(vim.wo[file_win].diff, true, "diff mode included")
t.eq(said("No diff view"), nil, "without saying there is no view")
vim.bo[index_buf].modified = false
notices = {}
press("<leader>gq")
closed("<leader>gq once the edit is dropped")

-- Closing the revision window ends diff mode in the file's through 'diffopt'
-- closeoff, Nvim's default. Without it, close() does that itself.
vim.opt.diffopt:remove("closeoff")
t.ok(open(), "<leader>gd without closeoff in 'diffopt'")
notices = {}
press("<leader>gq")
closed("<leader>gq without closeoff")
vim.opt.diffopt:append("closeoff")

-- Closed from the index side, the cursor goes back to the file, not to the
-- window left of the split that 'splitright' hands the space to.
vim.cmd("leftabove vnew")
local left_win = vim.api.nvim_get_current_win()
vim.api.nvim_set_current_win(file_win)
for _, key in ipairs({ "<leader>gq", "<leader>gd" }) do
  t.ok(open(), "<leader>gd with another window left of the file")
  vim.api.nvim_set_current_win(revisions()[1])
  press(key)
  t.eq(revisions(), {}, key .. " from the index side closes the split")
  t.eq(vim.api.nvim_get_current_win(), file_win, key .. " puts the cursor back in the file, not the window left of it")
end

-- In a buffer gitsigns has not attached to, diffthis can open nothing:
-- <leader>gd says so and leaves the split elsewhere in the tabpage alone.
local untracked = dir .. "/new.txt"
vim.fn.writefile({ "not in git yet" }, untracked)
for _, case in ipairs({ { "a scratch buffer", left_win }, { "an untracked file", "untracked" } }) do
  vim.api.nvim_set_current_win(file_win)
  t.ok(open(), "<leader>gd before trying it in " .. case[1])
  vim.api.nvim_set_current_win(left_win)
  if case[2] == "untracked" then
    vim.cmd.edit(vim.fn.fnameescape(untracked))
    -- gitsigns looks at it and stays detached; give it the time it would take.
    vim.wait(1000, function() return vim.b.gitsigns_status_dict ~= nil end, 20)
  end
  notices = {}
  press("<leader>gd")
  t.ok(said("gitsigns has not attached") ~= nil, "<leader>gd in " .. case[1] .. " says there is no diff")
  t.eq(#revisions(), 1, "and leaves b.txt's split open")
  t.eq(vim.wo[file_win].diff, true, "in diff mode")
  vim.api.nvim_set_current_win(file_win)
  press("<leader>gq")
end
vim.api.nvim_win_close(left_win, false)
vim.api.nvim_set_current_win(file_win)

-- Vim compares every diff window of a tabpage with every other. <leader>gd
-- in a second file's window moves the split there instead of adding one, so
-- the two files are never diffed with each other, nor left so afterwards.
local function diffed()
  return vim.tbl_filter(function(w) return vim.wo[w].diff end, layout())
end
vim.cmd("rightbelow vsplit " .. vim.fn.fnameescape(file))
local a_win = vim.api.nvim_get_current_win()
t.ok(vim.wait(5000, function() return #(gs.get_hunks(0) or {}) > 0 end, 50), "a.txt beside b.txt has changes too")
vim.api.nvim_set_current_win(file_win)
t.ok(open(), "<leader>gd in b.txt's window")
vim.api.nvim_set_current_win(a_win)
press("<leader>gd")
t.ok(vim.wait(5000, function()
  local r = revisions()
  return #r == 1 and vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(r[1])):match("a%.txt$") ~= nil
end, 20), "<leader>gd in a.txt's window moves the split to a.txt")
t.eq(vim.wo[file_win].diff, false, "b.txt's window leaves diff mode")
t.eq(#diffed(), 2, "a.txt and its index are all that is compared")
notices = {}
press("<leader>gq")
t.eq(diffed(), {}, "<leader>gq then leaves no window in diff mode")
t.eq(said("No diff view"), nil, "and finds the view to close")
vim.api.nvim_win_close(a_win, false)

-- A :split of the file's window inherits diff mode: three windows compare,
-- and closeoff, which only ends the last one left, would leave two comparing
-- with nothing to close them. <leader>gq ends diff mode in all of them.
vim.api.nvim_set_current_win(file_win)
t.ok(open(), "<leader>gd before splitting the file's window")
vim.cmd("split")
local copy = vim.api.nvim_get_current_win()
t.eq(#diffed(), 3, "the split joins the diff (what this case is about)")
notices = {}
press("<leader>gq")
t.eq(diffed(), {}, "<leader>gq leaves no window in diff mode")
t.eq(said("No diff view"), nil, "and finds the view to close")
vim.api.nvim_win_close(copy, false)
vim.api.nvim_set_current_win(file_win)

-- Only the current tabpage is touched. The same file's split in another
-- tabpage shares its revision buffer, which survives there.
t.ok(open(), "<leader>gd in the first tabpage")
local first_tab = vim.api.nvim_get_current_tabpage()
local function revisions_in(tab)
  return vim.tbl_filter(function(w)
    return vim.wo[w].diff and vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(w)):match("^gitsigns://") ~= nil
  end, vim.api.nvim_tabpage_list_wins(tab))
end
vim.cmd("tabnew " .. vim.fn.fnameescape(other))
t.ok(open(), "<leader>gd for the same file in a second tabpage")
notices = {}
press("<leader>gq")
t.eq(revisions(), {}, "<leader>gq closes the split in its own tabpage")
t.eq(#revisions_in(first_tab), 1, "and leaves the first tabpage's")
t.eq(vim.wo[revisions_in(first_tab)[1]].diff, true, "in diff mode")
t.ok(open(), "<leader>gd opens one again beside it")
press("<leader>gd")
t.eq(revisions(), {}, "a second <leader>gd closes it")
t.eq(#revisions_in(first_tab), 1, "a second <leader>gd closes only its own too")
notices = {}
press("<leader>gq")
t.ok(said("No diff view in this tab") ~= nil, "a tabpage without one says so while another has one")
vim.cmd.tabclose()
t.eq(vim.api.nvim_get_current_tabpage(), first_tab, "back in the first tabpage")
notices = {}
press("<leader>gq")
closed("<leader>gq in the first tabpage")

-- Diff mode is what makes it a view. With the file's window closed by hand,
-- closeoff ends it in the revision's: <leader>gq leaves that window alone.
t.ok(open(), "<leader>gd before closing the file's window")
local index_win = revisions()[1]
vim.api.nvim_win_close(file_win, false)
t.eq(vim.wo[index_win].diff, false, "closeoff ends diff mode in the window left")
notices = {}
press("<leader>gq")
t.ok(said("No diff view in this tab") ~= nil, "<leader>gq finds no view there")
t.eq(layout(), { index_win }, "and closes nothing")
vim.cmd.buffer(vim.fn.bufnr(other))
file_win = index_win
fdm = vim.wo.foldmethod
t.eq(revision_bufs(), {}, "showing the file again wipes the revision buffer")

-- A file with conflicts gets ours and theirs: two revision windows, both
-- closed by one key.
local merge = vim.fn.tempname()
vim.fn.mkdir(merge, "p")
local function mgit(...)
  return vim.system({ "git", "-C", merge, ... }, { text = true }):wait()
end
mgit("init", "-q", "-b", "main")
mgit("config", "user.email", "spec@example.com")
mgit("config", "user.name", "spec")
local conflicted = merge .. "/c.txt"
vim.fn.writefile({ "one", "two", "three" }, conflicted)
mgit("add", "c.txt")
mgit("commit", "-q", "-m", "base")
mgit("checkout", "-q", "-b", "theirs")
vim.fn.writefile({ "one", "THEIRS", "three" }, conflicted)
mgit("commit", "-qam", "theirs")
mgit("checkout", "-q", "main")
vim.fn.writefile({ "one", "OURS", "three" }, conflicted)
mgit("commit", "-qam", "ours")
t.ok(mgit("merge", "theirs").code ~= 0, "the merge stops on a conflict")
vim.cmd.edit(vim.fn.fnameescape(conflicted))
fdm = vim.wo.foldmethod
-- get_hunks answers nil until gitsigns has attached; diffthis before then
-- does nothing.
t.ok(vim.wait(5000, function() return gs.get_hunks(0) ~= nil end, 50), "gitsigns attaches to the conflicted file")
t.ok(open(2), "<leader>gd opens ours and theirs")
t.eq(#layout(), 3, "beside the file's window")
notices = {}
press("<leader>gq")
closed("<leader>gq over the three-way split")

-- <leader>gD can draw no inline view of a conflict and opens the same split;
-- a second <leader>gD closes it, as it would its inline view.
press("<leader>gD")
t.ok(vim.wait(5000, function() return #revisions() == 2 end, 20), "<leader>gD opens ours and theirs too")
notices = {}
press("<leader>gD")
closed("a second <leader>gD over the three-way split")

-- That split moves here like <leader>gd's: beside b.txt's, c.txt and b.txt
-- would be compared with each other too.
-- b.txt was hidden since; shown again, gitsigns rereads it, and diffthis
-- pressed in those few milliseconds fails gitsigns' own assertion. Wait for
-- its update (no user types that fast).
local updated = false
local on_update = vim.api.nvim_create_autocmd("User", {
  pattern = "GitSignsUpdate", callback = function() updated = true end,
})
vim.cmd("rightbelow vsplit " .. vim.fn.fnameescape(other))
vim.wait(2000, function() return updated end, 10)
vim.api.nvim_del_autocmd(on_update)
local b_win = vim.api.nvim_get_current_win()
t.ok(open(), "<leader>gd in b.txt beside the conflicted file")
vim.api.nvim_set_current_win(file_win)
press("<leader>gD")
t.ok(vim.wait(5000, function()
  local r = revisions()
  return #r == 2 and vim.iter(r):all(function(w)
    return vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(w)):match("c%.txt$") ~= nil
  end)
end, 20), "<leader>gD on the conflicted file moves the split to ours and theirs")
t.eq(vim.wo[b_win].diff, false, "b.txt leaves the comparison")
press("<leader>gD")
t.eq(#vim.tbl_filter(function(w) return vim.wo[w].diff end, layout()), 0, "a second <leader>gD ends it")
vim.api.nvim_win_close(b_win, false)
vim.api.nvim_set_current_win(file_win)

-- With the file's window closed by hand, the last of the two is the
-- tabpage's last split. Closing it would close the tabpage (here, the
-- second one; in the only one Nvim would refuse). It stays, out of diff mode.
vim.cmd("tabnew " .. vim.fn.fnameescape(conflicted))
local second_tab = vim.api.nvim_get_current_tabpage()
file_win = vim.api.nvim_get_current_win()
t.ok(open(2), "<leader>gd opens ours and theirs in a second tabpage")
vim.api.nvim_win_close(file_win, false)
-- A float in the tabpage (a notification; a headless run has none) is no split.
vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), false,
  { relative = "editor", row = 0, col = 0, width = 10, height = 1 })
notices = {}
press("<leader>gq")
t.eq(#layout(), 1, "<leader>gq closes one of the two")
t.ok(vim.api.nvim_tabpage_is_valid(second_tab) and #vim.api.nvim_list_tabpages() == 2, "and keeps the tabpage")
t.eq(vim.wo[layout()[1]].diff, false, "the other is out of diff mode")
t.eq(notices, {}, "without an error or a claim that there was no view")
vim.cmd.tabclose()
t.eq(revision_bufs(), {}, "closing that tabpage wipes the revision buffer")

vim.notify = notify
vim.fn.delete(merge, "rf")
vim.fn.delete(dir, "rf")
t.done()
