return {
  "ThePrimeagen/refactoring.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-treesitter/nvim-treesitter",
  },
  keys = {
    { "<leader>rf", function() require("refactoring").refactor("Extract Function") end,         desc = "Extract function",      mode = "x" },
    { "<leader>rF", function() require("refactoring").refactor("Extract Function To File") end, desc = "Extract function to file", mode = "x" },
    { "<leader>rx", function() require("refactoring").refactor("Extract Variable") end,         desc = "Extract variable",      mode = "x" },
    { "<leader>ri", function() require("refactoring").refactor("Inline Variable") end,          desc = "Inline variable",       mode = { "n", "x" } },
    { "<leader>rb", function() require("refactoring").refactor("Extract Block") end,            desc = "Extract block" },
    { "<leader>rB", function() require("refactoring").refactor("Extract Block To File") end,    desc = "Extract block to file" },
    { "<leader>rs", function() require("refactoring").select_refactor() end,                    desc = "Select refactor",       mode = { "n", "x" } },
  },
  opts = {},
}
