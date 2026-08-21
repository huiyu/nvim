-- A scratch buffer for composing an agent prompt with the full editor.
--
-- Why this exists: the agent TUI's input box is a single-line-ish field, and
-- Nvim claims <C-h/j/k/l> in Terminal-mode for window navigation
-- (lua/mappings.lua:102-116), which are exactly the TUI's editing keys. Rather
-- than fight over keys, hand the whole job to a real buffer.
--
-- Submit semantics are `git commit`'s, and `buftype=acwrite` is what implements
-- them without inventing a mapping:
--
--   :w / :wq / ZZ   BufWriteCmd fires -> marked submitted -> sent on wipeout
--   :q!             BufWriteCmd never fires -> nothing is sent
--   :q with text    refused with E37 because 'modified' is set
--   blank buffer    discarded with a notice, exactly like an empty commit
--
-- The usage hint lives in the window's winbar, never in the buffer. `git commit`
-- puts instructions in the file and strips `#` lines afterwards; that is not
-- safe here because prompts legitimately contain `#` (markdown headings, shell
-- comments, issue references), and a stripping rule would silently eat them.

local config = require("ai.config")

local M = {}

-- Indirection so tests can capture sends without a live agent.
M._send = function(text, opts)
  require("ai").send_text(text, opts)
end

-- A draft whose send failed, held for the next open(). Delivery is asynchronous,
-- so by the time a failure is known the buffer is already gone -- without this
-- the text would simply be lost (UC-8).
local orphaned_draft = nil

local state = { buf = nil, win = nil }

local function is_open()
  return state.buf ~= nil and vim.api.nvim_buf_is_valid(state.buf)
end

local function blank(text)
  return vim.trim(text) == ""
end

local function finish(buf)
  local submitted = vim.b[buf] and vim.b[buf].ai_composer_submitted
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local text = table.concat(lines, "\n")

  state.buf, state.win = nil, nil

  if not submitted then return end
  if blank(text) then
    vim.notify("Empty prompt; nothing sent", vim.log.levels.INFO)
    return
  end

  M._send(text, {
    submit = true,
    focus = true,
    on_error = function(reason)
      orphaned_draft = text
      vim.notify(
        ("%s -- draft kept, reopen the composer to recover it"):format(reason),
        vim.log.levels.WARN
      )
    end,
  })
end

---Open the prompt composer. Focuses an already-open one rather than stacking.
---@param seed string? initial buffer content
function M.open(seed)
  if is_open() then
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      vim.api.nvim_set_current_win(state.win)
    end
    return
  end

  -- A draft that failed to send outranks an empty open, but not an explicit
  -- seed: an explicit seed is a fresh intent.
  if not seed and orphaned_draft then
    seed = orphaned_draft
    orphaned_draft = nil
  end

  local buf = vim.api.nvim_create_buf(false, false)
  state.buf = buf

  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  -- Markdown highlighting is worth having: prompts are written in it. But the
  -- filetype also opts this buffer into conform's markdown -> prettier rule
  -- (lua/lang/frontend.lua:48), and conform triggers on BufWritePre -- which
  -- `:w` fires here. Formatting a prompt before sending it would silently
  -- rewrite list markers and reflow lines the user chose. Use conform's own
  -- documented per-buffer opt-out.
  vim.bo[buf].filetype = "markdown"
  vim.b[buf].autoformat = false
  -- A name is required for :w to have a target at all, and it is what the
  -- statusline shows. Nothing is ever written to this path.
  vim.api.nvim_buf_set_name(buf, ("ai://compose/%s"):format(buf))

  if seed and seed ~= "" then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(seed, "\n", { plain = true }))
  end

  local group = vim.api.nvim_create_augroup("ai_composer_" .. buf, { clear = true })

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    group = group,
    buffer = buf,
    callback = function()
      vim.b[buf].ai_composer_submitted = true
      -- Clearing 'modified' is what lets the following :q succeed. Nothing
      -- touches the filesystem.
      vim.bo[buf].modified = false
    end,
  })

  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    buffer = buf,
    callback = function() finish(buf) end,
  })

  -- `:q` on a modified acwrite buffer raises E37, which protects a half-written
  -- prompt but explains nothing. Say what the ways out actually are.
  vim.api.nvim_create_autocmd("QuitPre", {
    group = group,
    buffer = buf,
    callback = function()
      if vim.bo[buf].modified then
        vim.notify(
          "Prompt not sent. :wq sends · :q! or <C-c> discards",
          vim.log.levels.INFO
        )
      end
    end,
  })

  -- Normal-mode only. <C-c> is globally bound in Insert mode to leave Insert
  -- (lua/mappings.lua:61) and that meaning must survive here, so discarding
  -- takes <C-c> twice from Insert: once to leave, once to close.
  vim.keymap.set("n", "<C-c>", function()
    vim.b[buf].ai_composer_submitted = nil
    vim.bo[buf].modified = false
    vim.api.nvim_buf_delete(buf, { force = false })
  end, { buffer = buf, desc = "Discard prompt", silent = true, nowait = true })

  local width = math.min(100, math.floor(vim.o.columns * 0.8))
  local height = math.min(20, math.floor(vim.o.lines * 0.5))
  state.win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = (" Prompt · %s "):format(config.label),
    title_pos = "center",
  })

  vim.wo[state.win].winbar = "  :wq send   ·   <C-c> / :q! discard   ·   empty discards"
  vim.wo[state.win].wrap = true
  vim.wo[state.win].linebreak = true

  vim.cmd("startinsert!")
end

return M
