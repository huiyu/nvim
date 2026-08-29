-- Host side of the agent TUI's ctrl+g handoff.
--
-- Both native agents bind ctrl+g to "edit the input box in $EDITOR". With
-- $EDITOR pointed at scripts/agent-editor, that wrapper forwards the temp file
-- here over RPC instead of starting a nested nvim, and blocks until this module
-- says the buffer is closed.
--
-- This is the answer to "the text I already typed in the TUI didn't come
-- across": there is nothing to carry across, because the TUI hands over its own
-- input. Reading it off the screen instead cannot work -- a real newline and a
-- soft wrap render identically (both are a two-space-indented continuation
-- line), so scraped text can never be reassembled reliably.
--
-- This replaced a hand-written composer buffer that started empty and pasted
-- its result into the TUI. Round-tripping the TUI's own buffer removed the need
-- to clear the input box before sending -- leftover text used to be prepended to
-- whatever was sent.
--
-- Images still go through the TUI's own ctrl+v, because only the CLI can put
-- bytes into its request. <C-v> here stages them and replays that keystroke once
-- the CLI is listening again; an image attached in the TUI directly survives the
-- round trip on its own, as a `[Image #N]` placeholder the CLI owns.

local config = require("ai.config")

local M = {}

-- How long to wait after the prompt buffer closes before attaching images.
--
-- The agent is blocked on the wrapper for as long as the buffer is open, and it
-- throws away pty input during that window -- measured: a ctrl+v sent while the
-- editor was open never arrived, the same one sent afterwards did. So the
-- attach has to wait for the CLI to resume and re-read the prompt file. 100ms
-- was still too early and 300ms landed, so this keeps a wide margin while
-- staying under the threshold anyone would notice.
local ATTACH_DELAY_MS = 750

-- The byte both agent TUIs bind to "edit this prompt in $EDITOR". Verified
-- against both CLIs: a bare 0x07 on the pty opens the external editor, and the
-- on-screen hint reads "ctrl+g to edit in <$EDITOR>".
M.EDIT_KEY = "\7"

-- Text to add to the next prompt this Nvim is handed, consumed by the first
-- open() that follows.
--
-- Seeding used to be a bracketed paste sent just ahead of the edit key, on the
-- reasoning that one channel write fixes their order. The bytes do arrive in
-- order, but the TUI applies a paste asynchronously and acts on the key first,
-- so the editor opened on the pre-paste box -- measured: the float came up
-- empty with a Visual selection staged. Handing the text to the buffer instead
-- has no ordering to lose, and needs no paste sanitising.
local pending_seed = nil

---Stage text for the next prompt buffer. Pass nil to stage nothing.
---@param text string?
function M.stage_seed(text)
  pending_seed = (text ~= nil and text ~= "") and text or nil
end

-- Waiting for a freshly started CLI to reach its input box.
--
-- The box being drawn is not the same as input being accepted: Codex painted
-- `› Ask Codex to do anything` while still starting up, and a key sent at that
-- moment was swallowed with no editor to show for it. So readiness has to hold
-- across consecutive polls, and even then the key waits out a short settle.
local READY_POLL_MS = 200
local READY_STABLE_POLLS = 3
local READY_SETTLE_MS = 400
local READY_TIMEOUT_MS = 45000

