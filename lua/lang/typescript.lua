-- TypeScript / JavaScript *language* support.
--
-- This file owns the language itself and is runtime-agnostic: the same setup
-- applies whether the code targets Node, the browser, Deno or Bun. Web-frontend
-- tooling (HTML / CSS / Tailwind) lives in `lang/frontend.lua`, not here.
-- <leader>cx runners (dispatched centrally by util.run; keymap in mappings.lua).
-- TS has no dependency-free single-file runner, so use `npx tsx` (resolves a
-- project/global tsx; the terminal shows a clear error if tsx is unavailable).
require("util.run").register("javascript", function(path)
  return "node " .. vim.fn.shellescape(path)
end)
require("util.run").register("typescript", function(path)
  return "npx tsx " .. vim.fn.shellescape(path)
end)

return {
  -- LSP: vtsls (a vscode-tsserver wrapper) for JS/TS, plus ESLint.
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        eslint = {
          settings = {
            workingDirectories = { mode = "auto" },
          },
        },
        vtsls = {
          filetypes = {
            "javascript",
            "javascriptreact",
            "javascript.jsx",
            "typescript",
            "typescriptreact",
            "typescript.tsx",
          },
          settings = {
            complete_function_calls = true,
            vtsls = {
              enableMoveToFileCodeAction = true,
              autoUseWorkspaceTsdk = true,
              experimental = {
                maxInlayHintLength = 30,
                completion = {
                  enableServerSideFuzzyMatch = true,
                },
              },
            },
            typescript = {
              updateImportsOnFileMove = { enabled = "always" },
              suggest = {
                completeFunctionCalls = true,
              },
              inlayHints = {
                enumMemberValues = { enabled = true },
                functionLikeReturnTypes = { enabled = true },
                parameterNames = { enabled = "literals" },
                parameterTypes = { enabled = true },
                propertyDeclarationTypes = { enabled = true },
                variableTypes = { enabled = false },
              },
            },
          },
        },
      },
      tools = {
        -- prettier is the configured formatter for js/ts/json/yaml/css/etc.;
        -- install it via mason so formatting does not depend on a global PATH binary.
        -- (eslint/cssls and the other servers are installed from `servers` by
        -- mason-lspconfig, so they are not duplicated here.)
        ["prettier"] = {},
      },
    },
  },

  -- Treesitter parsers for the language.
  {
    "nvim-treesitter/nvim-treesitter",
    opts = { ensure_installed = { "javascript", "jsdoc", "typescript", "tsx" } },
  },

  -- Formatting via prettier.
  {
    "stevearc/conform.nvim",
    optional = true,
    opts = {
      formatters_by_ft = {
        ["javascript"] = { "prettier" },
        ["javascriptreact"] = { "prettier" },
        ["typescript"] = { "prettier" },
        ["typescriptreact"] = { "prettier" },
      },
    },
  },

  -- Debugging via vscode-js-debug (mason package: js-debug-adapter).
  --
  -- A single adapter covers BOTH runtimes: `pwa-node` for Node processes and
  -- `pwa-chrome` for the browser. The runtime is selected by the launch config,
  -- not by the plugin, which is exactly why debugging belongs to the *language*
  -- rather than to "web" or "node". The `js` handler makes mason install the
  -- adapter and register the default Node launch/attach configs for JS/TS files.
  --
  -- For TypeScript with source maps or a custom runtime (tsx / ts-node), add a
  -- project-level `.vscode/launch.json`; it is picked up via `dap.ext.vscode`.
  {
    "mfussenegger/nvim-dap",
    opts = {
      handlers = {
        ["js"] = {},
      },
    },
  },
}
