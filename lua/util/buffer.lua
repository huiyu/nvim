-- Buffer housekeeping that bufferline and Snacks do not provide on their own.
local M = {}

--- Whether `buf` is a listed file buffer whose file no longer exists on disk.
---
--- Only plain file buffers qualify: a terminal, oil/codediff URI, help page or
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

--- Whether `buf` is a listed, plain buffer that no window shows.
---
--- Every tabpage counts, floats included: a file open in a CodeDiff or debug
--- tabpage is in use there even while this tabpage cannot see it. That is the
--- difference from Snacks.bufdelete.invisible(), which asks bufwinnr() and so
--- only looks at the current tabpage. Terminals, help, oil and CodeDiff's own
--- buffers carry a buftype and never qualify.
---@param buf integer
---@return boolean
function M.is_hidden(buf)
  return vim.bo[buf].buflisted and vim.bo[buf].buftype == "" and #vim.fn.win_findbuf(buf) == 0
end

--- Delete every listed buffer that no window in any tabpage shows.
---
--- No window changes, since none of these buffers is on screen. A modified one
--- still gets Snacks' save/discard/cancel prompt.
function M.delete_hidden()
  local hidden = vim.tbl_filter(M.is_hidden, vim.api.nvim_list_bufs())
  if #hidden == 0 then
    vim.notify("No hidden buffers", vim.log.levels.INFO)
    return
  end
  local existed = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do existed[buf] = true end

  Snacks.bufdelete({ filter = M.is_hidden })

  -- Snacks hands each deleted buffer's windows the most recent listed buffer
  -- and creates an empty one when none is left -- which happens here whenever
  -- every window shows an unlisted buffer (dashboard, terminal). A hidden
  -- buffer has no windows, so that placeholder would only be a stray
  -- [No Name] in the bufferline.
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if not existed[buf] and vim.api.nvim_buf_get_name(buf) == "" and not vim.bo[buf].modified
      and #vim.fn.win_findbuf(buf) == 0 then
      pcall(vim.api.nvim_buf_delete, buf, {})
    end
  end

  local deleted = #vim.tbl_filter(function(buf)
    return not (vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buflisted)
  end, hidden)
  vim.notify(("Deleted %d hidden buffer%s"):format(deleted, deleted == 1 and "" or "s"),
    vim.log.levels.INFO)
end

return M
