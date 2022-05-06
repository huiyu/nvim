local status_ok, lsp_installer = pcall(require, "nvim-lsp-installer")
if not status_ok then
  return
end

-- avaiable lsps: https://github.com/williamboman/nvim-lsp-installer#available-lsps
local servers = {
  sumneko_lua = require("user.lsp.config.sumneko_lua"),
  html = require("user.lsp.config.html"),
  cssls = require("user.lsp.config.cssls"),
  tsserver = require("user.lsp.config.tsserver"),
  gopls = require("user.lsp.config.gopls"),
  rust_analyzer = require("user.lsp.config.rust"),
  clang = require("user.lsp.config.clang"),
  pyright = require("user.lsp.config.pyright"),
  jdtls = require("user.lsp.config.jtdls"),
  jsonls = require("user.lsp.config.jsonls"),
  sqlls = require("user.lsp.config.sqlls"),
}

-- automatic install lsp server
for name, _ in pairs(servers) do
  local server_found, server = lsp_installer.get_server(name)
  if server_found then
    if not server:is_installed() then
      print("Installing " .. name)
      server:install()
    end
  end
end

lsp_installer.on_server_ready(function(server)
  local opts = {}

  local custom_opts = servers[server.name]

  if custom_opts == nil then
    return
  end

  opts = vim.tbl_deep_extend("force", custom_opts, opts)

  server:setup(opts)
end)
