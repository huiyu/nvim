return {
  "folke/persistence.nvim",
  event = "BufReadPre",
  keys = {
    { "<leader>sl", function() require("persistence").load({ last = true }) end, desc = "Load last session",    mode = "n" },
    { "<leader>s.", function() require("persistence").load() end,                desc = "Load current session", mode = "n" },
    { "<leader>ss", function() require("persistence").save() end,                desc = "Save the session",     mode = "n" },
  },
  opts = {
    save_empty = false,
  },
}
