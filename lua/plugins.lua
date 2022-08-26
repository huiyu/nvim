local fn = vim.fn

-- Automatically install packer
local install_path = fn.stdpath("data") .. "/site/pack/packer/start/packer.nvim"
if fn.empty(fn.glob(install_path)) > 0 then
  PACKER_BOOTSTRAP = fn.system({
    "git",
    "clone",
    "--depth",
    "1",
    "https://github.com/wbthomason/packer.nvim",
    install_path,
  })
  print("Installing packer close and reopen Neovim...")
  vim.cmd([[packadd packer.nvim]])
end

--- Autocommand that reloads neovim whenever you save the plugins.lua file
vim.cmd([[
  augroup packer_user_config
  autocmd!
  autocmd BufWritePost plugins.lua source <afile> | PackerSync
  augroup end
]])

-- Use a protected call so we don't error out on first use
local status, packer = pcall(require, "packer")
if not status then
  return
end

-- Have packer use a popup window
packer.init({
  display = {
    open_fn = function()
      return require("packer.util").float({ border = "rounded" })
    end,
  },
})

-- Install your plugins here
packer.startup(function(use)
  use("wbthomason/packer.nvim") -- Have packer manage itself
  use("nvim-lua/popup.nvim") -- An implementation of the Popup API from vim in Neovim
  use("nvim-lua/plenary.nvim") -- Useful lua functions used ny lots of plugins

  use({ "svrana/neosolarized.nvim", requires = { "tjdevries/colorbuddy.nvim" } }) -- solarized color scheme

  use("windwp/nvim-autopairs") -- auto pair
  use("windwp/nvim-ts-autotag") -- auto tags for typesciprt

  -- cmp plugins
  use("hrsh7th/nvim-cmp") -- The completion plugin
  use("hrsh7th/cmp-buffer") -- buffer completions
  use("hrsh7th/cmp-path") -- path completions
  use("hrsh7th/cmp-cmdline") -- cmdline completions
  use("saadparwaiz1/cmp_luasnip") -- snippet completions
  use("hrsh7th/cmp-nvim-lsp")
  use("hrsh7th/cmp-nvim-lua")

  -- snippets
  use("L3MON4D3/LuaSnip") --snippet engine
  use("rafamadriz/friendly-snippets") -- a bunch of snippets to use

  -- telescope
  use("nvim-telescope/telescope.nvim")
  use("nvim-telescope/telescope-project.nvim")
  use({ "nvim-telescope/telescope-fzf-native.nvim", run = "make" })
  use("nvim-telescope/telescope-file-browser.nvim")

  -- treesitter
  use({ "nvim-treesitter/nvim-treesitter", run = ":TSUpdate" })

  -- lsp
  use("neovim/nvim-lspconfig") -- enable lsp
  use("jose-elias-alvarez/null-ls.nvim")
  use("onsails/lspkind-nvim")
  use("glepnir/lspsaga.nvim")
  use("MunifTanjim/prettier.nvim")
  use("williamboman/mason.nvim") -- Portable package manger for LSP servers, DAP servers
  use("williamboman/mason-lspconfig.nvim") -- Lspconfig extension for mason.nvim

  use("dinhhuy258/git.nvim") -- A simple clone of the plugin vim-fugitive
  use("lewis6991/gitsigns.nvim") -- Git integration for buffers

  use("norcalli/nvim-colorizer.lua")
  use("kyazdani42/nvim-web-devicons") -- icon
  use("kyazdani42/nvim-tree.lua") -- nvim tree
  use("folke/which-key.nvim") -- which key keybindings
  use("nvim-lualine/lualine.nvim") -- lualine
  use("arkav/lualine-lsp-progress")
  use("lukas-reineke/indent-blankline.nvim") -- indent line
  use("xiyaowong/nvim-transparent") -- transparent theme
  use("numToStr/Comment.nvim") -- comments
  use("lewis6991/impatient.nvim") -- improve performance
  use("folke/todo-comments.nvim") -- highlight todo comments
  use("akinsho/toggleterm.nvim") -- toggle terminal
  use("ur4ltz/surround.nvim") -- surround plugin

  -- Automatically set up your configuration after cloning packer.nvim
  -- Put this at the end after all plugins
  if PACKER_BOOTSTRAP then
    require("packer").sync()
  end
end)

require("plugin.config.autopairs")
require("plugin.config.colorizer")
require("plugin.config.comment")
require("plugin.config.git")
require("plugin.config.gitsigns")
require("plugin.config.impatient")
require("plugin.config.indentline")
require("plugin.config.lualine")
require("plugin.config.nvim-tree")
require("plugin.config.surround")
require("plugin.config.telescope")
require("plugin.config.todo-comments")
require("plugin.config.toggleterm")
require("plugin.config.transparent")
require("plugin.config.treesitter")
