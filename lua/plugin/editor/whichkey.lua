return {
	"folke/which-key.nvim",
	opts = {
		-- the presets plugin, adds help for a bunch of default keybindings in Neovim
		-- No actual key bindings are created
		presets = {
			operators = true, -- adds help for operators like d, y, ... and registers them for motion / text object completion
			motions = true, -- adds help for motions
			text_objects = true, -- help for text objects triggered after entering an operator
			windows = true, -- default bindings on <c-w>
			nav = true, -- misc bindings to work with windows
			z = true, -- bindings for folds, spelling and others prefixed with z
			g = true, -- bindings for prefixed with g
		},
		window = {
			border = "single", -- none, single, double, shadow
			position = "bottom", -- bottom, top
			margin = { 1, 0, 1, 0 }, -- extra window margin [top, right, bottom, left]
			padding = { 2, 2, 2, 2 }, -- extra window padding [top, right, bottom, left]
			winblend = 0,
		},
		layout = {
			height = { min = 4, max = 25 }, -- min and max height of the columns
			width = { min = 20, max = 50 }, -- min and max width of the columns
			spacing = 3, -- spacing between columns
			align = "center", -- align columns left, center or right
		},
	},
	init = function()
		-- local whichkey = require("which-key")
		-- local mappings = require("keybindings").whichkey

		-- for key, map in pairs(mappings) do
		-- 	whichkey.register(map, { prefix = key, mode = "n" })
		-- end

		require("util.keymap-util").register_keybind_consumer(function(keybind)
			local whichkey = require("which-key")
			if keybind:has_cmd() then
				vim.keymap.set(keybind.mode, keybind.key, keybind.cmd, keybind.opts)
			else
				if keybind.opts.name == nil then
					keybind.opts.name = keybind.opts.desc
				end
				local registeration = {}
				registeration[keybind.key] = keybind.opts
				whichkey.register(registeration, { mode = keybind.mode })
			end
		end)
	end,
}
