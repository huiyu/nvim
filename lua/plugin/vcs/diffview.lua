return {
  "sindrets/diffview.nvim",
  cmd = { "DiffviewOpen", "DiffviewFileHistory" },
  keys = {
    { "<leader>gv", "<cmd>DiffviewOpen<cr>",                       desc = "Diff view",          mode = "n" },
    { "<leader>gq", "<cmd>DiffviewClose<cr>",                      desc = "Close diff view",    mode = "n" },
    {
      "<leader>gm",
      function()
        -- Detect main branch: check for main, then master, fallback to HEAD
        local main = vim.fn.system("git rev-parse --verify --quiet main"):find("%w") and "main"
          or vim.fn.system("git rev-parse --verify --quiet master"):find("%w") and "master"
          or "HEAD"
        vim.cmd("DiffviewOpen " .. main)
      end,
      desc = "Diff against main branch",
      mode = "n",
    },
    {
      "<leader>gM",
      function()
        -- Fuzzy pick a git ref (branches, tags, recent commits) then diff against it.
        -- Goes through vim.ui.select, which snacks.picker (ui_select=true) intercepts.
        local refs = {}
        local branches = vim.fn.systemlist("git branch --all --format='%(refname:short)'")
        for _, b in ipairs(branches) do
          table.insert(refs, { ref = b, display = " " .. b })
        end
        local tags = vim.fn.systemlist("git tag --sort=-creatordate")
        for _, t in ipairs(tags) do
          table.insert(refs, { ref = t, display = " " .. t })
        end
        local commits = vim.fn.systemlist("git log --oneline -50")
        for _, c in ipairs(commits) do
          local hash = c:match("^(%S+)")
          table.insert(refs, { ref = hash, display = " " .. c })
        end

        vim.ui.select(refs, {
          prompt = "Diff against",
          format_item = function(item) return item.display end,
        }, function(choice)
          if choice then
            vim.cmd("DiffviewOpen " .. choice.ref)
          end
        end)
      end,
      desc = "Diff against commit/branch",
      mode = "n",
    },
    { "<leader>gV", "<cmd>DiffviewFileHistory %<cr>",             desc = "File history",        mode = "n" },
    { "<leader>gH", "<cmd>DiffviewFileHistory<cr>",               desc = "Git log (all)",       mode = "n" },
  },
  opts = {},
  config = function(_, opts)
    local actions = require("diffview.actions")

    -- Keys that only make sense in the normal editing layout: each loads a file
    -- or buffer into the current window, which would clobber a diff window and
    -- break the layout. Neutralize them inside every diffview buffer so muscle
    -- memory can't wreck the view. The diff content windows are real file
    -- buffers, so diffview's own keymap hook is the only place these
    -- buffer-local overrides can land. `nowait` makes the override fire
    -- immediately — without it Vim keeps waiting for the longer global maps,
    -- so a fast `;f` would still reach the picker and break the view.
    local function blocked(key)
      return function()
        vim.notify(
          key .. " is disabled inside Diffview — exit with <leader>gq first",
          vim.log.levels.WARN,
          { title = "Diffview" }
        )
      end
    end
    local function block_prefixes(keys)
      local mappings = {}
      for _, key in ipairs(keys) do
        mappings[#mappings + 1] = { "n", key, blocked(key), { desc = "Disabled in Diffview", nowait = true } }
      end
      return mappings
    end
    -- The file openers now live on the `;` prefix (lua/plugin/editor/snacks.lua),
    -- so that is what has to be blocked here; the old <leader> spellings are gone.
    -- `;` opens files and is unsafe everywhere. `s` opens splits, but the file
    -- panel already owns exact `s` for stage/unstage; that single-letter panel
    -- action must win instead of being replaced by the prefix guard.
    local file_blocks = block_prefixes({ ";" })
    local layout_blocks = block_prefixes({ ";", "s" })

    -- <leader> keeps its global meaning everywhere (Buffer/Explorer/Code, as
    -- the which-key popup advertises); diffview's view-local actions live on
    -- <localleader> instead, per Vim convention. Drop the plugin's <leader>
    -- defaults and re-add the same actions under <localleader>.
    local dropped = {}
    for _, lhs in ipairs({
      "<leader>e", "<leader>b",
      "<leader>co", "<leader>ct", "<leader>cb", "<leader>ca",
      "<leader>cO", "<leader>cT", "<leader>cB", "<leader>cA",
    }) do
      dropped[#dropped + 1] = { "n", lhs, false } -- falsy rhs deletes the default
    end

    local panel = {
      { "n", "<localleader>e", actions.focus_files,  { desc = "Focus the file panel" } },
      { "n", "<localleader>b", actions.toggle_files, { desc = "Toggle the file panel" } },
    }
    local conflict_hunk = {
      { "n", "<localleader>co", actions.conflict_choose("ours"),   { desc = "Conflict: choose OURS" } },
      { "n", "<localleader>ct", actions.conflict_choose("theirs"), { desc = "Conflict: choose THEIRS" } },
      { "n", "<localleader>cb", actions.conflict_choose("base"),   { desc = "Conflict: choose BASE" } },
      { "n", "<localleader>ca", actions.conflict_choose("all"),    { desc = "Conflict: choose all" } },
    }
    local conflict_file = {
      { "n", "<localleader>cO", actions.conflict_choose_all("ours"),   { desc = "Conflict (whole file): choose OURS" } },
      { "n", "<localleader>cT", actions.conflict_choose_all("theirs"), { desc = "Conflict (whole file): choose THEIRS" } },
      { "n", "<localleader>cB", actions.conflict_choose_all("base"),   { desc = "Conflict (whole file): choose BASE" } },
      { "n", "<localleader>cA", actions.conflict_choose_all("all"),    { desc = "Conflict (whole file): choose all" } },
    }

    local function join(...)
      local out = {}
      for _, list in ipairs({ ... }) do
        vim.list_extend(out, list)
      end
      return out
    end

    opts.keymaps = {
      view = join(layout_blocks, dropped, panel, conflict_hunk, conflict_file),
      file_panel = join(file_blocks, dropped, panel, conflict_file),
      file_history_panel = join(layout_blocks, dropped, panel),
    }

    require("diffview").setup(opts)

    -- Give the <localleader>c prefix a "Conflict" which-key group label where
    -- conflict maps actually exist (it would otherwise show as an unnamed
    -- prefix). Buffer-local, so VimTeX's <localleader> maps in tex buffers
    -- stay untouched; the keymap check keeps a mislabeled buffer impossible
    -- even if the event fires with an unexpected buffer current. pcall:
    -- cosmetic only, must not break the view if which-key is absent.
    -- Scheduled: both events can fire before diffview has applied its
    -- buffer-local keymaps, and the guard below needs to see them.
    local function label_conflict_group(buf)
      if not vim.api.nvim_buf_is_valid(buf) then return end
      -- nvim_buf_get_keymap reports lhs with the leader already expanded, so
      -- build the probe from maplocalleader instead of assuming it is `\`.
      -- Nvim's own default applies when the variable is unset.
      local ll = vim.g.maplocalleader or "\\"
      for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
        if m.lhs == ll .. "co" or m.lhs == ll .. "cO" then
          pcall(function()
            require("which-key").add({
              { "<localleader>c", group = "Conflict", mode = "n", buffer = buf },
            })
          end)
          return
        end
      end
    end
    vim.api.nvim_create_autocmd("FileType", {
      pattern = "DiffviewFiles",
      callback = function(ev)
        vim.schedule(function() label_conflict_group(ev.buf) end)
      end,
    })
    vim.api.nvim_create_autocmd("User", {
      pattern = "DiffviewDiffBufWinEnter",
      callback = function()
        local buf = vim.api.nvim_get_current_buf()
        vim.schedule(function() label_conflict_group(buf) end)
      end,
    })

    -- A diffview:// buffer closed by ANY means (mapped key, manual :bd/:bw, Lua
    -- API) means the user wants out of the diff — tear the whole view down via
    -- DiffviewClose instead of leaving orphan buffers behind. Deferred with
    -- schedule() because closing windows/tabs isn't allowed from inside the
    -- delete event; once DiffviewClose runs get_current_view() is nil, so the
    -- re-fired events are no-ops and no extra re-entrancy guard is needed.
    vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
      pattern = "diffview://*",
      callback = function()
        vim.schedule(function()
          if require("diffview.lib").get_current_view() then
            pcall(vim.cmd, "DiffviewClose")
          end
        end)
      end,
    })
  end,
}
