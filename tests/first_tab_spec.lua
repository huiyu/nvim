-- Guards the invariant that the first tabpage is one the global prefixes work
-- in.
--
-- diffview disables `;`, `,` and the rest inside its own tabpage. Views open
-- after the editing page already -- `tab split` inserts after the current
-- tabpage -- so the invariant breaks only when the pages in front of a view go
-- away, and then there is nowhere left to run `;f` from. The guard notices that
-- state and puts a fresh page back in front.
local t = dofile("tests/helper.lua")
local win = require("util.window")

local function filetypes(tabpage)
  local fts = {}
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
    if vim.api.nvim_win_get_config(w).relative == "" then
      fts[#fts + 1] = vim.bo[vim.api.nvim_win_get_buf(w)].filetype
    end
  end
  return fts
end

local editor_tab = vim.api.nvim_get_current_tabpage()

-- A real diffview tabpage is a git operation and a whole plugin load; the guard
-- only ever reads filetypes, so a window carrying the panel's filetype is the
-- honest stand-in for one.
vim.cmd("tabnew")
local view_tab = vim.api.nvim_get_current_tabpage()
vim.bo.filetype = "DiffviewFiles"
vim.cmd("vsplit")
vim.cmd("enew")
t.eq(vim.bo.buftype, "", "the stand-in carries an ordinary file window, as diffview does")

win.protect_first_tab()
t.eq(#vim.api.nvim_list_tabpages(), 2, "a view behind an editing page is left alone")
t.eq(vim.api.nvim_list_tabpages()[1], editor_tab, "and the editing page stays first")

-- The reported end state: nothing in front of the view.
vim.api.nvim_set_current_tabpage(view_tab)
vim.cmd("noautocmd " .. vim.api.nvim_tabpage_get_number(editor_tab) .. "tabclose")
t.eq(#vim.api.nvim_list_tabpages(), 1, "leaving the view as the only tabpage")

win.protect_first_tab()
t.eq(#vim.api.nvim_list_tabpages(), 2, "the guard restores a page in front of the view")
t.eq(vim.api.nvim_list_tabpages()[2], view_tab, "the view keeps its windows, moved back one place")
t.eq(vim.api.nvim_get_current_tabpage(), view_tab, "the repair does not steal focus")

local restored = vim.api.nvim_list_tabpages()[1]
local fts = filetypes(restored)
t.eq(#fts, 1, "the restored page is a single window")
t.eq(vim.bo[vim.api.nvim_win_get_buf(vim.api.nvim_tabpage_list_wins(restored)[1])].buftype, "",
  "and it is a page a file can be opened into")

win.protect_first_tab()
t.eq(#vim.api.nvim_list_tabpages(), 2, "running the guard again adds nothing")

-- The debug view is deliberately not protected against: its keys stay global
-- and it carries a file window, so it is a perfectly good first page.
vim.api.nvim_set_current_tabpage(restored)
vim.bo.filetype = "dapui_scopes"
win.protect_first_tab()
t.eq(#vim.api.nvim_list_tabpages(), 2, "a debug panel does not make a page unusable")

t.done()
