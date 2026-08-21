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
-- one. This levels the two so the composer behaves identically under either
-- provider -- start if needed, then send.
--
-- Delivery is asynchronous on the start path, so failure is reported through
-- `opts.on_error` rather than a return value.
---@param text string
---@param opts { submit?: boolean, focus?: boolean, images?: string[], on_error?: fun(reason: string) }
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

  local function deliver()
    local images = opts.images or {}
    if #images == 0 then
      send_body()
      return
    end

    -- Images have to reach Claude through its own paste path (ctrl+v is bound
    -- to "chat:imagePaste"), because there is no way to put image bytes into
    -- the request from here. Attach first, then the text.
    local bufnr = terminal.get_active_terminal_bufnr()
    local channel = bufnr and vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].channel
    if not channel or channel <= 0 then
      send_body()
      return
    end

    require("ai.clipboard").attach(channel, images, function()
      for _, path in ipairs(images) do vim.fn.delete(path) end
      send_body()
    end)
  end

  local bufnr = terminal.get_active_terminal_bufnr()
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    deliver()
  else
    terminal.ensure_visible()
    vim.defer_fn(deliver, CHANNEL_READY_MS)
  end
end

return M
