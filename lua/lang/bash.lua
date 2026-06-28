-- <leader>cx runner (dispatched centrally by util.run; keymap in mappings.lua).
require("util.run").register({ "sh", "bash" }, function(path)
  return "bash " .. vim.fn.shellescape(path)
end)

return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = { ensure_installed = { "bash" } },
  },
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        bashls = {}
      },
      tools = {
        shfmt = {}
      },
    },
  },
  {
    "stevearc/conform.nvim",
    optional = true,
    opts = {
      formatters_by_ft = {
        sh = { "shfmt" },
        bash = { "shfmt" },
      },
    },
  },
}
