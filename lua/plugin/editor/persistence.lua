return {
  "folke/persistence.nvim",
  event = "BufReadPre",
  keys = {
    { "<leader>ql", function() require("persistence").load({ last = true }) end, desc = "Load last session",    mode = "n" },
    { "<leader>q.", function() require("persistence").load() end,                desc = "Load current session", mode = "n" },
    { "<leader>qs", function() require("persistence").save() end,                desc = "Save the session",     mode = "n" },
  },
  opts = {
    save_empty = false,
  },
}
