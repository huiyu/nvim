-- A terminal buffer keeps one line per grid row, so text the terminal wrapped
-- -- Codex leaves a link longer than the pane for it to wrap -- was yanked with
-- newlines the program never printed. util.terminal.soft_wraps reads the shape
-- a wrap leaves; the TextYankPost handler in lua/autocmds.lua joins those rows.
local t = dofile("tests/helper.lua")
local a = vim.api
local terminal = require("util.terminal")

vim.o.columns = 180
vim.o.lines = 40
a.nvim_exec_autocmds("VimEnter", { modeline = false })
vim.wait(100, function() return false end)

-- A stand-in clipboard: the config yanks to "+ (clipboard=unnamedplus), and a
-- spec must not replace what the user has on the real one.
local fake = { ["+"] = { { "" }, "v" }, ["*"] = { { "" }, "v" } }
vim.g.clipboard = {
  name = "terminal-wrap-spec",
  copy = {
    ["+"] = function(lines, regtype) fake["+"] = { lines, regtype } end,
    ["*"] = function(lines, regtype) fake["*"] = { lines, regtype } end,
  },
  paste = {
    ["+"] = function() return fake["+"] end,
    ["*"] = function() return fake["*"] end,
  },
}
vim.g.loaded_clipboard_provider = nil
vim.cmd("runtime autoload/provider/clipboard.vim")
t.eq(vim.fn["provider#clipboard#Executable"](), "terminal-wrap-spec", "the stand-in clipboard provider is active")
t.eq(vim.o.clipboard, "unnamedplus", "yanks go to the system clipboard, as configured")

