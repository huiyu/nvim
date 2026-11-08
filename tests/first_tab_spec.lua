-- Guards the invariant that the first tabpage is one the global prefixes work
-- in.
--
-- CodeDiff disables `;` and `s` inside its own tabpage. Views open after the
-- editing page already -- `tab split` inserts after the current tabpage -- so
-- the invariant breaks only when the pages in front of a view go away, and
-- then there is nowhere left to run `;f` from. The guard notices that
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

-- A real CodeDiff tabpage is a git operation and a whole plugin load; the
-- guard reads the tabpage variable util.codediff sets while the view is open,
-- so setting it is the honest stand-in for one. Two ordinary windows, as a
-- single-file `:CodeDiff file` has: no panel to recognise it by.
vim.cmd("tabnew")
local view_tab = vim.api.nvim_get_current_tabpage()
vim.t.blocks_global_prefixes = true
vim.cmd("vsplit")
vim.cmd("enew")
t.eq(vim.bo.buftype, "", "the stand-in carries an ordinary file window, as CodeDiff does")
t.ok(win.blocks_global_prefixes(view_tab), "the tabpage variable marks a prefix-blocking view")
t.ok(not win.blocks_global_prefixes(editor_tab), "and only where it is set")

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

-- A panel CodeDiff left on screen after its session went: the variable is
-- cleared then, and the explorer's filetype still identifies the page.
vim.t[view_tab].blocks_global_prefixes = nil
t.ok(not win.blocks_global_prefixes(view_tab), "without the variable or a panel the page is ordinary")
vim.api.nvim_set_current_tabpage(view_tab)
vim.cmd("vnew")
vim.bo.buftype = "nofile"
vim.bo.filetype = "codediff-explorer"
t.ok(win.blocks_global_prefixes(view_tab), "a CodeDiff explorer window marks the page too")
vim.api.nvim_set_current_tabpage(restored)
vim.cmd("noautocmd tabclose")
t.eq(#vim.api.nvim_list_tabpages(), 1, "closing the page in front leaves only the view")
win.protect_first_tab()
t.eq(#vim.api.nvim_list_tabpages(), 2, "and the guard puts a page back in front of it")
restored = vim.api.nvim_list_tabpages()[1]

-- The debug view is deliberately not protected against: its keys stay global
-- and it carries a file window, so it is a perfectly good first page.
vim.api.nvim_set_current_tabpage(restored)
vim.bo.filetype = "dapui_scopes"
win.protect_first_tab()
t.eq(#vim.api.nvim_list_tabpages(), 2, "a debug panel does not make a page unusable")

t.done()
