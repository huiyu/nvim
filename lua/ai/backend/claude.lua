local M = {}

local function command(cmd)
  vim.cmd(cmd)
end

function M.toggle() command("ClaudeCode") end
function M.focus() command("ClaudeCodeFocus") end
function M.resume() command("ClaudeCode --resume") end
function M.continue() command("ClaudeCode --continue") end
function M.select_model() command("ClaudeCodeSelectModel") end
function M.add_buffer() command("ClaudeCodeAdd %") end
function M.send_selection() command("ClaudeCodeSend") end
function M.accept_diff() command("ClaudeCodeDiffAccept") end
function M.deny_diff() command("ClaudeCodeDiffDeny") end
function M.tree_add() command("ClaudeCodeTreeAdd") end

-- How long to wait for a freshly opened terminal's job channel to exist.
--
-- Not a new guess: codex.lua uses the same 350ms for the same race, and both
-- providers start a TUI in a Snacks terminal. Kept here rather than shared
-- because the two backends must be able to diverge if one TUI gets slower.
local CHANNEL_READY_MS = 350

-- Provider-neutral text send.
--
-- claudecode.nvim's send_to_terminal deliberately does NOT start the terminal:
-- it warns and returns false when none is running. Codex's send() does start
-- one. This levels the two so a text send behaves identically under either
-- provider -- start if needed, then send.
--
-- Delivery is asynchronous on the start path, so failure is reported through
-- `opts.on_error` rather than a return value.
---@param text string
---@param opts { submit?: boolean, focus?: boolean, on_error?: fun(reason: string) }
function M.send_text(text, opts)
  opts = opts or {}
  local terminal = require("claudecode.terminal")

  local function fail(reason)
    if opts.on_error then
      opts.on_error(reason)
    else
      vim.notify(reason, vim.log.levels.WARN)
    end
  end

  local function send_body()
    -- send_to_terminal already wraps multi-line text in bracketed paste and
    -- appends the submit CR, so the text must not be wrapped a second time.
    local ok = terminal.send_to_terminal(text, {
      submit = opts.submit ~= false,
      focus = opts.focus ~= false,
    })
    if not ok then
      fail("Claude terminal is not ready")
    end
  end

  local bufnr = terminal.get_active_terminal_bufnr()
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    send_body()
  else
    terminal.ensure_visible()
    vim.defer_fn(send_body, CHANNEL_READY_MS)
  end
end

---Feed staged images to the TUI through its own ctrl+v. Backs <C-v> in the
---prompt editor.
---@param paths string[]
function M.attach_images(paths)
  local terminal = require("claudecode.terminal")
  local bufnr = terminal.get_active_terminal_bufnr()
  local channel = bufnr
    and vim.api.nvim_buf_is_valid(bufnr)
    and vim.bo[bufnr].channel

  local function discard()
    for _, png in ipairs(paths) do vim.fn.delete(png) end
  end

  if not channel or channel <= 0 then
    vim.notify("Claude terminal is gone; images were not attached", vim.log.levels.WARN)
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
  local terminal = require("claudecode.terminal")

  local editor = require("ai.editor")

  local function channel_of(bufnr)
    if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return nil end
    local channel = vim.bo[bufnr].channel
    return channel and channel > 0 and channel or nil
  end

  -- Sampled BEFORE ensure_visible, which starts the terminal when none exists.
  -- A freshly started job has a channel immediately, so checking afterwards
  -- would look "already running" and fire the key into a booting TUI.
  local running = channel_of(terminal.get_active_terminal_bufnr())

  terminal.ensure_visible()

  if running then
    vim.api.nvim_chan_send(running, editor.keys(opts.seed))
    return
  end

  -- Nothing was running, so the CLI is booting. Wait for its input box instead
  -- of firing a 0x07 it would swallow with nothing on screen to show for it.
  editor.when_ready(
    terminal.get_active_terminal_bufnr,
    function(buf)
      local ready = channel_of(buf)
      if ready then vim.api.nvim_chan_send(ready, editor.keys(opts.seed)) end
    end,
    function()
      vim.notify(
        "Claude Code did not reach its prompt — press <leader>ai again",
        vim.log.levels.WARN
      )
    end
  )
end

return M
