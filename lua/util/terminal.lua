local M = {}

-- Coalesce streamed bracketed pastes in :term buffers.
--
-- nvim's TUI splits bracketed pastes larger than ~64KB across multiple
-- vim.paste() invocations (phase 1 start, 2 continue, 3 end) and the default
-- impl emits one chansend per phase. TUIs like Claude Code interpret each
-- chansend as a separate paste event, producing fragmented output like
-- `[Pasted text #1][Pasted text #5]...` with raw characters leaking between.
--
-- We override vim.paste only for terminal buffers: single-chunk pastes
-- (phase == -1) pass through unchanged, while streamed phases are buffered
-- and handed back to the default impl as one phase=-1 call. All bracketed-
-- paste marker emission and line-ending handling stays owned by the
-- default implementation.
function M.setup_paste_coalesce()
  local chunks = {}
  local orig_paste = vim.paste
  vim.paste = function(lines, phase)
    if vim.bo.buftype ~= "terminal" or phase == -1 then
      return orig_paste(lines, phase)
    end
    if phase == 1 then chunks = {} end
    for _, line in ipairs(lines) do chunks[#chunks + 1] = line end
    if phase == 3 then
      local buffered = chunks
      chunks = {}
      return orig_paste(buffered, -1)
    end
    return true
  end
end

-- Nudge all terminal windows by 1 row so the TUI inside emits a SIGWINCH and
-- repaints. Used after events that can leave TUIs (claude, lazygit, etc.)
-- rendered at stale dimensions: a new bottom terminal opening (edgy reshuffle),
-- or macOS sleep/wake where the resize chain can drop events between the host
-- terminal, nvim, and the inner TUI.
function M.refresh_terminal_tuis()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_is_valid(win) then
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].buftype == "terminal" then
        local orig_fh = vim.wo[win].winfixheight
        vim.wo[win].winfixheight = false
        local h = vim.api.nvim_win_get_height(win)
        if h > 1 then
          pcall(vim.api.nvim_win_set_height, win, h - 1)
          pcall(vim.api.nvim_win_set_height, win, h)
        end
        vim.wo[win].winfixheight = orig_fh
      end
    end
  end
end

-- Toggle Snacks bottom terminal. edgy.nvim manages placement and sizing.
function M.toggle(id)
  local opts = { win = { position = "bottom", height = 25 } }
  if id then opts.id = id end
  Snacks.terminal(nil, opts)
  vim.defer_fn(M.refresh_terminal_tuis, 100)
end

return M
