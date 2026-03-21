return {
  "stevearc/conform.nvim",
  keys = {
    { "<leader>cf", function() require("conform").format() end, desc = "Format", mode = { "n", "v" } },
  },
  opts = {
    default_format_opts = {
      lsp_format = "fallback",
    },
    format_on_save = function(bufnr)
      -- Check global and buffer-level autoformat toggle
      if vim.g.autoformat == false or vim.b[bufnr].autoformat == false then
        return
      end
      return {
        timeout_ms = 3000,
        lsp_format = "fallback",
      }
    end,
  },
}
