return {
  "folke/trouble.nvim",
  cmd = "Trouble",
  keys = {
    { "<leader>cs", "<cmd>Telescope lsp_document_symbols<cr>",          desc = "Document Symbols" },
    { "<leader>cS", "<cmd>Telescope lsp_dynamic_workspace_symbols<cr>", desc = "Workspace Symbols" },
    { "<leader>xx", "<cmd>Telescope diagnostics<cr>",                   desc = "Diagnostics" },
    { "<leader>xX", function() require("telescope.builtin").diagnostics({ bufnr = 0 }) end, desc = "Buffer diagnostics" },
    { "<leader>xd", vim.diagnostic.open_float,                           desc = "Line diagnostics" },
    { "<leader>xL", "<cmd>Telescope loclist<cr>",                       desc = "Location list" },
    { "<leader>xQ", "<cmd>Telescope quickfix<cr>",                      desc = "Quickfix list" },
  },
  opts = {},
}
