local File = require("utils.file")
local lang_path = vim.fn.stdpath("config") .. "/lua/lang/"

local default_opts = {
	on_attach = function(client, bufnr)
		-- formatting
		if client.server_capabilities.documentFormattingProvider then
			vim.api.nvim_create_autocmd("BufWritePre", {
				group = vim.api.nvim_create_augroup("Format", { clear = true }),
				buffer = bufnr,
				callback = function()
					vim.notify("Auto formatting " .. bufnr)
					vim.lsp.buf.format({ timeout_ms = 2000 })
				end,
			})
		end
	end,
}

local server_files = File:of(lang_path):find(function(file)
	return file.path:ends_with(".lua")
end)

local server_table = {}
local server_names = {}

for _, sf in ipairs(server_files) do
	local m = sf:to_module()
	local opts = require(m)
	table.insert(server_names, opts.server_name)
	server_table[opts.server_name] = opts
end

local M = {}

function M.server_names()
	return server_names
end

function M.get_server_opts(server_name)
	local opts = vim.tbl_deep_extend("force", default_opts, {})
	local custom_opts = server_table[server_name]
	return vim.tbl_deep_extend("force", custom_opts, opts)
end

return M
