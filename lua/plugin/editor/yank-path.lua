-- Visual <leader>yy/<leader>yc copy text (config.keymaps); these copy where
-- the current file is. Selection ranges are captured by the action itself.
return {
  "folke/snacks.nvim",
  optional = true,
  keys = {
    { "<leader>ya", function() require("editor_core.yank_path").absolute() end, desc = "Yank file path (absolute)" },
    { "<leader>yr", function() require("editor_core.yank_path").relative() end, desc = "Yank file path (repo-relative)" },
    { "<leader>yl", function() require("editor_core.yank_path").line() end, mode = { "n", "x" }, desc = "Yank path:line" },
    { "<leader>yg", function() require("editor_core.yank_path").permalink() end, mode = { "n", "x" }, desc = "Yank Git permalink" },
  },
}
