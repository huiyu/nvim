local M = {}

function M.close_current()
	local win_num = #vim.api.nvim_list_wins()
	if win_num == 1 or (win_num == 2 and require("nvim-tree.view").get_winnr() ~= nil) then
		print("Can't close last window")
	else
		local win = vim.api.nvim_get_current_win()
		vim.api.nvim_win_close(win, false)
	end
end

function M.close_others()
	local wins = vim.api.nvim_list_wins()
	for _, win in ipairs(wins) do
		if win ~= vim.api.nvim_get_current_win() and win ~= require("nvim-tree.view").get_winnr() then
			vim.api.nvim_win_close(win, false)
		end
	end
end

return M
