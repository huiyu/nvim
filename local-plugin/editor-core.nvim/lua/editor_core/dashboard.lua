-- Snacks dashboard content and viewport locking. Loaded by the UI spec
-- when Snacks resolves its options, before its first dashboard can open.
-- Lock the dashboard buffer against scrolling: the layout is centered on open
-- and any viewport shift breaks the panes. We can't use FileType because
-- snacks sets `eventignore = "all"` while assigning the dashboard filetype,
-- so we hook the `SnacksDashboardOpened` user event it fires afterwards.
local installed = false
local function setup_viewport()
  if installed then return end
  installed = true
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
end

-- Dashboard banner pool. One is drawn at random per Nvim start.
-- Keep entries single-line; cowsay wraps them (see `cowsay_quote` below).


-- The lolcat pipe needs a shell, so the quote is escaped instead of passed as
-- argv. `-W 36` caps the bubble at 38 columns, which keeps it inside the
-- 64-column pane once the section centers the roughly 39-column output.
-- LuaJIT's math.random is deterministic until seeded, so hrtime seeds it —
-- otherwise every session would greet you with the same quote.
local function cowsay_quote(quotes)
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

  local function build(opts)
    opts = vim.deepcopy(opts or {})
    return {
      enabled = opts.enabled ~= false,
      -- Snacks has one shared pane width rather than per-pane widths, so both
      -- columns deliberately use the same geometry and content indentation.
      width = opts.width or 64,
      preset = {
        keys = opts.keys,
      },
      sections = {
        -- Left pane (pane 1): cowsay banner (rainbow via lolcat) + keys
        {
          section = "terminal",
          cmd = cowsay_quote(opts.quotes or { "Welcome to Nvim" }),
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
end

return { build = function(opts)
  setup_viewport()
  return build(opts)
end }
