local M = {}

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
---the grid broke it. Runs from TextYankPost (`local-plugin/editor-core.nvim/lua/editor_core/autocmds.lua`), registered
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