-- The shape of a wrap, on strings.
local full = ("a"):rep(10)
t.ok(terminal.soft_wraps(full, "b", 10), "a full row runs on into column 0")
t.ok(not terminal.soft_wraps(("a"):rep(9), "b", 10), "a row short of the edge ends where it ends")
t.ok(terminal.soft_wraps(("a"):rep(9), "路", 10), "a wide character the last cell cannot hold wraps a cell early")
t.ok(not terminal.soft_wraps(("a"):rep(8), "路", 10), "but not two cells early")
t.ok(not terminal.soft_wraps(full, "  b", 10), "an indented row is the program's own wrap (Codex, Claude)")
t.ok(not terminal.soft_wraps(full, "", 10), "a blank row ends the line")
t.ok(not terminal.soft_wraps(full, nil, 10), "the last row ends the line")
t.ok(terminal.soft_wraps(("a"):rep(9) .. " ", "b", 10), "one space on the last cell is a wrap at a word boundary")
t.ok(not terminal.soft_wraps(("a"):rep(8) .. "  ", "b", 10), "blanks painted to the edge are padding")
t.ok(not terminal.soft_wraps(("─"):rep(10), "❯ next", 10), "a full-width rule above a prompt is layout")
t.ok(not terminal.soft_wraps("│ > " .. ("a"):rep(5) .. "│", "╰" .. ("─"):rep(8) .. "╯", 10), "a frame is layout")
t.ok(not terminal.soft_wraps(full, "┌" .. ("─"):rep(9), 10), "a frame on the next row alone is layout too")
t.ok(not terminal.soft_wraps(("a"):rep(11), "b", 10), "a row wider than the grid predates a resize")
t.ok(not terminal.soft_wraps(full, "b", nil), "no grid width, no wrap")
-- Layout sized to the terminal on purpose, found by running real tools.
t.ok(not terminal.soft_wraps(("="):rep(10), "platform", 10), "pytest's separator above a line is a rule")
t.ok(not terminal.soft_wraps("x " .. ("="):rep(8), "y", 10), "a rule ending the row is one")
t.ok(not terminal.soft_wraps(full, "____ test", 10), "a rule leading the next row is one")
t.ok(terminal.soft_wraps(("a"):rep(8) .. "==", "b", 10), "base64 padding at the edge still wraps")
t.ok(not terminal.soft_wraps("1%|███| 3/3", "done", 11), "a tqdm bar sized to the width is layout")
t.ok(not terminal.soft_wraps(("a"):rep(9), "✅ passed", 10), "a status line led by an emoji starts its own line")
t.ok(not terminal.soft_wraps(("a"):rep(9), "⚠️ warn", 10), "an emoji with a variation selector counts as wide and as an emoji")
t.ok(not terminal.soft_wraps(("a"):rep(4) .. "[6/101]", "• Ran", 11), "tmux copy-mode's position indicator is layout")
local tqdm0 = "Up:   0%|          | 0/9 [00:00<?, ?it/s]"
t.ok(not terminal.soft_wraps(tqdm0, "Error: failed", vim.fn.strdisplaywidth(tqdm0)), "an empty tqdm bar is layout too")
local pytest_v = "tests/t.py::test_x FAILED [ 37%]"
t.ok(not terminal.soft_wraps(pytest_v, "tests/t.py::test_y", #pytest_v), "pytest -v's progress at the edge is layout")
-- A tree prefix has two box characters, not a bar: cargo tree's long paths wrap.
local tree = "└── crate v0.1.0 (/private/tmp/a-very-long-p"
t.ok(terminal.soft_wraps(tree, "ath/crates/crate)", vim.fn.strdisplaywidth(tree)), "a tree row still wraps")

-- The grid's width follows Nvim's pty sizing: the widest window showing it.
vim.cmd("tabnew")
local win = a.nvim_get_current_win()
local probe = a.nvim_create_buf(false, true)
a.nvim_win_set_buf(win, probe)
a.nvim_open_term(probe, {})
vim.cmd("vsplit")
local other = a.nvim_get_current_win()
a.nvim_win_set_width(win, 40)
local widths = {}
for _, w in ipairs({ win, other }) do
  local info = vim.fn.getwininfo(w)[1]
  widths[#widths + 1] = info.width - info.textoff
end
t.eq(terminal.grid_width(probe), math.max(unpack(widths)), "the grid is as wide as its widest window")
a.nvim_win_close(other, true)
t.eq(terminal.grid_width(a.nvim_create_buf(false, true)), nil, "a buffer no window shows has no grid width")

-- Stream text into a terminal `width` cells wide and let the terminal wrap it.
local function wrapped(width, text)
  a.nvim_set_current_win(win)
  local buf = a.nvim_create_buf(false, true)
  a.nvim_win_set_buf(win, buf)
  local channel = a.nvim_open_term(buf, {})
  a.nvim_win_set_width(win, width + vim.fn.getwininfo(win)[1].textoff)
  t.eq(terminal.grid_width(buf), width, "the fixture's grid is " .. width .. " cells")
  vim.wait(50, function() return false end) -- the pty follows the window on Nvim's refresh timer
  a.nvim_chan_send(channel, text)
  local last = text:match("[^\n]*$")
  t.ok(vim.wait(1000, function()
    return table.concat(a.nvim_buf_get_lines(buf, 0, -1, false)):find(last:sub(-6), 1, true) ~= nil
  end), "the fixture renders")
  a.nvim_win_set_cursor(win, { 1, 0 })
  return buf
end
vim.cmd("vsplit")
a.nvim_set_current_win(win)

local link = "https://example.com/aaaa/bbbb/cccc/dddd"
local line = "  (" .. link .. ")。 done"
local buf = wrapped(30, line .. "\r\n  indented next")
t.eq(a.nvim_buf_get_lines(buf, 0, 3, false), {
  "  (https://example.com/aaaa/bb", "bb/cccc/dddd)。 done", "  indented next",
}, "the terminal wraps the link mid-path")

fake["+"] = { { "stale" }, "v" }
vim.cmd("normal! ggVjy")
t.eq({ vim.fn.getreg('"'), vim.fn.getregtype('"') }, { line .. "\n", "V" }, "a linewise yank joins the wrapped rows")
t.eq(vim.fn.getreg("0"), line .. "\n", 'and "0')
-- An unnamed yank under unnamedplus reached the provider before TextYankPost,
-- split, and setreg("") never reaches it. Headless Nvim holds that first
-- write back, so the provider seeing the joined text here is the handler's
-- own write to "+ -- without it, the clipboard (and yanky's `p`) kept the
-- newline at the wrap.
t.eq(fake["+"], { { line, "" }, "V" }, "a plain yank puts the joined text on the system clipboard")
fake["+"] = { { "stale" }, "v" }
vim.cmd('normal! ggVj"+y')
t.eq(fake["+"], { { line, "" }, "V" }, 'and so does an explicit "+ yank')
vim.cmd("normal! gg0f(lvj$y")
t.eq(vim.fn.getreg('"'), link .. ")。 done\n", "a charwise selection through the end of the row joins too")

vim.cmd("normal! gg0f(lyi(")
t.eq(vim.fn.getreg('"'), link, "yi( takes the whole wrapped link")
vim.cmd("normal! gg0f(lvjf)hy")
t.eq(vim.fn.getreg('"'), link, "a charwise selection across the wrap takes it too")

vim.cmd('normal! ggVj"ay')
t.eq(vim.fn.getreg("a"), line .. "\n", "a named register is joined")
vim.fn.setreg("a", "before", "V")
vim.cmd('normal! ggVj"Ay')
t.eq(vim.fn.getreg("a"), "before\n  (https://example.com/aaaa/bb\nbb/cccc/dddd)。 done\n",
  "an appending yank is left alone rather than appended twice")
vim.fn.setreg("b", {}, "V")
vim.cmd('normal! ggVj"By')
t.eq(vim.fn.getreg("b"), "  (https://example.com/aaaa/bb\nbb/cccc/dddd)。 done\n",
  "an appending yank into an empty register holds its rows once")
vim.cmd("normal! gg0\22jly")
t.eq(vim.fn.getregtype('"'), "\0222", "a blockwise yank stays blockwise")
t.eq(vim.fn.getreg('"'), "  \nbb", "and is not joined")

vim.cmd("normal! ggV2jy")
t.eq(vim.fn.getreg('"'), line .. "\n  indented next\n", "a newline the program wrote survives next to a joined wrap")

-- The real `y` is yanky's: its ring records the joined text, not the rows.
vim.cmd("normal ggVjy")
t.eq(require("yanky.history").first().regcontents, line .. "\n", "the yank ring keeps the joined text")

-- Rows that fill the grid on purpose keep their newlines.
wrapped(10, ("x"):rep(10) .. "\r\n  indented")
vim.cmd("normal! ggVjy")
t.eq(vim.fn.getreg('"'), ("x"):rep(10) .. "\n  indented\n", "an indented row after a full one keeps its newline")
wrapped(10, "╭" .. ("─"):rep(8) .. "╮\r\n│ > hi   │")
vim.cmd("normal! ggVjy")
t.eq(vim.fn.getreg('"'), "╭" .. ("─"):rep(8) .. "╮\n│ > hi   │\n", "a frame keeps its rows")
local summary = ("="):rep(5) .. " 2 passed " .. ("="):rep(5)
wrapped(20, summary .. "\r\nuser@host:~$")
vim.cmd("normal! ggVjy")
t.eq(vim.fn.getreg('"'), summary .. "\nuser@host:~$\n", "a pytest summary keeps its newline")
wrapped(10, "pad" .. (" "):rep(7) .. "\r\nnext")
vim.cmd("normal! ggVjy")
t.ok(vim.fn.getreg('"'):find("\nnext\n$") ~= nil, "a row painted to the edge with blanks keeps its newline")
wrapped(10, ("a"):rep(9) .. "路径")
vim.cmd("normal! ggVjy")
t.eq(vim.fn.getreg('"'), ("a"):rep(9) .. "路径\n", "a wide character wrapped a cell early is joined")

-- An ordinary buffer's newlines are text, however long the lines are.
vim.cmd("enew")
a.nvim_buf_set_lines(0, 0, -1, false, { ("a"):rep(a.nvim_win_get_width(0)), "b" })
vim.cmd("normal! ggVjy")
t.eq(vim.fn.getreg('"'), ("a"):rep(a.nvim_win_get_width(0)) .. "\nb\n", "a file buffer's yank is untouched")

vim.cmd("tabclose!")
t.done()
