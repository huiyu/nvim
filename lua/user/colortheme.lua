local scheme = "sonokai"

vim.g.sonokai_style = "maia"
vim.g.sonokai_better_performance = 1

-- Set contrast.
-- This configuration option should be placed before `colorscheme everforest`.
-- Available values: 'hard', 'medium'(default), 'soft'
vim.g.everforest_background = "soft"

-- For better performance
vim.g.everforest_better_performance = 1

vim.g.sonokai_style = "maia"

local status_ok, _ = pcall(vim.cmd, "colorscheme " .. scheme)

if not status_ok then
	vim.notify("colortheme " .. scheme .. " not found!")
	return
end
