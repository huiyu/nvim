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

-- Snacks does not move the cursor into a window it reopens, so a shape switch
-- would leave the float on screen with the cursor still behind it.
local function focus(term)
  if term and term:win_valid() then
    vim.api.nvim_set_current_win(term.win)
  end
end

-- Tell edgy whether this terminal is floating.
--
-- edgy claims every non-agent `snacks_terminal` for its bottom edge and would
-- otherwise dock the float the moment it opens. It asks about a buffer, and
-- asks while the window is still being built, so the answer lives on the
-- buffer rather than being read off the window.
local function mark_shape(term)
  if term and term.buf and vim.api.nvim_buf_is_valid(term.buf) then
    vim.b[term.buf].terminal_floating = term.opts.position == "float"
  end
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
  local term = Snacks.terminal(nil, opts)

  if term and term.buf and vim.api.nvim_buf_is_valid(term.buf) then
    mark_shape(term)
  end
  vim.defer_fn(function()
    if count_term_wins() > before then
      local agent_win = find_agent_win()
      if agent_win then M.fix_drift(agent_win) end
    end
  end, 0)
end

-- Float or unfloat a terminal.
--
-- One terminal, two shapes -- not two terminals. The shell, buffer and job are
-- untouched; only the window Snacks draws for it changes.
--
-- The shape is stored in the Snacks window's own `opts`, which it reads at show
-- time (`snacks/win.lua` M:show -> M:win_opts). That is what makes the shape
-- stick across every hide/show cycle without a parallel record of our own, and
-- what lets a terminal be *created* already floating rather than being opened
-- at the bottom and converted afterwards -- the conversion is what made the
-- bottom flash into view first.
--
-- Which terminal: the one you are sitting in, or `vim.v.count1` otherwise. So
-- <leader>Tf floats terminal 1 from the editor, 3<leader>Tf floats terminal 3,
-- and pressing it inside a terminal always acts on that terminal.

-- Every key either shape sets, so switching cannot leave the other one's
-- geometry behind.
local SHAPE_KEYS = { "position", "width", "height", "row", "col", "border", "title", "title_pos", "b" }

-- `b` is not decoration. Snacks applies `opts.b` to the buffer inside `show()`
-- *before* it opens the window (snacks/win.lua: open_buf, then the b loop, then
-- the window). edgy inspects the buffer while the window is being built, so
-- marking afterwards is too late -- it docks the float first, which is exactly
-- what made a freshly floated terminal snap back to the bottom.
local SHAPES = {
  bottom = {
    position = "bottom",
    height = 25,
    b = { terminal_floating = false },
  },
  float = {
    position = "float",
    width = 0.85,
    height = 0.8,
    border = "rounded",
    title = " Terminal ",
    title_pos = "center",
    b = { terminal_floating = true },
  },
}

---@param buf integer
---@return boolean
function M.is_float_buf(buf)
  return vim.b[buf].terminal_floating == true
end

local function is_terminal_win(win)
  local buf = vim.api.nvim_win_get_buf(win)
  return vim.bo[buf].buftype == "terminal" and vim.b[buf].snacks_terminal ~= nil
end

---Toggle whether a terminal is floating.
---@param count integer? which terminal; defaults to the current one, else v:count1
function M.toggle_float(count)
  local win = vim.api.nvim_get_current_win()

  local id
  if is_terminal_win(win) then
    -- Acting on the terminal under the cursor needs no lookup: you asked about
    -- *this* one, whatever number it happens to be.
    local info = vim.b[vim.api.nvim_win_get_buf(win)].snacks_terminal
    id = info and info.id
  end
  id = id or count or vim.v.count1

  -- Ask without creating, so a terminal that does not exist yet can be born
  -- floating instead of appearing docked and being moved a frame later.
  local term = Snacks.terminal.get(nil, { count = id, create = false })

  if not term then
    term = Snacks.terminal.get(nil, { count = id, win = vim.deepcopy(SHAPES.float) })
    mark_shape(term)
    focus(term)
    return term
  end

  local shape = term.opts.position == "float" and SHAPES.bottom or SHAPES.float
  for _, key in ipairs(SHAPE_KEYS) do
    term.opts[key] = vim.deepcopy(shape[key])
  end

  -- Snacks builds the window from these opts when it opens one, so reopening is
  -- how the new shape takes effect. The buffer and its job are not involved.
  if term:win_valid() then term:hide() end
  term:show()
  mark_shape(term)
  focus(term)

  return term
end

return M
