local M = {}


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

local function get_win_info(win_id)
  local buf_id = vim.api.nvim_win_get_buf(win_id)

  return {
    is_valid = vim.api.nvim_win_is_valid(win_id),
    is_current = ((win_id) == vim.api.nvim_get_current_win()),
    is_preview = vim.wo[win_id].previewwindow,
    is_modifiable = vim.bo[buf_id].modifiable,
    filetype = vim.bo[buf_id].filetype,
    buftype = vim.bo[buf_id].buftype,
  }
end

function M.close_current()
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_close(win, false)
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
    if info.is_modifiable and
        not info.is_current and
        not info.is_preview and
        not vim.list_contains(SPECIAL_BUFTYPES, info.buftype) and
        not vim.list_contains(SPECIAL_FILETYPES, info.filetype) then
      -- Close the window if it meets all the criteria
      vim.api.nvim_win_close(win, false)
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
    -- behave like <leader>ww and hand focus to the previous window.
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

return M
