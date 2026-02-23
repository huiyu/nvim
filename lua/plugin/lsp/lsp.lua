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
  "neovim/nvim-lspconfig",
  keys = {
    { "<leader>ca", function() vim.lsp.buf.code_action() end,    desc = "Code action",    mode = { "n", "v" } },
    { "<leader>cr", function() vim.lsp.buf.rename() end,         desc = "Rename",         mode = { "n", "v" } },
    { "<leader>ch", function() vim.lsp.buf.hover() end,          desc = "Hover doc",      mode = { "n", "v" } },
    { "<leader>cH", function() vim.lsp.buf.signature_help() end, desc = "Signature help", mode = { "n", "v" } },
  },
  dependencies = {
    { "williamboman/mason.nvim",           opts = {} },
    { "williamboman/mason-lspconfig.nvim", config = function() end },
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
    -- Refresh Mason registry and install specified tools if not already installed
    -- mason-registry: link=https://mason-registry.dev/registry/list

    local mr = require("mason-registry")
    mr.refresh(function()
      for tool, config in pairs(normalize_options(opts.tools)) do
        local p = mr.get_package(tool)
        if not p:is_installed() then
          p:install(config)
        end
      end
    end)

    -- Map LSP servers to their setup functions and configure them using mason-lspconfig
    -- mason-lspconfig: link=https://github.com/williamboman/mason-lspconfig.nvim
    local common = require("util.common")
    local table_handlers = common.table(normalize_options(opts.servers)):map(function(k, v)
      return k, function() require("lspconfig")[k].setup(v) end
    end)

    require("mason-lspconfig").setup({
      automatic_enable = true,
      handlers = table_handlers:get()
    })
  end,
}
