local telescope_theme = require("telescope.themes")

local M = {}

local default_opts = {
	hidden = true,
	path_display = { "truncate" },
}

local function extend(opts)
	if opts == nil then
		return default_opts
	end

	for k, v in pairs(default_opts) do
		if opts[k] == nil then
			opts[k] = v
		end
	end
	return opts
end

-- get telescope opts
--   theme: default|ivy|cursor|dropdown
--   opts: see https://github.com/nvim-telescope/telescope.nvim/wiki/Configuration-Recipes
function M.get_opts(opts)
	local extend_opts = extend(opts)

	local theme = opts["theme"]
	if theme == nil or theme == "default" then
		return extend_opts
	else
		return telescope_theme["get_" .. theme](extend_opts)
	end
end

return M
