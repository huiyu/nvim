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

-- Toggle Snacks bottom terminal.
-- The terminal should always span full width at the bottom, with left sidebars
-- (explorer) occupying only the top portion above it. Right-side panels (e.g.
-- Claude Code) should remain full-height, with the terminal only under the editor.
--
-- When a RIGHT-side winfixwidth panel exists, promote it to a full-height column
-- via `wincmd L` so the terminal sits beneath the editor only.
-- Left-side panels are left as-is — botright naturally puts them above the terminal.
function M.toggle(id)
  local opts = { win = { position = "bottom", height = 25 } }
  if id then opts.id = id end

  local term = Snacks.terminal(nil, opts)
  if not term or not term.win or not vim.api.nvim_win_is_valid(term.win) then
    return
  end

  vim.schedule(function()
    local term_win = term.win
    if not term_win or not vim.api.nvim_win_is_valid(term_win) then return end

    -- Only promote RIGHT-side winfixwidth panels to full-height columns.
    -- Left-side panels (explorer) stay partial height so the terminal spans full width.
    local right_fixed = {}
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if win ~= term_win
          and vim.api.nvim_win_is_valid(win)
          and vim.api.nvim_win_get_config(win).relative == ""
          and vim.wo[win].winfixwidth then
        local col = vim.api.nvim_win_get_position(win)[2]
        if col * 2 >= vim.o.columns then
          right_fixed[#right_fixed + 1] = win
        end
      end
    end

    if #right_fixed > 0 then
      local was_current = vim.api.nvim_get_current_win()
      for _, win in ipairs(right_fixed) do
        local width = vim.w[win]._fixed_width_target or vim.api.nvim_win_get_width(win)
        vim.api.nvim_set_current_win(win)
        vim.cmd("wincmd L")
        if vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_win_set_width(win, width)
        end
      end
      if vim.api.nvim_win_is_valid(was_current) then
        vim.api.nvim_set_current_win(was_current)
      end
    end

    require("util.window").restore_fixed_panels()
  end)
end

return M
