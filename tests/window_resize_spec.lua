-- Guards window sizing against edgy's geometry.
--
-- edgy re-applies its panels' sizes on WinResized and every panel is
-- winfixwidth/winfixheight, so a bare `:resize` on an editor window beside one
-- is a plain no-op and `wincmd _` is undone on the next tick. Both keys routed
-- through util.window now hand edgy's windows to edgy.
local t = dofile("tests/helper.lua")
require("lazy").load({ plugins = { "edgy.nvim" } })
local W = require("util.window")

local function settle()
  local done = false
  vim.schedule(function() vim.schedule(function() done = true end) end)
  vim.wait(2000, function() return done end, 10)
end

local function H(win) return vim.api.nvim_win_get_height(win) end

local function layout()
  local src, panel
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].buftype == "" then src = win
    elseif vim.bo[buf].filetype == "qf" then panel = win end
  end
  return src, panel
end

-- Without edgy in the tabpage the plain commands must still be what runs.
vim.cmd("tabnew")
vim.cmd("split")
local plain = vim.api.nvim_get_current_win()
local before = H(plain)
W.resize("height", 3)
t.eq(H(plain), before + 3, "a window edgy does not own resizes through :resize")
W.toggle_zoom()
local zoomed = H(plain)
t.ok(zoomed > before + 3, "and zooms to the whole tabpage")
W.toggle_zoom()
settle()
t.eq(H(plain), before, "unzoom restores the split")

-- quickfix is an edgy-managed bottom panel, so one is enough to arm all of it.
vim.cmd("tabnew")
vim.fn.setqflist({ { filename = "init.lua", lnum = 1, text = "x" } })
vim.cmd("copen")
settle()
local src, panel = layout()
t.ok(panel ~= nil, "the quickfix panel is open")
t.ok(require("edgy.editor").get_win(panel) ~= nil, "and edgy owns it")

-- The thickness of a bottom bar is the bar's own size: `Window:resize` can
-- only ever grow it, which is why this goes through the edgebar instead.
vim.api.nvim_set_current_win(panel)
local panel_before = H(panel)
W.resize("height", -5)
settle()
t.ok(H(panel) < panel_before, "shrinking an edgy panel takes effect")
t.ok(H(layout()) > 0, "and the editor window keeps the space")
W.resize("height", 5)
settle()
t.eq(H(select(2, layout())), panel_before, "growing it again restores the size")

-- The regression: zoom used to be reverted a tick later.
src = layout()
vim.api.nvim_set_current_win(src)
local src_before = H(src)
W.toggle_zoom()
settle()
t.ok(H(src) > src_before, "zoom survives edgy re-applying its layout")

W.toggle_zoom()
settle()
local restored_src, restored_panel = layout()
t.eq(H(restored_src), src_before, "unzoom restores the editor window")
t.ok(restored_panel ~= nil and H(restored_panel) == panel_before,
  "and brings the panel back at its own size, rather than closing it")

t.done()
