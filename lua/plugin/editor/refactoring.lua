return {
  "ThePrimeagen/refactoring.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-treesitter/nvim-treesitter",
  },
  keys = {
    { ",ef", function() require("refactoring").refactor("Extract Function") end,         desc = "Extract function",      mode = "x" },
    { ",eF", function() require("refactoring").refactor("Extract Function To File") end, desc = "Extract function to file", mode = "x" },
    { ",ex", function() require("refactoring").refactor("Extract Variable") end,         desc = "Extract variable",      mode = "x" },
    { ",i", function() require("refactoring").refactor("Inline Variable") end,          desc = "Inline variable",       mode = { "n", "x" } },
    { ",eb", function() require("refactoring").refactor("Extract Block") end,            desc = "Extract block" },
    { ",eB", function() require("refactoring").refactor("Extract Block To File") end,    desc = "Extract block to file" },
    { ",R", function() require("refactoring").select_refactor() end,                    desc = "Select refactor",       mode = { "n", "x" } },
  },
  opts = {},
}
