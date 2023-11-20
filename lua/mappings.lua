--- Keybindings
--- see https://neovim.io/doc/user/intro.html#vim-modes-intro
vim.g.mapleader = " "
vim.g.maplocalleder = "\\"

local maps = (function()
	local maps = {}
	for _, mode in ipairs({ "", "n", "i", "v", "x", "s", "o", "!", "i", "l", "c", "t" }) do
		maps[mode] = {}
	end
	return maps
end)()

--------------------------
-- NORMAL MODE
--------------------------
-- Standard operations
maps.n["j"] = { "v:count == 0 ? 'gj' : 'j'", expr = true, desc = "Move cursor down" }
maps.n["k"] = { "v:count == 0 ? 'gk' : 'k'", expr = true, desc = "Move cursor up" }

maps.n["<leader>e"] = { "<cmd>ExploreCurrentDirectory<cr>", desc = "Explore current directory" }
maps.n["<leader>E"] = { "<cmd>ExploreWorkingDirectory<cr>", desc = "Explore working directory" }
maps.n["<leader>t"] = { "<cmd>NvimTreeToggle<cr>", desc = "File tree" }
maps.n["<C-t>"] = { "<cmd>ToggleTerm<cr>", desc = "Toggle terminal" }
maps.i["<C-t>"] = maps.n["<C-t>"]
maps.t["<C-t>"] = maps.n["<C-t>"]
maps.v["<C-t>"] = maps.n["<C-t>"]
maps.n["<leader>h"] = { "<cmd>nohlsearch<cr>", desc = "No hightlight" }
maps.n["<leader>f"] = { "<cmd>FindFiles<cr>", desc = "Find files" }
maps.n["<leader>F"] = { "<cmd>FindFiles hidden=true<cr>", desc = "Find files(include hidden)" }
maps.n["<leader>r"] = { "<cmd>FindRecentFiles<cr>", desc = "Recent files" }
maps.n["<leader>R"] = { "<cmd>FindFrecentFiles<cr>", desc = "Frecent files" }
maps.n["<leader>o"] = { "<cmd>Lspsaga outline<cr>", desc = "Outline" }
maps.n["]]"] = { "<C-i>", desc = "Forward" }
maps.n["[["] = { "<C-o>", desc = "Backward" }

-- Save / Quit / Session
maps.n["<leader>q"] = { desc = "Quit/Session" }
maps.n["<leader>qw"] = { "<cmd>w<cr>", desc = "Save" }
maps.n["<C-s>"] = { "<cmd>w<cr>", desc = "Save" }
maps.i["<C-s>"] = maps.n["<C-s>"]
maps.n["<leader>qW"] = { "<cmd>wall<cr>", desc = "Save all" }
maps.n["<leader>qq"] = { "<cmd>qa<cr>", desc = "Quit all" }
maps.n["<leader>qQ"] = { "<cmd>wqa!<cr>", desc = "Save and quit all" }
maps.n["<leader>ql"] = { "<cmd>SessionLoadLast<cr>", desc = "Load last session" }
maps.n["<leader>q."] = { "<cmd>SessionLoadCurrent<cr>", desc = "Load current sessions" }
maps.n["<leader>qs"] = { "<cmd>SessionSave<cr>", desc = "Save the session" }

-- Search
maps.n["<leader>s"] = { desc = "Search" }
maps.n["<leader>sw"] = { "<cmd>SearchWord<cr>", desc = "Search word" }
maps.n["<leader>sW"] = { "<cmd>SearchWordUnderCursor<cr>", desc = "Search word under cursor" }
maps.n["<leader>ss"] = { "<cmd>SearchBufferSymbols<cr>", desc = "Search buffer symbols" }
maps.n["<leader>sS"] = { "<cmd>SearchWorkspaceSymbols<cr>", desc = "Search workspace symbols" }
maps.n["<leader>sh"] = { "<cmd>HelpTags<cr>", desc = "Help tags" }
maps.n["<leader>sm"] = { "<cmd>ManPages<cr>", desc = "Man pages" }

-- Buffer
maps.n["<leader>b"] = { "<cmd>FindBuffers<cr>", desc = "Find buffers" }
maps.n["[b"] = { "<cmd>bprev<cr>", desc = "Previous buffer" }
maps.n["]b"] = { "<cmd>bnext<cr>", desc = "Next buffer" }

-- Todo
maps.n["<leader>st"] = { "<cmd>TodoTelescope<cr>", desc = "Todos" }
maps.n["[t"] = {
	function()
		require("todo-comments").jump_prev()
	end,
	desc = "Previous todo",
}
maps.n["]t"] = {
	function()
		require("todo-comments").jump_next()
	end,
	desc = "Next todo",
}

