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

-- Ordinary files must not inherit the terminal-only localleader digit row.
-- The Ctrl-digit chords died inside an outer tmux (Ghostty encodes ctrl+digit
-- as legacy bytes under modifyOtherKeys), so they stay gone rather than linger
-- as a second, environment-dependent route.
for n = 1, 9 do
  t.eq(mapping("<localleader>" .. n), {}, "\\" .. n .. " is absent from ordinary buffers")
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

local prefix = vim.g.maplocalleader or "\\"
press(prefix .. "2")
local two = vim.api.nvim_get_current_buf()
t.eq(terminal_id(), 2, "terminal-local \\2 opens terminal 2")
t.ok(two ~= three, "numbered terminals have distinct buffers")
press(prefix .. "2")
t.eq(vim.api.nvim_get_current_buf(), two, "repeating \\2 keeps the selected terminal open")
press(prefix .. "3")
t.eq(vim.api.nvim_get_current_buf(), three, "\\3 reuses the original terminal 3")

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

t.done()
