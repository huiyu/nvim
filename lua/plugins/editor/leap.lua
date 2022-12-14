local leap = require("leap")

leap.add_default_mappings()

vim.keymap.set({ "x", "o", "n" }, "r", "<Plug>(leap-forward-to)")
vim.keymap.set({ "x", "o", "n" }, "R", "<Plug>(leap-backword-to)")

-- flit config
require("flit").setup({
	keys = {
		f = "f",
		F = "F",
		t = "t",
		T = "T",
	},
	-- A string like "nv", "nvo", "o", etc
	labeld_modes = "v",
	multiline = true,
	opts = {},
})
