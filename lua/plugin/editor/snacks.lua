return {
  "folke/snacks.nvim",
  lazy = false,
  keys = {
    {
      "<leader>e",
      function()
        require("snacks").explorer({
          on_show = function()
            -- Fix layout: ensure bottom terminal spans full width when explorer opens after terminal
            vim.defer_fn(function()
              for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
                if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_config(win).relative == "" then
                  local buf = vim.api.nvim_win_get_buf(win)
                  if vim.bo[buf].buftype == "terminal" and not vim.wo[win].winfixwidth then
                    local col = vim.api.nvim_win_get_position(win)[2]
                    if col > 0 then
                      local height = vim.api.nvim_win_get_height(win)
                      local cur_win = vim.api.nvim_get_current_win()
                      vim.api.nvim_set_current_win(win)
                      vim.cmd("wincmd J")
                      vim.api.nvim_win_set_height(win, height)
                      vim.api.nvim_set_current_win(cur_win)
                      vim.schedule(function()
                        require("util.window").restore_fixed_panels()
                      end)
                    end
                  end
                end
              end
            end, 10)
          end,
        })
      end,
      desc = "File tree",
      mode = { "n", "v" },
    },
    { "<leader>E", function() require("snacks").explorer({ layout = { preset = "default" }, auto_close = true }) end, desc = "File explorer", mode = { "n", "v" } },
    { "<leader>n", function() Snacks.notifier.show_history() end, desc = "Notification history" },
    { "<leader>un", function() Snacks.notifier.hide() end,        desc = "Dismiss notifications" },
    { "<C-/>",      function() Snacks.terminal(nil, { win = { position = "bottom", height = 25 } }) end, desc = "Toggle terminal", mode = { "n", "t" } },
    { "<C-_>",      function() Snacks.terminal(nil, { win = { position = "bottom", height = 25 } }) end, desc = "Toggle terminal", mode = { "n", "t" } },
    { "<leader>T1", function() Snacks.terminal(nil, { win = { position = "bottom", height = 25 }, id = "term1" }) end, desc = "Terminal 1" },
    { "<leader>T2", function() Snacks.terminal(nil, { win = { position = "bottom", height = 25 }, id = "term2" }) end, desc = "Terminal 2" },
    { "<leader>T3", function() Snacks.terminal(nil, { win = { position = "bottom", height = 25 }, id = "term3" }) end, desc = "Terminal 3" },
    { "<leader>T4", function() Snacks.terminal(nil, { win = { position = "bottom", height = 25 }, id = "term4" }) end, desc = "Terminal 4" },
    { "<leader>T5", function() Snacks.terminal(nil, { win = { position = "bottom", height = 25 }, id = "term5" }) end, desc = "Terminal 5" },
    { "<leader>T6", function() Snacks.terminal(nil, { win = { position = "bottom", height = 25 }, id = "term6" }) end, desc = "Terminal 6" },
    { "<leader>T7", function() Snacks.terminal(nil, { win = { position = "bottom", height = 25 }, id = "term7" }) end, desc = "Terminal 7" },
    { "<leader>T8", function() Snacks.terminal(nil, { win = { position = "bottom", height = 25 }, id = "term8" }) end, desc = "Terminal 8" },
    { "<leader>T9", function() Snacks.terminal(nil, { win = { position = "bottom", height = 25 }, id = "term9" }) end, desc = "Terminal 9" },
  },
  opts = {
    notifier = { enabled = false },
    indent = { enabled = true },
    scroll = { enabled = true },
    dashboard = {
      enabled = true,
      preset = {
        keys = {
          { icon = " ", key = "f", desc = "Find File", action = ":lua Snacks.dashboard.pick('files')" },
          { icon = " ", key = "g", desc = "Find Text", action = ":lua Snacks.dashboard.pick('live_grep')" },
          { icon = " ", key = "r", desc = "Recent Files", action = ":lua Snacks.dashboard.pick('oldfiles')" },
          { icon = " ", key = "c", desc = "Config", action = ":lua Snacks.dashboard.pick('files', {cwd = vim.fn.stdpath('config')})" },
          { icon = " ", key = "s", desc = "Restore Session", section = "session" },
          { icon = " ", key = "q", desc = "Quit", action = ":qa" },
        },
      },
      sections = {
        { section = "terminal",     cmd = "cowsay 'Talk is cheap, show me the code.'", hl = "header", padding = 1, indent = 8 },
        { section = "keys",         padding = 1 },
        { section = "recent_files", title = "Recent files",                            cwd = true,    limit = 8,   padding = 1 },
        { section = "projects",     title = "Projects",                                padding = 1 },
        {
          icon = " ",
          desc = "Browse Repo",
          padding = 1,
          key = "b",
          action = function() Snacks.gitbrowse() end,
        },
        {
          icon = " ",
          title = "Git Status",
          section = "terminal",
          enabled = function()
            return Snacks.git.get_root() ~= nil
          end,
          cmd = "git status --short --branch --renames",
          height = 5,
          padding = 1,
          ttl = 5 * 60,
          indent = 3,
        },
        { section = "startup" },
      },
    }
  }
}
