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

-- Sources whose confirmation target is an editor location. Snacks otherwise
-- falls back to the first non-floating window when a tab contains only panels,
-- which can replace Oil or an agent terminal. Non-location pickers such as
-- commands, registers and vim.ui.select must not split the layout just by
-- opening, so keep this list explicit instead of applying the hook globally.
local editor_picker_sources = {
  buffers = true,
  diagnostics = true,
  diagnostics_buffer = true,
  files = true,
  git_files = true,
  git_status = true,
  grep = true,
  grep_word = true,
  jumps = true,
  loclist = true,
  lsp_incoming_calls = true,
  lsp_symbols = true,
  lsp_workspace_symbols = true,
  marks = true,
  qflist = true,
  recent = true,
  smart = true,
}

-- Dashboard banner pool. One is drawn at random per Nvim start.
-- Keep entries single-line; cowsay wraps them (see `cowsay_quote` below).
local quotes = {
  "Talk is cheap. Show me the code.  -- Linus Torvalds",
  "Make it work, make it right, make it fast.  -- Kent Beck",
  "Premature optimization is the root of all evil.  -- Donald Knuth",
  "There are only two hard things in CS: cache invalidation and naming things.",
  "Programs must be written for people to read, and only incidentally for machines to execute.  -- SICP",
  "Any fool can write code a computer understands. Good programmers write code humans understand.  -- Martin Fowler",
  "Always code as if the person maintaining it is a violent psychopath who knows where you live.  -- John Woods",
  "First, solve the problem. Then, write the code.",
  "Simplicity is the soul of efficiency.  -- Austin Freeman",
  "Deleted code is debugged code.  -- Jeff Sickel",
  "The best code is no code at all.",
  "Documentation is a love letter to your future self.  -- Damian Conway",
  "Weeks of coding can save you hours of planning.",
  "Debugging: being the detective in a crime movie where you are also the murderer.",
  "It's not a bug, it's an undocumented feature.",
  "It works on my machine.",
  "99 little bugs in the code. Take one down, patch it around: 127 little bugs in the code.",
  "// TODO: clean this up properly. Committed 2019.",
  "There is no cloud, it's just someone else's computer.",
  "One does not simply merge into main on a Friday.",
  "git commit -m 'minor fix'   # 47 files changed",
  "Real programmers count from zero.",
  "Rest in peace, my beautiful one-liner. You have been refactored.",
  "The code works and nobody knows why. The code fails and nobody knows why.",
}

