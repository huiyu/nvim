return {
  {
    "nvim-treesitter/nvim-treesitter",
    -- jsonc has no dedicated parser; nvim-treesitter aliases the jsonc filetype
    -- to the json parser, so listing it here only triggers an "unsupported" warning.
    opts = { ensure_installed = { "json", "json5" } },
  },
  {
    "b0o/SchemaStore.nvim",
    lazy = true,
    version = false,
  },
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        jsonls = {
          -- Inject SchemaStore catalogs via before_init (a real LSP ClientConfig
          -- hook). The old nvim-lspconfig `on_new_config` is ignored by the
          -- native vim.lsp.config API this config uses.
          before_init = function(_, config)
            config.settings.json.schemas = config.settings.json.schemas or {}
            vim.list_extend(config.settings.json.schemas, require("schemastore").json.schemas())
          end,
          settings = {
            json = {
              format = { enable = true },
              validate = { enable = true },
            },
          },
        },
      },
    },
  },
  {
    "stevearc/conform.nvim",
    optional = true,
    opts = {
      formatters_by_ft = {
        ["json"] = { "prettier" },
        ["jsonc"] = { "prettier" },
      },
    },
  },
}
