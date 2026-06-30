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
    require("diffview").setup(opts)

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
