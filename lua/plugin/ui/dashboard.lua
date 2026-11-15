return {
  "folke/snacks.nvim",
  optional = true,
  opts = function(_, opts)
    opts.dashboard = require("editor_core.dashboard")
  end,
}
