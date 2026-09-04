return {
  "MeanderingProgrammer/render-markdown.nvim",
  ft = { "markdown", "codecompanion" },
  dependencies = {
    "nvim-treesitter/nvim-treesitter",
    "nvim-tree/nvim-web-devicons",
  },
  keys = {
    -- <localleader>, not <leader>u: the toggle only means something in the
    -- filetypes render-markdown draws, and AGENTS.md keeps <leader> global so
    -- the which-key popup stays truthful in every other buffer. ft-gated to
    -- the same list as the plugin's own trigger, so CodeCompanion chat
    -- buffers get it too.
    { "<localleader>r", "<cmd>RenderMarkdown toggle<cr>", desc = "Toggle Markdown render", mode = "n",
      ft = { "markdown", "codecompanion" } },
  },
  opts = {},
}
