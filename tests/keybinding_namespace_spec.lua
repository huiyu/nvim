local t = dofile("tests/helper.lua")

local function mapping(lhs, mode)
  return vim.fn.maparg(lhs, mode or "n", false, true)
end

-- Buffer cycling has one fast pair and one discoverable bracket pair. Tab must
-- remain native so legacy terminals can still send <C-I> for jumplist-forward.
t.eq(mapping("<Tab>"), {}, "Tab is not repurposed for buffer cycling")
t.eq(mapping("<S-Tab>"), {}, "Shift-Tab is not repurposed for buffer cycling")
t.ok(mapping("<S-h>").desc == "Prev buffer", "Shift-H cycles to the previous buffer")
t.ok(mapping("<S-l>").desc == "Next buffer", "Shift-L cycles to the next buffer")
t.ok(mapping("[b").desc == "Prev buffer", "[b keeps bracket navigation")
t.ok(mapping("]b").desc == "Next buffer", "]b keeps bracket navigation")

-- Todo search belongs to the location namespace exactly once. Bracket keys
-- remain the sequential navigation form; the old Diagnostics aliases stay gone.
t.ok(mapping(";t").desc == "Todos", ";t finds todos")
t.ok(mapping(";T").desc == "Todo/Fix/Fixme", ";T finds actionable todos")
t.eq(mapping("<leader>xt"), {}, "Diagnostics no longer duplicates Todo search")
t.eq(mapping("<leader>xT"), {}, "Diagnostics no longer duplicates filtered Todo search")
t.ok(mapping("[t").desc == "Prev todo", "[t keeps previous-Todo navigation")
t.ok(mapping("]t").desc == "Next todo", "]t keeps next-Todo navigation")

