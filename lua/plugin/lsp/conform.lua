return {
  "stevearc/conform.nvim",
  keys = {
    { "<leader>cf", function() require("conform").format() end, desc = "Format", mode = { "n", "v" } },
  },
  opts = {
    default_format_opts = {
      lsp_format = "fallback",
    },
    format_on_save = {
      timeout_ms = 3000,
      lsp_format = "fallback",
    },
  },
}
