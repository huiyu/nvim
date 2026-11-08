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

  editor.stage_seed(opts.seed)

  terminal.ensure_visible()

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
