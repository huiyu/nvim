-- Byte-compile and cache Lua modules from the first `require` on. lazy.nvim
-- turns on the same loader when it starts (a no-op once it is already
-- enabled), but only from there, and everything in lua/config/ loads before
-- it.
vim.loader.enable()
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
vim.opt.rtp:prepend(root)

-- The startup sequence lives in lua/config/init.lua.
require("config")
