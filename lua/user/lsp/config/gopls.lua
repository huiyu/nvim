local opts = {

	on_attach = function(client, _)
		-- disable internal formatting capability, using null-ls instead
		client.server_capabilities.document_formatting = false
		client.server_capabilities.document_range_formatting = false

		vim.cmd("autocmd BufWritePre <buffer> lua vim.lsp.buf.format()")
	end,
}

return opts
