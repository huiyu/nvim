-- Lock the dashboard buffer against scrolling: the layout is centered on open
-- and any viewport shift breaks the panes. We can't use FileType because
-- snacks sets `eventignore = "all"` while assigning the dashboard filetype,
-- so we hook the `SnacksDashboardOpened` user event it fires afterwards.
vim.api.nvim_create_autocmd("User", {
  pattern = "SnacksDashboardOpened",
  callback = function()
    local buf = vim.api.nvim_get_current_buf()
    if vim.bo[buf].filetype ~= "snacks_dashboard" then return end
    vim.b[buf].snacks_scroll = false
    local map_opts = { buffer = buf, silent = true, nowait = true }
    -- Only disable keys that genuinely scroll the viewport. j/k/arrows/gg/G are
    -- left alone so snacks' built-in cursor navigation between menu items still
    -- works (it snaps the cursor to the nearest actionable key).
    for _, key in ipairs({
      "<C-d>", "<C-u>", "<C-f>", "<C-b>", "<C-e>", "<C-y>",
      "<ScrollWheelUp>", "<ScrollWheelDown>",
      "<PageUp>", "<PageDown>",
    }) do
      vim.keymap.set("n", key, "<Nop>", map_opts)
    end
    -- Belt and suspenders: any WinScrolled on this buffer restores the
    -- initial topline so external scroll sources (mouse-drag, plugins) can't
    -- shift the layout either.
    local view
    vim.schedule(function()
      local win = vim.fn.bufwinid(buf)
      if win ~= -1 then
        view = vim.api.nvim_win_call(win, vim.fn.winsaveview)
      end
    end)
    local restoring = false
    vim.api.nvim_create_autocmd("WinScrolled", {
      buffer = buf,
      callback = function()
        if restoring or not view then return end
        restoring = true
        vim.schedule(function()
          local win = vim.fn.bufwinid(buf)
          if win ~= -1 then
            vim.api.nvim_win_call(win, function() vim.fn.winrestview(view) end)
          end
          restoring = false
        end)
      end,
    })
  end,
})

