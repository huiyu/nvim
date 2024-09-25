local common = require("util.common")
local runtime_path = vim.split(package.path, ";")
table.insert(runtime_path, "lua/?.lua")
table.insert(runtime_path, "lua/?/init.lua")

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
            runtime = {
              -- Tell the language server which version of Lua you're using (most likely LuaJIT in the case of Neovim)
              version = "LuaJIT",
              -- Setup your lua path
              path = runtime_path,
            },
            diagnostics = {
              -- Get the language server to recognize the `vim` global
              globals = { "vim" },
            },
            workspace = {
              -- Make the server aware of Neovim runtime files
              library = vim.api.nvim_get_runtime_file("", true),
              checkThirdParty = false,
            },
            -- Do not send telemetry data containing a randomized but unique identifier
            telemetry = {
              enable = false,
            },
          },
        },
        flags = {
          debounce_text_changes = 150,
        },
      },
    }
  },
  config = function(_, opts)
    -- Refresh Mason registry and install specified tools if not already installed
    -- mason-registry: link=https://mason-registry.dev/registry/list

    local mr = require("mason-registry")
    mr.refresh(function()
      for tool, config in ipairs(normalize_options(opts.tools)) do
        local p = mr.get_package(tool)
        if not p:is_installed() then
          p:install(config)
        end
      end
    end)

    -- Map LSP servers to their setup functions and configure them using mason-lspconfig
    -- mason-lspconfig: link=https://github.com/williamboman/mason-lspconfig.nvim
    local table_handlers = common.table(normalize_options(opts.servers)):map(function(k, v)
      return k, function() require("lspconfig")[k].setup(v) end
    end)

    require("mason-lspconfig").setup_handlers(table_handlers:get())
  end,
}