-- Changed hunks are a place to be, so the repository-wide picker is on `;`
-- (Normal only) while ]h/[h keep stepping from the cursor.
t.ok(mapping(";c").desc == "Git hunks", ";c lists the repository's hunks")
for _, mode in ipairs({ "x", "o", "i", "t" }) do
  t.eq(mapping(";c", mode), {}, ";c is Normal-mode only (" .. mode .. ")")
end

-- The path keys take a Visual range as well; the inline diff and the hidden
-- buffer sweep are Normal-only. None of them reaches Insert, terminal input
-- or operator-pending mode.
for lhs, modes in pairs({
  ["<leader>yl"] = { n = true, x = true },
  ["<leader>yg"] = { n = true, x = true },
  ["<leader>gD"] = { n = true },
  ["<leader>bh"] = { n = true },
  ["<leader>ax"] = { n = true },
  -- The chat on the right: the pickers take a Visual selection along, toggle
  -- and focus take none.
  ["<leader>an"] = { n = true, x = true },
  ["<leader>al"] = { n = true, x = true },
  ["<leader>ac"] = { n = true },
  ["<leader>af"] = { n = true },
  -- The prompt editor seeds from a Visual selection.
  ["<leader>ai"] = { n = true, x = true },
  -- CodeCompanion: inline edits take a Visual range; saved chats have nothing
  -- to take. The per-kind chat keys and the action palette's key are gone:
  -- <leader>an starts a chat of any kind, and the palette stays
  -- :CodeCompanionActions.
  ["<leader>ag"] = {},
  ["<leader>aG"] = {},
  ["<leader>ah"] = {},
  ["<leader>aH"] = {},
  ["<leader>ae"] = { n = true, x = true },
  ["<leader>ap"] = {},
  ["<leader>ao"] = { n = true },
  -- Review rounds: opening the review and starting a round take no selection.
  ["<leader>av"] = { n = true },
  ["<leader>aV"] = { n = true },
}) do
  for _, mode in ipairs({ "n", "x", "o", "i", "t" }) do
    t.eq(next(mapping(lhs, mode)) ~= nil, modes[mode] == true,
      ("%s is %smapped in %s"):format(lhs, modes[mode] and "" or "not ", mode))
  end
end
-- <leader>an and <leader>al are leaves: a longer mapping would make them wait
-- out 'timeoutlen'.
for _, mode in ipairs({ "n", "x" }) do
  local longer = {}
  for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do
    local keys = vim.fn.keytrans(vim.keycode(m.lhs))
    if keys:find("^<Space>a[nl].") then longer[#longer + 1] = keys end
  end
  t.eq(longer, {}, "no <leader>an* / <leader>al* mapping in " .. mode .. " mode")
end

-- Terminal mode keeps its window keys. <C-q> used to close the terminal and
-- was removed deliberately: `exit`, <C-/> and :bd! already cover it, so the
-- chord only offered a way to force-delete a buffer. <C-c> must stay unmapped
-- in Terminal mode, because it is SIGINT and shadowing it would make a runaway
-- process unkillable.
for _, lhs in ipairs({ "<C-h>", "<C-l>", "<C-S-l>" }) do
  t.ok(next(mapping(lhs, "t")) ~= nil, "terminal-mode " .. lhs .. " is unchanged")
end
t.eq(mapping("<C-q>", "t"), {}, "close-terminal chord stays removed")
t.eq(mapping("<C-c>", "t"), {}, "terminal-mode <C-c> stays unmapped (SIGINT)")

-- Ordinary files must not inherit the terminal-only localleader digit row.
-- The Ctrl-digit chords died inside an outer tmux (Ghostty encodes ctrl+digit
-- as legacy bytes under modifyOtherKeys), so they stay gone rather than linger
-- as a second, environment-dependent route.
for n = 1, 9 do
  t.eq(mapping("<localleader>" .. n), {}, "," .. n .. " is absent from ordinary buffers")
  t.eq(mapping("<C-" .. n .. ">"), {}, "<C-" .. n .. "> is no longer a terminal key")
  t.eq(mapping("<C-" .. n .. ">", "t"), {}, "<C-" .. n .. "> is gone from terminal mode too")
end

-- Exercise the real key paths after scheduled mapping loaders. Terminal-local
-- maps must stay absent from a file even while a terminal remains visible.
vim.api.nvim_exec_autocmds("VimEnter", { modeline = false })
vim.wait(100, function() return false end, 10)
local editor_win = vim.api.nvim_get_current_win()
local editor_buf = vim.api.nvim_get_current_buf()
local function press(keys)
  vim.api.nvim_feedkeys(vim.keycode(keys), "xt", false)
end
local function terminal_id()
  local info = vim.b.snacks_terminal
  return info and info.id
end

-- ;c opens Snacks' git_diff source, whose <C-x> restores (discards) a hunk
-- (tests/panel_keys_spec.lua pins the key).
-- Snacks closes a picker that finds nothing, and this checkout may be clean
-- (CI always is), so the key runs from a scratch repository with one hunk.
local scratch = vim.fn.tempname()
vim.fn.mkdir(scratch, "p")
local function git(...)
  return vim.system({ "git", "-C", scratch, "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
    "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null", ... }):wait()
end
git("init", "-q")
vim.fn.writefile({ "one" }, scratch .. "/hunk.txt")
git("add", "hunk.txt")
git("commit", "-qm", "fixture")
vim.fn.writefile({ "two" }, scratch .. "/hunk.txt")
local spec_cwd = vim.fn.chdir(scratch)
mapping(";c").callback()
local hunks
vim.wait(2000, function()
  hunks = Snacks.picker.get({ source = "git_diff" })[1]
  return hunks ~= nil
end, 10)
t.ok(hunks ~= nil, ";c opens the git_diff picker")
if hunks then hunks:close() end
vim.fn.chdir(spec_cwd)
vim.api.nvim_set_current_win(editor_win)

press("3<C-/>")
local three = vim.api.nvim_get_current_buf()
t.eq(terminal_id(), 3, "3<C-/> from a file opens terminal 3")
t.eq(vim.bo.buftype, "terminal", "the numbered shortcut opens a real terminal")
for n = 1, 9 do
  local key = "<localleader>" .. n
  t.eq(mapping(key).buffer, 1, key .. " is buffer-local in a terminal")
  t.eq(mapping(key).desc, "Terminal " .. n, key .. " has a discoverable description")
  t.eq(mapping(key, "t"), {}, key .. " does not intercept shell input")
end

local prefix = vim.g.maplocalleader
press(prefix .. "2")
local two = vim.api.nvim_get_current_buf()
t.eq(terminal_id(), 2, "terminal-local ,2 opens terminal 2")
t.ok(two ~= three, "numbered terminals have distinct buffers")
press(prefix .. "2")
t.eq(vim.api.nvim_get_current_buf(), two, "repeating ,2 keeps the selected terminal open")
press(prefix .. "3")
t.eq(vim.api.nvim_get_current_buf(), three, ",3 reuses the original terminal 3")

vim.api.nvim_set_current_win(editor_win)
t.eq(vim.api.nvim_get_current_buf(), editor_buf, "switching terminals preserved the editor buffer")
t.ok(vim.fn.bufwinid(three) ~= -1, "terminal 3 remains visible beside the file")
for _, ft in ipairs({ "lua", "markdown", "text" }) do
  vim.bo.filetype = ft
  for n = 1, 9 do
    t.eq(mapping("<localleader>" .. n), {}, ft .. ": terminal digits do not leak into file mappings")
  end
end

-- TermOpen also covers plain :terminal and the native agents, independently of
-- whichever filetype a plugin later assigns to the terminal buffer.
vim.cmd.enew()
local job = vim.fn.jobstart({ "sh", "-c", "cat" }, { term = true })
t.eq(mapping("<localleader>9").buffer, 1, "plain terminals also receive the local digit row")
vim.fn.jobstop(job)
for _, buf in ipairs({ two, three }) do
  local id = vim.b[buf].terminal_job_id
  if id then vim.fn.jobstop(id) end
end

-- [B/]B are the first and last buffer of the bar, in the order [b/]b cycle
-- through, and moving a buffer along the bar is <leader>b< / <leader>b>.
require("lazy").load({ plugins = { "bufferline.nvim" } })
vim.api.nvim_set_current_win(editor_win)
local ends_dir = vim.fn.tempname()
vim.fn.mkdir(ends_dir, "p")
local by_name = {}
for _, name in ipairs({ "a", "b", "c" }) do
  vim.cmd.edit(vim.fn.fnameescape(ends_dir .. "/" .. name .. ".txt"))
  by_name[name] = vim.api.nvim_get_current_buf()
end
-- Render the bar, which is what fills bufferline's list; nothing redraws headless.
local function render() vim.api.nvim_eval_statusline(vim.o.tabline, { use_tabline = true }) end
render()
-- c moves to the front, so the bar's order is no longer the buffer numbers'.
t.eq(vim.api.nvim_get_current_buf(), by_name.c, "c is current")
for _ = 1, 2 do
  press("<leader>b<")
  render()
end
local first, last = mapping("[B"), mapping("]B")
t.ok(first.desc == "First buffer" and last.desc == "Last buffer", "[B/]B go to the first/last buffer")
vim.api.nvim_set_current_buf(by_name.a)
last.callback()
local bar = vim.tbl_map(function(c) return c.id end, require("bufferline.state").components)
t.eq(vim.api.nvim_get_current_buf(), bar[#bar], "]B goes to the bar's last buffer")
first.callback()
t.eq(vim.api.nvim_get_current_buf(), by_name.c, "[B goes to the buffer moved to the front, not the lowest number")
t.ok(mapping("<leader>b>").desc == "Move buffer right", "<leader>b> moves the buffer right")

t.done()
