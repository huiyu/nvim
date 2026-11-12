-- Byte-compile and cache Lua modules from the first `require` on. lazy.nvim
-- turns on the same loader when it starts (a no-op once it is already
-- enabled), but only from there, and everything in lua/config/ loads before
-- it.
vim.loader.enable()

-- The startup sequence lives in lua/config/init.lua.
require("config")
