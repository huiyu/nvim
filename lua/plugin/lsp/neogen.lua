return {
  "danymat/neogen",
  dependencies = { "nvim-treesitter/nvim-treesitter" },
  opts = { snippet_engine = "nvim" },
  keys = {
    { ",n", function() require("neogen").generate() end, desc = "Generate Annotations" },
  },
}