-- The lolcat pipe needs a shell, so the quote is escaped instead of passed as
-- argv. `-W 36` caps the bubble at 38 columns, which keeps it inside the
-- 64-column pane once the section centers the roughly 39-column output.
-- LuaJIT's math.random is deterministic until seeded, so hrtime seeds it —
-- otherwise every session would greet you with the same quote.
local function cowsay_quote()
  math.randomseed(vim.uv.hrtime())
  local quote = quotes[math.random(#quotes)]
  return ("cowsay -W 36 %s | lolcat -f"):format(vim.fn.shellescape(quote))
end

-- The `square` colorscript from shell-color-scripts, inlined so the dashboard
-- banner needs no external binary. Each group is a 7-cell block drawn with the
-- normal ANSI foreground on its left half and the bright/bold one on its right.
-- Returned as list-form argv so no shell parses the raw escape bytes.
local function color_squares()
  local rows = { { "▀ █", "█ ▀" }, { "██ ", " ██" }, { "▄ █", "█ ▄" } }
  local lines = {}
  for _, row in ipairs(rows) do
    local groups = {}
    for color = 1, 6 do -- red, green, yellow, blue, magenta, cyan
      groups[#groups + 1] = ("\27[3%dm%s \27[1;9%dm%s\27[0m"):format(color, row[1], color, row[2])
    end
    lines[#lines + 1] = " " .. table.concat(groups, "   ")
  end
  return { "printf", "%s\n", table.concat(lines, "\n") }
end

-- Dashboard data is optional. Keep gh failures visible in their own section
-- without triggering Snacks' job-error popup. Capturing output and closing
-- stdin also prevents gh from probing the dashboard's noninteractive terminal.
local function dashboard_gh(args)
  return vim.list_extend({
    "sh", "-c", [[
unset GH_FORCE_TTY
if output=$(GH_PROMPT_DISABLED=1 GH_PAGER=cat GH_NO_UPDATE_NOTIFIER=1 GH_NO_EXTENSION_UPDATE_NOTIFIER=1 NO_COLOR=1 gh "$@" </dev/null 2>&1); then
  printf '%s\n' "$output"
else
  printf 'GitHub unavailable\n%s\n' "$output"
fi
]], "dashboard-gh",
  }, args)
end

-- <leader>y path keys. Each copies to the clipboard and the unnamed register,
-- and says what it copied.
local function yank(text)
  vim.fn.setreg("+", text); vim.fn.setreg('"', text)
  vim.notify("Yanked: " .. text)
end

---@return string? path the current buffer's absolute path, nil (with a warning) when it has none
local function buffer_path()
  local path = vim.fn.expand("%:p")
  if path == "" then
    vim.notify("Buffer has no file", vim.log.levels.WARN)
    return nil
  end
  return path
end

-- Relative to the git root, falling back to the cwd outside a repository.
local function project_path(path)
  local root = Snacks.git.get_root() or vim.fn.getcwd()
  return (path:find(root, 1, true) == 1) and path:sub(#root + 2) or vim.fn.fnamemodify(path, ":~:.")
end

-- The cursor line in Normal mode; in Visual the selected lines, after leaving
-- Visual so a copy ends the selection the way `y` does.
---@return integer first, integer last
local function target_lines()
  local first, last = vim.fn.line("."), vim.fn.line(".")
  if vim.fn.mode():find("^[vV\22]") then
    first, last = math.min(first, vim.fn.line("v")), math.max(first, vim.fn.line("v"))
    vim.cmd.normal({ vim.keycode("<Esc>"), bang = true })
  end
  return first, last
end

local function lazygit(cmd)
  return Snacks.terminal(cmd, {
    cwd = Snacks.git.get_root(),
    interactive = true,
    win = {
      style = "float", width = 0.9, height = 0.9,
      on_buf = function(win)
        -- j must be immediate; an already-buffered jk must pass through too.
        -- nowait alone cannot beat a complete global chord in the typeahead;
        -- define j last so it is found before the local jk partial match.
        for _, key in ipairs({ "jk", "j" }) do
          vim.keymap.set("t", key, key, {
            buffer = win.buf, nowait = true, desc = "Send " .. key .. " to Lazygit",
          })
        end
      end,
    },
  })
end

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
    -- symbol under the cursor live on `g` instead (see plugin/lsp/lsp.lua).
    { ";s",       function() Snacks.picker.lsp_symbols() end,                                       desc = "[LSP] Symbol in file" },
    { ";S",       function() Snacks.picker.lsp_workspace_symbols() end,                             desc = "[LSP] Symbol in workspace" },
    { ";l",       function() Snacks.picker.lines() end,                                             desc = "Lines in file" },
    { ";D",       function() Snacks.picker.grep({ cwd = require("util.cwd").buffer_dir() }) end,    desc = "Search from here (file's dir)" },
    { ";j",       function() Snacks.picker.jumps() end,                                             desc = "Jumps" },
    { ";m",       function() Snacks.picker.marks() end,                                             desc = "Marks" },
    -- Every changed hunk in the repository, staged and unstaged. Like a mark,
    -- a hunk is a place to be that needs no cursor context, unlike ]h/[h. In
    -- the picker <Tab> stages or unstages a hunk and <C-r> restores it: after
    -- a confirmation an unstaged hunk is discarded from the working tree.
    { ";c",       function() Snacks.picker.git_diff() end,                                          desc = "Git hunks" },

    -- ── <leader>y — yank a path ─────────────────────────────────────────
    -- Visual-mode <leader>yy/<leader>yc yank the selection (lua/mappings.lua);
    -- these yank where the current file is.
    {
      "<leader>ya",
      function()
        local path = buffer_path()
        if path then yank(path) end
      end,
      desc = "Yank file path (absolute)"
    },
    {
      "<leader>yr",
      function()
        local path = buffer_path()
        if path then yank(project_path(path)) end
      end,
      desc = "Yank file path (repo-relative)"
    },
    -- `path:12` / `path:12-18`, the form gF, terminal links and agent prompts
    -- read. Not GitHub's `#L12-L18`: that is <leader>yg's job.
    {
      "<leader>yl",
      function()
        local first, last = target_lines()
        local path = buffer_path()
        if not path then return end
        local lines = first == last and tostring(first) or ("%d-%d"):format(first, last)
        yank(project_path(path) .. ":" .. lines)
      end,
      mode = { "n", "x" },
      desc = "Yank path:line"
    },
    -- Pinned to the last commit that touched the file, so the link keeps
    -- pointing at these lines after the branch moves on. The line numbers are
    -- that commit's: with uncommitted changes above the cursor they drift.
    {
      "<leader>yg",
      function()
        local first, last = target_lines()
        if not buffer_path() then return end
        Snacks.gitbrowse({
          what = "permalink",
          line_start = first,
          line_end = last,
          -- Its own notice would say "Opening"; yank() reports the copy instead.
          notify = false,
          open = yank,
        })
      end,
      mode = { "n", "x" },
      desc = "Yank Git permalink"
    },
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

    -- ── Code (LSP symbols) ──────────────────────────────────────────────

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
    -- `;o`, lua/plugin/editor/oil.lua) and files are reached through the
    -- pickers above.
    { "<leader>un", function() Snacks.notifier.hide() end, desc = "Dismiss notifications" },

    -- ── Messages (<leader>mn) ───────────────────────────────────────────
    -- Two histories: vim.notify goes to the snacks notifier and its own
    -- history, while Vim's messages (:echomsg, print(), errors; never a plain
    -- :echo, which only g< shows again) stay in :messages, which
    -- ui2 (lua/options.lua) shows in its pager. Dismissing notifications is
    -- <leader>un alone: one act, one key.
    { "<leader>mnh", function() Snacks.notifier.show_history() end,  desc = "Notification history" },
    { "<leader>mnt", function() Snacks.picker.notifications() end,   desc = "Search notifications" },
    { "<leader>mnl", "g<",                                           desc = "Last command output" },
    { "<leader>mna", "<Cmd>messages<CR>",                            desc = "Message history" },
    {
      "<leader>gg",
      function()
        lazygit("lazygit")
      end,
      desc = "Lazygit",
      mode = { "n" }
    },
    {
      "<leader>gf",
      function()
        lazygit({ "lazygit", "log", "--filter", vim.api.nvim_buf_get_name(0) })
      end,
      desc = "File history (Lazygit)",
      mode = { "n" }
    },
    { "<C-/>",      function() require("util.terminal").toggle() end,        desc = "Toggle terminal", mode = { "n", "t" } },
    { "<C-_>",      function() require("util.terminal").toggle() end,        desc = "Toggle terminal", mode = { "n", "t" } },
    -- Numbered switching is buffer-local, installed by TermOpen in autocmds.lua.
  },
  config = function(_, opts)
    require("snacks").setup(opts)
    -- Started without a UI (`nvim --headless --listen`), the notifier is off,
    -- so a UI attached later through --remote-ui would keep the builtin
    -- vim.notify. Hand it over on that first UIEnter, the way setup() would
    -- have; the notifier module itself works whether or not it was enabled.
    -- A headless run never fires UIEnter, so stderr keeps every message.
    if not opts.notifier.enabled then
      vim.api.nvim_create_autocmd("UIEnter", {
        once = true,
        callback = function() vim.notify = Snacks.notifier.notify end,
        desc = "Route vim.notify to the snacks notifier for a UI that attached after startup",
      })
    end
  end,
  opts = {
    image = {
      enabled = true,
      backend = "kitty",
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
      --
      -- snacks/picker/core/main.lua filters non-file buffers out of its target
      -- search, but records a `non_float` fallback *before* that filter and
      -- returns it when nothing qualifies. A tab holding only an oil listing
      -- and an agent panel therefore gets the file dropped on top of one of
      -- them, and no window variable prevents it -- the fallback is
      -- unconditional. util.window.ensure_editor_win() reuses the editor area
      -- (including unmodified Oil/GitHub views) and only splits when no safe
      -- target exists.
      on_show = function(picker)
        if editor_picker_sources[picker.opts.source] then
          picker.main = require("util.window").ensure_editor_win()
        end
      end,
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
        -- given again under a name of its own.
        projects = {
          win = {
            input = {
              keys = {
                ["<c-w>"] = { { "tcd" }, mode = { "n" } },
                i_ctrl_w = { "<c-w>", "<c-s-w>", mode = { "i" }, expr = true, desc = "delete word" },
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
    dashboard = {
      enabled = true,
      -- Snacks has one shared pane width rather than per-pane widths, so both
      -- columns deliberately use the same geometry and content indentation.
      width = 64,
      preset = {
        keys = {
          { icon = "󰈞 ", key = "f", desc = "Find file", action = ":lua Snacks.dashboard.pick('files')" },
          { icon = "󰊄 ", key = "g", desc = "Find text", action = ":lua Snacks.dashboard.pick('live_grep')" },
          { icon = "󰋚 ", key = "r", desc = "Recent files", action = ":lua Snacks.dashboard.pick('oldfiles')" },
          { icon = "󰙅 ", key = "e", desc = "Browse files", action = ":Oil" },
          { icon = "󰒓 ", key = "c", desc = "Config", action = ":lua Snacks.dashboard.pick('files', {cwd = vim.fn.stdpath('config')})" },
          { icon = "󰒲 ", key = "l", desc = "Lazy", action = ":Lazy" },
          -- Repo/GitHub jumps: open the repo / issues list / PRs list in browser.
          { icon = "󰊤 ", key = "b", desc = "Browse repo", action = ":lua Snacks.gitbrowse()" },
          { icon = "󰨰 ", key = "i", desc = "Issues (browser)", action = ":lua vim.fn.jobstart('gh issue list --web', {detach=true})" },
          { icon = "󰜘 ", key = "o", desc = "PRs (browser)", action = ":lua vim.fn.jobstart('gh pr list --web', {detach=true})" },
          { icon = "󰦛 ", key = "s", desc = "Restore session", section = "session" },
          { icon = "󰩈 ", key = "q", desc = "Quit", action = ":qa" },
        },
      },
      sections = {
        -- Left pane (pane 1): cowsay banner (rainbow via lolcat) + keys
        {
          section = "terminal",
          cmd = cowsay_quote(),
          padding = 1,
          -- The cow is much narrower than the color banner, so center it
          -- independently instead of treating its indent as content padding.
          indent = 12,
          enabled = vim.fn.executable("cowsay") == 1 and vim.fn.executable("lolcat") == 1,
        },
        -- Both panes use the same three-column content inset. Decorative
        -- banners above are centered independently according to their width.
        { section = "keys",   gap = 1, padding = 1, indent = 3 },

        -- Right pane (pane 2): color squares + gh + git status
        {
          pane = 2,
          section = "terminal",
          cmd = color_squares(),
          height = 3,
          padding = 2,
          -- Art is 58 columns wide; centers it in the 64-column pane.
          indent = 3,
        },
        function()
          -- Snacks.git.get_root() returns non-nil inside bare-repo controller dirs
          -- (e.g. ~/repo/ with .git pointing to .bare/), but those aren't worktrees.
          local toplevel = vim.fn.system({ "git", "rev-parse", "--is-inside-work-tree" })
          local in_git = vim.v.shell_error == 0 and vim.trim(toplevel) == "true"
          local has_gh = vim.fn.executable("gh") == 1
          -- gh subcommands fatal with "no git remotes found" when cwd has no
          -- github remote (e.g. fresh `git init` without `git remote add`).
          local has_gh_remote = in_git
              and vim.fn.system("git remote -v 2>/dev/null"):find("github") ~= nil
          local cmds = {
            {
              title = "Notifications",
              -- Plain `gh api` instead of the gh-notify extension: gh ships its
              -- own template/jq engine, so this needs no extra install. The feed
              -- is account-wide, hence no `has_gh_remote` guard.
              cmd = dashboard_gh({ "api", "notifications?per_page=5", "--template",
                [[{{range .}}{{tablerow (timeago .updated_at) ]]
                  .. [[(.repository.full_name | truncate 18) ]]
                  .. [[(.subject.title | truncate 24)}}{{end}}{{tablerender}}]],
              }),
              action = function() vim.ui.open("https://github.com/notifications") end,
              key = "n",
              icon = "󰂚 ",
              height = 5,
              enabled = has_gh,
            },
            {
              title = "Open Issues",
              cmd = dashboard_gh({ "issue", "list", "-L", "3" }),
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
              cmd = dashboard_gh({ "pr", "list", "-L", "3" }),
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
