local telescope_builtins = require("telescope.builtin")
local get_opts = require("utils.telescope").get_opts

local M = {}

function M.find_files()
	local opts = get_opts({ cwd_only = true })
	telescope_builtins.find_files(opts)
end

function M.recent_files()
	local opts = get_opts({ cwd_only = true })
	telescope_builtins.oldfiles(opts)
end

function M.find_text()
	-- local opts = get_opts({ cwd_only = true, path_display = { "smart" } })
	-- telescope_builtins.live_grep(opts)
  telescope_builtins.live_grep()
end

function M.find_buffers()
	local opts = get_opts({ cwd_only = true })
	telescope_builtins.buffers(opts)
end

return M
