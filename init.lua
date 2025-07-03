-- Initialize core configuration
require("options")
require("mappings")
require("autocmds")
require("bootstrap")

-- Load development utilities in development environment
if vim.env.NVIM_DEV == "1" then
  require("util.dev")
end
