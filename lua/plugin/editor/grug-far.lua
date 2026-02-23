return {
  "MagicDuck/grug-far.nvim",
  cmd = "GrugFar",
  keys = {
    { "<leader>sr", function() require("grug-far").open() end,                                          desc = "Search and replace", mode = { "n", "v" } },
    { "<leader>sw", function() require("grug-far").open({ prefills = { search = vim.fn.expand("<cword>") } }) end, desc = "Replace current word", mode = "n" },
  },
  opts = {},
}
