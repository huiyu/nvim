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

-- Autocommand that reloads neovim whenever you save the plugins.lua file
vim.cmd([[
  augroup packer_user_config
  autocmd!
  autocmd BufWritePost plugins.lua source <afile> | PackerSync
  augroup end
]])

-- Use a protected call so we don't error out on first use
local status_ok, packer = pcall(require, "packer")
if not status_ok then
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
return packer.startup(function(use)
  -- My plugins here
  use("wbthomason/packer.nvim") -- Have packer manage itself
  use("nvim-lua/popup.nvim") -- An implementation of the Popup API from vim in Neovim
  use("nvim-lua/plenary.nvim") -- Useful lua functions used ny lots of plugins

  -- Colorschemes
  use("sainnhe/sonokai")

  -- autopair
  use("windwp/nvim-autopairs")

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

  -- treesitter
  use({ "nvim-treesitter/nvim-treesitter", run = ":TSUpdate" })

  -- lsp
  use("neovim/nvim-lspconfig") -- enable lsp
  use("williamboman/nvim-lsp-installer") -- language server installer
  use("jose-elias-alvarez/null-ls.nvim")
  use("onsails/lspkind-nvim")
  use("tami5/lspsaga.nvim")

  -- gitsign
  use("lewis6991/gitsigns.nvim")

  -- nvim-tree
  use({ "kyazdani42/nvim-tree.lua", requires = "kyazdani42/nvim-web-devicons" })

  -- which-key
  use("folke/which-key.nvim")

  -- lualine
  use({ "nvim-lualine/lualine.nvim", requires = { "kyazdani42/nvim-web-devicons" } })
  use("arkav/lualine-lsp-progress")

  -- tabline
  use("kdheepak/tabline.nvim")

  -- indentline
  use("lukas-reineke/indent-blankline.nvim")

  -- transparent
  use("xiyaowong/nvim-transparent")

  -- comments
  use("numToStr/Comment.nvim")

  -- improve performance
  use("lewis6991/impatient.nvim")

  -- todo-comments
  use("folke/todo-comments.nvim")

  -- toggle terminal
  use("akinsho/toggleterm.nvim")

  -- surround
  use("ur4ltz/surround.nvim")

  -- Automatically set up your configuration after cloning packer.nvim
  -- Put this at the end after all plugins
  if PACKER_BOOTSTRAP then
    require("packer").sync()
  end
end)
