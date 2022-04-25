local status_ok, treesitter = pcall(require, "nvim-treesitter.configs")

if not status_ok then
  vim.notify("treesistter not found!")
end


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
  }
})
