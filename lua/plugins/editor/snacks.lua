-- Snacks base setup, pickers, notifications and terminal toggle. Dashboard,
-- path-copy actions, Lazygit and zen contribute through their feature specs.

-- Directories skipped by file/grep pickers when `ignored = true` is on, so
-- searching gitignored files still stays fast and noise-free. `.git/` is
-- always excluded by snacks itself, so it is not listed here.
--
-- NOTE: `exclude` maps to `fd -E <name>` / `rg -g '!<name>'`, which drops any
-- directory of that name UNCONDITIONALLY — even git-tracked source. Only
-- unique, unambiguous build/dep dir names are listed. Generic names that
-- often hold tracked source (bin, out, vendor, deps, obj) are deliberately
-- left out to avoid hiding real files.
local search_exclude = {
  -- JS / TS / web
  "node_modules", ".next", ".nuxt", ".svelte-kit", ".astro", ".turbo",
  ".parcel-cache", ".angular", "bower_components", "coverage",
  -- Python
  ".venv", "venv", "__pycache__", ".mypy_cache", ".pytest_cache",
  ".ruff_cache", ".tox", ".ipynb_checkpoints",
  -- JVM (Gradle / Maven) + Rust (target) + Scala
  "target", "build", ".gradle",
  -- iOS / Swift / Xcode
  "Pods", "DerivedData", ".build",
  -- Elixir / Erlang
  "_build",
  -- Dart / Flutter
  ".dart_tool",
  -- Haskell
  "dist-newstyle", ".stack-work",
  -- Infra / tooling
  ".terraform", ".serverless", ".cache",
  -- General build output
  "dist",
}

