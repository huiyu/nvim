local opts = {

	on_attach = function(client, _)
		-- disable internal formatting capability, using null-ls instead
		client.resolved_capabilities.document_formatting = false
		client.resolved_capabilities.document_range_formatting = false

		vim.cmd("autocmd BufWritePre <buffer> lua vim.lsp.buf.formatting_sync()")
	end,
}

return opts