-- Window management
maps.n["<leader>w"] = { desc = "Window" }
maps.n["<leader>w+"] = { "<C-w>+", desc = "Increase height" }
maps.n["<leader>w-"] = { "<C-w>-", desc = "Descrease height" }
maps.n["<leader>w="] = { "<C-w>=", desc = "Increase height" }
maps.n["<leader>w<"] = { "<C-w><", desc = "Descrease width" }
maps.n["<leader>w>"] = { "<C-w>>", desc = "Increase width" }
maps.n["<leader>w|"] = { "<C-w>|", desc = "Max out the width" }
maps.n["<leader>wv"] = { "<cmd>vsplit<cr>", desc = "Split window vertically" }
maps.n["<leader>ws"] = { "<cmd>split<cr>", desc = "Split window horizontally" }
maps.n["<leader>wc"] = { "<cmd>WindowCloseCurrent<cr>", desc = "Close current window" }
maps.n["<leader>wo"] = { "<cmd>WindowCloseOthers<cr>", desc = "Close other windows" }
maps.n["<leader>wh"] = { "<C-w>h", desc = "Go to the up window" }
maps.n["<leader>wj"] = { "<C-w>j", desc = "Go to the down window" }
maps.n["<leader>wk"] = { "<C-w>k", desc = "Go to the up window" }
maps.n["<leader>wl"] = { "<C-w>l", desc = "Go to the right window" }
maps.n["<leader>ww"] = { "<C-w>w", desc = "Switch window" }

maps.n["s+"] = { "<C-w>+", desc = "Increase height" }
maps.n["s-"] = { "<C-w>-", desc = "Descrease height" }
maps.n["s="] = { "<C-w>=", desc = "Increase height" }
maps.n["s<"] = { "<C-w><", desc = "Descrease width" }
maps.n["s>"] = { "<C-w>>", desc = "Increase width" }
maps.n["s|"] = { "<C-w>|", desc = "Max out the width" }
maps.n["sv"] = { "<cmd>vsplit<cr>", desc = "Split window vertically" }
maps.n["ss"] = { "<cmd>split<cr>", desc = "Split window horizontally" }
maps.n["sc"] = { "<cmd>WindowCloseCurrent<cr>", desc = "Close current window" }
maps.n["so"] = { "<cmd>WindowCloseOthers<cr>", desc = "Close other windows" }
maps.n["sh"] = { "<C-w>h", desc = "Go to the up window" }
maps.n["sj"] = { "<C-w>j", desc = "Go to the down window" }
maps.n["sk"] = { "<C-w>k", desc = "Go to the up window" }
maps.n["sl"] = { "<C-w>l", desc = "Go to the right window" }
maps.n["sw"] = { "<C-w>w", desc = "Switch window" }

-- LSP
maps.n[","] = { desc = "LSP" }
maps.n[",a"] = { "<cmd>Lspsaga code_action<cr>", desc = "Code action" }
maps.n[",f"] = { "<cmd>LspFormatCode<cr>", desc = "Code format" }
maps.n[",r"] = { "<cmd>LspRename<cr>", desc = "Rename" }
maps.n[",d"] = { "<cmd>LspDefinition<cr>", desc = "Show definition" }
maps.n["gd"] = { "<cmd>LspGotoDefinition<cr>", desc = "Goto definition" }
maps.n[",t"] = { "<cmd>LspTypeDefinition<cr>", desc = "Show type definition" }
maps.n["gt"] = { "<cmd>LspGotoTypeDefinitioncr>", desc = "Goto type definition" }
maps.n[",e"] = { "<cmd>LspReferences<cr>", desc = "Show references" }
maps.n[",i"] = { "<cmd>LspImplementations<cr>", desc = "Show implementations" }

maps.n[",c"] = { "<cmd>LspCursorDiagnostics<cr>", desc = "Cursor diagnostics" }
maps.n[",l"] = { "<cmd>LspLineDiagnostics<cr>", desc = "Line diagnostics" }
maps.n[",b"] = { "<cmd>LspBufDiagnostics<cr>", desc = "Buffer diagnostics" }
maps.n[",w"] = { "<cmd>LspWorkspaceDiagnostics<cr>", desc = "Workspace diagnostics" }
maps.n["[d"] = { "<cmd>LspPrevDiagnostics<cr>", desc = "Prev diagnostic" }
maps.n["]d"] = { "<cmd>LspNextDiagnostics<cr>", desc = "Next diagnostic" }
maps.n[",q"] = { "<cmd>lua vim.diagnostic.setloclist()<cr>", desc = "Quickfix" }
maps.n[",h"] = { "<cmd>Lspsaga hover_doc<cr>", desc = "Help" }

