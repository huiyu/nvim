local M = {}

local vim_error = require("util.vim_error")

local SPECIAL_BUFTYPES = {
  'help', 'quickfix', 'terminal', 'prompt', 'nofile', 'acwrite', 'nowrite'
}

local SPECIAL_FILETYPES = {
  'NvimTree', 'neo-tree', 'nerdtree', 'CHADTree', 'fern',    -- File explorers
  'Outline', 'aerial', 'tagbar', 'vista', 'symbols-outline', -- Outline views
  'fugitive', 'git', 'gitcommit',                            -- Git related
  'help',                                                    -- Help documentation
  'qf', 'quickfix', 'locationlist',                          -- Quickfix/Location list
  'snacks_picker_input', 'snacks_picker_list', 'snacks_picker_preview', 'fzf', -- Fuzzy finders
  'dashboard', 'startify', 'alpha',                          -- Start pages
  'lspinfo', 'mason', 'lazy', 'packer',                      -- Plugin/LSP management
  'terminal', 'toggleterm',                                  -- Terminals
  'dap-repl', 'dapui',                                       -- Debugging
}

--- Nil once the window is gone: the list `close_others` walks is a snapshot,
--- and closing one window can take a paired one with it (a picker's list and
--- input, an edgy relayout), so a later entry may no longer exist.
local function get_win_info(win_id)
  if not vim.api.nvim_win_is_valid(win_id) then return nil end
  local buf_id = vim.api.nvim_win_get_buf(win_id)

  return {
    is_current = (win_id == vim.api.nvim_get_current_win()),
    is_preview = vim.wo[win_id].previewwindow,
    is_modifiable = vim.bo[buf_id].modifiable,
    filetype = vim.bo[buf_id].filetype,
    buftype = vim.bo[buf_id].buftype,
  }
end

--- Close the current window. Nvim refuses over the last window (E444) or a
--- modified buffer that cannot be hidden (E37); that refusal is one warning
--- here, not a traceback out of :WindowCloseCurrent.
function M.close_current()
  local ok, err = pcall(vim.api.nvim_win_close, vim.api.nvim_get_current_win(), false)
  if not ok then vim_error.notify(err) end
end

-- Function to close all windows except the current one and special windows
function M.close_others()
  -- A window belongs to exactly one tab page.  nvim_list_wins() spans every
  -- tab, which made this command unexpectedly close windows in background tabs.
  local wins = vim.api.nvim_tabpage_list_wins(0)

  for _, win in ipairs(wins) do
    local info = get_win_info(win)

    -- Check if the window should be closed:
    -- - Is modifiable
    -- - Is not the current window
    -- - Is not a preview window
    -- - Does not have a special buffer type
    -- - Does not have a special file type
    if info and info.is_modifiable and
        not info.is_current and
        not info.is_preview and
        not vim.list_contains(SPECIAL_BUFTYPES, info.buftype) and
        not vim.list_contains(SPECIAL_FILETYPES, info.filetype) then
      -- Nvim refuses over the last ordinary window, as when this runs from a
      -- float above a single split. One warning, and the rest of the loop.
      local ok, err = pcall(vim.api.nvim_win_close, win, false)
      if not ok then vim_error.notify(err) end
    end
  end
end

