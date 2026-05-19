return {
  "sindrets/diffview.nvim",
  cmd = { "DiffviewOpen", "DiffviewFileHistory" },
  keys = {
    { "<leader>gv", "<cmd>tabnew | DiffviewOpen<cr>",              desc = "Diff view",          mode = "n" },
    {
      "<leader>gm",
      function()
        -- Detect main branch: check for main, then master, fallback to HEAD
        local main = vim.fn.system("git rev-parse --verify --quiet main"):find("%w") and "main"
          or vim.fn.system("git rev-parse --verify --quiet master"):find("%w") and "master"
          or "HEAD"
        vim.cmd("tabnew | DiffviewOpen " .. main)
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
            vim.cmd("tabnew | DiffviewOpen " .. choice.ref)
          end
        end)
      end,
      desc = "Diff against commit/branch",
      mode = "n",
    },
    { "<leader>gV", "<cmd>tabnew | DiffviewFileHistory %<cr>",     desc = "File history",        mode = "n" },
    { "<leader>gH", "<cmd>tabnew | DiffviewFileHistory<cr>",       desc = "Git log (all)",       mode = "n" },
  },
  opts = {},
}
