return {
  "mfussenegger/nvim-lint",
  event = { "BufWritePost", "BufReadPost", "InsertLeave" },
  opts = {
    linters_by_ft = {
      -- Language-specific linters can be added here or extended from lang/ files
      -- e.g. javascript = { "eslint" },
    },
  },
  config = function(_, opts)
    local lint = require("lint")
    lint.linters_by_ft = opts.linters_by_ft

    vim.api.nvim_create_autocmd({ "BufWritePost", "BufReadPost", "InsertLeave" }, {
      group = vim.api.nvim_create_augroup("nvim-lint", { clear = true }),
      callback = function()
        lint.try_lint()
      end,
    })
  end,
}
