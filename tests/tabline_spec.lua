-- Guards the tabline never hiding itself.
--
-- Left to itself bufferline hides the whole tabline whenever it has at most one
-- buffer to show, and its count never looks at tabpages. Opening a diff with no
-- files loaded therefore hid the far-right `1`/`2` tabpage indicators along
-- with the buffer list -- at the one moment they matter most, since CodeDiff
-- disables the global prefixes inside its tabpage and knowing another one
-- exists is the way out.
local t = dofile("tests/helper.lua")
-- bufferline loads on VeryLazy, after the first frame. Until then the row
-- comes from lua/options.lua: a `1` there would leave the first frame without
-- it, and the whole screen would move down a line once bufferline turned it on.
t.eq(vim.o.showtabline, 2, "the tabline is on before bufferline loads")
-- VeryLazy has not fired while a spec runs.
require("lazy").load({ plugins = { "bufferline.nvim" } })

local function settle()
  local done = false
  vim.schedule(function() vim.schedule(function() done = true end) end)
  vim.wait(1000, function() return done end, 10)
end

local function unlist_everything()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].buflisted then vim.bo[buf].buflisted = false end
  end
end

--- The rendered tabline, as Nvim would draw it.
local function rendered()
  return vim.api.nvim_eval_statusline(vim.o.tabline, { use_tabline = true, maxwidth = 120 }).str
end

vim.cmd("tabonly")
unlist_everything()
vim.cmd("doautocmd BufAdd")
settle()
t.eq(vim.o.showtabline, 2, "nothing listed and one tabpage still shows the tabline")

-- The bug was bufferline turning it off again from the tabline's own redraw
-- (`_G.nvim_bufferline`), so a draw has to leave it alone.
rendered()
settle()
t.eq(vim.o.showtabline, 2, "a tabline redraw does not turn it off")

vim.cmd("tabnew")
settle()
t.eq(vim.o.showtabline, 2, "a second tabpage keeps it shown")
t.ok(rendered():match("%f[%w]1%f[%W].*%f[%w]2%f[%W]") ~= nil,
  "and the tabpage indicators are actually drawn")

vim.cmd("tabclose")
unlist_everything()
vim.cmd("badd init.lua")
vim.cmd("doautocmd BufAdd")
settle()
t.eq(vim.o.showtabline, 2, "a single buffer keeps it shown")

-- The filter that keeps CodeDiff's revision buffers out of the bufferline
-- still applies; it just no longer decides whether the tabline exists.
vim.cmd("badd codediff:////tmp/repo///0123abcd/a.lua")
settle()
t.ok(rendered():match("a%.lua") == nil, "CodeDiff's revision buffers stay out of the list")

-- The permanent tabline must not draw a band across the top when it is empty.
-- The colorscheme runs with `transparent`, which clears Normal but leaves
-- TabLineFill opaque, and bufferline's unset `fill` background inherits that
-- group rather than reaching the terminal -- so both have to be clear.
for _, group in ipairs({ "BufferLineFill", "TabLineFill" }) do
  t.eq(vim.api.nvim_get_hl(0, { name = group, link = false }).bg, nil,
    group .. " has no background, so an empty tabline stays invisible")
end

t.done()
