local M = {}

local pending_drift_fixes = {}

-- Snacks records the original command on every terminal buffer, which is what
-- tells an agent panel from a shell -- and which agent it is. Any configured
-- agent counts, the default or not: both can be running, and each panel keeps
-- its own rules.
---@param buf integer?
---@return string|nil provider
function M.agent_of(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "terminal" then return nil end
  local info = vim.b[buf].snacks_terminal
  return info ~= nil and require("ai.config").provider_of_command(info.cmd) or nil
end

-- Only native coding-agent TUIs need the automatic resize workaround; applying
-- it to plain shell terminals would make every Normal -> Terminal-mode
-- transition flicker.
function M.is_agent_buf(buf)
  return M.agent_of(buf) ~= nil
end

-- Identifies a native AI agent's :terminal window in the current tabpage, if
-- visible. Matches edgy.lua's command-based filter.
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
---Which terminal was last acted on, so <C-/> after closing terminal 3 comes
---back to terminal 3 rather than starting over at 1.
local last_id = nil

-- Floats stack, so showing a second terminal leaves the first sitting behind it.
-- Closing the top one then reveals the other, which reads as jumping between
-- terminals rather than dismissing the one in front of you. Docked terminals do
-- not need this: edgy already gives them one shared slot.
---@param keep integer the terminal that is about to be shown
local function hide_other_floats(keep)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    local info = vim.bo[buf].buftype == "terminal" and vim.b[buf].snacks_terminal
    if
      info
      and info.id
      and info.id ~= keep
      and vim.api.nvim_win_get_config(win).relative ~= ""
      and not M.is_agent_buf(buf)
    then
      local other = Snacks.terminal.get(nil, { count = info.id, create = false })
      if other and other:win_valid() then other:hide() end
    end
  end
end

---@param count integer
---@return table win options for this terminal in the configured shape
local function win_opts_for(count)
  local floating = M.floats()
  local opts = vim.deepcopy(SHAPES[floating and "float" or "bottom"])
  if floating then
    opts.title = float_title(count)
  end
  return opts
end

-- Repair the agent pane after a docked terminal reshuffles the layout (issue
-- #2). Only on open -- close reshuffles too, but the flash isn't worth it. The
-- `defer_fn(..., 0)` lets Snacks' reflow and edgy's autocmd cascade finish
-- first; non-zero delays just add visible flicker. Floats never reflow the
-- window tree, so they need no repair.
---@param before integer terminal-window count before the operation
local function repair_agent_after_dock(before)
  if M.floats() then return end
  vim.defer_fn(function()
    if count_term_wins() > before then
      local agent_win = find_agent_win()
      if agent_win then M.fix_drift(agent_win) end
    end
  end, 0)
end

---Show terminal `count` and put the cursor in it. Never closes anything.
---
---This is what terminal-local `,1`..`,9` do in Normal mode. They choose
---which terminal you are looking at, so pressing its own number has to
---leave it open -- closing is <C-/>'s single job.
---@param count integer
function M.focus(count)
  last_id = count

  local before = count_term_wins()
  hide_other_floats(count)

  local term = Snacks.terminal.get(nil, { count = count, win = win_opts_for(count) })
  if term then
    if not term:win_valid() then term:show() end
    if term:win_valid() then vim.api.nvim_set_current_win(term.win) end
  end

  repair_agent_after_dock(before)
end

---Open or close a terminal -- the only thing that closes one.
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

  count = count or vim.v.count1

  -- Showing but not focused: go to it rather than close it. Dismissing a window
  -- you are not looking at is a surprise, and pressing again -- now from inside
  -- it -- closes it, so nothing is lost.
  local existing = Snacks.terminal.get(nil, { count = count, create = false })
  if
    existing
    and existing:win_valid()
    and vim.api.nvim_get_current_win() ~= existing.win
  then
    M.focus(count)
    return
  end

  last_id = count

  local before = count_term_wins()
  hide_other_floats(count)

  Snacks.terminal(nil, { count = count, win = win_opts_for(count) })

  repair_agent_after_dock(before)
end

-- Box drawing (U+2500-257F) and block elements (U+2580-259F). Rules, table
-- borders and TUI frames (Claude's input box, Codex's "Worked for" rule) fill
-- a row and are followed by another row in column 0: layout, not a wrap.
local FRAME = [[^[─-▟]$]]
-- A rule drawn with one ASCII character, sized to the terminal on purpose:
-- pytest's ===/--- separators fill the width on every run.
local RULE = "([-=_*#~+])%1%1%1"

---Width in cells of the grid behind terminal `buf`. Nvim sizes the pty to
---the widest window showing the buffer, less its number and sign columns
---(measured on 0.12: windows 30 and 49 wide gave a 49-column pty).
---@param buf integer
---@return integer|nil width nil when no window shows the buffer
function M.grid_width(buf)
  local width = 0
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    local info = vim.fn.getwininfo(win)[1]
    if info then width = math.max(width, info.width - info.textoff) end
  end
  return width > 0 and width or nil
end

---Whether terminal row `line` runs on into `next_line` because the terminal
---wrapped it at `width` cells, not because the program wrote a newline.
---
---A terminal buffer keeps one line per grid row and Nvim exposes no wrap
---flag, so this reads the shape a wrap leaves: the row is full -- the next
---row's first character did not fit after it, which lets a wide character
---wrap from the last-but-one cell -- and that character sits in column 0.
---Codex prints a link longer than the pane as one line and leaves the wrap to
---the terminal; its own wrapping, like Claude's, indents the next row.
---
---A newline written at exactly the full width looks the same and is taken for
---a wrap, and so is a program's own word wrap at exactly the width without an
---indent (rich, textwrap), which then glues two words. Rows that fill the
---width on purpose are not: frames, ASCII rules, progress bars, padding,
---tmux copy-mode's position indicator, and a next row led by an emoji (a
---status line). Rows from before a resize are never joined: Nvim reflows only
---what is on screen, and the pty can lag a change of 'number' or 'signcolumn'
---until the window is next resized.
---@param line string
---@param next_line string|nil
---@param width integer|nil
---@return boolean
function M.soft_wraps(line, next_line, width)
  if not width or not next_line or line == "" then return false end
  -- skipcc keeps an emoji's variation selector (⚠️), which makes it wide.
  local first = vim.fn.strcharpart(next_line, 0, 1, 1)
  if first == "" or first:find("^%s") then return false end
  -- A wrapped sentence leaves at most the one space that fell on the last
  -- column; a run of blanks is a TUI painting its background to the edge.
  if line:find("%s%s$") then return false end
  local used = vim.fn.strdisplaywidth(line)
  -- Wider than the grid: an old row from before a resize, never reflowed.
  if used > width or used + vim.fn.strdisplaywidth(first) <= width then return false end
  local last = vim.fn.strcharpart(line, vim.fn.strchars(line) - 1, 1)
  if vim.fn.match(last, FRAME) >= 0 or vim.fn.match(first, FRAME) >= 0 then return false end
  if line:find(RULE .. "$") or next_line:find("^" .. RULE) then return false end
  -- A progress bar is sized to the width: a run of one box or block character
  -- (tqdm's █, rich's ━; a tree's "└──" has only two), or tqdm's whole shape,
  -- which an empty or barely started bar still has.
  if vim.fn.match(line, [[\([─-▟]\)\1\{2,}]]) >= 0 then return false end
  if line:find("%d%%|.*| %S+/%S+ %[[^%]]*%]$") then return false end
  -- Counters pinned to the edge: tmux copy-mode's position, pytest -v's
  -- progress.
  if line:find("%[%d+/%d+%]$") or line:find(" %[%s*%d+%%%]$") then return false end
  return vim.fn.charclass(first) ~= 3
end

---Rejoin a yank from terminal `buf` across rows the terminal wrapped, so a
---long URL or sentence is copied as the program printed it rather than as
---the grid broke it. Runs from TextYankPost (`lua/autocmds.lua`), registered
---before yanky's handler so the ring stores the joined text too.
---@param buf integer
function M.unwrap_yank(buf)
  local event = vim.v.event
  local contents, regname, regtype = event.regcontents, event.regname, event.regtype
  if event.operator ~= "y" or #contents < 2 or (regtype ~= "v" and regtype ~= "V") then return end
  -- An uppercase register appends: setting it again would append the text a
  -- second time. A blockwise yank is columns, not text.
  if regname == "_" or regname:match("^%u$") then return end
  local first = vim.api.nvim_buf_get_mark(buf, "[")[1]
  local last = vim.api.nvim_buf_get_mark(buf, "]")[1]
  local span = last - first + 1
  -- A charwise selection through the end of its last row (v$y, v}y) carries
  -- that row's newline as one more, empty, item.
  local eol = regtype == "v" and #contents == span + 1 and contents[#contents] == ""
  if first < 1 or span < 2 or #contents ~= span + (eol and 1 or 0) then return end
  local rows = vim.api.nvim_buf_get_lines(buf, first - 1, last, false)
  local width = M.grid_width(buf)
  local joined = { contents[1] }
  for i = 2, span do
    if M.soft_wraps(rows[i - 1], rows[i], width) then
      joined[#joined] = joined[#joined] .. contents[i]
    else
      joined[#joined + 1] = contents[i]
    end
  end
  if eol then joined[#joined + 1] = "" end
  if #joined == #contents then return end
  -- Sets "" (with "0) for an unnamed yank, or the register named.
  vim.fn.setreg(regname, joined, regtype)
  -- An unnamed yank under 'clipboard' also went to "+ or "*, and Nvim handed
  -- it to the clipboard provider before this event. setreg("") does not reach
  -- the provider, so the clipboard registers are written again by name. The
  -- provider receives the split text first and the joined text second, as it
  -- does for an explicit "+y through the setreg above.
  -- Without a provider, setreg("+") would repeat the warning Nvim gives once.
  if regname == "" and vim.fn.has("clipboard") == 1 then
    local clipboard = vim.opt.clipboard:get()
    if vim.tbl_contains(clipboard, "unnamedplus") then vim.fn.setreg("+", joined, regtype) end
    if vim.tbl_contains(clipboard, "unnamed") then vim.fn.setreg("*", joined, regtype) end
  end
end

return M
