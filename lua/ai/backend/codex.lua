local ai_config = require("ai.config")

local M = {}

local current
local tmux_watchdog_started = false

-- Codex uses synchronized terminal updates for each TUI frame. Neovim's
-- libvterm does not implement that protocol, so let a dedicated tmux server
-- compose the frame before it reaches :terminal. Precedence: env > vim.g > on.
local function should_wrap_tmux()
  local env = vim.env.CODEX_WRAP_TMUX
  if env == "1" or env == "true" then return true end
  if env == "0" or env == "false" then return false end
  return vim.g.codex_wrap_tmux ~= false
end

-- A detached watchdog covers abrupt host-terminal closure, where tmux's
-- client-detached hook may not run. It also removes stale wrapper sockets from
-- earlier crashes. Start it on first use because this backend loads lazily,
-- after VimEnter has already fired.
local function ensure_tmux_watchdog()
  if tmux_watchdog_started then return end
  tmux_watchdog_started = true

  local pid = vim.fn.getpid()
  local script = string.format([[
    for s in /private/tmp/tmux-*/codex-nvim-* /tmp/tmux-*/codex-nvim-*; do
      [ -e "$s" ] || continue
      owner=${s##*codex-nvim-}
      if ! kill -0 "$owner" 2>/dev/null; then
        tmux -S "$s" kill-server 2>/dev/null
        rm -f "$s"
      fi
    done
    while kill -0 %d 2>/dev/null; do sleep 2; done
    tmux -L codex-nvim-%d kill-server 2>/dev/null
    rm -f /private/tmp/tmux-*/codex-nvim-%d /tmp/tmux-*/codex-nvim-%d
  ]], pid, pid, pid, pid)
  vim.fn.jobstart({ "sh", "-c", script }, { detach = true })
end

-- ctrl+g in the TUI edits the input box in $EDITOR. Pointing it at the wrapper
-- routes that back into this nvim instead of nesting a second one -- see
-- lua/ai/editor.lua.
local function editor_env()
  local wrapper = require("ai.editor").wrapper()
  return { EDITOR = wrapper, VISUAL = wrapper }
end

local function terminal_command(args)
  if vim.fn.executable("tmux") ~= 1 or not should_wrap_tmux() then return args end

  ensure_tmux_watchdog()
  local term = vim.env.TERM or "xterm-256color"
  local socket = "codex-nvim-" .. vim.fn.getpid()
  local wrapper = require("ai.editor").wrapper()
  local command = {
    "env", "TERM=" .. term,
    "tmux", "-f", "/dev/null", "-L", socket,
    "set-option", "-g", "default-terminal", term,
    ";", "set-option", "-g", "history-limit", "50000",
    ";", "set-option", "-g", "mouse", "on",
    ";", "bind-key", "-T", "root", "WheelUpPane", "copy-mode", "-eu",
    ";", "bind-key", "-T", "root", "PPage", "copy-mode", "-eu",
    ";", "new-session", "-A", "-s", "main",
    -- tmux only puts into the pane what is whitelisted here; the pane does not
    -- inherit this process's environment. $NVIM has to be spelled out from
    -- v:servername because this list is handed to jobstart without a shell, so
    -- there is nothing to expand `$NVIM` -- and the host nvim does not set
    -- NVIM for itself anyway, only for its :terminal children.
    "-e", "EDITOR=" .. wrapper,
    "-e", "VISUAL=" .. wrapper,
    "-e", "NVIM=" .. vim.v.servername,
  }
  vim.list_extend(command, args)
  vim.list_extend(command, {
    ";", "set-option", "-g", "destroy-unattached", "on",
    ";", "set-option", "-g", "exit-empty", "on",
    ";", "set-option", "-g", "status", "off",
    ";", "set-hook", "-g", "client-detached", "kill-server",
  })
  return command
end

local function snacks()
  return _G.Snacks or require("snacks")
end

local function active()
  return current ~= nil and current:buf_valid()
end

-- Shared with ai.selection and the transcript adapters: all three must agree on
-- which directory a session belongs to.
local project_root = ai_config.project_root

local function terminal_opts(root)
  return {
    cwd = root,
    -- Covers the non-tmux path; the wrapper build injects the same pair through
    -- `new-session -e` because a tmux pane does not inherit this environment.
    env = editor_env(),
    auto_insert = true,
    start_insert = true,
    auto_close = true,
    win = {
      position = "right",
      width = ai_config.panel.width,
      wo = { winfixwidth = true },
    },
  }
end

-- Keep the transcript in the wrapper tmux pane history and run Codex without
-- approvals or its built-in sandbox. These flags apply equally to new,
-- resumed, and continued sessions.
local function codex_command(args)
  return vim.list_extend({ "codex", "--no-alt-screen", "--yolo" }, args or {})
end

local function enter_insert(term)
  if not term or not term:buf_valid() then return end
  local win = term.win
  if
    not win
    or not vim.api.nvim_win_is_valid(win)
    or vim.api.nvim_win_get_buf(win) ~= term.buf
    or vim.bo[term.buf].buftype ~= "terminal"
  then
    return
  end

  vim.api.nvim_win_call(win, function() vim.cmd.startinsert() end)
end

-- Nvim Normal-mode scrolling only sees the tmux client's current screen. When
-- the wrapper owns the real history, forward the first scroll action into tmux
-- and return to terminal-input mode; subsequent keys/wheel events are then
-- handled by tmux copy-mode directly.
local function setup_scrollback_maps(term)
  if vim.fn.executable("tmux") ~= 1 or not should_wrap_tmux() then return end

  local keys = {
    ["<C-u>"] = "\27[5~",
    ["<PageUp>"] = "\27[5~",
    ["<ScrollWheelUp>"] = "\27[5~",
    ["<C-d>"] = "\27[6~",
    ["<PageDown>"] = "\27[6~",
    ["<ScrollWheelDown>"] = "\27[6~",
  }
  for lhs, sequence in pairs(keys) do
    vim.keymap.set("n", lhs, function()
      if not term:buf_valid() then return end
      local channel = vim.bo[term.buf].channel
      if not channel or channel <= 0 then return end
      vim.api.nvim_chan_send(channel, sequence)
      enter_insert(term)
    end, {
      buffer = term.buf,
      desc = "Scroll Codex tmux history",
      silent = true,
    })
  end
end

local function start(args, root)
  current = snacks().terminal.open(terminal_command(args), terminal_opts(root))
  local term = current
  term:on("TermClose", function()
    if current == term then current = nil end
  end, { buf = true })
  setup_scrollback_maps(term)
  enter_insert(term)
  return current
end

local function ensure()
  if active() then return current, false end
  local path = vim.api.nvim_buf_get_name(0)
  return start(codex_command(), project_root(path)), true
end

local function show_and_focus(term)
  term:show()
  term:focus()
  enter_insert(term)
end

-- Delivery is asynchronous whenever the terminal had to be started, so this
-- reports failure through `opts.on_error` rather than a return value: by the
-- time the channel turns out to be missing, the caller has long since returned.
local function send(text, opts)
  opts = opts or {}
  local term, created = ensure()
  local delay = created and 350 or 0

  local function fail(reason)
    if opts.on_error then
      opts.on_error(reason)
    else
      vim.notify(reason, vim.log.levels.WARN)
    end
  end

  vim.defer_fn(function()
    if not term:buf_valid() then
      fail("Codex terminal closed before the text could be sent")
      return
    end
    local channel = vim.bo[term.buf].channel
    if not channel or channel <= 0 then
      fail("Codex terminal is not ready")
      return
    end

    show_and_focus(term)
    text = text:gsub("\r\n", "\n"):gsub("\r", "\n"):gsub("\27", "")
    local payload
    if opts.raw then
      payload = text
    else
      payload = "\27[200~" .. text .. "\27[201~"
    end
    if opts.submit then payload = payload .. "\r" end
    vim.api.nvim_chan_send(channel, payload)
  end, delay)
end

local function buffer_context()
  local buf = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(buf)
  if path == "" then
    vim.notify("Current buffer has no file path", vim.log.levels.WARN)
    return
  end

  local root = project_root(path)
  local rel = vim.fs.relpath(root, path) or path
  return buf, rel
end

function M.toggle()
  if active() then
    current:toggle()
    enter_insert(current)
    return
  end
  local path = vim.api.nvim_buf_get_name(0)
  start(codex_command(), project_root(path))
end

function M.focus()
  local term = ensure()
  show_and_focus(term)
end

function M.resume()
  if active() then
    show_and_focus(current)
    vim.notify("A Codex session is already active; exit it before resuming another", vim.log.levels.INFO)
    return
  end
  local path = vim.api.nvim_buf_get_name(0)
  start(codex_command({ "resume" }), project_root(path))
end

function M.continue()
  if active() then
    show_and_focus(current)
    return
  end
  local path = vim.api.nvim_buf_get_name(0)
  start(codex_command({ "resume", "--last" }), project_root(path))
end

---Feed staged images to the TUI through its own ctrl+v. Backs <C-v> in the
---prompt editor.
---@param paths string[]
function M.attach_images(paths)
  local function discard()
    for _, png in ipairs(paths) do vim.fn.delete(png) end
  end

  if not active() then
    vim.notify("Codex terminal is gone; images were not attached", vim.log.levels.WARN)
    discard()
    return
  end

  local term = ensure()
  local channel = term:buf_valid() and vim.bo[term.buf].channel
  if not channel or channel <= 0 then
    vim.notify("Codex terminal is not ready; images were not attached", vim.log.levels.WARN)
    discard()
    return
  end

  require("ai.clipboard").attach(channel, paths, discard)
end

---Ask the TUI to open its own prompt editor, seeding the input box first when
---`opts.seed` is given. Backs `<leader>ai`.
---@param opts { seed?: string }?
function M.edit_prompt(opts)
  opts = opts or {}

  local editor = require("ai.editor")
  local running = active()
  local term = ensure()
  show_and_focus(term)

  local function channel_of()
    if not term:buf_valid() then return nil end
    local channel = vim.bo[term.buf].channel
    return channel and channel > 0 and channel or nil
  end

  if running then
    local channel = channel_of()
    if channel then
      vim.api.nvim_chan_send(channel, editor.keys(opts.seed))
    else
      vim.notify("Codex terminal is not ready", vim.log.levels.WARN)
    end
    return
  end

  -- Freshly started: Codex takes seconds to draw its input box, and anything
  -- sent before then is swallowed silently.
  editor.when_ready(
    function() return term:buf_valid() and term.buf or nil end,
    function()
      local channel = channel_of()
      if channel then vim.api.nvim_chan_send(channel, editor.keys(opts.seed)) end
    end,
    function()
      vim.notify("Codex did not reach its prompt — press <leader>ai again", vim.log.levels.WARN)
    end
  )
end

function M.select_model()
  send("/model", { raw = true, submit = true })
end

function M.add_buffer()
  local buf, rel = buffer_context()
  if not buf then return end
  if vim.bo[buf].modified then
    vim.notify("Codex @-mentions read the saved file; this buffer has unsaved changes", vim.log.levels.WARN)
  end
  send("@" .. rel .. " ", { submit = false })
end

-- Codex CLI has file mentions but no editor selection attachment API, so a
-- selection travels as text. The text itself is built by ai.selection, which
-- <leader>ai shares -- see that module for why it is not a backend concern.
function M.send_selection()
  local draft, err, notice = require("ai.selection").draft()
  if not draft then
    vim.notify(err, vim.log.levels.WARN)
    return
  end
  if notice then
    vim.notify(notice, vim.log.levels.INFO)
  end

  send(draft, { submit = false })
end

return M
