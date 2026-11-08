-- Everything here must be buffer- or window-local: an ftplugin runs for each
-- Lua buffer, and a plain `:set` also changes the global value that every
-- buffer opened later starts from. `iskeyword` keeps its default because a
-- Lua identifier never contains `-` (adding it fuses `n-1` or `--x` into one
-- word), and `whichwrap` has no local value to set here at all.
vim.opt_local.formatoptions:remove({ "c", "r", "o" })
