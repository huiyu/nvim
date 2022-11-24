local fn = vim.fn
local config_path = fn.stdpath("config") .. "/lua/"

-- dertermin whether a string ends with the characters of a specified string
local function ends_with(str, ending)
	return ending == "" or str:sub(-#ending) == ending
end

local function source_file_from_dir(dir)
	for _, f in pairs(vim.fn.readdir(dir)) do
		local file = dir .. "/" .. f
		if fn.isdirectory(file) ~= 0 then
			source_file_from_dir(file)
		elseif fn.filereadable(file) and not ends_with(file, "init.lua") then
			fn.execute("source " .. file)
		end
	end
end

-- local all modules
local modules_path = config_path .. "modules"
source_file_from_dir(modules_path)
