local M = {}

local INFO = vim.log.levels.INFO

local function command(cmd)
  vim.cmd(cmd)
end

function M.toggle() command("ClaudeCode") end
function M.focus() command("ClaudeCodeFocus") end
function M.add_buffer() command("ClaudeCodeAdd %") end
function M.send_selection() command("ClaudeCodeSend") end
function M.accept_diff() command("ClaudeCodeDiffAccept") end
function M.deny_diff() command("ClaudeCodeDiffDeny") end
function M.tree_add() command("ClaudeCodeTreeAdd") end

-- The Snacks terminal claudecode.nvim manages. Answering never loads the
-- plugin: with it unloaded there is no Claude panel to find.
local function panel()
  if not package.loaded["claudecode"] then return nil end
  local buf = require("claudecode.terminal").get_active_terminal_bufnr()
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then return nil end
  for _, term in ipairs(require("snacks").terminal.list()) do
    if term.buf == buf then return term end
  end
end

---Is a Claude session running in this Nvim, shown or not?
---@return boolean
function M.running()
  return panel() ~= nil
end

---The session's terminal buffer, while one runs.
---@return integer|nil
function M.buf()
  local term = panel()
  return term and term.buf or nil
end

---Show the session here and focus it, starting it when none runs. This is
---claudecode's open, not its toggles: it reuses the one terminal (cc_show) and
---never hides it, and it judges "shown" by the terminal's own window, so a
---copy claudecode put in a diff tabpage does not stop it opening here. Through
---the command until the plugin has loaded -- the command is what loads it --
---and the module function after, which is also what a spec stands in for.
---@param args string? CLI arguments for a session it starts; a running one ignores them
function M.reveal(args)
  if package.loaded["claudecode"] then
    require("claudecode.terminal").open({}, args)
  else
    command("ClaudeCodeOpen" .. (args and (" " .. args) or ""))
  end
end

local function already(what)
  vim.notify("Claude Code is already running: " .. what, INFO, { title = "AI" })
end

-- These start a session with their arguments. One that is running already is
-- shown and left as it is: claudecode keeps one terminal, and its toggles
-- would drop the arguments and hide a shown panel instead.
function M.resume()
  if M.running() then
    M.reveal()
    return already("use /resume in it, or exit it first")
  end
  M.reveal("--resume")
end
function M.continue()
  if M.running() then
    M.reveal()
    return already("this is its session")
  end
  M.reveal("--continue")
end
function M.select_model()
  if M.running() then
    M.reveal()
    -- The TUI's own model menu, as Codex's /model.
    if not require("claudecode.terminal").send_to_terminal("/model") then already("use /model in it") end
    return
  end
  command("ClaudeCodeSelectModel")
end

---Mention a file, as <leader>ab does for the current buffer.
---@param path string
function M.add_path(path)
  command("ClaudeCodeAdd " .. vim.fn.fnameescape(path))
end

---Mention lines `l1`..`l2` (1-based) of `path`: what :ClaudeCodeSend makes of
---a selection, without needing that selection to be live -- the facade has
---captured it before asking where it goes (lua/ai/init.lua). claudecode's
---public send_at_mention, which queues the mention while the TUI is still
---connecting.
---@param path string
---@param l1 integer
---@param l2 integer
function M.send_range(path, l1, l2)
  local ok, err = require("claudecode").send_at_mention(path, l1 - 1, l2 - 1, "ClaudeCodeSend")
  if not ok then
    vim.notify("Claude Code did not take the selection: " .. tostring(err), vim.log.levels.WARN, { title = "AI" })
  end
end

---The panel's window, in whichever tabpage shows it; nil while hidden.
---@return integer|nil
function M.window()
  local term = panel()
  local win = term and term.win
  if not (win and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == term.buf) then return nil end
  -- claudecode parks a hidden float with `hide = true` instead of closing it.
  if vim.api.nvim_win_get_config(win).hide then return nil end
  return win
end

---Is the panel on screen in the current tabpage?
---@return boolean
function M.visible()
  local win = M.window()
  return win ~= nil and vim.api.nvim_win_get_tabpage(win) == vim.api.nvim_get_current_tabpage()
end

---Hide the panel in the current tabpage only. The job and its tmux client stay:
---claudecode patches the terminal's hide (terminal/snacks.lua `cc_hide`) to
---close the split and keep the buffer, the same path its own toggle takes.
function M.hide()
  local term = M.visible() and panel()
  if term then term:hide() end
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
---`opts.seed` is given. Backs `<leader>ai`, and review feedback (ai.feed),
---which hears through the callbacks whether the seed reached a prompt.
---@param opts { seed?: string, on_consumed?: fun(), on_expired?: fun(), ttl_ms?: integer }?
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

  editor.stage_seed(opts.seed, { provider = "claude", on_consumed = opts.on_consumed, on_expired = opts.on_expired, ttl_ms = opts.ttl_ms })

  -- ensure_visible counts any window on the terminal as shown, the copy in a
  -- diff tabpage too, and would then open nothing here: the slot just made
  -- room for this panel (lua/ai/slot.lua), and the prompt would go to a
  -- terminal in another tabpage. A hidden session is shown through open().
  if M.running() and not M.window() then
    terminal.open()
  else
    terminal.ensure_visible()
  end

  if running then
    vim.api.nvim_chan_send(running, editor.EDIT_KEY)
    return
  end

  -- Nothing was running, so the CLI is booting. Wait for its input box instead
  -- of firing a 0x07 it would swallow with nothing on screen to show for it.
  editor.when_ready(
    terminal.get_active_terminal_bufnr,
    function(buf)
      local ready = channel_of(buf)
      if ready then vim.api.nvim_chan_send(ready, editor.EDIT_KEY) end
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
