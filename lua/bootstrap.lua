local fn = vim.fn
local install_path = fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(install_path) then
  fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", -- latest stable release
    install_path,
  })
end
vim.opt.rtp:prepend(install_path)

require("lazy").setup({
  spec = {
    { import = "plugin.editor" },
    { import = "plugin.lsp" },
    { import = "plugin.ui" },
    { import = "plugin.vcs" },
    { import = "lang" },
  },
  default = {
    lazy = false,
    version = false, -- try installing the latest stable version for plugins
  },
  install = {},
  checker = { enabled = true }, -- automatically check for plugin updates
  performance = {
    rtp = {
      disabled_plugins = {
        "gzip",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
      },
    },
  },
})
