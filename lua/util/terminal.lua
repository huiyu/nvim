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

-- Manual drift fix for the current :terminal window (claude in particular).
-- libvterm's grid only invalidates on shrink, not on grow. Shrinking forces
-- row truncation, which clears the residue cells; growing back restores the
-- original window size after Ink has fully re-rendered to the shrunken size.
--
-- Uses ex commands (`:resize`) and an explicit 200ms gap between them so the
-- behavior matches what works when typed manually — both commands going
-- through the same code path the user invokes, and enough wall-clock time
-- between them for Ink to fully process the shrink SIGWINCH and stabilize
-- its renderer before the grow event hits.
--
-- See issue #2 for the full mechanism. The 200ms is visible (window briefly
-- smaller) but the alternatives (shorter delays) leave drift artifacts.
function M.fix_drift()
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_win_get_buf(win)
  if vim.bo[buf].buftype ~= "terminal" then
    vim.notify("fix_drift: current window is not a :terminal", vim.log.levels.WARN)
    return
  end
  local orig_fh = vim.wo[win].winfixheight
  vim.wo[win].winfixheight = false
  vim.api.nvim_win_call(win, function() vim.cmd("resize -5") end)
  vim.defer_fn(function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_call(win, function() vim.cmd("resize +5") end)
      vim.wo[win].winfixheight = orig_fh
    end
  end, 200)
end

-- Toggle Snacks bottom terminal. edgy.nvim manages placement and sizing.
function M.toggle(id)
  local opts = { win = { position = "bottom", height = 25 } }
  if id then opts.id = id end
  Snacks.terminal(nil, opts)
end

return M
