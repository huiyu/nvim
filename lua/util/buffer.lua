-- Buffer housekeeping that bufferline and Snacks do not provide on their own.
local M = {}

--- Whether `buf` is a listed file buffer whose file no longer exists on disk.
---
--- Only plain file buffers qualify: a terminal, oil/diffview URI, help page or
--- unnamed scratch buffer has no file to be missing. A modified buffer is
--- still reported -- after an agent deletes a file the user may want to save
--- it back -- and Snacks' save prompt decides that case.
---@param buf integer
---@return boolean
function M.is_missing_file(buf)
  if not vim.bo[buf].buflisted or vim.bo[buf].buftype ~= "" then return false end
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" or name:match("^%w+://") then return false end
  return vim.uv.fs_stat(name) == nil
end

--- Delete every listed buffer whose file has been removed from disk.
---
--- Goes through Snacks.bufdelete so the window layout survives and a modified
--- buffer gets the usual save/discard/cancel prompt instead of being forced.
function M.delete_missing()
  local gone = vim.tbl_filter(M.is_missing_file, vim.api.nvim_list_bufs())
  if #gone == 0 then
    vim.notify("No buffers of missing files", vim.log.levels.INFO)
    return
  end
  Snacks.bufdelete({ filter = M.is_missing_file })
  vim.notify(("Deleted %d buffer%s of missing files"):format(#gone, #gone == 1 and "" or "s"),
    vim.log.levels.INFO)
end

return M
