return {
  "folke/snacks.nvim",
  lazy = false,
  keys = {
    {
      "<leader>e",
      function()
        require("snacks").explorer({
          focus = "list",
          on_show = function(picker)
            -- Fix layout: ensure bottom terminal spans full width when explorer
            -- opens after terminal. wincmd J needs the window to be truly current;
            -- nvim_win_call is unreliable for tree-restructuring wincmd commands.
            -- Use vim.defer_fn to let the picker settle, then temporarily switch
            -- focus and restore it to the explorer list afterward.
            vim.defer_fn(function()
              local layout_changed = false
              for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
                if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_config(win).relative == "" then
                  local buf = vim.api.nvim_win_get_buf(win)
                  if vim.bo[buf].buftype == "terminal" and not vim.wo[win].winfixwidth then
                    local col = vim.api.nvim_win_get_position(win)[2]
                    if col > 0 then
                      local height = vim.api.nvim_win_get_height(win)
                      vim.api.nvim_set_current_win(win)
                      vim.cmd("wincmd J")
                      if vim.api.nvim_win_is_valid(win) then
                        vim.api.nvim_win_set_height(win, height)
                      end
                      layout_changed = true
                    end
                  end
                end
              end
              if layout_changed then
                -- Restore focus to explorer list and fix panel sizes
                pcall(function() picker:focus("list") end)
                vim.schedule(function()
                  require("util.window").restore_fixed_panels()
                end)
              end
            end, 50)
          end,
        })
      end,
      desc = "File tree",
      mode = { "n", "v" },
    },
    { "<leader>E", function() require("snacks").explorer({ layout = { preset = "default" }, auto_close = true, focus = "list" }) end, desc = "File explorer", mode = { "n", "v" } },
    { "<leader>n", function() Snacks.notifier.show_history() end, desc = "Notification history" },
    { "<leader>un", function() Snacks.notifier.hide() end,        desc = "Dismiss notifications" },
    { "<leader>gg", function() Snacks.terminal("lazygit", { cwd = Snacks.git.get_root(), interactive = true, win = { style = "float", width = 0.9, height = 0.9 } }) end, desc = "Lazygit", mode = { "n" } },
    { "<leader>gf", function() Snacks.terminal({ "lazygit", "log", "--filter", vim.api.nvim_buf_get_name(0) }, { cwd = Snacks.git.get_root(), interactive = true, win = { style = "float", width = 0.9, height = 0.9 } }) end, desc = "Lazygit file history", mode = { "n" } },
    { "<C-/>",      function() require("util.terminal").toggle() end,              desc = "Toggle terminal",   mode = { "n", "t" } },
    { "<C-_>",      function() require("util.terminal").toggle() end,              desc = "Toggle terminal",   mode = { "n", "t" } },
    { "<leader>T1", function() require("util.terminal").toggle("term1") end,       desc = "Terminal 1" },
    { "<leader>T2", function() require("util.terminal").toggle("term2") end,       desc = "Terminal 2" },
    { "<leader>T3", function() require("util.terminal").toggle("term3") end,       desc = "Terminal 3" },
    { "<leader>T4", function() require("util.terminal").toggle("term4") end,       desc = "Terminal 4" },
    { "<leader>T5", function() require("util.terminal").toggle("term5") end,       desc = "Terminal 5" },
    { "<leader>T6", function() require("util.terminal").toggle("term6") end,       desc = "Terminal 6" },
    { "<leader>T7", function() require("util.terminal").toggle("term7") end,       desc = "Terminal 7" },
    { "<leader>T8", function() require("util.terminal").toggle("term8") end,       desc = "Terminal 8" },
    { "<leader>T9", function() require("util.terminal").toggle("term9") end,       desc = "Terminal 9" },
  },
  opts = {
    image = {
      enabled = true,
      backend = "kitty",
    },
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
