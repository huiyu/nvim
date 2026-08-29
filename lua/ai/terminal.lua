---@module "ai.terminal"
---Buffer-local input rules for the native agent panels.
---
---Both providers run their TUI in a Snacks `:terminal`, so both inherit two
---Nvim behaviours that quietly take input away from the agent. Neither is
---wrong for an ordinary shell terminal, which is why this is scoped to the
---agent buffers instead of being turned off globally.

local M = {}

---Whether this panel's command goes through a tmux wrapper.
---
---The wrapper is the only thing in the pane that turns mouse reporting on
---(`set-option -g mouse on` in both backends), and that single fact decides
---who handles a click -- so the recorded command is the honest test.
---@param buf integer
---@return boolean
local function wrapped_in_tmux(buf)
  local info = vim.b[buf].snacks_terminal
  local cmd = info and info.cmd
  if type(cmd) == "table" then cmd = table.concat(vim.tbl_map(tostring, cmd), " ") end
  return type(cmd) == "string" and cmd:find("tmux", 1, true) ~= nil
end

-- Nvim only forwards a mouse event to the terminal job when the job asked for
-- mouse reporting. An agent TUI never asks, so Nvim handles the click itself --
-- and handling it means leaving Terminal-mode. Coming back to the window
-- manager and clicking on the Ghostty window is enough to trigger that, which
-- is what made the panel look like it "randomly" returned in Normal mode.
--
-- Under the tmux wrapper tmux does ask, Nvim forwards, and Terminal-mode
-- survives on its own. Mapping there would steal the click from tmux's own
-- copy-mode instead of fixing anything, so this covers the unwrapped path only.
local MOUSE_KEYS = {
  "<LeftMouse>", "<2-LeftMouse>", "<3-LeftMouse>", "<LeftDrag>", "<LeftRelease>",
  "<RightMouse>", "<MiddleMouse>",
}

---@param buf integer
local function keep_terminal_mode_on_click(buf)
  for _, lhs in ipairs(MOUSE_KEYS) do
    vim.keymap.set("t", lhs, function()
      -- Only clicks that land in the panel itself are swallowed. Clicking
      -- another window from Terminal-mode still has to move there, so that
      -- one keeps the default handling.
      if vim.fn.getmousepos().winid == vim.api.nvim_get_current_win() then return "" end
      return "<C-\\><C-n>" .. lhs
    end, {
      buffer = buf,
      expr = true,
      nowait = true,
      silent = true,
      desc = "Stay in Terminal-mode when clicking inside the agent panel",
    })
  end
end

-- Claude and Codex both use a quick double Esc for their own "go back to the
-- previous message" action, and neither has ever received it here: Snacks maps
-- <esc> on its terminal buffers as a 200ms double-tap to Normal mode, and
-- lua/mappings.lua maps <Esc><Esc> globally. The panels opt out of both --
-- Snacks' entry through `keys.term_normal = false` where each terminal is
-- created, the global pair through the mapping below, which is a complete
-- match and therefore wins over the longer global sequence without waiting out
-- 'timeoutlen'. `jk` and <C-\> still leave Terminal-mode.
---@param buf integer
local function pass_esc_to_agent(buf)
  vim.keymap.set("t", "<Esc>", "<Esc>", {
    buffer = buf,
    nowait = true,
    noremap = true,
    silent = true,
    desc = "Send Esc to the agent (double Esc is the agent's own shortcut)",
  })
end

-- Nvim's own Normal-mode scrolling only sees what the tmux client currently
-- has on screen: under the wrapper tmux owns the real history, and the
-- :terminal buffer holds one screenful of the frames tmux composed. So from
-- terminal-Normal mode the scroll keys are forwarded into the pane instead,
-- which puts tmux into copy-mode over the actual transcript, and terminal
-- input is restored so the next wheel event reaches copy-mode directly rather
-- than scrolling the near-empty buffer again.
local SCROLL_KEYS = {
  ["<C-u>"] = "\27[5~",
  ["<PageUp>"] = "\27[5~",
  ["<ScrollWheelUp>"] = "\27[5~",
  ["<C-d>"] = "\27[6~",
  ["<PageDown>"] = "\27[6~",
  ["<ScrollWheelDown>"] = "\27[6~",
}

---@param buf integer
local function forward_scrollback(buf)
  for lhs, sequence in pairs(SCROLL_KEYS) do
    vim.keymap.set("n", lhs, function()
      if not vim.api.nvim_buf_is_valid(buf) then return end
      local channel = vim.bo[buf].channel
      if not channel or channel <= 0 then return end
      vim.api.nvim_chan_send(channel, sequence)
      -- Safe unconditionally: the mapping is buffer-local, so the terminal is
      -- the current buffer of the current window whenever it runs.
      vim.cmd.startinsert()
    end, {
      buffer = buf,
      silent = true,
      desc = "Scroll the agent's tmux history",
    })
  end
end

---Apply the panel input rules to one agent terminal buffer.
---@param buf integer
function M.attach(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  pass_esc_to_agent(buf)
  if wrapped_in_tmux(buf) then
    forward_scrollback(buf)
  else
    keep_terminal_mode_on_click(buf)
  end
end

---Install the TermOpen hook that calls `attach` on the selected provider's
---panel. Both backends open through Snacks, so one hook covers both; the
---per-backend alternative would need a callback threaded through
---claudecode.nvim's own terminal provider.
function M.setup()
  vim.api.nvim_create_autocmd("TermOpen", {
    group = vim.api.nvim_create_augroup("ai_terminal_input", { clear = true }),
    callback = function(event)
      if require("util.terminal").is_agent_buf(event.buf) then M.attach(event.buf) end
    end,
  })
end

return M
