---@module "bootstrap"
---Lazy.nvim plugin manager initialization
---
---Handles automatic installation and configuration of the lazy.nvim plugin manager.
---Sets up plugin loading from organized directories (editor, lsp, ui, vcs, lang).
---
---This file is responsible for:
---  1. Installing lazy.nvim if not present
---  2. Configuring plugin specifications from modular directories
---  3. Setting performance optimizations
---  4. Enabling lazy loading for faster startup

-- Initialize logging early
local logger = require("util.logger")

local fn = vim.fn
local install_path = fn.stdpath("data") .. "/lazy/lazy.nvim"

-- Auto-install lazy.nvim if not present
if not vim.uv.fs_stat(install_path) then
  logger.debug("Installing lazy.nvim plugin manager...")
  
  local result = fn.system({
    "git",
    "clone",
    "--filter=blob:none",  -- Shallow clone for faster download
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",     -- Use stable release
    install_path,
  })
  
  if vim.v.shell_error ~= 0 then
    logger.error("Failed to install lazy.nvim: %s", result)
    error("Failed to install lazy.nvim plugin manager")
  else
    logger.debug("Successfully installed lazy.nvim")
  end
else
  logger.debug("lazy.nvim already installed at: %s", install_path)
end

-- Add lazy.nvim to runtime path
vim.opt.rtp:prepend(install_path)
logger.debug("Added lazy.nvim to runtime path")

-- Configure lazy.nvim with modular plugin specifications
logger.debug("Configuring lazy.nvim plugin manager...")

local success, error_msg = pcall(function()
  require("lazy").setup({
    spec = {
      -- Plugin modules organized by functionality
      { import = "plugin.editor" },  -- Editor enhancement plugins (telescope, surround, etc.)
      { import = "plugin.lsp" },     -- LSP, completion, and development tools
      { import = "plugin.ui" },      -- UI enhancements and themes
      { import = "plugin.vcs" },     -- Version control integration
      { import = "lang" },           -- Language-specific configurations
    },
    default = {
      lazy = true,     -- Enable lazy loading for better performance
      version = false, -- Use latest versions instead of tagged releases
    },
    rocks = {
      enabled = false, -- Disable Luarocks integration until broken rockspecs are fixed (e.g. nvim-dap-python)
    },
    install = {
      -- Install missing plugins on startup
      missing = true,
      -- Use a more conservative install approach
      colorscheme = { "solarized-osaka" },
    },
    checker = { 
      enabled = true,  -- Automatically check for plugin updates
      frequency = 3600 -- Check every hour
    },
    performance = {
      cache = {
        enabled = true,  -- Enable plugin caching
      },
      rtp = {
        -- Disable built-in plugins for better performance
        disabled_plugins = {
          "gzip",       -- Archive file support
          "tarPlugin",  -- Tar file support
          "tohtml",     -- Convert to HTML
          "tutor",      -- Vim tutor
          "zipPlugin",  -- Zip file support
          "netrw",      -- Network file explorer (replaced by custom solution)
          "netrwPlugin",
        },
      },
    },
    ui = {
      -- Use a simple border for lazy UI
      border = "rounded",
    },
  })
end)

if not success then
  logger.error("Failed to configure lazy.nvim: %s", error_msg)
  error("Plugin manager configuration failed: " .. error_msg)
else
  logger.debug("Successfully configured lazy.nvim plugin manager")
end
