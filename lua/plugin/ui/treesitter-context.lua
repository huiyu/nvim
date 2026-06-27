-- Sticky scope: pin the current function/class header to the top of the window
-- while scrolling through a long body. It relies on core `vim.treesitter`
-- (parsers/queries), not nvim-treesitter's Lua API, so it works with the
-- 'main' branch used in plugin/ui/treesitter.lua.
return {
  "nvim-treesitter/nvim-treesitter-context",
  event = { "BufReadPost", "BufNewFile" },
  dependencies = { "nvim-treesitter/nvim-treesitter" },
  keys = {
    {
      "<leader>uC",
      function() require("treesitter-context").toggle() end,
      desc = "Toggle context (sticky scope)",
    },
  },
  opts = {
    max_lines = 3,           -- cap the sticky header height
    multiline_threshold = 1, -- collapse a multiline scope to a single line
    trim_scope = "outer",
    mode = "cursor",
  },
}
