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
  'telescope', 'TelescopePrompt', 'fzf',                     -- Fuzzy finders
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
  local wins = vim.api.nvim_list_wins()
  local table = require("util.common").table

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
        not table(SPECIAL_BUFTYPES):containsValue(info.buftype) and
        not table(SPECIAL_FILETYPES):containsValue(info.filetype) then
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