return {
  "folke/snacks.nvim",
  lazy = false,
  keys = {
    -- ── `;` — go to a file ──────────────────────────────────────────────
    -- Project navigation uses two keys under `;`. The bare prefix stays
    -- unmapped so builtin repeat-f/t still runs after 'timeoutlen'.
    -- Nvim config and installed plugin source are editor maintenance:
    -- their file pickers live under <leader>mf / <leader>mF in Manage below.
    { ";<space>", function() Snacks.picker.smart({ filter = { cwd = true } }) end,                  desc = "Smart find (buffers/recent/files, cwd-only)" },
    { ";;",       function() Snacks.picker.resume() end,                                            desc = "Resume last picker" },
    { ";f",       function() Snacks.picker.files() end,                                             desc = "Find file in cwd" },
    { ";i",       function() Snacks.picker.files({ ignored = false, exclude = {} }) end,           desc = "Find file in cwd (respect gitignore)" },
    { ";F",       function() Snacks.picker.files({ cwd = require("util.cwd").buffer_dir() }) end,   desc = "Find file from here (file's dir)" },
    { ";r",       function() Snacks.picker.recent({ filter = { cwd = true } }) end,                 desc = "Recent files in cwd" },
    { ";b",       function() Snacks.picker.buffers() end,                                           desc = "Buffers" },
    { ";g",       function() Snacks.picker.git_files() end,                                         desc = "Git files" },
    { ";p",       function() Snacks.picker.projects() end,                                          desc = "Switch project" },
    { ";/",       function() Snacks.picker.grep() end,                                              desc = "Search in cwd" },
    { ";?",       function() Snacks.picker.grep({ ignored = false, exclude = {} }) end,            desc = "Search in cwd (respect gitignore)" },
    { ";w",       function() Snacks.picker.grep_word() end,                                         desc = "Search word under cursor", mode = { "n", "x" } },
    -- Symbols and in-file matches answer the same question as the file
    -- pickers above -- "where do I need to be?" -- so they share the prefix.
    -- These search without a starting point; the LSP jumps that begin from the
    -- symbol under the cursor live on `g` instead (see plugins/coding/lsp.lua).
    { ";s",       function() Snacks.picker.lsp_symbols() end,                                       desc = "[LSP] Symbol in file" },
    { ";S",       function() Snacks.picker.lsp_workspace_symbols() end,                             desc = "[LSP] Symbol in workspace" },
    { ";l",       function() Snacks.picker.lines() end,                                             desc = "Lines in file" },
    { ";D",       function() Snacks.picker.grep({ cwd = require("util.cwd").buffer_dir() }) end,    desc = "Search from here (file's dir)" },
    { ";j",       function() Snacks.picker.jumps() end,                                             desc = "Jumps" },
    { ";m",       function() Snacks.picker.marks() end,                                             desc = "Marks" },
    -- Every changed hunk in the repository, staged and unstaged. Like a mark,
    -- a hunk is a place to be that needs no cursor context, unlike ]h/[h. In
    -- the picker <Tab> stages or unstages a hunk and <C-x> restores it: after
    -- a confirmation an unstaged hunk is discarded from the working tree.
    { ";c",       function() Snacks.picker.git_diff() end,                                          desc = "Git hunks" },

    -- ── <leader>m — Manage the editor ────────────────────────────────────
    { "<leader>mf", function() Snacks.picker.files({ cwd = vim.fn.stdpath("config") }) end, desc = "Find Nvim config file" },
    {
      "<leader>mF",
      function()
        Snacks.picker.files({ cwd = require("lazy.core.config").options.root, ignored = false, exclude = {} })
      end,
      desc = "Find plugin source file",
    },
    { "<leader>mh", function() Snacks.picker.help() end,                                 desc = "Help pages" },
    { "<leader>mk", function() Snacks.picker.keymaps() end,                              desc = "Keymaps" },
    { "<leader>mc", function() Snacks.picker.command_history() end,                      desc = "Command history" },
    { "<leader>mC", function() Snacks.picker.commands() end,                             desc = "Commands" },
    { '<leader>y"', function() Snacks.picker.registers() end,                            desc = "Registers" },
    {
      "<leader>mM",
      function()
        local name = vim.fn.input("Man: ")
        if name and name ~= "" then vim.cmd("Man " .. vim.fn.fnameescape(name)) end
      end,
      desc = "Man page…"
    },

    -- ── Diagnostics ─────────────────────────────────────────────────────
    { "<leader>xx", function() Snacks.picker.diagnostics() end,           desc = "Diagnostics" },
    { "<leader>xb", function() Snacks.picker.diagnostics_buffer() end,    desc = "File diagnostics" },
    { "<leader>xd", vim.diagnostic.open_float,                            desc = "Line diagnostics" },
    { "<leader>xL", function() Snacks.picker.loclist() end,               desc = "Location list (picker)" },
    { "<leader>xQ", function() Snacks.picker.qflist() end,                desc = "Quickfix list (picker)" },

    -- ── Git ─────────────────────────────────────────────────────────────
    { "<leader>gs", function() Snacks.picker.git_status() end,            desc = "Git status" },
    { "<leader>gb", function() Snacks.picker.git_branches() end,          desc = "Git branches" },
    { "<leader>gc", function() Snacks.picker.git_log_file() end,          desc = "File commits" },
    { "<leader>gC", function() Snacks.picker.git_log() end,               desc = "Repo commits" },

    -- ── Misc snacks ─────────────────────────────────────────────────────
    -- No tree sidebar: directories are browsed and edited through oil (`-`,
    -- `;o`, lua/plugins/editor/oil.lua) and files are reached through the
    -- pickers above.
    {
      "<leader>un",
      function()
        -- noice's dismiss also closes the split a long message opened
        -- (lua/plugins/ui/noice.lua). It is only asked once loaded: requiring
        -- it here would load it, and without a UI it must stay unloaded.
        if package.loaded.noice then pcall(require("noice").cmd, "dismiss") end
        Snacks.notifier.hide()
      end,
      desc = "Dismiss notifications",
    },

    -- ── Messages (<leader>mn) ───────────────────────────────────────────
    -- Two histories: vim.notify goes to the snacks notifier and its own
    -- history, while Vim's messages (:echomsg, print(), errors; never a plain
    -- :echo, which only g< shows again) stay in :messages. noice
    -- (lua/plugins/ui/noice.lua) shows both of those in a split, and pops
    -- Vim's messages up through the notifier as well: its history keeps
    -- their errors and warnings, and the latest ordinary message.
    -- Dismissing notifications is <leader>un alone: one act, one key.
    { "<leader>mnh", function() Snacks.notifier.show_history() end,  desc = "Notification history" },
    { "<leader>mnt", function() Snacks.picker.notifications() end,   desc = "Search notifications" },
    { "<leader>mnl", "g<",                                           desc = "Last command output" },
    { "<leader>mna", "<Cmd>messages<CR>",                            desc = "Message history" },
    { "<C-/>",      function() require("util.terminal").toggle() end,        desc = "Toggle terminal", mode = { "n", "t" } },
    { "<C-_>",      function() require("util.terminal").toggle() end,        desc = "Toggle terminal", mode = { "n", "t" } },
    -- Numbered switching is buffer-local, installed by TermOpen in lua/config/autocmds.lua.
  },
  config = function(_, opts)
    require("snacks").setup(opts)
    -- Started without a UI (`nvim --headless --listen`), the notifier is off,
    -- so a UI attached later through --remote-ui would keep the builtin
    -- vim.notify. Hand it over on that first UIEnter, the way setup() would
    -- have; the notifier module itself works whether or not it was enabled.
    -- The flag goes on too: noice (VeryLazy, which runs after this on that
    -- same UIEnter) sends Vim's messages to the notifier only when it reads
    -- enabled, and to a view of its own otherwise.
    -- A headless run never fires UIEnter, so stderr keeps every message.
    if not opts.notifier.enabled then
      vim.api.nvim_create_autocmd("UIEnter", {
        once = true,
        callback = function()
          Snacks.config.notifier.enabled = true
          vim.notify = Snacks.notifier.notify
        end,
        desc = "Route vim.notify to the snacks notifier for a UI that attached after startup",
      })
    end
  end,
  opts = {
    image = {
      enabled = true,
    },
    -- Only with a UI attached. Enabled, it takes over vim.notify as soon as
    -- snacks is set up, and in --headless that would swallow every warning
    -- and error the specs and the startup check rely on seeing on stderr.
    -- A UI that attaches later gets it from `config` below.
    notifier = { enabled = #vim.api.nvim_list_uis() > 0 },
    indent = { enabled = true },
    scroll = { enabled = true },
    picker = {
      enabled = true,
      ui_select = true, -- replace vim.ui.select with snacks picker
      -- Give location pickers somewhere legitimate to put the file they open.
      -- snacks/picker/core/main.lua falls back to a panel's window when no
      -- window in the tab holds a plain file; util.buffer aims them at the
      -- editor area instead and holds the list of sources it does this for.
      on_show = function(picker) require("util.buffer").picker_on_show(picker) end,
      -- Toggle hidden files moves from <M-h> to <M-.>: tmux takes Alt-h for
      -- pane navigation before Nvim sees it, and `.` is oil's `g.`. Both
      -- windows also answer g?, the help key of every other view, beside
      -- their own `?` (Normal mode).
      win = {
        input = {
          keys = {
            ["<M-h>"] = false,
            ["<M-.>"] = { "toggle_hidden", mode = { "i", "n" } },
            ["g?"] = "toggle_help_input",
          },
        },
        list = {
          keys = {
            ["<M-h>"] = false,
            ["<M-.>"] = "toggle_hidden",
            ["g?"] = "toggle_help_list",
          },
        },
      },
      sources = {
        -- filename-first display: shorter, scannable in Java deep paths
        -- hidden: show dotfiles; ignored: also search gitignored files
        -- (.git/ is always excluded by snacks); exclude: skip heavy dep/build
        -- dirs (see `search_exclude` above) so gitignored search stays fast.
        files = {
          hidden = true,
          ignored = true,
          exclude = search_exclude,
          format = "file",
        },
        grep = {
          hidden = true,
          ignored = true,
          exclude = search_exclude,
        },
        recent = {
          format = "file",
        },
        -- Upstream maps <C-w> to "tcd to the project" in Insert mode too, so
        -- typing a query cannot delete a word. Insert <C-w> goes back to the
        -- picker's own delete-word: the input is a prompt buffer, where a
        -- bare <C-w> would start a window command, hence <c-s-w>. The source
        -- key replaces the default spec whole, so the delete-word spec is
        -- given again under a name of its own. <C-r> ("tcd, then recent
        -- files") is Normal only too: upstream's nowait Insert spec took the
        -- input's register inserts (<C-r>a, <C-r><C-w>, <C-r>%).
        projects = {
          win = {
            input = {
              keys = {
                ["<c-w>"] = { { "tcd" }, mode = { "n" } },
                i_ctrl_w = { "<c-w>", "<c-s-w>", mode = { "i" }, expr = true, desc = "delete word" },
                ["<c-r>"] = { { "tcd", "picker_recent" }, mode = { "n" } },
              },
            },
          },
        },
        -- Upstream restores (discards) a file or hunk on a nowait <C-r> in
        -- Insert and Normal mode, which takes the input's register inserts
        -- (<C-r><C-w>, <C-r>%) and Normal redo. It moves to <C-x>, the
        -- "remove an item" chord of the other pickers (buffers, marks,
        -- branches), and keeps Snacks' own confirmation.
        git_status = {
          win = {
            input = {
              keys = {
                ["<c-r>"] = false,
                ["<c-x>"] = { "git_restore", mode = { "n", "i" } },
              },
            },
          },
        },
        git_diff = {
          win = {
            input = {
              keys = {
                ["<c-r>"] = false,
                ["<c-x>"] = { "git_restore", mode = { "n", "i" } },
              },
            },
          },
        },
        buffers = {
          format = "file",
          -- Even with hidden buffers shown, selecting an agent terminal here
          -- must not replace the editor and let edgy absorb it into the edge.
          -- This filter also applies to the buffers source in smart find.
          filter = {
            filter = function(item) return item.buftype ~= "terminal" end,
          },
        },
      },
    },
  }
}
