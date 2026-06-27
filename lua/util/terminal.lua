local M = {}

-- Identifies the claude :terminal window in the current tabpage, if visible.
-- Matches edgy.lua's filter: a snacks_terminal buffer whose cmd contains
-- "claude" (claude is wrapped in tmux so the cmd string isn't just "claude").
local function find_claude_win()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].buftype == "terminal" then
      local info = vim.b[buf].snacks_terminal
      if info then
        local cmd = info.cmd
        if type(cmd) == "table" then cmd = table.concat(cmd, " ") end
        if cmd and cmd:match("claude") then return win end
      end
    end
  end
end

-- Drift fix for a :terminal window (claude in particular).
-- libvterm's grid only invalidates on shrink, not on grow. Shrinking forces
-- row truncation, which clears the residue cells; growing back restores the
-- original window size after Ink has fully re-rendered to the shrunken size.
--
-- Uses ex commands (`:resize`) so shrink and grow go through the same code
-- path as a manual :resize. The grow is scheduled via `defer_fn(..., 0)` —
-- not for wall-clock delay, but to push it out of the current synchronous
-- frame so nvim flushes the shrink SIGWINCH (and Ink's re-render in
-- response) before the grow event hits. Empirically 0 is enough; non-zero
-- delays only add a visible flash without improving the fix.
--
-- See issue #2 for the full mechanism.
function M.fix_drift(win)
  win = win or vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_win_get_buf(win)
  if vim.bo[buf].buftype ~= "terminal" then
    vim.notify("fix_drift: target window is not a :terminal", vim.log.levels.WARN)
    return
  end
  local orig_fh = vim.wo[win].winfixheight
  vim.wo[win].winfixheight = false
  vim.api.nvim_win_call(win, function() vim.cmd("noautocmd resize -1") end)
  vim.defer_fn(function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_call(win, function() vim.cmd("noautocmd resize +1") end)
      vim.wo[win].winfixheight = orig_fh
    end
  end, 0)
end

local function count_term_wins()
  local n = 0
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].buftype == "terminal" then n = n + 1 end
  end
  return n
end

-- Toggle Snacks bottom terminal. edgy.nvim manages placement and sizing.
--
-- Opening the bottom terminal reliably drifts the claude pane (see issue #2).
-- We auto-fix only on open — close also reshuffles layout but in practice
-- the visible flash on close isn't worth the cost. Open vs close is inferred
-- from the :terminal window-count delta (Snacks.terminal toggles in place).
-- The `defer_fn(..., 0)` pushes fix_drift to the next event loop tick so
-- Snacks.terminal's reflow + edgy's autocmd cascade finish first; non-zero
-- delays just add visible flicker.
function M.toggle(id)
  local opts = { win = { position = "bottom", height = 25 } }
  if id then opts.id = id end
  local before = count_term_wins()
  Snacks.terminal(nil, opts)
  vim.defer_fn(function()
    if count_term_wins() > before then
      local claude_win = find_claude_win()
      if claude_win then M.fix_drift(claude_win) end
    end
  end, 0)
end

return M
