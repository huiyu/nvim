return {
  "kevinhwang91/nvim-ufo",
  event = "BufReadPost",
  dependencies = { "kevinhwang91/promise-async" },
  keys = {
    { "zR", function() require("ufo").openAllFolds() end,  desc = "Open all folds" },
    { "zM", function() require("ufo").closeAllFolds() end, desc = "Close all folds" },
    { "zK", function() require("ufo").peekFoldedLinesUnderCursor() end, desc = "Peek fold" },
  },
  init = function()
    vim.o.foldcolumn = "1"
    vim.o.foldlevel = 99
    vim.o.foldlevelstart = 99
    vim.o.foldenable = true
  end,
  opts = {
    provider_selector = function()
      return { "treesitter", "indent" }
    end,
  },
}
