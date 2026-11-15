-- Bootstrap exceptions: cwd recovery and leaders must precede lazy imports.
_G.dd = function(...) return require("util.debug").dump(...) end
vim.print = _G.dd
require("config.cwd")
local keys = require("config.keymaps")
vim.g.mapleader, vim.g.maplocalleader = keys.leader, keys.localleader
require("config.lazy")
