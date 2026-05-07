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
        -- Fuzzy pick a git ref (branches, tags, recent commits) then diff against it
        local pickers = require("telescope.pickers")
        local finders = require("telescope.finders")
        local actions = require("telescope.actions")
        local action_state = require("telescope.actions.state")
        local conf = require("telescope.config").values

        -- Gather branches, tags, and recent commits
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

        pickers
          .new({}, {
            prompt_title = "Diff against",
            finder = finders.new_table({
              results = refs,
              entry_maker = function(entry)
                return {
                  value = entry.ref,
                  display = entry.display,
                  ordinal = entry.display,
                }
              end,
            }),
            sorter = conf.generic_sorter({}),
            attach_mappings = function(prompt_bufnr)
              actions.select_default:replace(function()
                actions.close(prompt_bufnr)
                local selection = action_state.get_selected_entry()
                if selection then
                  vim.cmd("tabnew | DiffviewOpen " .. selection.value)
                end
              end)
              return true
            end,
          })
          :find()
      end,
      desc = "Diff against commit/branch",
      mode = "n",
    },
    { "<leader>gV", "<cmd>tabnew | DiffviewFileHistory %<cr>",     desc = "File history",        mode = "n" },
    { "<leader>gH", "<cmd>tabnew | DiffviewFileHistory<cr>",       desc = "Git log (all)",       mode = "n" },
  },
  opts = {},
}
