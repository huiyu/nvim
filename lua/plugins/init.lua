local fn = vim.fn
local config_path = fn.stdpath("config") .. "/lua/"

require("utils.string-ext")

local File = require("utils.file")

File:of(config_path .. "plugins"):walk(function(file)
	if not file:is_dir() and file.path:ends_with(".lua") and not file.path:ends_with("init.lua") then
		local m = file:to_module()
		require(m)
	end
end)
