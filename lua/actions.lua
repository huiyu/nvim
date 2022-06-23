local M = {}

local telescope_builtins = require("telescope.builtin")
local telescope_default_opts = {
  hidden = true,
  path_display = { "truncate" },
}

function M.find_files()
  telescope_builtins.find_files(get_telescope_theme_opts({ cwd_only = true }))
end

function M.recent_files()
  telescope_builtins.oldfiles(get_telescope_theme_opts({ cwd_only = true }))
end

function M.all_recent_files()
  telescope_builtins.oldfiles(get_telescope_theme_opts())
end

function M.find_text()
  telescope_builtins.live_grep(get_telescope_theme_opts({ cwd_only = true, path_display = { "smart" } }))
end

function M.find_buffers()
  telescope_builtins.buffers(get_telescope_theme_opts({ cwd_only = true }))
end

function M.find_all_buffers()
  telescope_builtins.buffers(get_telescope_theme_opts())
end

function M.find_projects()
  require("telescope._extensions.project.main").project(get_telescope_theme_opts())
end

function M.toggle_explorer()
  vim.api.nvim_command("NvimTreeToggle")
end

function M.toggle_terminal()
  -- direction = 'vertical' | 'horizontal' | 'tab' | 'float'
  vim.api.nvim_command("ToggleTerm")
end

function M.toggle_todos()
  vim.api.nvim_command("TodoTelescope theme=ivy")
end

function M.close_current_window()
  local win_num = #vim.api.nvim_list_wins()
  if win_num == 1 or (win_num == 2 and require("nvim-tree.view").get_winnr() ~= nil) then
    print("Can't close last window")
  else
    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_close(win, false)
  end
end

function M.close_other_windows()
  local wins = vim.api.nvim_list_wins()
  for _, win in ipairs(wins) do
    if win ~= vim.api.nvim_get_current_win() and win ~= require("nvim-tree.view").get_winnr() then
      vim.api.nvim_win_close(win, false)
    end
  end
end

function M.git_next_hunk()
  require("gitsigns").next_hunk()
end

function M.git_prev_hunk()
  require("gitsigns").prev_hunk()
end

function M.git_blame_line()
  require("gitsigns").blame_line()
end

function M.git_status()
  telescope_builtins.git_status(get_telescope_theme_opts())
end

function M.git_branches()
  telescope_builtins.git_branches(get_telescope_theme_opts())
end

function M.git_commits()
  telescope_builtins.git_commits(get_telescope_theme_opts())
end

function M.lsp_code_action()
  vim.api.nvim_command("Lspsaga code_action")
end

function M.lsp_range_code_action()
  vim.api.nvim_command("Lspsaga range_code_action")
end

function M.lsp_formatting()
  vim.lsp.buf.formatting_sync()
end

function M.lsp_rename()
  vim.api.nvim_command("Lsp rename")
end

function M.lsp_definitions()
  telescope_builtins.lsp_definitions(get_telescope_theme_opts())
end

function M.lsp_type_definition()
  telescope_builtins.lsp_type_definitions(get_telescope_theme_opts())
end

function M.lsp_implementations()
  telescope_builtins.lsp_implementations(get_telescope_theme_opts())
end

function M.lsp_references()
  telescope_builtins.lsp_references(get_telescope_theme_opts())
end

function M.lsp_document_symbols()
  telescope_builtins.lsp_document_symbols(get_telescope_theme_opts())
end

function M.lsp_workspace_symbols()
  telescope_builtins.lsp_workspace_symbols(get_telescope_theme_opts())
end

function M.lsp_diagnostics()
  telescope_builtins.lsp_diagnostics(get_telescope_theme_opts())
end

function M.lsp_next_diagnostic()
  vim.lsp.diagnostic.goto_next()
end

function M.lsp_prev_diagnostic()
  vim.lsp.diagnostic.goto_prev()
end

function extend_telescope_opts(opts)
  if opts == nil then
    return telescope_default_opts
  end

  for k, v in pairs(telescope_default_opts) do
    if opts[k] == nil then
      opts[k] = v
    end
  end
  return opts
end

function get_telescope_theme_opts(opts)
  return require("telescope.themes").get_ivy(extend_telescope_opts(opts))
end

return M
