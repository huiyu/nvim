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
