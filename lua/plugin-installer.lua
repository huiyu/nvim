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
  autocmd BufWritePost plugin-installer.lua source <afile> | PackerSync
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

	use("folke/which-key.nvim") -- which key keybindings
	use({ "svrana/neosolarized.nvim", requires = { "tjdevries/colorbuddy.nvim" } }) -- solarized color scheme

	-- lsp
	use({
		"neovim/nvim-lspconfig",
		requires = {
			"onsails/lspkind-nvim", -- vscode-like pictograms
			"glepnir/lspsaga.nvim", -- light-weight lsp ui
			"williamboman/mason.nvim", -- Portable package manger for LSP servers, DAP servers
			"williamboman/mason-lspconfig.nvim",
			"jose-elias-alvarez/null-ls.nvim",
			"MunifTanjim/prettier.nvim",
		},
	})

	-- cmp plugins
	use({
		"hrsh7th/nvim-cmp",
		requires = {
			"L3MON4D3/LuaSnip", -- snippet engine
			"saadparwaiz1/cmp_luasnip",
			"rafamadriz/friendly-snippets", -- a bunch of snippets to use
			"hrsh7th/cmp-buffer",
			"hrsh7th/cmp-path",
			"hrsh7th/cmp-cmdline",
			"hrsh7th/cmp-nvim-lsp",
			"hrsh7th/cmp-nvim-lua",
		},
	})

	use("github/copilot.vim")

	use({
		"nvim-telescope/telescope.nvim",
		requires = {
			"nvim-lua/plenary.nvim",
			"nvim-telescope/telescope-file-browser.nvim",
			{ "nvim-telescope/telescope-fzf-native.nvim", run = "make" },
			"nvim-telescope/telescope-ui-select.nvim",
		},
	})
	use({
		"kyazdani42/nvim-tree.lua",
		requires = {
			"kyazdani42/nvim-web-devicons",
		},
	})

	use({
		"nvim-lualine/lualine.nvim",
		requires = {
			"arkav/lualine-lsp-progress",
		},
	})

	use({ "nvim-treesitter/nvim-treesitter", run = ":TSUpdate" })
	use({ "nvim-treesitter/nvim-treesitter-textobjects" })
	use("dinhhuy258/git.nvim") -- A simple clone of the plugin vim-fugitive
	use("lewis6991/gitsigns.nvim") -- Git integration for buffers
	use("norcalli/nvim-colorizer.lua")
	use("windwp/nvim-autopairs") -- auto pair
	use("windwp/nvim-ts-autotag") -- auto tags for typesciprt
	use("lukas-reineke/indent-blankline.nvim") -- indent line
	use("xiyaowong/nvim-transparent") -- transparent theme
	use("numToStr/Comment.nvim") -- comments
	use("lewis6991/impatient.nvim") -- improve performance
	use("folke/todo-comments.nvim") -- highlight todo comments
	use("akinsho/toggleterm.nvim") -- toggle terminal
	use("ur4ltz/surround.nvim") -- surround plugin
	use({
		"ggandor/leap.nvim",
		requires = {
			"ggandor/flit.nvim",
			"ggandor/leap-ast.nvim",
		},
	})

	-- Automatically set up your configuration after cloning packer.nvim
	-- Put this at the end after all plugins
	if PACKER_BOOTSTRAP then
		require("packer").sync()
	end
end)
