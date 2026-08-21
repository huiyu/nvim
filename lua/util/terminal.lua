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

-- Where terminals open. One shape, chosen once -- not switchable at runtime.
--
-- Snacks decides a window's shape when it opens one, and edgy decides whether a
-- terminal belongs to its bottom edge; making the shape switchable meant keeping
-- those two in agreement across every hide, show and relayout, and that proved
-- more trouble than the feature was worth.
--
-- Override in init.lua, matching the vim.g.*_wrap_tmux precedent:
--   vim.g.terminal_position = "bottom"
---@return "float"|"bottom"
local function position()
  return vim.g.terminal_position == "bottom" and "bottom" or "float"
end

-- A float has no tabline or statusline to say which terminal it is, and Snacks
-- deliberately leaves float titles empty (`snacks/terminal.lua`: the id-prefixed
-- title is built only for docked positions). With several terminals open that
-- makes them indistinguishable, so the number goes in the border title.
---@param count integer
local function float_title(count)
  return (" Terminal %d "):format(count)
end

local SHAPES = {
  bottom = { position = "bottom", height = 25 },
  float = {
    position = "float",
    width = 0.85,
    height = 0.8,
    border = "rounded",
    title_pos = "center",
  },
}

-- Shells announce the running command through an OSC title sequence, which Nvim
-- surfaces as `b:term_title`. Reflecting it means the float says what is running
-- in it, not just which number it is.
vim.api.nvim_create_autocmd("TermRequest", {
  group = vim.api.nvim_create_augroup("terminal_float_title", { clear = true }),
  callback = function(ev)
    local info = vim.b[ev.buf].snacks_terminal
    if not info or not info.id then return end

    -- Deferred: TermRequest fires as the escape sequence arrives, before Nvim
    -- has finished writing `b:term_title`. Reading it here would always see the
    -- previous value.
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(ev.buf) then return end
      local win = vim.fn.bufwinid(ev.buf)
      if win == -1 then return end
      local ok, config = pcall(vim.api.nvim_win_get_config, win)
      if not ok or config.relative == "" then return end

      local label = float_title(info.id)
      local running = vim.b[ev.buf].term_title
      if type(running) == "string" and vim.trim(running) ~= "" then
        label = ("%s· %s "):format(label, vim.trim(running))
      end
      pcall(vim.api.nvim_win_set_config, win, { title = label, title_pos = "center" })
    end)
  end,
})

---Do terminals float in this configuration?
---
---edgy asks this: it claims every non-agent `snacks_terminal` for its bottom
---edge, which would drag a float into the layout the moment it opens.
---@return boolean
function M.floats()
  return position() == "float"
end

-- Toggle Snacks terminal `count`. edgy.nvim manages placement when docked.
--
-- Opening a docked terminal reliably drifts the claude pane (see issue #2). We
-- auto-fix only on open -- close also reshuffles layout but in practice the
-- visible flash on close isn't worth the cost. Open vs close is inferred from
-- the :terminal window-count delta (Snacks.terminal toggles in place). The
-- `defer_fn(..., 0)` pushes fix_drift to the next event loop tick so
-- Snacks.terminal's reflow + edgy's autocmd cascade finish first; non-zero
-- delays just add visible flicker. A float never reflows the window tree, so it
-- needs no repair.
--
-- Terminals are identified by `count`, not by a name. Snacks derives a
-- terminal's identity from cmd/cwd/env/count only (`M.tid` in
-- snacks/terminal.lua); `opts.id` is accepted by the caller and never read, so
-- passing distinct name strings silently returns one shared terminal.
---Which terminal an unnumbered toggle last acted on, so closing terminal 3 and
---reopening returns to terminal 3 rather than starting over at 1.
local last_id = nil

---@param count integer? which terminal; nil resolves to the current one, an
---explicit v:count, or the one you were last in
function M.toggle(count)
  if not count then
    local buf = vim.api.nvim_get_current_buf()
    local info = vim.bo[buf].buftype == "terminal" and vim.b[buf].snacks_terminal

    if info and info.id then
      -- Sitting in a terminal: this is the one you mean. Without it, an
      -- unnumbered toggle always meant terminal 1, so pressing it inside
      -- terminal 3 dismissed a different terminal entirely.
      count = info.id
    elseif vim.v.count > 0 then
      -- `3<C-/>`. v:count is 0 when nothing was typed, which is the only way to
      -- tell a deliberate "1" from no count at all.
      count = vim.v.count
    else
      count = last_id
    end
  end

  last_id = count or vim.v.count1

  local floating = M.floats()
  local before = count_term_wins()

  -- Floats stack, so opening a second terminal leaves the first sitting behind
  -- it. Closing the top one then reveals the other, which reads as jumping
  -- between terminals rather than dismissing the one in front of you. Docked
  -- terminals do not need this -- edgy already gives them one shared slot.
  if floating then
    local target = count or vim.v.count1
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      local buf = vim.api.nvim_win_get_buf(win)
      local info = vim.bo[buf].buftype == "terminal" and vim.b[buf].snacks_terminal
      if
        info
        and info.id
        and info.id ~= target
        and vim.api.nvim_win_get_config(win).relative ~= ""
        and not M.is_agent_buf(buf)
      then
        local other = Snacks.terminal.get(nil, { count = info.id, create = false })
        if other and other:win_valid() then other:hide() end
      end
    end
  end

  local win_opts = vim.deepcopy(SHAPES[floating and "float" or "bottom"])
  if floating then
    -- Snacks resolves an absent count to v:count1, so resolve it the same way
    -- here or the title would disagree with the terminal it labels.
    win_opts.title = float_title(count or vim.v.count1)
  end

  Snacks.terminal(nil, { count = count, win = win_opts })

  if floating then return end

  vim.defer_fn(function()
    if count_term_wins() > before then
      local agent_win = find_agent_win()
      if agent_win then M.fix_drift(agent_win) end
    end
  end, 0)
end

return M
