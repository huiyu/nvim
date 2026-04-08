---Clear gopls cache and restart LSP to force a full re-index.
---Useful after large refactors, branch switches, or rebases.
local function rebuild_gopls()
  local cache_dir = vim.fn.expand("~/Library/Caches/gopls")
  if vim.fn.isdirectory(cache_dir) == 1 then
    vim.fn.delete(cache_dir, "rf")
  end
  vim.cmd("LspRestart")
  vim.notify("gopls cache cleared and LSP restarted", vim.log.levels.INFO)
end

vim.api.nvim_create_user_command("GoplsRebuildIndex", rebuild_gopls, {
  desc = "Clear gopls cache and restart LSP",
})

vim.api.nvim_create_autocmd("FileType", {
  pattern = "go",
  callback = function(ev)
    vim.keymap.set("n", "<leader>cR", rebuild_gopls, { buffer = ev.buf, desc = "Rebuild gopls index" })
  end,
})

return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        gopls = {
          settings = {
            gopls = {
              gofumpt = true,
              codelenses = {
                gc_details = false,
                generate = true,
                regenerate_cgo = true,
                run_govulncheck = true,
                test = true,
                tidy = true,
                upgrade_dependency = true,
                vendor = true,
              },
              hints = {
                assignVariableTypes = true,
                compositeLiteralFields = true,
                compositeLiteralTypes = true,
                constantValues = true,
                functionTypeParameters = true,
                parameterNames = true,
                rangeVariableTypes = true,
              },
              analyses = {
                fieldalignment = true,
                nilness = true,
                unusedparams = true,
                unusedwrite = true,
                useany = true,
              },
              usePlaceholders = true,
              completeUnimported = true,
              staticcheck = true,
              directoryFilters = { "-.git", "-.vscode", "-.idea", "-.vscode-test", "-node_modules" },
              semanticTokens = true,
            },
          },
        }
      },
      tools = {
        ["goimports"] = {},
        ["gofumpt"] = {},
        ["gomodifytags"] = {},
        ["impl"] = {},
        ["golangci-lint"] = {},
      }
    },
  },
  {
    "nvim-treesitter/nvim-treesitter",
    opts = {
      ensure_installed = { "go", "gowork", "gomod", "gosum" }
    },
  },
  {
    "stevearc/conform.nvim",
    optional = true,
    opts = {
      formatters_by_ft = {
        go = { "goimports", "gofumpt" },
      },
    },
  },
  {
    "mfussenegger/nvim-lint",
    optional = true,
    opts = {
      linters_by_ft = {
        go = { "golangcilint" },
      },
    },
  },
  {
    "nvim-neotest/neotest",
    optional = true,
    dependencies = {
      "fredrikaverpil/neotest-golang",
    },
    opts = {
      adapters = {
        ["neotest-golang"] = {
          dap_go_enabled = true,
        },
      },
    }
  },
  {
    "mfussenegger/nvim-dap",
    opts = {
      handlers = {
        delve = {}
      }
    }
  },
  {
    "leoluz/nvim-dap-go",
    config = true,
    dependencies = {
      "mfussenegger/nvim-dap",
    },
  },
}
