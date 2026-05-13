-- Whether to wrap claude in a dedicated tmux server when launching the
-- terminal. Precedence: env var > vim.g > default.
--   CLAUDE_WRAP_TMUX=1 nvim    -> force on
--   CLAUDE_WRAP_TMUX=0 nvim    -> force off (one-off A/B testing)
--   vim.g.claude_wrap_tmux = false in init.lua -> persistent opt-out
-- Default is ON: claude's Ink TUI emits DEC mode 2026 (Synchronized Output)
-- sequences, which nvim's :terminal buffer does not understand. Without the
-- wrapper you get visible mid-frame tearing (status bar double-render, lines
-- bleeding into the next). tmux absorbs the 2026 protocol and emits already-
-- composed plain ANSI to nvim :terminal. Trade-off: minor CJK width
-- misalignment in box-bordered UI inside the wrapped tmux — acceptable
-- vs. the tearing without it.
local function should_wrap_tmux()
  local env = vim.env.CLAUDE_WRAP_TMUX
  if env == "1" or env == "true" then return true end
  if env == "0" or env == "false" then return false end
  return vim.g.claude_wrap_tmux ~= false
end

local function build_terminal_cmd()
  local plugin_args = vim.env.CLAUDE_PLUGIN_DIR
    and (" " .. table.concat(vim.tbl_map(function(d) return "--plugin-dir " .. d end, vim.split(vim.env.CLAUDE_PLUGIN_DIR, ",")), " "))
    or ""
  local claude_cmd = "claude" .. plugin_args

  -- Skip the wrapper unless tmux is available AND wrapping is explicitly enabled.
  if vim.fn.executable("tmux") ~= 1 or not should_wrap_tmux() then
    return claude_cmd
  end

  -- Rationale for the wrapper lives in should_wrap_tmux above. Implementation
  -- notes below.
  --
  -- Dedicated tmux server (-L <socket>) isolates our hooks and sessions from
  -- the user's regular tmux. The client-detached -> kill-server hook tears
  -- down this server when the host terminal closes, so claude exits with it
  -- and we never leak into unrelated sessions.
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
    -- Fullscreen / alt-screen rendering: doesn't fix the resize drift bugs
    -- (see huiyu/nvim#2) but keeps scrollback memory bounded and enables
    -- mouse support inside the TUI. Hardcoded =1 so it doesn't depend on
    -- the user's shell env (tmux only forwards what's whitelisted via -e).
    "-e CLAUDE_CODE_NO_FLICKER=1",
    claude_cmd .. ' "$@"',
    "\\; set-option -g destroy-unattached on",
    "\\; set-option -g exit-empty on",
    -- Hide status bar in wrapper tmux: avoids periodic status redraws
    -- and stale-frame artifacts on resize (host's tmux.conf still loads,
    -- but status is overridden here per-server).
    "\\; set-option -g status off",
    "\\; set-hook -g client-detached kill-server",
  }, " ")
  return "sh -c '" .. inner .. "' _"
end

-- Detached watchdog: polls our nvim pid and tears down the dedicated tmux
-- server when nvim dies. Needed because when claude is launched via tmux
-- (see build_terminal_cmd above), abruptly closing the host terminal window
-- leaves the tmux server alive — the `client-detached -> kill-server` hook
-- only fires on a graceful detach, and VimLeavePre cleanup runs as a child
-- of nvim and gets killed alongside it on SIGHUP (e.g. terminal tab close),
-- so its kill-server never completes. Without this watchdog, orphaned tmux
-- servers (and the claude processes inside them) accumulate across crashes
-- and forced window closes. The watchdog is spawned via `setsid` to leave
-- nvim's process group/session, making it immune to the SIGHUP cascade.
-- Also sweeps stale sockets from prior crashes on startup.
if vim.fn.executable("tmux") == 1 and should_wrap_tmux() then
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
