local function normalize_options(opts)
  local ret = {}
  for name, config in pairs(opts or {}) do
    if type(name) == "number" then
      ret[config] = {}
    elseif type(config) == "function" then
      ret[name] = config()
    else
      ret[name] = config
    end
  end
  return ret
end

return {
  {
    "mason-org/mason.nvim",
    opts = {},
  },
  {
    "mason-org/mason-lspconfig.nvim",
    dependencies = { "mason-org/mason.nvim", "neovim/nvim-lspconfig" },
    opts = {
      ensure_installed = {
        "lua_ls",
        "basedpyright",
        "ruff",
        "gopls",
        "html",
        "cssls",
        "eslint",
        "tailwindcss",
        "vtsls",
        "bashls",
        "jsonls",
        "yamlls",
        "jdtls",
      },
      automatic_enable = {
        exclude = { "jdtls" },
      },
    },
  },
  {
    "neovim/nvim-lspconfig",
    keys = {
      -- Non-LSP keys (global mappings are fine for these)
      { "[[",  function() require("illuminate").goto_prev_reference(false) end, desc = "Prev reference" },
      { "]]",  function() require("illuminate").goto_next_reference(false) end, desc = "Next reference" },
      { "<leader>cm", "<cmd>Mason<cr>",                            desc = "Mason" },
      { "<leader>cl", "<cmd>LspInfo<cr>",                          desc = "Lsp Info" },
    },
    opts = {
      servers = {
        ["lua_ls"] = {
          settings = {
            Lua = {
              workspace = { checkThirdParty = false },
              telemetry = { enable = false },
            },
          },
        },
      }
    },
    config = function(_, opts)
      -- Override Neovim 0.11 default global LSP mappings (grr, gra, grn, gri, grt, gO)
      -- These are set globally in vim/_defaults.lua, not in LspAttach, so override them globally
      vim.keymap.set("n",      "grr", "<cmd>Telescope lsp_references<cr>",       { desc = "References" })
      vim.keymap.set("n",      "gri", "<cmd>Telescope lsp_implementations<cr>",  { desc = "Goto Implementation" })
      vim.keymap.set("n",      "grt", "<cmd>Telescope lsp_type_definitions<cr>", { desc = "Goto Type Definition" })
      vim.keymap.set("n",      "gO",  "<cmd>Telescope lsp_document_symbols<cr>", { desc = "Document Symbols" })
      vim.keymap.set({ "n", "x" }, "gra", function() vim.lsp.buf.code_action() end, { desc = "Code Action" })
      vim.keymap.set("n",      "grn", function() vim.lsp.buf.rename() end,       { desc = "Rename" })

      -- Buffer-local LSP mappings via LspAttach (for non-default keybindings)
      vim.api.nvim_create_autocmd("LspAttach", {
        callback = function(args)
          local buf = args.buf
          local map = function(lhs, rhs, desc, mode)
            vim.keymap.set(mode or "n", lhs, rhs, { buffer = buf, desc = desc })
          end
          map("gd",  "<cmd>Telescope lsp_definitions<cr>",      "Goto Definition")
          map("gr",  "<cmd>Telescope lsp_references<cr>",       "References")
          map("gI",  "<cmd>Telescope lsp_implementations<cr>",  "Goto Implementation")
          map("gy",  "<cmd>Telescope lsp_type_definitions<cr>", "Goto Type Definition")
          map("gD",  function() vim.lsp.buf.declaration() end,  "Goto Declaration")
          map("K",   function() vim.lsp.buf.hover() end,        "Hover")
          map("gK",  function() vim.lsp.buf.signature_help() end, "Signature Help")
          map("<C-k>", function() vim.lsp.buf.signature_help() end, "Signature Help", "i")
          map("<leader>ca", function() vim.lsp.buf.code_action() end, "Code action", { "n", "v" })
          map("<leader>cr", function() vim.lsp.buf.rename() end,      "Rename")
        end,
      })

      -- Register LSP server configs via vim.lsp.config() (Neovim 0.11+ / mason-lspconfig v2)
      for name, config in pairs(normalize_options(opts.servers)) do
        vim.lsp.config(name, config)
      end

      -- Auto-install tools (formatters, linters, etc.) via Mason registry
      -- mason-registry: link=https://mason-registry.dev/registry/list
      if opts.tools then
        local mr = require("mason-registry")
        mr.refresh(function()
          for tool, config in pairs(normalize_options(opts.tools)) do
            local ok, p = pcall(mr.get_package, tool)
            if ok and not p:is_installed() then
              p:install(config)
            end
          end
        end)
      end
    end,
  },
}
