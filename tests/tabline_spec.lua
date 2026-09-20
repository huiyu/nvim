-- Guards the tabline never hiding itself.
--
-- Left to itself bufferline hides the whole tabline whenever it has at most one
-- buffer to show, and its count never looks at tabpages. Opening a diff with no
-- files loaded therefore hid the far-right `1`/`2` tabpage indicators along
-- with the buffer list -- at the one moment they matter most, since diffview
-- disables the global prefixes inside its tabpage and knowing another one
-- exists is the way out.
local t = dofile("tests/helper.lua")
-- bufferline loads on VeryLazy, which has not fired while a spec runs.
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

-- The filter that keeps diffview's buffers out of the bufferline still applies;
-- it just no longer decides whether the tabline exists.
vim.cmd("badd diffview://null/a.lua")
settle()
t.ok(rendered():match("diffview") == nil, "diffview's internal buffers stay out of the list")

t.done()
