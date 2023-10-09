return {
  "xiyaowong/nvim-transparent",
  opts = {
    extra_groups = {
      "BufferLineTabClose",
      "BufferlineBufferSelected",
      "BufferLineFill",
      "BufferLineBackground",
      "BufferLineSeparator",
      "BufferLineIndicatorSelected",
    },
  },
  config = function(_, opts)
    require("transparent").setup(opts)
    vim.api.nvim_create_autocmd("User", {
      pattern = "LazyDone",
      once = true,
      callback = function(_)
        vim.api.nvim_command("highlight NormalFloat guibg=none")
      end,
    })
  end,
}
