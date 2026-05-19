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
        { section = "terminal", cmd = "cowsay 'Talk is cheap, show me the code.'", hl = "header", padding = 1, indent = 8, ttl = 60 * 60 },
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
          enabled = function() return Snacks.git.get_root() ~= nil end,
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
