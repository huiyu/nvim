return {
  "folke/persistence.nvim",
  event = "BufReadPre",
  keys = {
    { "<leader>sl", function() require("persistence").load({ last = true }) end, desc = "Load last session",    mode = "n" },
    { "<leader>s.", function() require("persistence").load() end,                desc = "Load cwd session",     mode = "n" },
    { "<leader>ss", function() require("persistence").save() end,                desc = "Save session",         mode = "n" },
  },
  opts = {
    -- Skip the save when no file buffer is open (replaces `save_empty = false`).
    need = 1,
  },
}
