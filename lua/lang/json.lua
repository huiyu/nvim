-- JSON shows its quotes. nvim-treesitter's json highlights conceal every `"`,
-- so under the global conceallevel = 2 (lua/options.lua) `"name": "x"` reads
-- `name: x` and a key can no longer be told from a bare word. jsonc reuses the
-- json parser and its query; json5's own query conceals nothing today, but the
-- whole family gets the same window setting.
--
-- 'conceallevel' is window-local, so FileType alone misses one path: diffview
-- detects a revision buffer's filetype inside nvim_buf_call, where the option
-- lands on a scratch autocmd window instead of the diff window that later
-- shows the buffer. BufWinEnter catches every window it is displayed in.
local json_filetypes = { json = true, jsonc = true, json5 = true }
vim.api.nvim_create_autocmd({ "FileType", "BufWinEnter" }, {
  group = vim.api.nvim_create_augroup("json_conceal", { clear = true }),
  callback = function(args)
    if json_filetypes[vim.bo[args.buf].filetype] and args.buf == vim.api.nvim_get_current_buf() then
      vim.opt_local.conceallevel = 0
    end
  end,
})

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
