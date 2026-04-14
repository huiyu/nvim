local function build_terminal_cmd()
  local plugin_args = vim.env.CLAUDE_PLUGIN_DIR
    and (" " .. table.concat(vim.tbl_map(function(d) return "--plugin-dir " .. d end, vim.split(vim.env.CLAUDE_PLUGIN_DIR, ",")), " "))
    or ""
  local claude_cmd = "claude" .. plugin_args

  -- Fall back to a plain claude invocation when tmux is unavailable.
  if vim.fn.executable("tmux") ~= 1 then
    return claude_cmd
  end

  -- Wrap in tmux to work around iTerm2's DEC mode 2026 rendering glitches.
  -- Use a dedicated tmux server (-L <socket>) so our hooks and sessions are
  -- fully isolated from the user's regular tmux usage, and so kill-server
  -- on client-detached cannot leak into unrelated sessions. When the host
  -- terminal is closed, the client detaches, the hook tears down the server,
  -- and claude exits with it — no orphaned sessions.
  --
  -- Wrap in `sh -c '...' _` so that cmd args appended by claudecode.nvim
  -- (e.g. --resume, --continue) land inside the claude invocation via "$@"
  -- rather than after the trailing tmux set-hook.
  local socket = "claude-nvim-" .. vim.fn.getpid()
  local inner = table.concat({
    "tmux -L " .. socket .. " new-session -A -s main",
    "-e CLAUDE_CODE_SSE_PORT=$CLAUDE_CODE_SSE_PORT",
    "-e ENABLE_IDE_INTEGRATION=$ENABLE_IDE_INTEGRATION",
    "-e FORCE_CODE_TERMINAL=$FORCE_CODE_TERMINAL",
    "-e no_proxy=localhost,127.0.0.1",
    claude_cmd .. ' "$@"',
    "\\; set-option -g destroy-unattached on",
    "\\; set-option -g exit-empty on",
    "\\; set-hook -g client-detached kill-server",
  }, " ")
  return "sh -c '" .. inner .. "' _"
end

-- Detached watchdog: polls our nvim pid and tears down the dedicated tmux
-- server when nvim dies. Needed because VimLeavePre cleanup runs as a child
-- of nvim and gets killed alongside it on SIGHUP (e.g. host terminal tab
-- close), so its kill-server never completes. The watchdog is spawned via
-- `setsid` to leave nvim's process group/session, making it immune to the
-- SIGHUP cascade. Also sweeps stale sockets from prior crashes.
if vim.fn.executable("tmux") == 1 then
  vim.api.nvim_create_autocmd("VimEnter", {
    group = vim.api.nvim_create_augroup("ClaudeTmuxWatchdog", { clear = true }),
    callback = function()
      local pid = vim.fn.getpid()
      local script = string.format([[
        # Sweep stale sockets whose owning nvim pid is gone.
        for s in /private/tmp/tmux-*/claude-nvim-* /tmp/tmux-*/claude-nvim-*; do
          [ -e "$s" ] || continue
          owner=${s##*claude-nvim-}
          if ! kill -0 "$owner" 2>/dev/null; then
            tmux -S "$s" kill-server 2>/dev/null
            rm -f "$s"
          fi
        done
        # Watchdog loop for this nvim instance.
        while kill -0 %d 2>/dev/null; do sleep 2; done
        tmux -L claude-nvim-%d kill-server 2>/dev/null
        rm -f /private/tmp/tmux-*/claude-nvim-%d /tmp/tmux-*/claude-nvim-%d
      ]], pid, pid, pid, pid)
      -- jobstart with detach=true calls setsid, placing the watchdog in a
      -- new session so it survives the SIGHUP cascade through nvim's pgroup.
      vim.fn.jobstart({ "sh", "-c", script }, { detach = true })
    end,
  })
end

return {
  {
    "coder/claudecode.nvim",
    dependencies = { "folke/snacks.nvim" },
    opts = {
      terminal_cmd = build_terminal_cmd(),
      terminal = {
        split_side = "right",
        provider = "snacks",
        snacks_win_opts = {
          auto_insert = false,
          width = 90,
          wo = { winfixwidth = true },
        },
      },
      -- Bypass proxy for localhost WebSocket connections (IDE integration)
      env = {
        no_proxy = "localhost,127.0.0.1",
      },
      diff_opts = {
        auto_close_on_accept = true,
        vertical_split = true,
      },
    },
    keys = {
      { "<leader>ac", "<cmd>ClaudeCode<cr>",              desc = "Toggle Claude" },
      { "<leader>af", "<cmd>ClaudeCodeFocus<cr>",         desc = "Focus Claude" },
      { "<leader>ar", "<cmd>ClaudeCode --resume<cr>",     desc = "Resume Claude" },
      { "<leader>aR", "<cmd>ClaudeCode --continue<cr>",   desc = "Continue Claude" },
      { "<leader>am", "<cmd>ClaudeCodeSelectModel<cr>",   desc = "Select model" },
      { "<leader>ab", "<cmd>ClaudeCodeAdd %<cr>",         desc = "Add current buffer" },
      { "<leader>as", "<cmd>ClaudeCodeSend<cr>",          desc = "Send to Claude",  mode = "v" },
      { "<leader>aa", "<cmd>ClaudeCodeDiffAccept<cr>",    desc = "Accept diff" },
      { "<leader>ad", "<cmd>ClaudeCodeDiffDeny<cr>",      desc = "Deny diff" },
      {
        "<leader>aS",
        "<cmd>ClaudeCodeTreeAdd<cr>",
        desc = "Add file from tree",
        mode = "n",
        ft = { "NvimTree", "neo-tree", "oil", "minifiles", "snacks_explorer" },
      },
    },
  },
}
