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

local file = vim.fn.tempname() .. ".txt"
local buf = fixture({ "no URL here" }, false)
a.nvim_buf_set_name(buf, file)
check(1, 0, file, "without a URL gx still opens the current file")

t.done()
