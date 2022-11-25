local M = {}

local gitsign = require("gitsigns")
local telescope_builtins = require("telescope.builtin")

M.next_hunk = function()
	gitsign.next_hunk()
end

M.prev_hunk = function()
	gitsign.prev_hunk()
end

M.blame_line = function()
	gitsign.blame_line()
end

M.preview_hunk = function()
	gitsign.preview_hunk()
end

M.reset_hunk = function()
	gitsign.reset_hunk()
end

M.reset_buffer = function()
	gitsign.reset_buffer()
end

M.stage_hunk = function()
	gitsign.stage_hunk()
end

M.undo_stage_hunk = function()
	gitsign.undo_stage_hunk()
end

M.status = function()
	telescope_builtins.git_status()
end

M.branches = function()
	telescope_builtins.git_branches()
end

M.commits = function()
	telescope_builtins.git_commits()
end

M.buffer_commits = function()
	telescope_builtins.git_bcommits()
end

return M
