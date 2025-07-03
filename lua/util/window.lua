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

return M
