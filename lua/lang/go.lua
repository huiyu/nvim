local lsp = require("util.lsp")

-- Multi-client Delve preserves the target's paused state and breakpoints on
-- disconnect. Remove this editor's source breakpoints from the server (keep
-- the local signs for reattachment), then resume before dropping the client.
local function before_remote_disconnect(session, done)
  local requests = {}
  for bufnr in pairs(require("dap.breakpoints").get()) do
    local path = vim.api.nvim_buf_get_name(bufnr)
    if path ~= "" then
      table.insert(requests, { "setBreakpoints", { source = { path = path }, breakpoints = {} } })
    end
  end
  if session.stopped_thread_id then
    table.insert(requests, { "continue", { threadId = session.stopped_thread_id } })
  end
  local function advance(err)
    if session.closed then return end
    if err then
      vim.notify("Delve disconnect cancelled: " .. tostring(err), vim.log.levels.ERROR)
      return
    end
    local request = table.remove(requests, 1)
    if request then
      session:request_with_timeout(request[1], request[2], 5000, advance)
    else
      done()
    end
  end
  advance()
end

---Clear gopls cache and restart LSP to force a full re-index.
---Useful after large refactors, branch switches, or rebases.
local function rebuild_gopls()
  -- Checked before the cache goes: `:lsp restart` refuses when no client is
  -- attached, which used to leave the cache deleted, the index not rebuilt,
  -- and a traceback on screen.
  if #vim.lsp.get_clients({ bufnr = 0 }) == 0 then
    vim.notify("No LSP client attached to this buffer, nothing to restart. "
      .. "Reopen the file (:e) to start gopls, then rebuild.", vim.log.levels.WARN)
    return
  end
  local cache_dir = vim.fn.expand("~/Library/Caches/gopls")
  if vim.fn.isdirectory(cache_dir) == 1 then
    vim.fn.delete(cache_dir, "rf")
  end
  -- Nvim 0.12 builtin; lspconfig no longer defines `:LspRestart`.
  vim.cmd("lsp restart")
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
    -- <localleader>, not `,`: rebuilding the gopls index means nothing outside a
    -- Go buffer, and <localleader> is where this config keeps per-filetype
    -- actions (VimTeX, diffview). `,` stays reserved for code operations that
    -- work in any language.
    vim.keymap.set("n", "<localleader>G", rebuild_gopls, { buffer = ev.buf, desc = "Rebuild gopls index" })
    vim.keymap.set("n", "<localleader>o", lsp.action["source.organizeImports"],
      { buffer = ev.buf, desc = "Organize Imports" })
  end,
})

-- ,x runner (dispatched centrally by util.run; keymap in mappings.lua).
require("util.run").register("go", function(path)
  return "go run " .. vim.fn.shellescape(path)
end)

return {
  {
    "mfussenegger/nvim-dap",
    opts = { targets = { go = {
      file = function(ctx)
        require("dap").run({ name = "go: current file", type = "go", request = "launch",
          program = ctx.path, cwd = vim.fs.root(ctx.path, "go.mod") or vim.fs.dirname(ctx.path) })
      end,
      test = function(ctx) require("neotest").debug_target(ctx, false) end,
      test_file = function(ctx) require("neotest").debug_target(ctx, true) end,
    } } },
  },
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
                -- No fieldalignment: gopls removed that analyzer in v0.17.0
                -- (go.dev/issue/67762) and now rejects the setting outright,
                -- so every Go buffer opened with it started with an error.
                -- Struct size/offset is on hover instead.
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
    -- Go debugging is owned by nvim-dap-go (also used by neotest-golang).
    -- It loads on Go files so the adapter/configs are ready
    -- for a standalone `<leader>dc`. delve is installed through the `tools`
    -- list above; the mason-nvim-dap `delve` handler is intentionally dropped
    -- to avoid registering the Go adapter/configs twice.
    "leoluz/nvim-dap-go",
    ft = "go",
    config = function()
      require("dap-go").setup()
      local dap = require("dap")
      table.insert(dap.configurations.go, {
        type = "go_remote",
        name = "go: attach to remote Delve",
        request = "attach",
        mode = "remote",
      })
      -- The plugin's `go` adapter always spawns dlv, even with a host/port.
      -- A separate server adapter connects to an already running dlv instead.
      dap.adapters.go_remote = function(callback, config)
        config = config or {}
        local function with_host(host)
          if not host or vim.trim(host) == "" then return end
          local function with_port(port)
            if port == nil then return end
            local number = tonumber(port)
            if not number or number % 1 ~= 0 or number < 1 or number > 65535 then
              vim.notify("Delve port must be an integer from 1 to 65535", vim.log.levels.WARN)
              return
            end
            callback({ type = "server", host = vim.trim(host), port = number,
              options = { before_disconnect = before_remote_disconnect } })
          end
          if config.port ~= nil then with_port(config.port)
          else vim.ui.input({ prompt = "Delve port: ", default = "38697" }, with_port) end
        end
        if type(config.host) == "string" then with_host(config.host)
        else vim.ui.input({ prompt = "Delve host: ", default = "127.0.0.1" }, with_host) end
      end
    end,
    dependencies = {
      "mfussenegger/nvim-dap",
    },
  },
}