---True once the agent TUI has drawn its input prompt in `buf`.
---
---This reads the rendered screen -- exactly what this module refuses to do for
---prompt *content*. The difference is what being wrong costs: a missed trigger
---loses one keystroke the user can repeat, while misread content would silently
---corrupt the prompt itself. Claude draws `❯ `, Codex `› `.
---
---A numbered line is one of the CLI's own choice lists (the "do you trust this
---folder?" gate draws `❯ 1. Yes...`), not an input box waiting for text.
---@param buf integer
---@return boolean
function M.tui_ready(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return false end

  -- Matched one marker at a time, never as a character class: Lua patterns work
  -- on bytes, so `[❯›]` would mean "any single byte of those six" and match
  -- neither marker whole.
  for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    for _, marker in ipairs({ "❯", "›" }) do
      -- Nothing may follow the marker. An empty input box renders as the marker
      -- alone, and that is exactly the state a freshly started agent is in --
      -- requiring a space after it made readiness never fire on a cold start.
      if line:match("^%s*" .. marker)
        and not line:match("^%s*" .. marker .. "%s*%d+%.%s")
      then
        return true
      end
    end
  end
  return false
end

---Run `action` once the terminal `get_buf` returns is showing an input prompt.
---
---Starting a CLI takes seconds, and anything sent before its input box exists is
---swallowed with nothing on screen to show for it. Polling replaces the "press
---the key again once it appears" note that used to stand in for this.
---@param get_buf fun(): integer|nil
---@param action fun(buf: integer)
---@param on_timeout fun()
function M.when_ready(get_buf, action, on_timeout)
  local deadline = vim.uv.now() + READY_TIMEOUT_MS
  local stable = 0

  local function tick()
    local buf = get_buf()
    if M.tui_ready(buf) then
      stable = stable + 1
      if stable >= READY_STABLE_POLLS then
        vim.defer_fn(function()
          local ready = get_buf()
          if M.tui_ready(ready) then action(ready) end
        end, READY_SETTLE_MS)
        return
      end
    else
      -- A box that comes and goes is a TUI still painting itself.
      stable = 0
    end

    if vim.uv.now() >= deadline then
      on_timeout()
      return
    end
    vim.defer_fn(tick, READY_POLL_MS)
  end

  tick()
end

-- Staged images are shown as virtual lines rather than buffer text. They must
-- not become part of the prompt: the CLI writes its own `[Image #N]` when the
-- attach happens, and a second marker of ours would be sent along as literal
-- text. Virtual lines are invisible to `:w` for exactly that reason.
local IMAGE_NS = vim.api.nvim_create_namespace("ai_editor_images")

---@param buf integer
---@param images string[]
local function show_staged(buf, images)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  vim.api.nvim_buf_clear_namespace(buf, IMAGE_NS, 0, -1)
  if #images == 0 then return end

  local virt = {}
  for i = 1, #images do
    virt[i] = { { ("  󰋩 image %d — attaches when you return the prompt"):format(i), "Comment" } }
  end
  vim.api.nvim_buf_set_extmark(buf, IMAGE_NS, math.max(vim.api.nvim_buf_line_count(buf) - 1, 0), 0, {
    virt_lines = virt,
  })
end

-- Indirection so tests can observe the handshake without a live agent.
M._release = function(sentinel)
  vim.fn.writefile({ "done" }, sentinel)
end

-- Prompts currently open, keyed by the temp file the agent handed over. Two
-- agents in one Nvim (Claude and Codex side by side) can legitimately have one
-- each, so this is a table rather than a single slot.
local state = { open = {} }

-- Each open gets its own augroup. Naming it after the buffer looked natural but
-- is a trap: `clear = true` means a second open of the SAME file silently
-- deletes the first one's BufWipeout, and that autocmd is the only thing that
-- releases the first wrapper -- leaving its agent TUI blocked forever.
local seq = 0

---Let the blocked wrapper go. Every path out of this module must reach here:
---the wrapper is spinning in a poll loop and the agent TUI is blocked on the
---wrapper, so a missed release hangs the agent, not just this buffer.
---@param sentinel string?
local function release(sentinel)
  if not sentinel or sentinel == "" then return end
  pcall(M._release, sentinel)
end

---@param path string
---@param sentinel string
local function present(path, sentinel)
  -- The float is entered from a :terminal window sitting in Terminal-mode.
  if vim.fn.mode() == "t" then vim.cmd("stopinsert") end

  -- Images staged by <C-v>, and whether the prompt was actually returned.
  -- Cancelling has to drop them: the box keeps its old text, so pushing images
  -- into it would attach them to a prompt the user just threw away.
  local images = {}
  local returned = false

  local buf = vim.fn.bufadd(path)
  vim.fn.bufload(buf)

  -- Consumed unconditionally, so a seed staged for a request that never arrived
  -- cannot leak into an unrelated ctrl+g later on.
  local seed, existing = pending_seed, vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  pending_seed = nil
  if seed then
    local lines = vim.split(seed, "\n", { plain = true })
    -- Appended after whatever was already typed in the box, which is where a
    -- selection belongs: the instruction usually comes first.
    if #existing == 1 and existing[1] == "" then
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    else
      vim.api.nvim_buf_set_lines(buf, -1, -1, false, lines)
    end
  end

  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "markdown"
  -- Turns on @file completion (lua/ai/mention.lua): the blink provider in
  -- lua/plugin/lsp/cmp.lua is gated on this mark, so ordinary markdown
  -- buffers never see project-file candidates.
  vim.b[buf].ai_prompt = true
  -- The agent hands over a real .md file, which puts it under conform's
  -- markdown -> prettier rule (lua/lang/frontend.lua). That rule runs on
  -- BufWritePre, and :w here is exactly how the prompt is handed back -- so
  -- without this opt-out, saving would reflow the prompt before the agent sees
  -- it.
  vim.b[buf].autoformat = false

  seq = seq + 1
  local group = vim.api.nvim_create_augroup(("ai_editor_%d"):format(seq), { clear = true })

  -- `:w` is what returns the prompt, so it is also what decides whether staged
  -- images belong to it.
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    buffer = buf,
    callback = function() returned = true end,
  })

  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    buffer = buf,
    callback = function()
      state.open[path] = nil
      release(sentinel)

      if not returned or #images == 0 then
        for _, png in ipairs(images) do vim.fn.delete(png) end
        return
      end

      -- Captured because `images` is per-open and this runs later.
      local queued = images
      vim.defer_fn(function() require("ai").attach_images(queued) end, ATTACH_DELAY_MS)
    end,
  })

  -- Quitting nvim with the prompt still open would otherwise leave the agent
  -- waiting on an editor that no longer exists.
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function() release(sentinel) end,
  })

  vim.api.nvim_create_autocmd("QuitPre", {
    group = group,
    buffer = buf,
    callback = function()
      if vim.bo[buf].modified then
        vim.notify(
          "Prompt not returned. :wq keeps the edit · :q! or <C-c> leaves the box unchanged",
          vim.log.levels.INFO
        )
      end
    end,
  })

  -- <C-d> against <C-c> reads the way a shell does -- end-of-input against
  -- cancel -- so neither key has to be learned.
  vim.keymap.set({ "n", "i" }, "<C-d>", function()
    if not vim.api.nvim_buf_is_valid(buf) then return end
    vim.cmd("silent write")
    vim.cmd("close")
  end, { buffer = buf, desc = "Return prompt to the agent", silent = true })

  -- Cancel means the box keeps what it had, so the file must stay untouched:
  -- clear 'modified' and let bufhidden = wipe drop the edits.
  vim.keymap.set("n", "<C-c>", function()
    if not vim.api.nvim_buf_is_valid(buf) then return end
    vim.bo[buf].modified = false
    vim.cmd("close")
  end, { buffer = buf, desc = "Discard edit", silent = true, nowait = true })

  -- Same key the TUIs use for image paste, so the habit carries over. Nothing
  -- is written into the buffer: the image cannot travel through the prompt file
  -- (it is plain markdown), and the CLI writes its own `[Image #N]` marker when
  -- the attach finally happens. Adding our own would leave a duplicate behind.
  vim.keymap.set({ "n", "i" }, "<C-v>", function()
    local clipboard = require("ai.clipboard")
    if not clipboard.has_image() then
      vim.notify("No image on the clipboard", vim.log.levels.INFO)
      return
    end
    local png = ("%s/%d-%d.png"):format(clipboard.staging_dir(), buf, #images + 1)
    local ok, err = clipboard.save_image(png)
    if not ok then
      vim.notify(("Could not stage the image: %s"):format(err), vim.log.levels.WARN)
      return
    end
    images[#images + 1] = png
    show_staged(buf, images)
  end, { buffer = buf, desc = "Attach clipboard image", silent = true })

  -- Centred and bounded rather than full-width: a prompt is read as a block,
  -- and the terminal underneath stays visible around it.
  local width = math.min(100, math.floor(vim.o.columns * 0.8))
  local height = math.min(20, math.floor(vim.o.lines * 0.5))
  local win = vim.api.nvim_open_win(buf, true, {
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

  state.open[path] = win

  -- Modal: focus stays here until the prompt is returned or cancelled.
  --
  -- The global <C-h/j/k/l> and <C-\> window keys work from a float too, and
  -- with the agent blocked on the wrapper there is no way back once they fire:
  -- <leader>ai sends ctrl+g into a TUI that is not reading its pty, and the
  -- windows underneath (dashboard, agent panel) have nothing to do while the
  -- prompt is open. So leaving is treated as a slip and undone. Deferred
  -- because the leave has not happened yet when WinLeave fires, and skipped
  -- when the destination is another prompt float -- two agents side by side
  -- may each have one open, and bouncing between them would never settle.
  vim.api.nvim_create_autocmd("WinLeave", {
    group = group,
    buffer = buf,
    callback = function()
      vim.schedule(function()
        if not vim.api.nvim_win_is_valid(win) then return end
        local now = vim.api.nvim_get_current_win()
        if now == win or M.is_prompt_win(now) then return end
        -- Landing in the agent panel put it into Terminal-mode via auto_insert.
        if vim.fn.mode() == "t" then vim.cmd("stopinsert") end
        vim.api.nvim_set_current_win(win)
      end)
    end,
  })

  vim.wo[win].winbar =
    "  <C-d> return to agent   ·   <C-v> image   ·   <C-c> cancel   ·   also ZZ / :wq"
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true

  -- An empty box means a prompt written from scratch; anything else is an edit
  -- of text that already exists, where Normal mode is the useful start.
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  if #lines <= 1 and vim.trim(lines[1] or "") == "" then
    vim.cmd("startinsert!")
  end
end

---Is `win` one of the prompt floats currently open?
---@param win integer
---@return boolean
function M.is_prompt_win(win)
  for _, open in pairs(state.open) do
    if open == win then return true end
  end
  return false
end

---Bring an already-open prompt float back into focus.
---
---The way back after focus slipped out despite the modal guard (a prompt for
---the other agent took it, say). Sending ctrl+g again cannot do this: the TUI
---is blocked on the wrapper and drops pty input for as long as the float is
---open, so <leader>ai checks here first. A Visual selection made in the
---meantime is appended to the prompt the way a seed would have been.
---@param text string? lines to append to the prompt
---@return boolean focused false when no prompt is open
function M.focus_open(text)
  for path, win in pairs(state.open) do
    if vim.api.nvim_win_is_valid(win) then
      if text and text ~= "" then
        local buf = vim.api.nvim_win_get_buf(win)
        vim.api.nvim_buf_set_lines(buf, -1, -1, false, vim.split(text, "\n", { plain = true }))
      end
      if vim.fn.mode() == "t" then vim.cmd("stopinsert") end
      vim.api.nvim_set_current_win(win)
      return true
    end
    state.open[path] = nil
  end
  return false
end

---Open a prompt file handed over by the agent TUI.
---
---Called over RPC from scripts/agent-editor, so the return value goes back to a
---shell. It is a status string, and any failure releases the wrapper before
---returning rather than leaving the agent blocked.
---@param path string     the temp file the agent wants edited
---@param sentinel string file to create once the buffer is closed
---@return string status
function M.open(path, sentinel)
  if type(path) ~= "string" or path == "" then
    release(sentinel)
    return "error: no path"
  end
  if vim.fn.filereadable(path) ~= 1 then
    release(sentinel)
    return "error: not readable"
  end

  -- A prompt already on screen for this same file means a duplicate request.
  -- Opening a second window on it would stack two editors on one buffer, so
  -- surface the one that exists and let the duplicate's wrapper go.
  local open = state.open[path]
  if open and vim.api.nvim_win_is_valid(open) then
    vim.schedule(function()
      if vim.api.nvim_win_is_valid(open) then vim.api.nvim_set_current_win(open) end
    end)
    release(sentinel)
    return "focused"
  end

  -- Off the RPC handler: this opens a window and changes the current buffer,
  -- which is not safe to do while nvim is blocked reading input in the terminal
  -- window the request came from.
  vim.schedule(function()
    local ok, err = pcall(present, path, sentinel)
    if not ok then
      release(sentinel)
      vim.notify(
        ("Could not open the agent prompt: %s"):format(err),
        vim.log.levels.ERROR
      )
    end
  end)

  return "opened"
end

---Path to the $EDITOR wrapper the agent terminals are launched with.
---@return string
function M.wrapper()
  return vim.fn.stdpath("config") .. "/scripts/agent-editor"
end

return M
