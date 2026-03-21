return {
  "gbprod/yanky.nvim",
  dependencies = { "kkharji/sqlite.lua" },
  opts = {
    ring = { history_length = 100 },
    highlight = { timer = 200 },
  },
  keys = {
    { "<leader>p", function() require("telescope").extensions.yank_history.yank_history({}) end, desc = "Yank history" },
    { "y",  "<Plug>(YankyYank)",                      mode = { "n", "x" }, desc = "Yank text" },
    { "p",  "<Plug>(YankyPutAfter)",                   mode = { "n", "x" }, desc = "Put after cursor" },
    { "P",  "<Plug>(YankyPutBefore)",                  mode = { "n", "x" }, desc = "Put before cursor" },
    { "gp", "<Plug>(YankyGPutAfter)",                  mode = { "n", "x" }, desc = "Put text after selection" },
    { "gP", "<Plug>(YankyGPutBefore)",                 mode = { "n", "x" }, desc = "Put text before selection" },
    { "[y", "<Plug>(YankyCycleForward)",                desc = "Cycle forward through yank history" },
    { "]y", "<Plug>(YankyCycleBackward)",               desc = "Cycle backward through yank history" },
    { "]p", "<Plug>(YankyPutIndentAfterLinewise)",      desc = "Put indented after cursor (linewise)" },
    { "[p", "<Plug>(YankyPutIndentBeforeLinewise)",     desc = "Put indented before cursor (linewise)" },
    { ">p", "<Plug>(YankyPutIndentAfterShiftRight)",    desc = "Put and indent right" },
    { "<p", "<Plug>(YankyPutIndentAfterShiftLeft)",     desc = "Put and indent left" },
    { ">P", "<Plug>(YankyPutIndentBeforeShiftRight)",   desc = "Put before and indent right" },
    { "<P", "<Plug>(YankyPutIndentBeforeShiftLeft)",    desc = "Put before and indent left" },
  },
}