--- Iterate non-floating windows with winfixwidth/winfixheight, yielding {win, width?, height?}
--- Uses stored target (_fixed_width_target / _fixed_height_target) when available,
--- otherwise records current size as the target for future use.
local function get_fixed_panels()
  local panels = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_config(win).relative == "" then
      local entry = {}
      if vim.wo[win].winfixwidth then
        local target = vim.w[win]._fixed_width_target
        if not target then
          target = vim.api.nvim_win_get_width(win)
          vim.w[win]._fixed_width_target = target
        end
        entry.width = target
      end
      if vim.wo[win].winfixheight then
        local target = vim.w[win]._fixed_height_target
        if not target then
          target = vim.api.nvim_win_get_height(win)
          vim.w[win]._fixed_height_target = target
        end
        entry.height = target
      end
      if entry.width or entry.height then
        entry.win = win
        panels[#panels + 1] = entry
      end
    end
  end
  return panels
end

--- Restore fixed panels to their target sizes (no equalization).
--- Use after window open/close to enforce sidebar widths.
function M.restore_fixed_panels()
  for _, entry in ipairs(get_fixed_panels()) do
    if vim.api.nvim_win_is_valid(entry.win) then
      if entry.width then
        vim.api.nvim_win_set_width(entry.win, entry.width)
      end
      if entry.height then
        vim.api.nvim_win_set_height(entry.win, entry.height)
      end
    end
  end
end

--- Filetypes that occupy the editor area without holding a real file buffer.
--- The dashboard qualifies: on a fresh session it is the only thing in the
--- editing area, so it has to be reachable as a jump target.
local EDITOR_FILETYPES = { 'snacks_dashboard' }

--- A window counts as "the editor" when it shows a normal file buffer.
--- Sidebars, terminals, pickers, quickfix, and help all carry a non-empty
--- buftype, which excludes them without needing a filetype denylist.
local function is_editor_win(win)
  if not vim.api.nvim_win_is_valid(win) then return false end
  if vim.api.nvim_win_get_config(win).relative ~= "" then return false end
  local buf = vim.api.nvim_win_get_buf(win)
  if vim.bo[buf].buftype == "" then return true end
  return vim.list_contains(EDITOR_FILETYPES, vim.bo[buf].filetype)
end

--- Pick the editor window to jump into, scoped to the current tab.
local function pick_editor_win()
  local wins = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if is_editor_win(win) then wins[#wins + 1] = win end
  end
  if #wins == 0 then return nil end

  -- Prefer the editor window the cursor last sat in: with two files split
  -- side by side, "go to the editor" means the one you were just working in.
  local last = vim.t.editor_win_last
  if last and vim.list_contains(wins, last) then return last end

  -- No usable record, so fall back to the widest window, which is what reads
  -- visually as the main editing area.
  local best, best_width = wins[1], vim.api.nvim_win_get_width(wins[1])
  for _, win in ipairs(wins) do
    local width = vim.api.nvim_win_get_width(win)
    if width > best_width then
      best, best_width = win, width
    end
  end
  return best
end

--- Guarantee a window a file can be opened into, and return it.
---
--- snacks' picker picks its target window in snacks/picker/core/main.lua. That
--- filter excludes non-file buffers correctly, but records a `non_float`
--- fallback *before* the filter runs and returns it when nothing qualifies --
--- so a layout of only an oil listing and an agent panel has the picked file
--- land on top of one of them. No window variable prevents that; the fallback
--- is unconditional.
---
--- So when the tab has no editor window at all, split the current one
--- horizontally and hand back the new half. The panel stays on screen, and the
--- file gets somewhere legitimate to go.
---@return integer win
function M.ensure_editor_win()
  local win = pick_editor_win()
  if win then return win end
  -- Split from a real layout window, not whatever is current: this runs from
  -- the picker's on_show, when the current window is the picker's own float.
  local base
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_config(w).relative == "" then base = w; break end
  end
  local created
  vim.api.nvim_win_call(base or 0, function()
    vim.cmd("belowright split")
    created = vim.api.nvim_get_current_win()
  end)
  return created
end

--- Returns win if it is still a usable jump target in the current tab.
local function resolve_win(win)
  if not win or not vim.api.nvim_win_is_valid(win) then return nil end
  if not vim.list_contains(vim.api.nvim_tabpage_list_wins(0), win) then return nil end
  return win
end

--- Record the current window when it is an editor window.
--- Driven by a WinLeave autocmd, where the window's buffer has settled, so
--- focus_editor returns to the file the cursor actually left rather than a
--- fixed position in the layout.
function M.track_editor_win()
  local win = vim.api.nvim_get_current_win()
  if is_editor_win(win) then
    vim.t.editor_win_last = win
  end
end

--- Jump to the editor area from anywhere, and back again.
--- A layout with a file tree on one side and a terminal or agent panel on the
--- other needs up to three <C-h>/<C-l> hops to cross back to the middle; this
--- collapses that into one key. Pressing it inside the editor returns to the
--- window it came from, so the same key travels in both directions.
function M.focus_editor()
  local cur = vim.api.nvim_get_current_win()

  if is_editor_win(cur) then
    local origin = resolve_win(vim.t.editor_win_origin)
    if origin == cur then origin = nil end
    -- Nothing recorded yet (the key was first pressed inside the editor), so
    -- behave like `sw` and hand focus to the previous window.
    if not origin then
      local prev = resolve_win(vim.fn.win_getid(vim.fn.winnr('#')))
      if prev ~= cur then origin = prev end
    end
    if origin then
      vim.api.nvim_set_current_win(origin)
    else
      vim.notify('No window to jump back to', vim.log.levels.INFO)
    end
    return
  end

  local target = pick_editor_win()
  if not target then
    vim.notify('No editor window in this tab', vim.log.levels.WARN)
    return
  end
  vim.t.editor_win_origin = cur
  vim.api.nvim_set_current_win(target)
end

--- Equalize window sizes while preserving winfixwidth/winfixheight windows.
--- Runs wincmd = then restores fixed panels to their target sizes.
--- Use on VimResized to redistribute editor space proportionally.
function M.equalize_respecting_fixed()
  local panels = get_fixed_panels()
  vim.cmd("wincmd =")
  for _, entry in ipairs(panels) do
    if vim.api.nvim_win_is_valid(entry.win) then
      if entry.width then
        vim.api.nvim_win_set_width(entry.win, entry.width)
      end
      if entry.height then
        vim.api.nvim_win_set_height(entry.win, entry.height)
      end
    end
  end
end

--- Buffers Nvim would refuse to quit over.
---
--- `getbufinfo()`'s `bufmodified` filter is the raw changed flag, which
--- terminal, scratch and prompt buffers carry permanently. The 'modified'
--- option applies Nvim's own rule instead (`bufIsChanged()`: `nofile`,
--- `nowrite`, `terminal` and `prompt` buffers never count), and that rule is
--- exactly what decides whether `:qall` is refused -- an `acwrite` buffer such
--- as oil's blocks the quit like a file.
local function unsaved_buffers()
  return vim.tbl_filter(function(info)
    return vim.bo[info.bufnr].modified
  end, vim.fn.getbufinfo({ bufmodified = 1 }))
end

--- Refuse the quit here, naming what blocks it, instead of letting `:qall`
--- raise its own E37.
---
--- `:qall` fires `ExitPre` before it looks at modified buffers, and Snacks
--- closes every terminal window from there. So a refused `:qall` already
--- costs the agent panel, and issued from inside that panel Nvim then drops
--- the quit without a word, because the autocommand closed the current
--- window. Issued through `vim.cmd`, the refusal also reaches the user as an
--- E5108 Lua traceback rather than the one-line E37 `:qa` shows, and loses
--- the E162 line that names the buffer.
local function refuse_quit(unsaved)
  local names = vim.tbl_map(function(info)
    return info.name ~= "" and vim.fn.fnamemodify(info.name, ":~:.") or "[No Name]"
  end, unsaved)
  vim.notify(
    "Not quitting: unsaved changes in " .. table.concat(names, ", ")
      .. "\nSave them, or <leader>qQ to quit without saving.",
    vim.log.levels.WARN
  )
end

--- Close the Snacks-managed terminal windows, as ordinary window operations.
---
--- The window is the whole story: Nvim only drops the quit when an autocommand
--- made a window disappear, so a Snacks terminal left merely hidden -- toggled
--- away, buffer still alive -- never blocked it, and the buffers can be left to
--- `ExitPre` as usual. Not deleting them also keeps this out of reach of the
--- textlock that `nvim_buf_delete` can hit in a nested command context.
---
--- All tabpages deliberately: this only runs on the way out of the editor, and
--- a terminal parked in another tab keeps the quit from finishing just as well.
local function close_snacks_terminals()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win)
      and vim.b[vim.api.nvim_win_get_buf(win)].snacks_terminal then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
