local cmd = vim.api.nvim_create_user_command

-- File commands
cmd(
	"ExploreCurrentDirectory",
	"Telescope file_browser path=%:p:h select_buffer=true",
	{ desc = "Explore current directory" }
)
cmd("ExploreWorkspaceDirectory", "Telescope file_browser", { desc = "Explore workspace directory" })

cmd("FindFiles", function(opts)
	-- merge opts with default
	opts = vim.tbl_deep_extend("force", {
		cwd_only = true,
		hidden = false,
		path_display = { "truncate" },
	}, opts or {})
	require("telescope.builtin").find_files(opts)
end, {
	desc = "Find files",
	nargs = "?",
})

cmd("FindRecentFiles", function()
	require("telescope.builtin").oldfiles({
		cwd_only = true,
		hidden = true,
		path_display = { "truncate" },
	})
end, { desc = "Find recent files" })

cmd("FindFrecentFiles", "Telescope frecency workspace=CWD", { desc = "Find frecent files" })

cmd("FindBuffers", function()
	require("telescope.builtin").buffers({
		cwd_only = true,
		hidden = true,
		path_display = { "truncate" },
	})
end, { desc = "Find buffers" })

cmd("HelpTags", function()
	require("telescope.builtin").help_tags()
end, { desc = "Help tags" })

cmd("ManPages", function()
	require("telescope.buitin").man_pages()
end, { desc = "Man Pages" })

-- Search commands
cmd("SearchWord", function()
	require("telescope.builtin").live_grep({
		cwd_only = true,
		path_display = { "truncate" },
	})
end, { desc = "Search word" })

cmd("SearchWordUnderCursor", function()
	require("telescope.builtin").grep_string({
		cwd_only = true,
		path_display = { "truncate" },
	})
end, { desc = "Search word under cursor" })

cmd("SearchWorkspaceSymbols", function()
	require("telescope.builtin").lsp_workspace_symbols()
end, { desc = "Search symbols" })

cmd("SearchBufferSymbols", function()
	require("telescope.builtin").lsp_document_symbols()
end, { desc = "Search symbols" })

--- Window
cmd("WindowCloseOthers", function()
	require("util.window").close_others()
end, { desc = "Close other windows" })

cmd("WindowCloseCurrent", function()
	require("util.window").close_current()
end, { desc = "Close current window" })

-- Plugin commands
cmd("PluginStatus", function()
	require("lazy").home()
end, { desc = "Plugin status" })

cmd("PluginInstall", function()
	require("lazy").install()
end, { desc = "Plugin install" })

cmd("PluginSync", function()
	require("lazy").sync()
end, { desc = "Plugin status" })

cmd("PluginUpdate", function()
	require("lazy").update()
end, { desc = "Plugin status" })

cmd("PluginCheck", function()
	require("lazy").check()
end, { desc = "Plugin check updates" })

cmd("PluginUpdateAll", function()
	require("lazy").sync({ wait = true })
	vim.cmd("MasonUpdate")
end, { desc = "Update plugins and packages" })

-- Lsp commands
cmd("LspRename", "Lspsaga rename", { desc = "Lsp rename" })
cmd("LspCodeAction", "Lspsaga code_action", { desc = "Lsp code action" })
cmd("LspFormatCode", function()
	vim.lsp.buf.format()
end, { desc = "Lsp format code" })
cmd("LspGotoDefinition", "Lspsaga goto_definition", { desc = "Lsp goto definition" })
cmd("LspDefinition", "Lspsaga peek_definition", { desc = "Lsp definition" })
cmd("LspGotoTypeDefinition", "Lspsaga type_definition", { desc = "Lsp goto type definition" })
cmd("LspTypeDefinition", "Lspsaga peek_type_definition", { desc = "Lsp type definition" })
cmd("LspReferences", "Telescope lsp_references path_display={'truncate'}", { desc = "Lsp references" })
cmd("LspImplementations", "Telescope lsp_implementations path_display={'truncate'}", { desc = "Lsp implementations" })
cmd("LspHoverDoc", "Lspsaga hover_doc", { desc = "Lsp hover doc" })
cmd("LspCursorDiagnostics", "Lspsaga show_cursor_diagnostics", { desc = "Lsp show cursor diagnostics" })
cmd("LspLineDiagnostics", "Lspsaga show_line_diagnostics", { desc = "Lsp show show line diagnostics" })
cmd("LspBufDiagnostics", "Lspsaga show_buf_diagnostics", { desc = "Lsp show buffer diagnostics" })
cmd("LspWorkspaceDiagnostics", "Lspsaga show_workspace_diagnostics", { desc = "Lsp show workspace diagnostics" })
cmd("LspPrevDiagnostic", "Lspsaga diagnostic_jump_prev", { desc = "Lsp prev diagnostic" })
cmd("LspNextDiagnostic", "Lspsaga diagnostic_jump_next", { desc = "Lsp next diagnostic" })

-- Session
cmd("SessionLoadLast", function()
	require("persistence").load({ last = true })
end, { desc = "Load last session" })

cmd("SessionLoadCurrent", function()
	require("persistence").load()
end, { desc = "Load current session" })

cmd("SessionSave", function()
	require("persistence").save()
end, { desc = "Save session" })
