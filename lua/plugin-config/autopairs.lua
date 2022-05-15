local status_ok, auto_pairs = pcall(require, "nvim-autopairs")
if not status_ok then
  return
end

auto_pairs.setup({
  check_ts = true,
  ts_config = {},
  disable_filetype = { "TelescopePromt" },
  fast_wrap = {},
})

local cmp_auto_pairs = require("nvim-autopairs.completion.cmp")
local cmp_status_ok, cmp = pcall(require, "cmp")
if not cmp_status_ok then
  return
end
cmp.event:on("confirm_done", cmp_auto_pairs.on_confirm_done({ map_char = { text = " " } }))