end

-- Indirection so tests can watch which quit was issued without taking the
-- editor down with them.
M._quit = function(command) vim.cmd(command) end

--- Quit Nvim, including from inside a Snacks terminal window.
---
--- Snacks closes each of its terminal windows from its own `ExitPre`, and Nvim
--- refuses to finish a quit whose autocommands made a window disappear. So a
--- plain `:qall` run from inside one -- the agent panel or a `<C-/>` terminal --
--- closes that terminal and then silently drops the quit, which reads as "the
--- agent exited but Nvim stayed". Closing those windows first, while it is
--- still an ordinary window operation, leaves `ExitPre` with nothing to close.
---
--- The unsaved check comes first because closing the panel is not free, and a
--- quit Nvim is going to refuse must not pay for it. No `:qall` is issued in
--- that case at all: see `refuse_quit` for why Nvim's own refusal is not
--- usable from here.
---
--- Typing `:qa` by hand still takes the upstream path; only these entry points
--- are covered.
---@param force boolean? issue `qall!`, discarding unsaved changes
function M.quit_all(force)
  if not force then
    local unsaved = unsaved_buffers()
    if #unsaved > 0 then
      refuse_quit(unsaved)
      return
    end
  end
  close_snacks_terminals()
  M._quit(force and "qall!" or "qall")
end

return M
