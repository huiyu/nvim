local lsp = require("util.lsp")

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

-- Run gopls `source.organizeImports` synchronously before save, replacing the
-- standalone `goimports` formatter (which timed out on cold cache / big modcache).
-- Runs before conform's BufWritePre so gofumpt formats the import-sorted buffer.
vim.api.nvim_create_autocmd("BufWritePre", {
  pattern = "*.go",
  group = vim.api.nvim_create_augroup("go_organize_imports", { clear = true }),
  callback = function()
    local clients = vim.lsp.get_clients({ bufnr = 0, name = "gopls" })
    if #clients == 0 then return end
    local enc = clients[1].offset_encoding or "utf-16"
    local params = vim.lsp.util.make_range_params(0, enc)
    params.context = { only = { "source.organizeImports" }, diagnostics = {} }
    local result = vim.lsp.buf_request_sync(0, "textDocument/codeAction", params, 3000)
    for _, res in pairs(result or {}) do
      for _, action in pairs(res.result or {}) do
        if action.edit then
          vim.lsp.util.apply_workspace_edit(action.edit, enc)
        end
      end
    end
  end,
})

vim.api.nvim_create_autocmd("FileType", {
  pattern = "go",
  callback = function(ev)
    vim.keymap.set("n", "<leader>cR", rebuild_gopls, { buffer = ev.buf, desc = "Rebuild gopls index" })
    vim.keymap.set("n", "<leader>co", lsp.action["source.organizeImports"],
      { buffer = ev.buf, desc = "Organize Imports" })
    vim.keymap.set("n", "<leader>cx", function()
      vim.cmd("write")
      vim.cmd("split | terminal go run " .. vim.fn.shellescape(vim.fn.expand("%:p")))
    end, { buffer = ev.buf, desc = "Run current file (go run)" })
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
        -- goimports removed; gopls `source.organizeImports` handles imports on save.
        ["gofumpt"] = {},
        ["gomodifytags"] = {},
        ["impl"] = {},
        ["golangci-lint"] = {},
        -- delve (dlv) is the Go debug adapter used by nvim-dap-go; mason puts it on PATH.
        ["delve"] = {},
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
        go = { "gofumpt" },
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
    -- Go debugging is owned by nvim-dap-go (also used by neotest-golang via
    -- dap_go_enabled). It loads on Go files so the adapter/configs are ready
    -- for a standalone `<leader>dc`. delve is installed through the `tools`
    -- list above; the mason-nvim-dap `delve` handler is intentionally dropped
    -- to avoid registering the Go adapter/configs twice.
    "leoluz/nvim-dap-go",
    ft = "go",
    config = true,
    dependencies = {
      "mfussenegger/nvim-dap",
    },
  },
}
