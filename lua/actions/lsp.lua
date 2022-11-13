local get_opts = require("actions.telescope").get_opts
local telescope_builtins = require("telescope.builtin")
local lspsaga_diag = require("lspsaga.diagnostic")

local M = {}

function M.code_action()
	vim.api.nvim_command("Lspsaga code_action")
end

function M.formatting()
	vim.lsp.buf.format({ timeout_ms = 2000 })
end

function M.rename()
	vim.api.nvim_command("Lspsaga rename")
end

function M.definitions()
	local opts = get_opts({ theme = "cursor" })
	telescope_builtins.lsp_definitions(opts)
end

function M.type_definitions()
	local opts = get_opts({ theme = "cursor" })
	telescope_builtins.lsp_type_definitions(opts)
end

function M.references()
	local opts = get_opts({ theme = "cursor" })
	telescope_builtins.lsp_references(opts)
end

function M.document_symbols()
	local opts = get_opts({ theme = "ivy" })
	telescope_builtins.lsp_document_symbols(opts)
end

function M.workspace_symbols()
	local opts = get_opts({ theme = "ivy" })
	telescope_builtins.lsp_workspace_symbols(opts)
end

function M.diagnostics()
	local opts = get_opts({ theme = "ivy" })
	telescope_builtins.lsp_workspace_symbols(opts)
end

function M.next_diagnostics()
	lspsaga_diag.goto_next()
end

function M.prev_diagnostics()
	lspsaga_diag.goto_prev()
end

function M.quickfix()
	vim.diagnostic.setloclist()
end

function M.show_doc()
	vim.api.nvim_command("Lspsaga hover_doc")
end

return M