maps.n["]m"] = { "<cmd>TSTextobjectGotoNextStart @function.outer<cr>", desc = "Goto next method start" }
maps.n["[m"] = { "<cmd>TSTextobjectGotoPreviousStart @function.outer<cr>", desc = "Goto privous method start" }
maps.n["[M"] = { "<cmd>TSTextobjectGotoPreviousEnd @function.outer<cr>", desc = "Goto privous method end" }
maps.n["]M"] = { "<cmd>TSTextobjectGotoNextEnd @function.outer<cr>", desc = "Goto next method end" }
maps.n["]c"] = { "<cmd>TSTextobjectGotoNextStart @class.outer<cr>", desc = "Goto next class start" }
maps.n["[c"] = { "<cmd>TSTextobjectGotoPreviousStart @class.outer<cr>", desc = "Goto privous class start" }
maps.n["]C"] = { "<cmd>TSTextobjectGotoNextEnd @class.outer<cr>", desc = "Goto next class end" }
maps.n["[C"] = { "<cmd>TSTextobjectGotoPreviousEnd @class.outer<cr>", desc = "Goto privous class end" }

-- Git
maps.n["<leader>g"] = { desc = "Git" }
maps.n["<leader>gj"] = { "<cmd>Gitsign next_hunk<cr>", desc = "Next hunk" }
maps.n["<leader>gk"] = { "<cmd>Gitsign prev_hunk<cr>", desc = "Prev hunk" }
maps.n["<leader>gl"] = { "<cmd>Gitsign blame_line<cr>", desc = "Blame line" }
maps.n["<leader>gp"] = { "<cmd>Gitsign preview_hunk<cr>", desc = "Preview hunk" }
maps.n["<leader>gr"] = { "<cmd>Gitsign reset_hunk<cr>", desc = "Reset hunk" }
maps.n["<leader>gR"] = { "<cmd>Gitsign reset_buffer<cr>", desc = "Reset buffer" }
maps.n["<leader>gs"] = { "<cmd>Gitsign stage_hunk<cr>", desc = "Stage hunk" }
maps.n["<leader>gu"] = { "<cmd>Gitsign undo_stage_hunk<cr>", desc = "Undo stage hunk" }
maps.n["<leader>go"] = { "<cmd>Telescope git_status<cr>", desc = "Status" }
maps.n["<leader>gb"] = { "<cmd>Telescope git_branches<cr>", desc = "Branches" }
maps.n["<leader>gc"] = { "<cmd>Telescope git_commits<cr>", desc = "Commits" }
maps.n["<leader>gC"] = { "<cmd>Telescope bcommits<cr>", desc = "Buffer commits" }
maps.n["<leader>gd"] = { "<cmd>Gitsign diffthis<cr>", desc = "Diff" }

-- Debug
maps.n["<leader>d"] = { desc = "Debug" }
maps.v["<leader>d"] = maps.n["<leader>d"]
-- TODO:

-- Plugin management
maps.n["<leader>p"] = { desc = "Plugin" }
maps.n["<leader>pi"] = { "<cmd>PluginInstall<cr>", desc = "Plugin install" }
maps.n["<leader>ps"] = { "<cmd>PluginStatus<cr>", desc = "Plugin status" }
maps.n["<leader>pS"] = { "<cmd>PluginSync<cr>", desc = "Plugin sync" }
maps.n["<leader>pu"] = { "<cmd>PluginUpdate<cr>", desc = "Plugin update" }
maps.n["<leader>pc"] = { "<cmd>PluginCheck<cr>", desc = "Plugin check" }
maps.n["<leader>pu"] = { "<cmd>PluginUpdate<cr>", desc = "Plugin update" }
maps.n["<leader>pU"] = { "<cmd>PluginUpdateAll<cr>", desc = "Update plugins and packages" }

----------------------------------
-- INSERT MODE
----------------------------------
maps.i["<C-t>"] = { "<cmd>ToggleTerm<cr>", desc = "Toggle terminal", noremap = true, silent = true }
maps.i["jk"] = { "<ESC>", desc = "Exit insert mode", noremap = true, silent = true }
maps.i["<C-c>"] = { "<ESC>", desc = "Exit insert mode", noremap = true, silent = true }

----------------------------------
-- VISUAL MODE
----------------------------------
maps.v["<"] = { "<gv", desc = "Indent left", noremap = true, silent = true }
maps.v[">"] = { ">gv", desc = "Indent right", noremap = true, silent = true }
maps.v["<A-j>"] = { ":m .+1<CR>==", desc = "Move text down", noremap = true, silent = true }
maps.v["<A-k>"] = { ":m .-2<CR>==", desc = "Move text up", noremap = true, silent = true }
maps.v["p"] = { '"_dP', desc = "Paste without yanking", noremap = true, silent = true }

----------------------------------
-- VISUAL BLOCK MODE KEYMAP
----------------------------------
maps.x["J"] = { ":m '>+1<cr>gv=gv", desc = "move text down", noremap = true, silent = true }
maps.x["K"] = { ":m '<-2<cr>gv=gv", desc = "move text up", noremap = true, silent = true }
maps.x["<A-j>"] = maps.v["<A-j>"]
maps.x["<A-k>"] = maps.v["<A->"]

return maps
