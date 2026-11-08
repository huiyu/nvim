-- JSON shows its quotes. nvim-treesitter's json highlights conceal every `"`,
-- so under the global conceallevel = 2 (lua/options.lua) `"name": "x"` reads
-- `name: x` and a key can no longer be told from a bare word. jsonc reuses the
-- json parser and its query; json5's own query conceals nothing today, but the
-- whole family gets the same window setting.
--
-- 'conceallevel' is window-local, so FileType alone misses two paths, and
-- BufWinEnter catches every window a buffer is displayed in:
-- - a buffer whose filetype was detected inside nvim_buf_call, where the
--   option lands on a scratch autocmd window instead of the one that later
--   shows the buffer;
-- - CodeDiff's revision buffers (codediff://.../a.json), which never get a
--   filetype at all: it starts Tree-sitter on them directly, json queries and
--   their concealed quotes included, so the name is all there is to go by.
local json_filetypes = { json = true, jsonc = true, json5 = true }

local function json_buffer(buf)
  local ft = vim.bo[buf].filetype
  if ft == "" then
    local name = vim.api.nvim_buf_get_name(buf)
    ft = name:match("^codediff://") and vim.filetype.match({ filename = name }) or ""
  end
  return json_filetypes[ft] == true
end

vim.api.nvim_create_autocmd({ "FileType", "BufWinEnter" }, {
  group = vim.api.nvim_create_augroup("json_conceal", { clear = true }),
  callback = function(args)
    if args.buf == vim.api.nvim_get_current_buf() and json_buffer(args.buf) then
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
