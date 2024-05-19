return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      vim.list_extend(opts.ensure_installed, {
        "yaml",
      })
    end,
  },
  {
    "williamboman/mason-lspconfig.nvim",
    opts = function(_, opts)
      vim.list_extend(opts.ensure_installed, {
        "yamlls",
      })
      opts.handlers["yamlls"] = function()
        require('lspconfig').yamlls.setup({})
      end
    end
  }
}
