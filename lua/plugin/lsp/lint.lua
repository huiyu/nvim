return {
  "mfussenegger/nvim-lint",
  event = { "BufWritePost", "BufReadPost", "InsertLeave" },
  opts = {
    linters_by_ft = {},
  },
  config = function(_, opts)
    local lint = require("lint")

    -- Merge the linters_by_ft contributed by lang/ files into nvim-lint's
    -- built-in defaults (per-ft list union, so language files only add to it).
    for ft, linters in pairs(opts.linters_by_ft) do
      lint.linters_by_ft[ft] = vim.list_extend(lint.linters_by_ft[ft] or {}, linters)
    end

    vim.api.nvim_create_autocmd({ "BufWritePost", "BufReadPost", "InsertLeave" }, {
      group = vim.api.nvim_create_augroup("nvim-lint", { clear = true }),
      callback = function()
        lint.try_lint()
      end,
    })
  end,
}
