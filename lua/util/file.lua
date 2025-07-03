---@module "util.file"
---File manipulation utilities for Neovim configuration
---
---Provides object-oriented file operations including directory traversal,
---filtering, and module path conversion. Useful for dynamic plugin loading
---and configuration file management.
---
---@example
---local File = require("util.file")
---
---# Find all Lua files in a directory
---local lua_files = File:of("lua/"):find(function(f) 
---  return f.path:match("%.lua$") 
---end)
---
---# Convert file path to module name
---local module = File:of("lua/plugin/editor.lua"):to_module()
---# Returns: "plugin.editor"

require("util.string-ext")
local config_path = vim.fn.stdpath("config") .. "/lua/"

local File = {}

---Concatenates folder and file paths with proper separator handling
---@param folder string The folder path
---@param file string The file name
---@return string The concatenated path
local function concat_path(folder, file)
	if folder:ends_with("/") then
		return folder .. file
	else
		return folder .. "/" .. file
	end
end

---Creates a new File object from a path
---@param p string The file or directory path
---@return File A new File object
---@example
---local file = File:of("/path/to/file.lua")
function File:of(p)
	local o = { path = p }
	setmetatable(o, File)
	File.__index = File
	return o
end

---Recursively walks through files/directories and applies a consumer function
---@param consumer function Function to apply to each file/directory
---@example
---file:walk(function(f) 
---  if f.path:match("%.lua$") then
---    print("Found Lua file:", f.path)
---  end
---end)
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

---Finds files matching a filter condition
---@param filter function Filter function that takes a File object and returns boolean
---@return table Array of File objects that match the filter
---@example
---local lua_files = file:find(function(f)
---  return f.path:match("%.lua$") and not f:is_dir()
---end)
function File:find(filter)
	local files = {}

	self:walk(function(f)
		if filter(f) then
			table.insert(files, f)
		end
	end)

	return files
end

---Checks if the file path is a directory
---@return boolean True if the path is a directory, false otherwise
function File:is_dir()
	return vim.fn.isdirectory(self.path) ~= 0
end

---Converts file path to Lua module name
---Strips the config path and .lua extension, converts slashes to dots
---@return string The module name suitable for require()
---@example
---local module = File:of("lua/plugin/editor.lua"):to_module()
---# Returns: "plugin.editor"
function File:to_module()
	local path = self.path
	-- Remove config path prefix and .lua extension
	if path:starts_with(config_path) then
		path = path:sub(#config_path + 1, -5)
	end

	-- Convert path separators to module separators
	return path:gsub("/", ".")
end

return File
