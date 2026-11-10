local t = dofile("tests/helper.lua")
local a = vim.api

vim.o.columns = 180
vim.o.lines = 40
vim.api.nvim_exec_autocmds("VimEnter", { modeline = false })
vim.wait(100, function() return false end)

local opened = {}
vim.ui.open = function(url) opened[#opened + 1] = url end

local function fixture(lines, terminal)
  local buf = a.nvim_create_buf(false, true)
  a.nvim_set_current_buf(buf)
  if terminal then
    -- gx opens a file beside a scratch fixture, so the checks above leave a
    -- stack of editor windows and this one can be down to a row. A terminal
    -- shorter than the fixture holds only its last rows, and the render wait
    -- below never sees the line it looks for.
    if a.nvim_win_get_height(0) < #lines then a.nvim_win_set_height(0, #lines) end
    local channel = a.nvim_open_term(buf, {})
    a.nvim_chan_send(channel, table.concat(lines, "\r\n"))
    t.ok(vim.wait(1000, function()
      return a.nvim_buf_get_lines(buf, #lines - 1, #lines, false)[1] == lines[#lines]
    end), "terminal fixture renders")
  else
    a.nvim_buf_set_lines(buf, 0, -1, false, lines)
  end
  return buf
end

local function check(row, col, want, label)
  opened = {}
  a.nvim_win_set_cursor(0, { row, col })
  vim.cmd("normal gx")
  t.eq(opened, { want }, label)
end

-- The CLI wraps the link inside a table cell, before the terminal's right
-- edge. The next cell still has content on the URL's first physical line.
fixture({
  "  ───────────────────────────────────  ─────────────────────  ────────────────",
  "  #799 (https://github.com/kabo-        iOS readiness 空基线校验  Huimin (@HathyHuimin)",
  "  sh/kabo/pull/799)",
  "  ───────────────────────────────────  ─────────────────────  ────────────────",
  "  #730 (https://github.com/kabo-        release 输入注入修复      Jeff Yu (@huiyu)",
  "  sh/kabo/pull/730)",
}, true)
for _, pos in ipairs({ { 2, 12 }, { 2, 2 }, { 3, 3 }, { 3, 15 } }) do
  check(pos[1], pos[2], "https://github.com/kabo-sh/kabo/pull/799",
    "gx opens the complete table URL from either line or its label")
end
check(5, 12, "https://github.com/kabo-sh/kabo/pull/730", "the next table row opens its own URL")

fixture({
  "│ 中文 │ #731 (https://github.com/kabo- │ 中文列 │",
  "│      │ sh/kabo/                      │        │",
  "│      │ pull/731)                     │        │",
}, true)
check(1, 25, "https://github.com/kabo-sh/kabo/pull/731", "table columns use display width after CJK")
check(3, 13, "https://github.com/kabo-sh/kabo/pull/731", "a URL may span more than two rows")

fixture({
  "  <https://example.com/path/",
  "  more?q=a%20b&x=1#section>",
}, true)
check(2, 6, "https://example.com/path/more?q=a%20b&x=1#section", "wrapped autolink preserves query and fragment")

fixture({
  "  (#799) (https://example.com/one)",
  "  unrelated/path)",
  "  (https://example.com/two)",
}, true)
check(1, 13, "https://example.com/one", "a complete URL never absorbs the following row")

fixture({
  "  (https://example.com/one-  other column",
  "                           unrelated/path)",
}, true)
check(1, 13, "https://example.com/one-", "a neighboring column is never appended")

fixture({
  "  (https://example.com/one-",
  "  ────────────────────────",
  "  unrelated/path)",
}, true)
check(1, 13, "https://example.com/one-", "a table separator ends continuation lookup")

fixture({
  "  (https://example.com/one-",
  "  (https://example.com/two)",
}, true)
check(1, 13, "https://example.com/one-", "the next URL is never appended")

fixture({
  "[entry](https://example.com/a_(b)?q=1&x=2#part).",
  "https://example.com/first and https://example.com/second",
  "  (https://example.com/one-",
  "  unrelated/path)",
}, false)
check(1, 15, "https://example.com/a_(b)?q=1&x=2#part", "Markdown keeps balanced URL parentheses and strips its wrapper")
check(1, 0, "https://example.com/a_(b)?q=1&x=2#part", "the label and URL resolve identically")
check(2, 0, "https://example.com/first", "nearest URL on the left")
check(2, 29, "https://example.com/second", "nearest URL on the right")
check(3, 13, "https://example.com/one-", "ordinary source lines are not joined as terminal output")

fixture({ "https://例子.测试/中文?q=你好#位置" }, false)
check(1, 8, "https://例子.测试/中文?q=你好#位置", "Unicode URL text survives without the old cfile shortcut")
fixture({
  "  (https://example.com/路",
  "  径?q=你好)",
}, true)
check(1, 13, "https://example.com/路径?q=你好", "wrapped Unicode paths and queries are preserved")
check(2, 2, "https://example.com/路径?q=你好", "a Unicode continuation resolves to the same URL")

-- CJK prose runs straight into a link without a space. Codex renders links as
-- `label (url)`; fullwidth punctuation after the wrapper, or after a bare URL,
-- is never part of it, while Unicode URL text still is.
local function col_of(line, needle) return line:find(needle, 1, true) - 1 end
local codex = "  打开 本地预览 (http://localhost:3105/agent)，点击侧栏 Profile。"
fixture({ codex }, true)
for _, needle in ipairs({ "本地预览", "3105", ")", "点击" }) do
  check(1, col_of(codex, needle), "http://localhost:3105/agent",
    "fullwidth punctuation after a parenthesized URL is left out")
end
local prose = "  详情见“https://example.com/docs”，以及 https://example.com/other、https://例子.测试/中文?q=你好#位置。"
fixture({
  prose,
  "  打开 http://localhost:3105/agent，点击侧栏 Profile。",
  "  （https://example.com/full），然后",
  "  (https://example.com/路",
  "  径?q=你好)，然后",
}, true)
check(1, col_of(prose, "docs"), "https://example.com/docs", "curly quotes end a URL")
check(1, col_of(prose, "other"), "https://example.com/other", "an ideographic comma ends a URL")
check(1, col_of(prose, "例子"), "https://例子.测试/中文?q=你好#位置", "Unicode URL text runs up to the fullwidth period")
check(2, 20, "http://localhost:3105/agent", "a bare URL ends at the fullwidth comma")
check(3, 8, "https://example.com/full", "fullwidth parentheses are not part of the URL")
check(5, 2, "https://example.com/路径?q=你好", "a wrapped URL still joins before the fullwidth comma")

local file = vim.fn.tempname() .. ".txt"
local buf = fixture({ "no URL here" }, false)
a.nvim_buf_set_name(buf, file)
vim.bo[buf].buftype = ""
check(1, 0, file, "without a URL gx still opens the current file")

local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
root = vim.uv.fs_realpath(root)
local report = root .. "/report.md"
local spaced = root .. "/中文 report (draft).md"
vim.fn.writefile({ "# Report" }, report)
vim.fn.writefile({ "# Draft" }, spaced)
vim.fn.writefile({ "read me" }, root .. "/README")

local function check_file(row, col, want, label)
  opened = {}
  a.nvim_win_set_cursor(0, { row, col })
  vim.cmd("normal gx")
  t.eq(a.nvim_buf_get_name(0), want, label)
  t.eq(opened, {}, "referenced files open in Nvim, without a system application")
end

-- The screenshot's /tmp/ prefix is a real directory. Only the joined file
-- should open; never open the directory when the cursor is on the first row.
local term = fixture({ "  完整报告 (" .. root .. "/", "  report.md)" }, true)
local term_win = a.nvim_get_current_win()
for _, pos in ipairs({ { 1, 2 }, { 2, 5 } }) do
  a.nvim_set_current_win(term_win)
  check_file(pos[1], pos[2], report, "either row of a wrapped terminal path opens the full file")
  t.eq(a.nvim_win_get_buf(term_win), term, "the terminal stays visible in its original window")
end

fixture({ '"' .. spaced .. '"' }, false)
check_file(1, 4, spaced, "quoted file paths preserve spaces, Unicode and parentheses")
for _, name in ipairs({ "report#draft.md", "report%done.md", "report$GX_FILE_TEST.md", "report  draft.md", "report|draft.md" }) do
  local path = root .. "/" .. name
  vim.fn.writefile({ "# Literal filename" }, path)
  fixture({ '"' .. path .. '"' }, false)
  check_file(1, 4, path, "quoted filenames stay literal: " .. name)
end
fixture({ "[report](" .. report .. ")" }, false)
check_file(1, 0, report, "a Markdown file link opens from its label")

local relative = fixture({ "./report.md" }, false)
a.nvim_buf_set_name(relative, root .. "/notes.txt")
vim.bo[relative].buftype = ""
check_file(1, 4, report, "relative references resolve beside an ordinary source file")
fixture({ "report.md" }, true)
vim.b.snacks_terminal = { cwd = root }
check_file(1, 3, report, "relative terminal references use the terminal's recorded cwd")
fixture({ "README" }, true)
vim.b.snacks_terminal = { cwd = root }
check_file(1, 2, root .. "/README", "existing extensionless files are recognized")
fixture({ "~/report.md" }, true)
local homedir = vim.uv.os_homedir
vim.uv.os_homedir = function() return root end
check_file(1, 3, report, "tilde paths expand without changing the working directory")
vim.uv.os_homedir = homedir

local mixed = report .. " https://example.com/report.md"
fixture({ mixed }, false)
check(1, #report + 5, "https://example.com/report.md", "a URL stays external when a file is on the same row")
check_file(1, 3, report, "the nearest file wins over a URL on the same row")

for _, lines in ipairs({
  { "  (" .. root .. "/", "  missing.md)" },
  { "  (" .. root .. "/", "                        report.md)" },
  { "  (" .. root .. "/", "  ─────────────────", "  report.md)" },
  { "no link or file here" },
}) do
  local missing = fixture(lines, true)
  check(1, 3, nil, "an unresolved terminal path never opens a directory or term URI")
  t.eq(a.nvim_get_current_buf(), missing, "an unresolved target leaves terminal focus unchanged")
end

fixture({ "  (" .. root .. "/", "  report.md)" }, false)
check(1, 3, nil, "ordinary source newlines are not joined into file paths")

-- Codex prints a link longer than the pane as one line and leaves the wrap to
-- the terminal (tmux's `capture-pane -J` joins it back), so the rest resumes in
-- column 0 whatever column the link started in. These fixtures stream text
-- into a terminal of a known width and let the terminal wrap it.
vim.cmd("tabnew")
local wrap_win = a.nvim_get_current_win()
vim.cmd("vsplit") -- the editor gx opens files in
local function wrapped(width, text)
  a.nvim_set_current_win(wrap_win)
  local term_buf = a.nvim_create_buf(false, true)
  a.nvim_win_set_buf(wrap_win, term_buf)
  local channel = a.nvim_open_term(term_buf, {})
  -- Whatever columns TermOpen leaves on, the grid itself is `width` cells.
  a.nvim_win_set_width(wrap_win, width + vim.fn.getwininfo(wrap_win)[1].textoff)
  t.eq(require("util.terminal").grid_width(term_buf), width, "the wrap fixture's grid is " .. width .. " cells")
  vim.wait(50, function() return false end) -- the pty follows the window on Nvim's refresh timer
  a.nvim_chan_send(channel, text)
  local last = text:match("[^\n]*$")
  t.ok(vim.wait(1000, function()
    return table.concat(a.nvim_buf_get_lines(term_buf, 0, -1, false)):find(last:sub(-6), 1, true) ~= nil
  end), "the wrap fixture renders")
  return term_buf
end

local guide = "https://github.com/kabo-sh/creator-skills/blob/2fb33b9147b5ca630a6903b9b36e4d0e20c2fb1e"
  .. "/creator-skills/runtime/creator-remake-web/references/atoms-and-edits.md#what-each-step-takes"
local screenshot = wrapped(90, "• 直接读这份：原子能力完整手册 · atoms-and-edits.md\r\n  (" .. guide .. ")。")
t.eq(a.nvim_buf_get_lines(screenshot, 1, 4, false), {
  "  (https://github.com/kabo-sh/creator-skills/blob/2fb33b9147b5ca630a6903b9b36e4d0e20c2fb1e",
  "/creator-skills/runtime/creator-remake-web/references/atoms-and-edits.md#what-each-step-ta",
  "kes)。",
}, "the terminal wraps the link exactly as Codex's pane showed it")
for _, pos in ipairs({ { 2, 3 }, { 2, 60 }, { 3, 0 }, { 3, 89 }, { 4, 0 }, { 4, 4 } }) do
  check(pos[1], pos[2], guide, "a link the terminal wrapped opens whole from any of its rows")
end

local long = "https://example.com/" .. ("segment/"):rep(8) .. "end?q=1"
wrapped(60, "  see " .. long .. " and more\r\nnext line")
for _, pos in ipairs({ { 1, 8 }, { 2, 0 }, { 2, 20 } }) do
  check(pos[1], pos[2], long, "a bare link the terminal wrapped opens whole")
end

-- 29 cells, then a wide character the last cell cannot hold: it wraps from
-- the last-but-one cell, which still counts as a full row.
wrapped(30, "https://example.com/abcdefghi路径?q=1")
check(2, 0, "https://example.com/abcdefghi路径?q=1", "a wide character wrapped early still continues the link")

-- A link that ends short of the edge, or a row Codex wrapped itself (it
-- indents the next one), has a newline the program wrote.
wrapped(60, "https://example.com/a\r\nb/c")
check(2, 0, nil, "a row that ends short of the edge does not continue")
check(1, 3, "https://example.com/a", "a link that ends short of the edge stays as written")
local edge = "  https://example.com/" .. ("x"):rep(60 - 22)
wrapped(60, edge .. "\r\n  indented/tail")
check(1, 5, edge:sub(3), "an indented next row is never appended to a full row")
wrapped(60, edge .. "https://example.com/next and more")
check(1, 5, edge:sub(3), "a link starting in column 0 is the next link, not a wrapped tail")
check(2, 3, "https://example.com/next", "the next link opens on its own")

-- The wrap can cut the scheme, so neither row holds "https://".
local filler = ("x"):rep(26) .. " "
wrapped(30, filler .. "htt" .. "ps://example.com/abc/def and more")
check(1, 28, "https://example.com/abc/def", "a scheme cut by the wrap opens from its first part")
check(2, 0, "https://example.com/abc/def", "and from the rest")
wrapped(30, ("x"):rep(22) .. " " .. "https:/" .. "/example.com/abc/def")
check(2, 3, "https://example.com/abc/def", "a cut between the slashes too")
wrapped(30, ("x"):rep(18) .. " 中文见" .. "htt" .. "ps://example.com/abc")
check(2, 1, "https://example.com/abc", "CJK prose running into the cut scheme still finds it")
wrapped(30, ("QUJD"):rep(7) .. "Xh" .. "ello/world")
check(1, 29, nil, "a word ending in a scheme letter at the edge is no link")

-- A signed URL can run past 16 rows; wrapped rows do not count against that.
local signed = "https://example.com/object?sig=" .. ("s"):rep(400)
wrapped(20, signed .. " expires")
local signed_rows = math.ceil(#signed / 20)
t.ok(signed_rows > 16, "the signed URL takes more than 16 rows")
for _, r in ipairs({ 1, 10, signed_rows }) do
  check(r, 0, signed, "a link longer than 16 rows opens whole from row " .. r)
end

-- base64 padding can be all a wrapped row holds; it is not a table rule.
local padded = "https://example.com/?s=" .. ("a"):rep(37) .. "=="
wrapped(30, padded .. "\r\nnext")
check(1, 3, padded, "a tail of '==' after the wrap stays in the link")
check(3, 0, padded, "and opens it from that row")

-- Once a link has wrapped, a cell below its original column is not its tail.
wrapped(20, "  (https://e.com/aaa" .. "bbbbbbbbbb\r\n  x)")
check(1, 4, "https://e.com/aaabbbbbbbbbb", "a wrapped link never continues down a table column")

-- Its end out of reach, a link opens nothing rather than a truncated URL.
local huge = "https://e.com/?s=" .. ("a"):rep(20 * 258 - 17)
wrapped(20, huge)
check(1, 0, nil, "a link wrapped past the cap opens nothing")

-- A long wrapped line near the link costs about one look per row, not one per
-- pair of rows: next to a 16 KB base64 or minified line gx took seconds.
local term_mod = require("util.terminal")
local soft_wraps = term_mod.soft_wraps
local calls = 0
term_mod.soft_wraps = function(...) calls = calls + 1; return soft_wraps(...) end
local blob = ("QUJD"):rep(80 * 200 / 4)
wrapped(80, blob .. "\r\n\r\nsee https://example.com/x done")
local blob_rows = 80 * 200 / 80
calls = 0
check(blob_rows + 2, 6, "https://example.com/x", "a link just below a long wrapped line opens")
t.ok(calls < 200, "and gx looks at each row about once (" .. calls .. " looks)")
local long_link = "https://example.com/?s=" .. ("b"):rep(80 * 120 - 23)
wrapped(80, long_link)
calls = 0
check(120, 10, long_link, "a 120-row link opens whole from its last row")
t.ok(calls < 1000, "in about one look per row (" .. calls .. " looks)")
term_mod.soft_wraps = soft_wraps

-- A file path wraps the same way; one whose joined form does not exist (a
-- newline written at exactly the full width) still opens its first row.
local label = "  完整报告 "
local path_width = vim.fn.strdisplaywidth(label) + #report - 3
wrapped(path_width, label .. report .. " done")
check_file(2, 1, report, "a file path the terminal wrapped opens whole")
wrapped(#report, report .. "\r\nxyz")
check_file(1, 3, report, "a full row's file opens when the joined path does not exist")
vim.cmd("tabclose")

-- Exercise the protected Snacks window used by both native providers, not
-- just a synthetic terminal, and ensure another tab's editor is not reused.
vim.cmd("enew")
local background_tab, background_win, background_buf =
  a.nvim_get_current_tabpage(), a.nvim_get_current_win(), a.nvim_get_current_buf()
vim.cmd("tabnew")
local editor_win = a.nvim_get_current_win()
local panel = Snacks.terminal.open({ "cat" }, { cwd = root, win = { position = "right" } })
vim.wait(100, function() return false end)
a.nvim_set_current_win(panel.win)
vim.cmd("stopinsert")
a.nvim_chan_send(vim.bo[panel.buf].channel, "report.md\n")
t.ok(vim.wait(1000, function() return a.nvim_buf_get_lines(panel.buf, 0, 1, false)[1] == "report.md" end),
  "a real terminal prints the local path")
check_file(1, 3, report, "gx opens a file from a protected Snacks terminal")
t.eq(a.nvim_get_current_win(), editor_win, "gx reuses the editor in this tab")
t.eq(a.nvim_win_get_buf(panel.win), panel.buf, "the protected terminal keeps its buffer")
t.eq(vim.fn.jobwait({ vim.bo[panel.buf].channel }, 0)[1], -1, "the terminal process remains running")
t.eq(a.nvim_win_get_buf(background_win), background_buf, "the other tab's editor is untouched")
a.nvim_chan_send(vim.bo[panel.buf].channel, "\4")
vim.wait(100, function() return false end)
vim.cmd("tabclose!")
a.nvim_set_current_tabpage(background_tab)
vim.fn.delete(root, "rf")

t.done()
