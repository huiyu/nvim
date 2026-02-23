return {
  "folke/todo-comments.nvim",
  event = "BufReadPost",
  dependencies = {
    "nvim-lua/plenary.nvim",
  },
  keys = {
    { "<leader>ht", "<cmd>TodoTelescope<cr>",                            desc = "Todos",         mode = { "n", "v" } },
    { "[t",         function() require("todo-comments").jump_prev() end, desc = "Previous todo", mode = "n" },
    { "]t",         function() require("todo-comments").jump_next() end, desc = "Next todo" },
  },
  opts = {},
}
