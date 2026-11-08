-- Byte-compile and cache Lua modules from the first `require` on. lazy.nvim
-- turns on the same loader in bootstrap (a no-op once it is already enabled),
-- but only from there: util.cwd, options, mappings, autocmds and the AI facade
-- all load before it.
vim.loader.enable()

-- `dd(value)` anywhere in this config pretty-prints it with the call site as the
-- title. Loaded lazily so a startup that never debugs never pays for it, and
-- taking over `vim.print` routes `:lua =expr` through the same view while
-- preserving the built-in function's pass-through return values.
-- See lua/util/debug.lua; `util.logger` remains the channel for user-facing
-- messages.
_G.dd = function(...) return require("util.debug").dump(...) end
vim.print = _G.dd

-- A deleted working directory is recovered before anything can trip over it.
require("util.cwd").setup()

-- Initialize core configuration
require("options")
require("mappings")
require("autocmds")
require("ai").setup()
require("bootstrap")
