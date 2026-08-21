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

local state = { buf = nil, win = nil, images = {} }

-- Stage a clipboard image and mark it in the buffer.
--
-- The image cannot live in the buffer, so what goes in is a placeholder and what
-- goes to the agent is the image itself, replayed through the TUI's own paste
-- mechanism at send time. Staging to a file immediately is required rather than
-- tidy: `clipboard = "unnamedplus"` means the next yank in this buffer would
-- otherwise overwrite the screenshot the user just pasted.
local function paste_image(buf)
  local clipboard = require("ai.clipboard")

  if not clipboard.has_image() then
    vim.notify("No image on the clipboard", vim.log.levels.INFO)
    return
  end

  local index = #state.images + 1
  local path = ("%s/%d-%d.png"):format(clipboard.staging_dir(), buf, index)

  local ok, err = clipboard.save_image(path)
  if not ok then
    vim.notify(("Could not stage the image: %s"):format(err), vim.log.levels.WARN)
    return
  end

  state.images[index] = path

  local marker = ("[image %d]"):format(index)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local line = vim.api.nvim_get_current_line()
  if vim.trim(line) == "" then
    vim.api.nvim_set_current_line(marker)
  else
    vim.api.nvim_buf_set_lines(buf, row, row, false, { marker })
    vim.api.nvim_win_set_cursor(0, { row + 1, #marker })
  end
  vim.bo[buf].modified = true

  vim.notify(("Image %d attached"):format(index), vim.log.levels.INFO)
end


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
  local images = state.images

  state.buf, state.win, state.images = nil, nil, {}

  if not submitted then
    for _, path in ipairs(images) do vim.fn.delete(path) end
    return
  end

  -- An image alone is a legitimate prompt, so blankness only aborts when there
  -- is nothing attached either.
  if blank(text) and #images == 0 then
    vim.notify("Empty prompt; nothing sent", vim.log.levels.INFO)
    return
  end

  M._send(text, {
    submit = true,
    focus = true,
    images = images,
    on_error = function(reason)
      orphaned_draft = text
      vim.notify(
        ("%s -- draft kept, reopen the composer to recover it"):format(reason),
        vim.log.levels.WARN
      )
    end,
  })
end

---Tear the composer down. Whether anything is sent is decided by the
---`ai_composer_submitted` flag, which BufWipeout reads.
---@param buf integer
function M.close(buf)
  -- Capture the window before anything can clear the module state: wiping the
  -- buffer fires BufWipeout, which resets it.
  local win = state.win

  -- Close the *window*, not the buffer. `bufhidden = "wipe"` then takes the
  -- buffer with it and fires BufWipeout. Deleting the buffer first leaves the
  -- float on screen showing whatever Nvim decides to put there instead, which
  -- is exactly the "it closed but the window stayed" symptom.
  if
    win
    and vim.api.nvim_win_is_valid(win)
    and vim.api.nvim_win_get_buf(win) == buf
  then
    pcall(vim.api.nvim_win_close, win, true)
  end

  -- Fallback for the case where the window could not be closed -- for instance
  -- if it were somehow the last one in the tab.
  if vim.api.nvim_buf_is_valid(buf) then
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end
end

---Throw the current draft away and close the composer.
---@param buf integer
function M.discard(buf)
  if vim.api.nvim_buf_is_valid(buf) then
    vim.b[buf].ai_composer_submitted = nil
    vim.bo[buf].modified = false
  end
  M.close(buf)
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
  vim.keymap.set("n", "<C-c>", function() M.discard(buf) end,
    { buffer = buf, desc = "Discard prompt", silent = true, nowait = true })

  -- Send without leaving Insert first. `:wq` and `ZZ` both work, but both need
  -- Normal mode, and a prompt is finished in Insert.
  --
  -- <C-d> pairs with the <C-c> above the way a shell does -- cancel and
  -- end-of-input -- so neither key has to be learned. <C-s> would read better
  -- still, but it cannot arrive: it is this machine's tmux prefix
  -- (~/.config/tmux/tmux.conf:29), so tmux consumes it before Nvim sees it.
  --
  -- The cost is Insert-mode dedent inside this float only.
  vim.keymap.set({ "n", "i" }, "<C-d>", function()
    if vim.api.nvim_buf_is_valid(buf) then
      vim.b[buf].ai_composer_submitted = true
      vim.bo[buf].modified = false
    end
    M.close(buf)
  end, { buffer = buf, desc = "Send prompt", silent = true })

  -- Same key the agent TUIs use for image paste, so the muscle memory carries
  -- over. Bound in Insert mode too because that is where a prompt is written.
  vim.keymap.set({ "n", "i" }, "<C-v>", function() paste_image(buf) end,
    { buffer = buf, desc = "Attach clipboard image", silent = true })

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

  vim.wo[state.win].winbar =
    "  <C-d> send   ·   <C-v> image   ·   <C-c> discard   ·   also ZZ / :wq / :q!"
  vim.wo[state.win].wrap = true
  vim.wo[state.win].linebreak = true

  vim.cmd("startinsert!")
end

return M
