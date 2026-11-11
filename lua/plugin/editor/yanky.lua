return {
  "gbprod/yanky.nvim",
  opts = {
    -- The ring persists through shada (yanky's default `ring.storage`), so it
    -- needs no sqlite.lua.
    ring = { history_length = 100 },
    -- The yank flash is lua/autocmds.lua's vim.hl.on_yank(); yanky's own
    -- TextYankPost handler would replace it on every yank. `timer` still
    -- times the put flash.
    highlight = { on_yank = false, timer = 200 },
  },
  keys = {
    { "<leader>yh", "<cmd>YankyRingHistory<cr>", desc = "Yank history" },
    { "y",  "<Plug>(YankyYank)",                      mode = { "n", "x" }, desc = "Yank text" },
    { "p",  "<Plug>(YankyPutAfter)",                   mode = { "n", "x" }, desc = "Put after cursor" },
    { "P",  "<Plug>(YankyPutBefore)",                  mode = { "n", "x" }, desc = "Put before cursor" },
    { "gp", "<Plug>(YankyGPutAfter)",                  mode = { "n", "x" }, desc = "Put after (cursor after text)" },
    { "gP", "<Plug>(YankyGPutBefore)",                 mode = { "n", "x" }, desc = "Put before (cursor after text)" },
    { "[y", "<Plug>(YankyCycleForward)",                desc = "Prev yank (older)" },
    { "]y", "<Plug>(YankyCycleBackward)",               desc = "Next yank (newer)" },
    { "]p", "<Plug>(YankyPutIndentAfterLinewise)",      desc = "Put below (indented)" },
    { "[p", "<Plug>(YankyPutIndentBeforeLinewise)",     desc = "Put above (indented)" },
    { ">p", "<Plug>(YankyPutIndentAfterShiftRight)",    desc = "Put below and indent right" },
    { "<p", "<Plug>(YankyPutIndentAfterShiftLeft)",     desc = "Put below and indent left" },
    { ">P", "<Plug>(YankyPutIndentBeforeShiftRight)",   desc = "Put above and indent right" },
    { "<P", "<Plug>(YankyPutIndentBeforeShiftLeft)",    desc = "Put above and indent left" },
  },
}
