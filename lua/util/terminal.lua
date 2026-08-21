local M = {}

local pending_drift_fixes = {}

-- Snacks records the original command on every terminal buffer. Only native
-- coding-agent TUIs need the automatic resize workaround; applying it to plain
-- shell terminals would make every Normal -> Terminal-mode transition flicker.
function M.is_agent_buf(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "terminal" then return false end
  local info = vim.b[buf].snacks_terminal
  return info ~= nil and require("ai.config").is_native_command(info.cmd)
end

-- Identifies the selected native AI agent's :terminal window in the current
-- tabpage, if visible. Matches edgy.lua's command-based filter.
local function find_agent_win()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if M.is_agent_buf(buf) then return win end
  end
end

local RESTORE_DELAY_MS = 25

-- Drift fix for a native-agent :terminal window.
-- libvterm's grid only invalidates on shrink, not on grow. Shrinking forces
-- row truncation, which clears the residue cells; growing back restores the
-- original window size after the child TUI has re-rendered to the shrunken size.
--
-- The grow needs real wall-clock delay, not just a hop to the next event-loop
-- tick. Nvim pushes a terminal window's new size down to the pty asynchronously
-- on its internal terminal refresh timer (~10ms). That path is not the redraw
-- path, so forcing `:redraw` does not trigger it either. With `defer_fn(..., 0)`
-- the grow lands before the timer ever fires, so nvim's terminal layer only
-- observes the original size: no pty resize, no SIGWINCH, no TUI repaint. The
-- shrink must survive at least one refresh tick to be seen at all.
--
-- Measured against a child that logs every SIGWINCH: 0ms never propagates,
-- >=10ms always does. 25ms keeps margin over timer jitter while staying short
-- enough that the one-row dip is barely visible.
--
-- Opening the bottom terminal spans several ticks of Snacks reflow and edgy
-- layout, but a manual repair has no such padding. Keeping the shrink alive for
-- 25ms makes both call paths reliably reach the pty.
--
-- See issue #2 for the full mechanism.
function M.fix_drift(win)
  win = win or vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(win) then return false end
  local buf = vim.api.nvim_win_get_buf(win)
  if vim.bo[buf].buftype ~= "terminal" then
    vim.notify("fix_drift: target window is not a :terminal", vim.log.levels.WARN)
    return false
  end
  if pending_drift_fixes[win] then return true end

  local height = vim.api.nvim_win_get_height(win)
  if height <= 1 then return false end
  local orig_fh = vim.wo[win].winfixheight
  vim.wo[win].winfixheight = false

  -- Use the window API instead of `:resize`. The Ex command can enter a buffer
  -- modification path while a non-modifiable terminal buffer is current and
  -- fail with E21. nvim_win_set_height only changes the window geometry while
  -- still sending the same SIGWINCH that makes the TUI redraw.
  local ok, err = pcall(vim.api.nvim_win_set_height, win, height - 1)
  if not ok then
    vim.wo[win].winfixheight = orig_fh
    vim.notify("Could not fix terminal TUI drift: " .. tostring(err), vim.log.levels.WARN)
    return false
  end

  pending_drift_fixes[win] = true
  vim.defer_fn(function()
    pending_drift_fixes[win] = nil
    if vim.api.nvim_win_is_valid(win) then
      -- Restore relatively, matching `:resize +1` if some other layout change
      -- happened between the two event-loop ticks.
      local current_height = vim.api.nvim_win_get_height(win)
      pcall(vim.api.nvim_win_set_height, win, current_height + 1)
      vim.wo[win].winfixheight = orig_fh
    end
  end, RESTORE_DELAY_MS)
  return true
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
--
-- Terminals are identified by `count`, not by a name. Snacks derives a
-- terminal's identity from cmd/cwd/env/count only (`M.tid` in
-- snacks/terminal.lua); `opts.id` is accepted by the caller and never read, so
-- passing distinct name strings silently returns one shared terminal.
---@param count integer? which terminal; nil means `vim.v.count1`, i.e. 1
function M.toggle(count)
  local opts = { count = count, win = { position = "bottom", height = 25 } }
  local before = count_term_wins()
  Snacks.terminal(nil, opts)
  vim.defer_fn(function()
    if count_term_wins() > before then
      local agent_win = find_agent_win()
      if agent_win then M.fix_drift(agent_win) end
    end
  end, 0)
end

-- Toggle a floating scratch terminal.
--
-- Separate from the bottom terminals on purpose: this one is for a quick
-- command you want gone again, so it should not take a share of the layout.
-- Being a float is also why it needs no fix_drift -- it overlays the window
-- tree instead of reflowing it, so the agent pane never resizes.
--
-- The session survives hiding: toggling brings the same shell back with its
-- scrollback and working directory intact.
-- Well clear of the 1-9 the bottom terminals use. Identity comes from `count`,
-- and the win config takes no part in it, so without a reserved number this
-- would resolve to an existing bottom terminal and open there instead.
local FLOAT_COUNT = 100

function M.toggle_float()
  local term = Snacks.terminal.toggle(nil, {
    count = FLOAT_COUNT,
    win = {
      position = "float",
      width = 0.85,
      height = 0.8,
      border = "rounded",
      title = " Terminal ",
      title_pos = "center",
    },
  })

  if not term or not term.buf or not vim.api.nvim_buf_is_valid(term.buf) then
    return term
  end

  -- <C-/> already means "toggle the terminal" in Terminal-mode, but the global
  -- mapping targets the bottom one. Shadow it here so the chord consistently
  -- toggles whichever terminal you are actually sitting in.
  for _, lhs in ipairs({ "<C-/>", "<C-_>" }) do
    vim.keymap.set("t", lhs, function() M.toggle_float() end, {
      buffer = term.buf,
      desc = "Hide floating terminal",
      silent = true,
    })
  end

  return term
end

return M
