local M = {}

-- Toggle Snacks bottom terminal. When a right-side winfixwidth panel (e.g. Claude Code)
-- exists, Snacks' botright split puts the terminal across the full width, squeezing the
-- right panel into a half-height stack. To match the "terminal-first" layout we instead
-- promote the right panel to a full-height column via `wincmd L`, so the terminal ends
-- up only beneath the editor.
function M.toggle(id)
  local opts = { win = { position = "bottom", height = 25 } }
  if id then opts.id = id end

  local term = Snacks.terminal(nil, opts)
  if not term or not term.win or not vim.api.nvim_win_is_valid(term.win) then
    return
  end

  vim.defer_fn(function()
    local term_win = term.win
    if not vim.api.nvim_win_is_valid(term_win) then return end

    local saved_lazyredraw = vim.o.lazyredraw
    vim.o.lazyredraw = true

    local fixed = {}
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if win ~= term_win
          and vim.api.nvim_win_is_valid(win)
          and vim.api.nvim_win_get_config(win).relative == ""
          and vim.wo[win].winfixwidth then
        fixed[#fixed + 1] = win
      end
    end
    if #fixed == 0 then
      vim.o.lazyredraw = saved_lazyredraw
      return
    end

    local was_current = vim.api.nvim_get_current_win()
    for _, win in ipairs(fixed) do
      local width = vim.w[win]._fixed_width_target or vim.api.nvim_win_get_width(win)
      local col = vim.api.nvim_win_get_position(win)[2]
      -- `wincmd L` promotes the window to a full-height rightmost column.
      -- `wincmd H` would do the same on the left. Pick based on current column.
      local cmd = (col * 2 >= vim.o.columns) and "wincmd L" or "wincmd H"
      vim.api.nvim_win_call(win, function() vim.cmd(cmd) end)
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_set_width(win, width)
      end
    end

    vim.schedule(function()
      require("util.window").restore_fixed_panels()
      if vim.api.nvim_win_is_valid(was_current) then
        vim.api.nvim_set_current_win(was_current)
      end
      vim.o.lazyredraw = saved_lazyredraw
      vim.cmd("redraw")
    end)
  end, 10)
end

return M
