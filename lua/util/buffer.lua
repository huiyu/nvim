-- Buffer operations this config owns: where a buffer it opens goes, and the
-- housekeeping bufferline and Snacks do not provide on their own.
--
-- Where a buffer goes is decided here and nowhere else. A key, picker hook or
-- callback of this config that puts a buffer in a window asks this module for
-- the window rather than using the current one: the current window may be a
-- panel -- a CodeCompanion chat, an agent terminal, aerial, quickfix -- and a
-- buffer opened there replaces it. A chat simply takes the buffer; Snacks'
-- terminal fixbuf sends it back out, and closes the panel when no plain file
-- window is left to send it to. Which windows make up the editor area is
-- util.window's model (`editor_win`, `ensure_editor_win`); this module applies
-- it. Typed commands (:e, :b) and upstream plugins' own jumps stay theirs.
local M = {}

---------------------------------------------------------------------------
-- Where a buffer goes
---------------------------------------------------------------------------

--- The window a buffer opened from the current window goes into: the current
--- one when it is a non-floating window showing a file, else the editor
--- area's (util.window.ensure_editor_win: the window the cursor last left
--- there, an unmodified Oil listing or GitHub view included, split off when
--- there is none). Not the current Oil listing, GitHub view or dashboard
--- itself: none of them is in the buffer list, so [b/]b would have nothing
--- to cycle from. Leaving a terminal stops terminal-input mode, which would
--- otherwise follow the cursor into the editor.
---@return integer win
function M.editor_target()
  local win = vim.api.nvim_get_current_win()
  if vim.bo.buftype == "" and vim.api.nvim_win_get_config(win).relative == "" then return win end
  if vim.bo.buftype == "terminal" then vim.cmd.stopinsert() end
  return require("util.window").ensure_editor_win()
end

--- Move to `editor_target()` only when the current window is a panel: a
--- non-floating window outside the editor area, such as a chat, an agent
--- terminal, help or quickfix. For commands that read the current buffer
--- where they run -- Oil lists the directory of the listing it is started
--- from -- and so must stay put in a reading view, modified or not.
function M.leave_panel()
  local win = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_get_config(win).relative ~= "" then return end
  if require("util.window").editor_win() == win then return end
  vim.api.nvim_set_current_win(M.editor_target())
end

--- `fn` wrapped to run from `editor_target()`, for keys whose command acts on
--- the current window: bufferline's cycling and first/last, Harpoon's files
--- and menu. Pressed in a panel, whose own buffer is not in the list, [b/]b
--- found nothing to cycle from while [B/]B and ;1 opened the file in the
--- panel's window.
---@param fn fun()
---@return fun()
function M.in_editor(fn)
  return function()
    vim.api.nvim_set_current_win(M.editor_target())
    fn()
  end
end

--- Show `buf` from the editor target and focus it: a file-tab click.
--- Scheduled like bufferline's own default, but the destination is chosen
--- before the buffer switches.
---@param buf integer
function M.open(buf)
  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(buf) then return end
    vim.api.nvim_set_current_win(M.editor_target())
    vim.api.nvim_set_current_buf(buf)
  end)
end

--- Pick a buffer by its tab letter, in the editor target. bufferline's pick
--- takes no callback, so a pick that changed nothing there (a cancel, or the
--- buffer already shown) goes back to where it started, closing the editor
--- window it had to open when the panel was alone in the tabpage.
function M.pick()
  local from = vim.api.nvim_get_current_win()
  local had = {}
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do had[w] = true end
  local win = M.editor_target()
  vim.api.nvim_set_current_win(win)
  local before = vim.api.nvim_win_get_buf(win)
  require("bufferline").pick()
  if win ~= from and vim.api.nvim_win_is_valid(from) and vim.api.nvim_get_current_win() == win
    and vim.api.nvim_win_get_buf(win) == before then
    vim.api.nvim_set_current_win(from)
    if not had[win] then
      -- ensure_editor_win's `:new` left an empty buffer there: it goes too,
      -- or it would stay in the list as [No Name].
      pcall(vim.api.nvim_win_close, win, false)
      if vim.api.nvim_buf_is_valid(before) and vim.api.nvim_buf_get_name(before) == ""
        and not vim.bo[before].modified and vim.api.nvim_buf_line_count(before) == 1
        and vim.api.nvim_buf_get_lines(before, 0, 1, false)[1] == "" then
        pcall(vim.api.nvim_buf_delete, before, {})
      end
    end
  end
end

-- Snacks picker sources whose confirmation opens an editor location. Snacks
-- picks the target window itself (picker/core/main.lua) and, when no window in
-- the tab holds a plain file, falls back to a non-floating one -- whichever
-- shows the least recently used buffer -- which can be Oil, an agent terminal
-- or a CodeCompanion chat. Non-location pickers such as commands, registers
-- and vim.ui.select must not split the layout just by opening, so the list
-- stays explicit instead of the hook applying to every picker.
local LOCATION_SOURCES = {
  buffers = true,
  diagnostics = true,
  diagnostics_buffer = true,
  files = true,
  git_diff = true,
  git_files = true,
  git_status = true,
  grep = true,
  grep_word = true,
  jumps = true,
  loclist = true,
  lsp_incoming_calls = true,
  lsp_symbols = true,
  lsp_workspace_symbols = true,
  marks = true,
  qflist = true,
  recent = true,
  smart = true,
  todo_comments = true,
}

-- The GitHub pickers take an editor window only when one already exists. A
-- tab of a PR reading view and a chat is the case they need it for: "Open in
-- buffer" put the next PR into the chat's window. But an issue or PR confirms
-- into an actions menu where browse, checkout and comment open nothing, and
-- <leader>G works inside a CodeDiff view, so a split made on show would be
-- left empty or wedged into the view. gh_diff is opened from that menu.
local GITHUB_SOURCES = { gh_diff = true, gh_issue = true, gh_pr = true }

--- The Snacks picker `on_show` hook: aim a location picker at the editor
--- target. A caller that passed its own `main` keeps it -- CodeCompanion's
--- /file and /buffer stay in the chat they were typed in.
---@param picker table a snacks.Picker
function M.picker_on_show(picker)
  if picker.init_opts and picker.init_opts.main ~= nil then return end
  local source = picker.opts.source
  local window = require("util.window")
  if LOCATION_SOURCES[source] then
    picker.main = window.ensure_editor_win()
  elseif GITHUB_SOURCES[source] then
    local win = window.editor_win(true)
    if win then picker.main = win end
  end
end

---------------------------------------------------------------------------
-- Housekeeping
---------------------------------------------------------------------------

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
