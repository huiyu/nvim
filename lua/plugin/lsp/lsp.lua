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
    -- Single source of truth: install exactly the servers declared across the
    -- lang/ files (nvim-lspconfig `opts.servers`). Adding a server there is
    -- enough — there is no second hand-maintained list to keep in sync.
    opts = function()
      local lspconfig = require("lazy.core.config").plugins["nvim-lspconfig"]
      local lsp_opts = require("lazy.core.plugin").values(lspconfig, "opts", false)
      return {
        -- jdtls is intentionally NOT a `servers` entry (it is started via
        -- nvim-jdtls and installed through java.lua's `tools`), so it is
        -- absent from the derived list and excluded from automatic_enable.
        ensure_installed = vim.tbl_keys(lsp_opts.servers or {}),
        automatic_enable = {
          exclude = { "jdtls" },
        },
      }
    end,
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
              diagnostics = { globals = { "vim", "Snacks" } },
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
      vim.keymap.set("n",      "grr", function() Snacks.picker.lsp_references() end,       { desc = "References" })
      vim.keymap.set("n",      "gri", function() Snacks.picker.lsp_implementations() end,  { desc = "Goto Implementation" })
      vim.keymap.set("n",      "grt", function() Snacks.picker.lsp_type_definitions() end, { desc = "Goto Type Definition" })
      vim.keymap.set("n",      "gO",  function() Snacks.picker.lsp_symbols() end,           { desc = "Document Symbols" })
      vim.keymap.set({ "n", "x" }, "gra", function() vim.lsp.buf.code_action() end, { desc = "Code Action" })
      vim.keymap.set("n",      "grn", function() vim.lsp.buf.rename() end,       { desc = "Rename" })

      -- Buffer-local LSP mappings via LspAttach (for non-default keybindings)
      vim.api.nvim_create_autocmd("LspAttach", {
        callback = function(args)
          local buf = args.buf
          local map = function(lhs, rhs, desc, mode)
            vim.keymap.set(mode or "n", lhs, rhs, { buffer = buf, desc = desc })
          end
          map("gd",  function() Snacks.picker.lsp_definitions() end,      "Goto Definition")
          map("gr",  function() Snacks.picker.lsp_references() end,       "References")
          map("gI",  function() Snacks.picker.lsp_implementations() end,  "Goto Implementation")
          map("gy",  function() Snacks.picker.lsp_type_definitions() end, "Goto Type Definition")
          map("gD",  function() vim.lsp.buf.declaration() end,  "Goto Declaration")
          map("K",   function() vim.lsp.buf.hover() end,        "Hover")
          map("gK",  function() vim.lsp.buf.signature_help() end, "Signature Help")
          map("<C-k>", function() vim.lsp.buf.signature_help() end, "Signature Help", "i")
          map("<leader>ca", function() vim.lsp.buf.code_action() end, "Code action", { "n", "v" })
          map("<leader>cr", function() vim.lsp.buf.rename() end,      "Rename")
        end,
      })

      -- Register LSP server configs via vim.lsp.config() (Neovim 0.11+ / mason-lspconfig v2).
      -- Re-enable after registering settings: mason-lspconfig's automatic_enable
      -- may have enabled the server earlier with empty config, so we re-enable
      -- here to make the just-registered settings actually take effect.
      -- Advertise blink.cmp's enhanced client capabilities to every server
      -- (snippet support, auto-import via resolveSupport/additionalTextEdits,
      -- lazy documentation/detail resolution). blink does not inject these on
      -- its own, and per-server `capabilities` (c/yaml) deep-merge on top.
      vim.lsp.config("*", {
        capabilities = require("blink.cmp").get_lsp_capabilities(nil, true),
      })

      for name, config in pairs(normalize_options(opts.servers)) do
        vim.lsp.config(name, config)
        vim.lsp.enable(name)
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
