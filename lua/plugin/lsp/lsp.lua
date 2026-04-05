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
      tools = {
        ["shfmt"] = {}
      },
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
      -- Override Neovim 0.11 default LSP mappings with Telescope pickers (buffer-local)
      -- Use vim.schedule to ensure these run AFTER Neovim's built-in LspAttach defaults
      vim.api.nvim_create_autocmd("LspAttach", {
        callback = function(args)
          vim.schedule(function()
            local buf = args.buf
            if not vim.api.nvim_buf_is_valid(buf) then return end
            local map = function(lhs, rhs, desc, mode)
              vim.keymap.set(mode or "n", lhs, rhs, { buffer = buf, desc = desc })
            end
            -- LSP navigation via Telescope
            map("gd",  "<cmd>Telescope lsp_definitions<cr>",      "Goto Definition")
            map("gr",  "<cmd>Telescope lsp_references<cr>",       "References")
            map("gI",  "<cmd>Telescope lsp_implementations<cr>",  "Goto Implementation")
            map("gy",  "<cmd>Telescope lsp_type_definitions<cr>", "Goto Type Definition")
            map("gD",  function() vim.lsp.buf.declaration() end,  "Goto Declaration")
            map("K",   function() vim.lsp.buf.hover() end,        "Hover")
            map("gK",  function() vim.lsp.buf.signature_help() end, "Signature Help")
            map("<C-k>", function() vim.lsp.buf.signature_help() end, "Signature Help", "i")
            -- Code actions
            map("<leader>ca", function() vim.lsp.buf.code_action() end, "Code action", { "n", "v" })
            map("<leader>cr", function() vim.lsp.buf.rename() end,      "Rename")
            map("<leader>cd", function() vim.diagnostic.open_float() end, "Line diagnostics")
          end)
        end,
      })

      -- Register LSP server configs via vim.lsp.config() (Neovim 0.11+ / mason-lspconfig v2)
      for name, config in pairs(normalize_options(opts.servers)) do
        vim.lsp.config(name, config)
      end

      -- Auto-install tools (formatters, linters, etc.) via Mason registry
      -- mason-registry: link=https://mason-registry.dev/registry/list
      local mr = require("mason-registry")
      mr.refresh(function()
        for tool, config in pairs(normalize_options(opts.tools)) do
          local ok, p = pcall(mr.get_package, tool)
          if ok and not p:is_installed() then
            p:install(config)
          end
        end
      end)
    end,
  },
}
