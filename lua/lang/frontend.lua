-- Web-frontend domain support: markup, styling and framework tooling.
--
-- This is the "web" layer, deliberately kept separate from the JS/TS *language*
-- (see `lang/typescript.lua`). A Node backend pulls in only the language file;
-- a browser/frontend project layers this on top.
return {
  -- LSP: HTML, CSS and Tailwind.
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        html = {},
        cssls = {},
        tailwindcss = {
          -- Explicit filetypes: the custom LSP loader ignores LazyVim-style
          -- `filetypes_exclude`/`filetypes_include`, so markdown is simply
          -- omitted here rather than excluded after the fact.
          filetypes = {
            "html", "css", "scss", "less", "postcss",
            "javascript", "javascriptreact",
            "typescript", "typescriptreact",
            "vue", "svelte",
          },
        },
      },
    },
  },

  -- Treesitter parsers for markup/styling.
  {
    "nvim-treesitter/nvim-treesitter",
    opts = { ensure_installed = { "html", "css" } },
  },

  -- Formatting via prettier for the markup/styling/docs filetypes.
  {
    "stevearc/conform.nvim",
    optional = true,
    opts = {
      formatters_by_ft = {
        ["vue"] = { "prettier" },
        ["css"] = { "prettier" },
        ["scss"] = { "prettier" },
        ["less"] = { "prettier" },
        ["html"] = { "prettier" },
        ["graphql"] = { "prettier" },
        ["handlebars"] = { "prettier" },
        ["markdown"] = { "prettier" },
        ["markdown.mdx"] = { "prettier" },
      },
    },
  },
}
