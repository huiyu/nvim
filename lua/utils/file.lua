require("utils.string-ext")
local config_path = vim.fn.stdpath("config") .. "/lua/"

local File = {}

local function concat_path(folder, file)
	if folder:ends_with("/") then
		return folder .. file
	else
		return folder .. "/" .. file
	end
end

function File:of(p)
	local o = { path = p }
	setmetatable(o, File)
	File.__index = File
	return o
end

function File:walk(consumer)
	local path = self.path
	if not self:is_dir() then
		consumer(self)
	else
		for _, f in pairs(vim.fn.readdir(path)) do
			File:of(concat_path(self.path, f)):walk(consumer)
		end
	end
end

function File:find(filter)
	local files = {}

	self:walk(function(f)
		if filter(f) then
			table.insert(files, f)
		end
	end)

	return files
end

function File:is_dir()
	return vim.fn.isdirectory(self.path) ~= 0
end

function File:to_module()
	local path = self.path
	if path:starts_with(config_path) then
		path = path:sub(#config_path + 1, -5)
	end

	return path:gsub("/", ".")
end

return File
