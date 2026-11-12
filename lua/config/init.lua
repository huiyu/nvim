-- The startup sequence. Every module here does its work when required --
-- none has a setup() to call -- and the order below is the only place that
-- knows the order.

-- `dd(value)` anywhere in this config pretty-prints it with the call site as the
-- title. Loaded lazily so a startup that never debugs never pays for it, and
-- taking over `vim.print` routes `:lua =expr` through the same view while
-- preserving the built-in function's pass-through return values.
-- See lua/util/debug.lua; `util.logger` remains the channel for user-facing
-- messages.
_G.dd = function(...) return require("util.debug").dump(...) end
vim.print = _G.dd

-- First: a deleted cwd is recovered before anything can trip over it, and the
-- first argument is captured now to pick the startup cwd at VimEnter.
require("config.cwd")
require("config.options")
require("config.keymaps")
require("config.autocmds")
-- The AI facade installs itself: the <leader>a keys, :AI, the one-window slot.
require("ai")
-- Last: the plugin specs see every option and mapping above.
require("config.lazy")
