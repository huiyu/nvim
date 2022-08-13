local treesitter = require("nvim-treesitter.configs")

treesitter.setup({
  ensure_installed = {
    "json",
    "html",
    "css",
    "vim",
    "lua",
    "javascript",
    "typescript",
    "tsx",
    "go",
    "python",
    "java",
    "kotlin",
    "ruby",
    "vue",
    "c",
    "c_sharp",
    "bash",
    "haskell",
  },
  highlight = {
    enable = true,
  },
  indent = {
    enable = true,
  },
})

local parser_config = require("nvim-treesitter.parsers").get_parser_configs()
parser_config.tsx.filetype_to_parsername = { "javascript", "javascript.tsx" }
