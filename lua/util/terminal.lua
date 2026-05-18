local M = {}

-- DISABLED 2026-05-18 (call site in autocmds.lua is commented out).
--
-- Has a cross-phase line-continuation bug: nvim's paste protocol says
-- lines[1] of phase N continues lines[#] of phase N-1 (chunking is at
-- byte boundaries), but the impl below appends each phase's lines as
-- separate entries — so single-line pastes crossing a phase boundary
-- gain a spurious `\n` at the chunk split.
--
-- Kept for reference during an observation period; delete this function
-- and the call site together if Claude Code paste stays clean.
--
-- Original purpose: coalesce streamed bracketed pastes in :term buffers.
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
