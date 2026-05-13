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
-- repaints. edgy's layout reshuffle can leave existing TUIs (notably tmux-
-- wrapped claude) rendered at stale dimensions when a new terminal opens.
local function refresh_terminal_tuis()
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

-- Manual drift fix for TUI :terminal contents (claude in particular).
-- libvterm's grid only invalidates on shrink, not on grow: a height nudge
-- of +1/-1 leaves stale cells untouched, but shrinking forces row truncation
-- which clears the residue. Both nvim_win_set_height calls run in the same
-- event-loop tick, so nvim never paints the intermediate shrunken state —
-- visually the window doesn't move. See issue #2 for the full mechanism.
function M.fix_drift()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_is_valid(win) then
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].buftype == "terminal" then
        local h = vim.api.nvim_win_get_height(win)
        local shrink = math.min(5, h - 1)
        if shrink >= 1 then
          local orig_fh = vim.wo[win].winfixheight
          vim.wo[win].winfixheight = false
          pcall(vim.api.nvim_win_set_height, win, h - shrink)
          pcall(vim.api.nvim_win_set_height, win, h)
          vim.wo[win].winfixheight = orig_fh
        end
      end
    end
  end
end

-- Toggle Snacks bottom terminal. edgy.nvim manages placement and sizing.
function M.toggle(id)
  local opts = { win = { position = "bottom", height = 25 } }
  if id then opts.id = id end
  Snacks.terminal(nil, opts)
  vim.defer_fn(refresh_terminal_tuis, 100)
end

return M
