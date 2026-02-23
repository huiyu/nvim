return {
  "windwp/nvim-autopairs",
  event = "InsertEnter",
  opts = {
    check_ts = true,
    ts_config = {},
    disable_filetype = { "TelescopePrompt" },
    fast_wrap = {},
  },
  init = function() end
}
