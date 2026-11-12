-- The command line, Vim's own messages and the cmdline completion menu, drawn
-- by noice instead of Nvim's message grid: `:` opens a popup near the top with
-- its completion menu under it, `/` and `?` stay on the bottom row.
--
-- vim.notify stays the snacks notifier's (lua/plugins/editor/snacks.lua), and
-- noice's `notify` view hands Vim's messages to that same notifier: one kind
-- of popup on screen. Errors and warnings each keep an entry in its history
-- (<leader>mnh); ordinary messages (:echo, :echomsg, print(), :! output)
-- share one "Messages" popup that the next one updates in place. :messages
-- (<leader>mna) keeps :echomsg and print(); :echo and :! output are kept in
-- neither.
--
-- Loaded on VeryLazy, which lazy.nvim fires only once a UI is attached
-- (UIEnter). A --headless run -- the specs, the startup check -- never loads
-- it, and keeps plain stdout/stderr messages; a UI attached later through
-- --remote-ui gets it on that first UIEnter.
return {
  "folke/noice.nvim",
  event = "VeryLazy",
  dependencies = { "MunifTanjim/nui.nvim" },
  opts = {
    -- vim.notify keeps going straight to the snacks notifier, as it does
    -- before VeryLazy and without a UI.
    notify = { enabled = false },
    lsp = {
      -- Each of these has an owner already, and a second one would draw the
      -- same thing twice: progress is lualine's `lsp_status`, hover is K's
      -- rounded, silent vim.lsp.buf.hover with <C-f>/<C-b> to scroll it, and
      -- signature help is blink.cmp's while typing, gK's on demand
      -- (lua/plugins/coding/lsp.lua, lua/plugins/coding/cmp.lua).
      progress = { enabled = false },
      hover = { enabled = false },
      signature = { enabled = false },
      -- A server's window/showMessage stays Nvim's own handler, which goes to
      -- vim.notify, the notifier. noice's would set the handler to nil at the
      -- pinned commit (lsp/message.lua assigns an undefined M._on_message),
      -- and every server message -- "failed to load workspace" -- would be
      -- dropped without a trace.
      message = { enabled = false },
    },
    -- Nvim 0.11+ gives these messages kinds of their own, which noice's
    -- default routes ("", echo, echomsg, lua_print, list_cmd, errors,
    -- warnings) do not list. A message no route takes is dropped, and with
    -- noice attached Nvim no longer draws it itself. User routes come before
    -- the presets', so `max_height` leaves 20 lines and more to
    -- long_message_to_split's split.
    routes = {
      {
        -- :w sends two `progress` messages: the bare quoted path while it
        -- writes, then the same path with "written". Nvim means the second to
        -- replace the first (by the message `id`, which noice does not read),
        -- so without this every save showed two lines.
        filter = { event = "msg_show", kind = "progress", find = '^"[^"]*"%s*$' },
        opts = { skip = true },
      },
      {
        -- Output asked for: :! (shell_cmd, the echoed command, stays out),
        -- 'verbose', 'wildmode' lists. The same popup as other messages.
        filter = {
          event = "msg_show",
          kind = { "shell_out", "shell_err", "shell_ret", "verbose", "wildlist" },
          max_height = 19,
        },
        view = "notify",
        opts = { replace = true, merge = true, title = "Messages" },
      },
      {
        -- Confirmations of what just happened: :w's "written" (`progress`
        -- since 0.12), u's "1 change; before #3", ]q's "(2 of 9)". Small at
        -- the bottom right for two seconds, and kept out of the notification
        -- history, where every save would bury the rest (:messages still has
        -- them).
        filter = { event = "msg_show", kind = { "progress", "undo", "quickfix" }, max_height = 19 },
        view = "mini",
      },
    },
    presets = {
      bottom_search = true,         -- / and ? on the bottom row, as Vim draws them
      command_palette = true,       -- : and its completion menu together, near the top
      long_message_to_split = true, -- a message of 20 lines or more opens in a split
    },
  },
}
