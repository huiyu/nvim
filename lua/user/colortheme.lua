local scheme = "sonokai"

-- :h sonokai
vim.g["sonokai_style"] = "maia"
vim.g["sonokai_better_performance"] = 1

local status_ok, _ = pcall(vim.cmd, "colorscheme " .. scheme)

if not status_ok then
  vim.notify("colortheme " .. scheme .. " not found!")
  return
end
