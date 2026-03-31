return {
  "folke/todo-comments.nvim",
  event = "BufReadPost",
  dependencies = {
    "nvim-lua/plenary.nvim",
  },
  keys = {
    { "<leader>st", "<cmd>TodoTelescope<cr>",                            desc = "Todos" },
    { "<leader>sT", "<cmd>TodoTelescope keywords=TODO,FIX,FIXME<cr>",   desc = "Todo/Fix/Fixme" },
    { "<leader>xt", "<cmd>TodoTelescope<cr>",                            desc = "Todo" },
    { "<leader>xT", "<cmd>TodoTelescope keywords=TODO,FIX,FIXME<cr>",   desc = "Todo/Fix/Fixme" },
    { "[t",         function() require("todo-comments").jump_prev() end, desc = "Prev todo" },
    { "]t",         function() require("todo-comments").jump_next() end, desc = "Next todo" },
  },
  opts = {},
}
