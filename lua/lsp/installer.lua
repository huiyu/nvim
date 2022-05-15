local lsp_installer = require("nvim-lsp-installer")

-- avaiable lsps: https://github.com/williamboman/nvim-lsp-installer#available-lsps
local servers = {
  sumneko_lua = require("lsp.config.sumneko_lua"),
  html = require("lsp.config.html"),
  cssls = require("lsp.config.cssls"),
  tsserver = require("lsp.config.tsserver"),
  gopls = require("lsp.config.gopls"),
  rust_analyzer = require("lsp.config.rust"),
  clang = require("lsp.config.clang"),
  pyright = require("lsp.config.pyright"),
  jdtls = require("lsp.config.jtdls"),
  jsonls = require("lsp.config.jsonls"),
  sqlls = require("lsp.config.sqlls"),
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