return {
  "folke/snacks.nvim",
  lazy = false,
  keys = {
    -- ── Top-level shortcuts (Doom-style) ────────────────────────────────
    -- <space> = smart picker (buffers + recent + files, frecency-boosted),
    -- . = pure file find in cwd, / = search project
    { "<leader><space>", function() Snacks.picker.smart() end,            desc = "Smart find (buffers/recent/files)" },
    { "<leader>.",       function() Snacks.picker.files() end,            desc = "Find file in cwd" },
    { "<leader>/",       function() Snacks.picker.grep() end,             desc = "Search project" },
    { "<leader>,",       function() Snacks.picker.buffers() end,          desc = "Buffers" },
    { "<leader>:",       function() Snacks.picker.command_history() end,  desc = "Command history" },
    { "<leader>'",       function() Snacks.picker.resume() end,           desc = "Resume last picker" },

    -- ── <leader>f — File ────────────────────────────────────────────────
    { "<leader>ff", function() Snacks.picker.files() end,                                          desc = "Find file in cwd" },
    { "<leader>fF", function() Snacks.picker.files({ cwd = vim.fn.expand("%:p:h") }) end,          desc = "Find file from here (buffer dir)" },
    { "<leader>fd", function() Snacks.explorer({ cwd = vim.fn.expand("%:p:h"), focus = "list" }) end, desc = "Find directory (browse)" },
    { "<leader>fr", function() Snacks.picker.recent({ filter = { cwd = true } }) end,              desc = "Recent files" },
    { "<leader>fb", function() Snacks.picker.buffers() end,                                        desc = "Buffers" },
    { "<leader>fg", function() Snacks.picker.git_files() end,                                      desc = "Git files" },
    { "<leader>fp", function() Snacks.picker.projects() end,                                       desc = "Switch project" },
    { "<leader>fc", function() Snacks.picker.files({ cwd = vim.fn.stdpath("config") }) end,        desc = "Find file in nvim config" },
    { "<leader>fn", "<cmd>enew<cr>",                                                                desc = "New file" },
    { "<leader>fs", "<cmd>w<cr>",                                                                   desc = "Save file" },
    { "<leader>fS", function()
        vim.ui.input({ prompt = "Save as: ", default = vim.fn.expand("%:p"), completion = "file" }, function(name)
          if name and name ~= "" then vim.cmd("saveas " .. vim.fn.fnameescape(name)) end
        end)
      end, desc = "Save file as..." },
    { "<leader>fR", function() Snacks.rename.rename_file() end,                                    desc = "Rename/move file" },
    { "<leader>fD", function()
        local path = vim.fn.expand("%:p")
        if path == "" then vim.notify("No file for current buffer", vim.log.levels.WARN); return end
        if vim.fn.confirm("Delete '" .. path .. "'?", "&Yes\n&No", 2) == 1 then
          vim.fn.delete(path)
          vim.cmd("bdelete!")
          vim.notify("Deleted: " .. path)
        end
      end, desc = "Delete this file" },
    { "<leader>fy", function()
        local path = vim.fn.expand("%:p")
        if path == "" then vim.notify("Buffer has no file", vim.log.levels.WARN); return end
        vim.fn.setreg("+", path); vim.fn.setreg('"', path)
        vim.notify("Yanked: " .. path)
      end, desc = "Yank file path (absolute)" },
    { "<leader>fY", function()
        local path = vim.fn.expand("%:p")
        if path == "" then vim.notify("Buffer has no file", vim.log.levels.WARN); return end
        local root = Snacks.git.get_root() or vim.fn.getcwd()
        local rel = (path:find(root, 1, true) == 1) and path:sub(#root + 2) or vim.fn.fnamemodify(path, ":~:.")
        vim.fn.setreg("+", rel); vim.fn.setreg('"', rel)
        vim.notify("Yanked: " .. rel)
      end, desc = "Yank file path from project" },
    { "<leader>ft", function() Snacks.terminal() end,                                              desc = "Terminal (root)" },
    { "<leader>fT", function() Snacks.terminal(nil, { cwd = vim.uv.cwd() }) end,                   desc = "Terminal (cwd)" },

    -- ── <leader>s — Search ──────────────────────────────────────────────
    { "<leader>sb", function() Snacks.picker.lines() end,                 desc = "Search buffer" },
    { "<leader>sB", function() Snacks.picker.grep_buffers() end,          desc = "Search all open buffers" },
    { "<leader>sd", function() Snacks.picker.grep({ cwd = vim.fn.expand("%:p:h") }) end, desc = "Search current directory" },
    { "<leader>sp", function() Snacks.picker.grep() end,                  desc = "Search project (cwd)" },
    { "<leader>sw", function() Snacks.picker.grep_word() end,             desc = "Word under cursor", mode = { "n", "x" } },
    { "<leader>ss", function() Snacks.picker.lsp_symbols() end,           desc = "Symbol in buffer" },
    { "<leader>sS", function() Snacks.picker.lsp_workspace_symbols() end, desc = "Symbol in workspace" },
    { "<leader>sR", function() Snacks.picker.resume() end,                desc = "Resume" },
    { "<leader>sh", function() Snacks.picker.help() end,                  desc = "Help pages" },
    { "<leader>sk", function() Snacks.picker.keymaps() end,               desc = "Keymaps" },
    { "<leader>sm", function() Snacks.picker.marks() end,                 desc = "Marks" },
    { "<leader>sj", function() Snacks.picker.jumps() end,                 desc = "Jumps" },
    { "<leader>sc", function() Snacks.picker.command_history() end,       desc = "Command history" },
    { "<leader>sC", function() Snacks.picker.commands() end,              desc = "Commands" },
    { '<leader>s"', function() Snacks.picker.registers() end,             desc = "Registers" },
    { "<leader>sM", function()
        local name = vim.fn.input("Man: ")
        if name and name ~= "" then vim.cmd("Man " .. vim.fn.fnameescape(name)) end
      end, desc = "Man pages" },

    -- ── Code (LSP symbols) ──────────────────────────────────────────────
    { "<leader>cs", function() Snacks.picker.lsp_symbols() end,           desc = "Document Symbols" },
    { "<leader>cS", function() Snacks.picker.lsp_workspace_symbols() end, desc = "Workspace Symbols" },

    -- ── Diagnostics ─────────────────────────────────────────────────────
    { "<leader>xx", function() Snacks.picker.diagnostics() end,           desc = "Diagnostics" },
    { "<leader>xX", function() Snacks.picker.diagnostics_buffer() end,    desc = "Buffer diagnostics" },
    { "<leader>xd", vim.diagnostic.open_float,                            desc = "Line diagnostics" },
    { "<leader>xL", function() Snacks.picker.loclist() end,               desc = "Location list" },
    { "<leader>xQ", function() Snacks.picker.qflist() end,                desc = "Quickfix list" },

    -- ── Git ─────────────────────────────────────────────────────────────
    { "<leader>gs", function() Snacks.picker.git_status() end,            desc = "Git status" },
    { "<leader>gb", function() Snacks.picker.git_branches() end,          desc = "Git branches" },
    { "<leader>gc", function() Snacks.picker.git_log_file() end,          desc = "Buffer commits" },
    { "<leader>gC", function() Snacks.picker.git_log() end,               desc = "Project commits" },

    -- ── Explorer / misc snacks ──────────────────────────────────────────
    {
      "<leader>e",
      function()
        require("snacks").explorer({
          hidden = true,
          focus = "list",
        })
      end,
      desc = "File tree",
      mode = { "n", "v" },
    },
    { "<leader>E", function() require("snacks").explorer({ hidden = true, layout = { preset = "default" }, auto_close = true, focus = "list" }) end, desc = "File explorer", mode = { "n", "v" } },
    { "<leader>fe", function() require("snacks").explorer({ hidden = true, ignored = true, layout = { preset = "default" }, auto_close = true, focus = "list" }) end, desc = "File explorer (with ignored)", mode = { "n", "v" } },
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
    picker = {
      enabled = true,
      ui_select = true, -- replace vim.ui.select with snacks picker
      sources = {
        -- filename-first display: shorter, scannable in Java deep paths
        files = {
          hidden = true,
          format = "file",
        },
        grep = {
          hidden = true,
        },
        recent = {
          format = "file",
        },
        buffers = {
          format = "file",
        },
      },
    },
    dashboard = {
      enabled = true,
      width = 70,
      preset = {
        keys = {
          { icon = "󰈞 ", key = "f", desc = "Find File", action = ":lua Snacks.dashboard.pick('files')" },
          { icon = "󰊄 ", key = "g", desc = "Find Text", action = ":lua Snacks.dashboard.pick('live_grep')" },
          { icon = "󰋚 ", key = "r", desc = "Recent Files", action = ":lua Snacks.dashboard.pick('oldfiles')" },
          { icon = "󰚩 ", key = "a", desc = "Claude Code", action = ":ClaudeCode" },
          { icon = "󱉭 ", key = "p", desc = "Projects", action = ":lua Snacks.picker.projects()" },
          { icon = "󰙅 ", key = "e", desc = "Explorer", action = ":lua Snacks.explorer({hidden=true, layout={preset='default'}, auto_close=true, focus='list'})" },
          { icon = "󰒓 ", key = "c", desc = "Config", action = ":lua Snacks.dashboard.pick('files', {cwd = vim.fn.stdpath('config')})" },
          { icon = "󰒲 ", key = "l", desc = "Lazy", action = ":Lazy" },
          -- Repo/GitHub jumps: open the repo / issues list / PRs list in browser.
          { icon = "󰊤 ", key = "b", desc = "Browse Repo", action = ":lua Snacks.gitbrowse()" },
          { icon = "󰨰 ", key = "i", desc = "Open Issues", action = ":lua vim.fn.jobstart('gh issue list --web', {detach=true})" },
          { icon = "󰜘 ", key = "o", desc = "Open PRs", action = ":lua vim.fn.jobstart('gh pr list --web', {detach=true})" },
          { icon = "󰦛 ", key = "s", desc = "Restore Session", section = "session" },
          { icon = "󰩈 ", key = "q", desc = "Quit", action = ":qa" },
        },
      },
      sections = {
        -- Left pane (pane 1): cowsay banner (rainbow via lolcat) + keys
        { section = "terminal", cmd = "cowsay 'Talk is cheap, show me the code.' | lolcat -f", padding = 1, indent = 15 },
        { section = "keys", gap = 1, padding = 1 },

        -- Right pane (pane 2): decoration + browse repo + gh + git status
        {
          pane = 2,
          section = "terminal",
          cmd = [[printf '\n\n████ ████ ████ ████ ████ ████ ████\n\n       Welcome back, Jeff\n       %s\n\n████ ████ ████ ████ ████ ████ ████\n' "$(date '+%A, %B %d')" | lolcat -f]],
          height = 8,
          padding = 1,
          indent = 18,
          enabled = vim.fn.executable("lolcat") == 1,
        },
        function()
          -- Snacks.git.get_root() returns non-nil inside bare-repo controller dirs
          -- (e.g. ~/repo/ with .git pointing to .bare/), but those aren't worktrees.
          local toplevel = vim.fn.system({ "git", "rev-parse", "--is-inside-work-tree" })
          local in_git = vim.v.shell_error == 0 and vim.trim(toplevel) == "true"
          local has_gh = vim.fn.executable("gh") == 1
          -- gh-notify is an extension; detect once at dashboard load
          local has_gh_notify = has_gh
            and vim.fn.system("gh extension list 2>/dev/null"):find("gh%-notify") ~= nil
          -- gh subcommands fatal with "no git remotes found" when cwd has no
          -- github remote (e.g. fresh `git init` without `git remote add`).
          local has_gh_remote = in_git
            and vim.fn.system("git remote -v 2>/dev/null"):find("github") ~= nil
          local cmds = {
            {
              title = "Notifications",
              cmd = "gh notify -s -a -n5",
              action = function() vim.ui.open("https://github.com/notifications") end,
              key = "n",
              icon = "󰂚 ",
              height = 5,
              enabled = has_gh_notify and has_gh_remote,
            },
            {
              title = "Open Issues",
              cmd = "gh issue list -L 3",
              -- Capital I opens snacks' native GitHub issue picker (fuzzy + live
              -- preview); <cr> shows the action menu, <a-b> opens in the browser.
              -- Lowercase i on the left opens the full issues list webpage.
              key = "I",
              action = function() Snacks.picker.gh_issue() end,
              icon = "󰨰 ",
              height = 7,
              enabled = has_gh and has_gh_remote,
            },
            {
              icon = "󰜘 ",
              title = "Open PRs",
              cmd = "gh pr list -L 3",
              -- Capital O opens snacks' native GitHub PR picker (fuzzy + live
              -- preview/diff); <cr> shows the action menu, <a-b> opens in the
              -- browser. Lowercase o on the left opens the full PR list webpage.
              key = "O",
              action = function() Snacks.picker.gh_pr() end,
              height = 7,
              enabled = has_gh and has_gh_remote,
            },
            {
              icon = "󰊢 ",
              title = "Git Status",
              cmd = "git --no-pager diff --stat -B -M -C",
              height = 10,
            },
          }
          return vim.tbl_map(function(cmd)
            return vim.tbl_extend("force", {
              pane = 2,
              section = "terminal",
              enabled = in_git and (cmd.enabled ~= false),
              padding = 1,
              ttl = 5 * 60,
              indent = 3,
            }, cmd)
          end, cmds)
        end,

        { section = "startup" },
      },
    }
  }
}
