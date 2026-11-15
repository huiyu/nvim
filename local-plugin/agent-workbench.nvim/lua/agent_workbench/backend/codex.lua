local ai_config = require("agent_workbench.state")
local launch = require("agent_workbench.backend.launch")

local M = {}

local current
local terminals = require("agent_workbench.terminal_provider")

-- Codex uses synchronized terminal updates for each TUI frame. Neovim's
-- libvterm does not implement that protocol, so let a dedicated tmux server
-- compose the frame before it reaches :terminal. Precedence: env > vim.g > on.
local function should_wrap_tmux()
  return launch.enabled("CODEX_WRAP_TMUX", "codex_wrap_tmux")
end

local function terminal_command(args)
  if vim.fn.executable("tmux") ~= 1 or not should_wrap_tmux() then return args end

  launch.ensure_watchdog("codex")
  local term = vim.env.TERM or "xterm-256color"
  local socket = "codex-nvim-" .. vim.fn.getpid()
  local env = launch.editor_env()
  local command = {
    "env", "TERM=" .. term,
    "tmux", "-f", "/dev/null", "-L", socket,
    "set-option", "-g", "default-terminal", term,
    ";", "set-option", "-g", "history-limit", "50000",
    ";", "set-option", "-g", "mouse", "on",
    -- Keep mouse scrolling, but suppress tmux's pane menu on right-click.
    ";", "unbind-key", "-T", "root", "MouseDown3Pane",
    ";", "unbind-key", "-T", "root", "M-MouseDown3Pane",
    -- <S-CR> reaches this pane as CSI u (ESC[13;2u) from local-plugin/editor-core.nvim/lua/editor_core/keymaps.lua.
    -- Under tmux's default `extended-keys off` that collapses to a bare CR,
    -- which submits the message instead of inserting a newline (measured on
    -- tmux 3.6b). `always` keeps the modifier without waiting for the pane to
    -- ask -- Codex never requests modifyOtherKeys, and tmux ignores its kitty
    -- request -- and `csi-u` matters because Codex (crossterm) does not parse
    -- tmux's default xterm form ESC[27;2;13~. Every key with a legacy encoding
    -- still reaches the pane byte-for-byte as before.
    ";", "set-option", "-g", "extended-keys", "always",
    ";", "set-option", "-g", "extended-keys-format", "csi-u",
    -- These two are half of the scrollback story. The other half is the
    -- terminal-Normal-mode forwarding in local-plugin/agent-workbench.nvim/lua/agent_workbench/terminal.lua, which sends
    -- PPage into the pane so a scroll that starts outside terminal input still
    -- lands in copy-mode instead of the near-empty :terminal buffer.
    -- The wheel enters copy-mode without `-u`, which PPage keeps: `-u` scrolls
    -- a full page on entry, so the first notch used to jump a whole screen. A
    -- page is what PageUp means; it is not what one notch means. Once in
    -- copy-mode, 2 lines per wheel event rather than tmux's default 5 --
    -- Ghostty sends 3 events per discrete notch (mouse-scroll-multiplier), so
    -- the default made one notch ~15 lines. Both copy-mode tables are bound
    -- because which one is live depends on mode-keys, which tmux derives from
    -- $EDITOR/$VISUAL in the server's own environment.
    ";", "bind-key", "-T", "root", "WheelUpPane", "copy-mode", "-e",
    ";", "bind-key", "-T", "root", "PPage", "copy-mode", "-eu",
    ";", "bind-key", "-T", "copy-mode", "WheelUpPane", "send-keys", "-X", "-N", "2", "scroll-up",
    ";", "bind-key", "-T", "copy-mode", "WheelDownPane", "send-keys", "-X", "-N", "2", "scroll-down",
    ";", "bind-key", "-T", "copy-mode-vi", "WheelUpPane", "send-keys", "-X", "-N", "2", "scroll-up",
    ";", "bind-key", "-T", "copy-mode-vi", "WheelDownPane", "send-keys", "-X", "-N", "2", "scroll-down",
    ";", "new-session", "-A", "-s", "main",
    -- tmux only puts into the pane what is whitelisted here; the pane does not
    -- inherit this process's environment. $NVIM has to be spelled out from
    -- v:servername because this list is handed to jobstart without a shell, so
    -- there is nothing to expand `$NVIM` -- and the host nvim does not set
    -- NVIM for itself anyway, only for its :terminal children.
    "-e", "EDITOR=" .. env.EDITOR,
    "-e", "VISUAL=" .. env.VISUAL,
    "-e", "NVIM=" .. vim.v.servername,
  }
  -- The pane runs Codex through the launcher, not directly: the wrapper's own
  -- teardown reports success to nvim whatever the pane's command did, so a
  -- Codex that fails on startup would close the panel and take its error with
  -- it. See local-plugin/agent-workbench.nvim/scripts/agent-run.
  command[#command + 1] = launch.runner()
  vim.list_extend(command, args)
  vim.list_extend(command, {
    -- Off, deliberately: the client-detached hook below is what ends this
    -- server, and with destroy-unattached on the session -- and the pane's
    -- process tree the hook has to record -- was gone before the hook ran
    -- (measured). exit-empty still ends the server when Codex itself exits.
    ";", "set-option", "-g", "destroy-unattached", "off",
    ";", "set-option", "-g", "exit-empty", "on",
    ";", "set-option", "-g", "status", "off",
    -- When the nvim client goes away -- panel closed, nvim quit, host terminal
    -- gone -- local-plugin/agent-workbench.nvim/scripts/agent-teardown kills the server and then the processes
    -- Codex left behind in their own groups (exec_command sessions), which a
    -- bare kill-server never reached. See ai.backend.launch.teardown_hook.
    ";", "set-hook", "-g", "client-detached", launch.teardown_hook(socket),
  })
  return command
end

-- Indirection so a spec can inspect the wrapper without starting Codex. The
-- launcher in there is what keeps a failed startup visible, and losing it fails
-- silently by construction, so it is worth a test.
M._terminal_command = terminal_command

local function valid(term)
  return term and term.buf and vim.api.nvim_buf_is_valid(term.buf)
end
local function active() return terminals.alive(current) end

-- Shared with ai.selection and the transcript adapters: all three must agree on
-- which directory a session belongs to.
local project_root = require("agent_workbench.context").project_root

local function terminal_opts(root)
  return { cwd = root, env = launch.editor_env(), width = ai_config.panel.width }
end
M._terminal_opts = terminal_opts

-- Keep the transcript in the wrapper tmux pane history and run Codex without
-- approvals or its built-in sandbox. These flags apply equally to new,
-- resumed, and continued sessions: a root-level `-c` reaches `resume` and
-- `resume --last` too.
--
-- The `-c` carries the review baseline's UserPromptSubmit hook with its trust
-- hash (local-plugin/agent-workbench.nvim/lua/agent_workbench/review/hook.lua), so it runs without a review prompt and nothing
-- is written to ~/.codex. Built per start, so sources.codex and hook_wait_ms
-- apply from the next spawn. The list reaches Codex without a shell -- jobstart
-- here, a multi-argument command under tmux -- so the TOML arrives byte-exact.
local function codex_command(args)
  local native = require("agent_workbench.options").get().native.codex
  local command = { native.command }
  vim.list_extend(command, native.args)
  if require("agent_workbench.options").get().integrations.review and require("agent_workbench.review.settings").get().sources.codex then
    vim.list_extend(command, { "-c", require("agent_workbench.review.hook").codex_override() })
  end
  vim.list_extend(command, require("agent_workbench.plugins").codex_args())
  return vim.list_extend(command, args or {})
end

-- For the specs, which record the argv a stand-in Codex receives.
M._codex_command = codex_command

local function enter_insert(term, visible_win)
  if not term or not valid(term) then return end
  local win = visible_win or terminals.window(term)
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

local function start(args, root)
  local request = terminal_opts(root)
  request.argv = terminal_command(args)
  current = terminals.open("codex", request)
  enter_insert(current)
  return current
end

local function ensure()
  if active() then return current, false end
  local path = vim.api.nvim_buf_get_name(0)
  return start(codex_command(), project_root(path)), true
end

local function show_and_focus(term)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_config(win).relative == "" and vim.api.nvim_win_get_buf(win) == term.buf then
      vim.api.nvim_set_current_win(win)
      enter_insert(term, win)
      return
    end
  end
  terminals.show(term)
  enter_insert(term)
end

-- Delivery is asynchronous whenever the terminal had to be started, so a
-- failure is a WARN notification from the deferred callback rather than a
-- return value: by the time the channel turns out to be missing, the caller
-- has long since returned.
local function send(text, opts)
  opts = opts or {}
  local term, created = ensure()
  -- A file reference must be formatted after resolving the recipient's root.
  if type(text) == "function" then text = text(term.root) end
  local delay = created and 350 or 0

  local function fail(reason)
    vim.notify(reason, vim.log.levels.WARN)
  end

  vim.defer_fn(function()
    if not valid(term) then
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
    local delivered, err = terminals.send(term, payload)
    if not delivered then fail(err and err.message or "Codex terminal refused the context") end
  end, delay)
end

---Is a Codex session running in this Nvim, shown or not?
---@return boolean
function M.running()
  return active()
end

---The session's terminal buffer, while one runs.
---@return integer|nil
function M.buf()
  return active() and current.buf or nil
end

---The panel's window, in whichever tabpage shows it; nil while hidden.
---@return integer|nil
function M.window()
  return terminals.window(current)
end

---Is the panel on screen in the current tabpage?
---@return boolean
function M.visible()
  local win = M.window()
  return win ~= nil and vim.api.nvim_win_get_tabpage(win) == vim.api.nvim_get_current_tabpage()
end

---Hide the panel in the current tabpage only. Snacks' hide closes the window
---and keeps the buffer, so the job and its tmux client stay.
function M.hide()
  if current then return terminals.hide(current) end
  return true
end

function M.focus()
  local term = ensure()
  show_and_focus(term)
end

---Show the session here and focus it, starting it when none runs; never
---hides it. Used by the tab's AI slot.
M.reveal = M.focus

function M.resume()
  if active() then
    show_and_focus(current)
    vim.notify("A Codex session is already active; exit it before resuming another", vim.log.levels.INFO, { title = "AI" })
    return
  end
  local path = vim.api.nvim_buf_get_name(0)
  start(codex_command({ "resume" }), project_root(path))
end

function M.continue()
  if active() then
    show_and_focus(current)
    vim.notify("Codex is already running: this is its session", vim.log.levels.INFO, { title = "AI" })
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
  local channel = valid(term) and vim.bo[term.buf].channel
  if not channel or channel <= 0 then
    vim.notify("Codex terminal is not ready; images were not attached", vim.log.levels.WARN)
    discard()
    return
  end

  require("agent_workbench.clipboard").attach(channel, paths, discard)
end

---Ask the TUI to open its own prompt editor, seeding the input box first when
---`opts.seed` is given. Backs `<leader>ai`, and review feedback (ai.feed),
---which hears through the callbacks whether the seed reached a prompt.
---@param opts { seed?: string, on_consumed?: fun(), on_expired?: fun(), ttl_ms?: integer }?
function M.edit_prompt(opts)
  opts = opts or {}

  local editor = require("agent_workbench.editor")
  local running = active()
  local term = ensure()
  show_and_focus(term)

  local function channel_of()
    if not valid(term) then return nil end
    local channel = vim.bo[term.buf].channel
    return channel and channel > 0 and channel or nil
  end

  editor.stage_seed(opts.seed, { agent = "codex", on_consumed = opts.on_consumed, on_expired = opts.on_expired, ttl_ms = opts.ttl_ms })

  if running then
    local channel = channel_of()
    if channel then
      vim.api.nvim_chan_send(channel, editor.EDIT_KEY)
    else
      vim.notify("Codex terminal is not ready", vim.log.levels.WARN)
    end
    return
  end

  -- Freshly started: Codex takes seconds to draw its input box, and anything
  -- sent before then is swallowed silently.
  editor.when_ready(
    function() return valid(term) and term.buf or nil end,
    function()
      local channel = channel_of()
      if channel then vim.api.nvim_chan_send(channel, editor.EDIT_KEY) end
    end,
    function()
      vim.notify("Codex did not reach its prompt — press <leader>ai again", vim.log.levels.WARN)
    end
  )
end

---The TUI's own model menu. A session it starts gets "/model" submitted into
---its empty box; a running one is only shown: the box may hold a half-typed
---prompt, which the Enter would submit with "/model" glued to it, or the TUI
---may be asking for an approval, which the Enter would answer.
function M.select_model()
  if active() then
    show_and_focus(current)
    vim.notify("Codex is already running: use /model in it", vim.log.levels.INFO, { title = "AI" })
    return
  end
  send("/model", { raw = true, submit = true })
end

---Mention a file relative to the running session, or by its absolute path
---outside that root. Typed into the input
---box, not submitted. Warns when `modified`: Codex reads the saved file.
---@param path string
---@param modified boolean?
function M.add_path(path, modified)
  if modified then
    vim.notify("Codex @-mentions read the saved file; this buffer has unsaved changes", vim.log.levels.WARN)
  end
  send(function(root)
    return "@" .. (vim.fs.relpath(root, path) or path) .. " "
  end, { submit = false })
end

---Type `text` into the input box as one paste, not submitted, starting Codex
---when it is not running. What a selection captured before asking where it
---goes becomes (local-plugin/agent-workbench.nvim/lua/agent_workbench/init.lua): Codex CLI has file mentions but no editor
---selection attachment API, so a selection travels as text.
---@param text string
function M.send_text(text)
  send(text, { submit = false })
end

---Stop only this native session and its owned tmux process tree.
function M.stop()
  if not current then return true end
  local info = current.buf and vim.b[current.buf].agent_workbench
  local argv = info and info.cmd or {}
  for i, arg in ipairs(argv) do
    if arg == "-L" and argv[i + 1] == "codex-nvim-" .. vim.fn.getpid() then
      vim.system({ launch.teardown(), "--wait", argv[i + 1] }, { timeout = 5000 }):wait()
      break
    end
  end
  local stopped, err = terminals.stop(current)
  if not stopped then return false, err end
  current = nil
  return true
end
return M
