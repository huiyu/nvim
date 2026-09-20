-- Guards the tabline staying visible while more than one tabpage exists.
--
-- bufferline hides the whole tabline when it has at most one buffer to show,
-- and its own count never looks at tabpages. Opening a diff with no files
-- loaded therefore hid the far-right `1`/`2` tabpage indicators along with the
-- buffer list -- at the one moment they matter most, since diffview disables
-- the global prefixes inside its tabpage and knowing another one exists is the
-- way out.
local t = dofile("tests/helper.lua")
-- bufferline loads on VeryLazy, which has not fired while a spec runs.
require("lazy").load({ plugins = { "bufferline.nvim" } })

-- The sync runs from a scheduled autocmd callback, so each assertion has to let
-- the event loop turn first.
local function settle()
  local done = false
  vim.schedule(function() vim.schedule(function() done = true end) end)
  vim.wait(1000, function() return done end, 10)
end

for _, buf in ipairs(vim.api.nvim_list_bufs()) do
  if vim.bo[buf].buflisted then vim.bo[buf].buflisted = false end
end
vim.cmd("tabonly")
settle()

-- An empty start still gets no tabline: taking the toggle over from bufferline
-- must not turn into forcing it always on.
vim.cmd("doautocmd BufAdd")
settle()
t.eq(vim.o.showtabline, 0, "one tabpage and nothing to list keeps the tabline hidden")

vim.cmd("tabnew")
settle()
t.eq(#vim.api.nvim_list_tabpages(), 2, "a second tabpage exists")
t.eq(vim.o.showtabline, 2, "a second tabpage shows the tabline, with nothing listed")

-- The regression came from the tabline's own redraw re-running bufferline's
-- toggle and undoing the override, so a redraw has to leave it alone.
vim.api.nvim_eval_statusline("%!v:lua.nvim_bufferline()", { use_tabline = true })
settle()
t.eq(vim.o.showtabline, 2, "and a tabline redraw does not hide it again")

vim.cmd("tabclose")
settle()
t.eq(vim.o.showtabline, 0, "closing it hides the tabline again")

-- A single listed buffer is still not worth a bufferline; two are. `tabnew`
-- above left its own scratch buffer listed, so clear the slate first.
for _, buf in ipairs(vim.api.nvim_list_bufs()) do
  if vim.bo[buf].buflisted then vim.bo[buf].buflisted = false end
end
vim.cmd("badd init.lua")
vim.cmd("doautocmd BufAdd")
settle()
t.eq(vim.o.showtabline, 0, "a single buffer keeps it hidden")
vim.cmd("badd AGENTS.md")
vim.cmd("doautocmd BufAdd")
settle()
t.eq(vim.o.showtabline, 2, "a second buffer shows it")

-- diffview's own buffers are filtered out of the count, the same as they are
-- filtered out of the bufferline itself.
vim.cmd("tabonly")
for _, buf in ipairs(vim.api.nvim_list_bufs()) do
  if vim.bo[buf].buflisted then vim.bo[buf].buflisted = false end
end
vim.cmd("badd diffview://null/a.lua")
vim.cmd("badd diffview://null/b.lua")
vim.cmd("doautocmd BufAdd")
settle()
t.eq(vim.o.showtabline, 0, "diffview's internal buffers do not count toward the tabline")

t.done()
