return {
  "folke/snacks.nvim",
  optional = true,
  opts = function(_, opts)
    opts.dashboard = require("config.dashboard")
  end,
}
