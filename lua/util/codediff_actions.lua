-- Hunk actions inside a CodeDiff view (,u ,U ,X), installed on every
-- `User CodeDiffKeys` pass through util.codediff.set_keys. Only util.codediff
-- and gitsigns' public API may be used from here.
local M = {}

--- Install this module's keys on the view in `tab`. Nothing yet.
---@param tab integer
---@diagnostic disable-next-line: unused-local
function M.attach(tab)
end

return M
