return {
	"windwp/nvim-autopairs",
  event = "InsertEnter",
	opts = {
		check_ts = true,
		ts_config = {},
		disable_filetype = { "TelescopePromt" },
		fast_wrap = {},
	},
  init = function()
    -- TODO: more configuration, see https://github.com/windwp/nvim-autopairs
  end
}
