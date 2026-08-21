-- Move the current line, or the selection, up and down.
--
-- Alt belongs to tmux on this setup (`bind -n M-h/j/k/l` for pane navigation),
-- so the LazyVim default <A-j>/<A-k> never reached Nvim -- see huiyu/nvim#12.
-- Moving to <leader> costs a keystroke per move, which is the wrong trade for
-- something usually done several times in a row.
--
-- So the first move is <leader>mj / <leader>mk, and after it bare j and k keep
-- moving until you press anything else. Repeating is one keystroke, and no
-- top-level j/k is spent to get it.

local M = {}

-- Injectable so the repeat loop can be driven in tests; `getcharstr` blocks on
-- real input, which a headless run never supplies.
M._getchar = vim.fn.getcharstr

---One move, in Normal or Visual mode.
---@param direction "up"|"down"
---@param visual boolean
---@param count integer
local function step(direction, visual, count)
  if visual then
    -- `:m` needs the '< and '> marks, which only exist outside Visual mode, so
    -- gv restores the selection afterwards and = reindents what moved.
    local range = direction == "down"
      and ("'<,'>move '>+%d"):format(count)
      or ("'<,'>move '<-%d"):format(count + 1)
    vim.cmd(range)
    vim.cmd("normal! gv=gv")
  else
    local target = direction == "down"
      and ("move .+%d"):format(count)
      or ("move .-%d"):format(count + 1)
    vim.cmd(target)
    vim.cmd("normal! ==")
  end
end

---Move, then keep moving while j/k are pressed.
---
---Anything else ends the run and is fed back, so `<leader>mjjjw` moves three
---lines and then jumps a word -- the trailing key is never swallowed.
---@param direction "up"|"down"
function M.run(direction)
  local visual = vim.fn.mode():sub(1, 1):match("[vV\22]") ~= nil
  local count = vim.v.count1

  -- Leave Visual mode so '< and '> are set; gv inside step() brings it back.
  if visual then
    vim.cmd("normal! \27")
  end

  local ok, err = pcall(step, direction, visual, count)
  if not ok then
    -- Hitting the first or last line is a normal outcome, not a failure worth
    -- a stack trace.
    vim.notify(tostring(err):gsub(".*:E%d+: ", ""), vim.log.levels.INFO)
    return
  end

  while true do
    vim.cmd("redraw")

    local got, char = pcall(M._getchar)
    if not got or char == "" or char == "\27" then return end

    if char == "j" or char == "k" then
      -- Each repeat moves one line: the count applied to the first move is a
      -- distance, not a rate.
      local moved = pcall(step, char == "j" and "down" or "up", visual, 1)
      if not moved then return end
    else
      -- Not ours. Give it back rather than eating it.
      vim.api.nvim_feedkeys(char, "n", false)
      return
    end
  end
end

return M
