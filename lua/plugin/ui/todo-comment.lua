return {
  "folke/todo-comments.nvim",
  event = "BufReadPost",
  dependencies = {
    "nvim-lua/plenary.nvim",
  },
  keys = {
    { "<leader>st", function() Snacks.picker.todo_comments() end,                                             desc = "Todos" },
    { "<leader>sT", function() Snacks.picker.todo_comments({ keywords = { "TODO", "FIX", "FIXME" } }) end,   desc = "Todo/Fix/Fixme" },
    { "<leader>xt", function() Snacks.picker.todo_comments() end,                                             desc = "Todo" },
    { "<leader>xT", function() Snacks.picker.todo_comments({ keywords = { "TODO", "FIX", "FIXME" } }) end,   desc = "Todo/Fix/Fixme" },
    { "[t",         function() require("todo-comments").jump_prev() end, desc = "Prev todo" },
    { "]t",         function() require("todo-comments").jump_next() end, desc = "Next todo" },
  },
  opts = {},
}
