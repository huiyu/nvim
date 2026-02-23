local lsp = require("util.lsp")
return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = { ensure_installed = { "ninja", "rst" } }
  },
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        ruff = {
          cmd_env = { RUFF_TRACE = "message" },
          init_options = {
            settings = {
              logLevel = "error",
            }
          },
          keys = {
            {
              "<leader>cO",
              lsp.action["source.organizeImports"],
              desc = "Organize Imports",
            }
          }
        },
      },
      tools = {
        ["black"] = {}
      }
    },
  },
  {
    "stevearc/conform.nvim",
    optional = true,
    opts = {
      formatters_by_ft = {
        ["python"] = { "black" }
      }

    }
  },
  {
    "mfussenegger/nvim-dap-python",
    lazy = true,
    config = function()
      local python = vim.fn.expand("~/.local/share/nvim/mason/packages/debugpy/venv/bin/python")
      require("dap-python").setup(python)
    end,
    -- Consider the mappings at
    -- https://github.com/mfussenegger/nvim-dap-python?tab=readme-ov-file#mappings
    dependencies = {
      "mfussenegger/nvim-dap",
    },

  },
  {
    "mfussenegger/nvim-dap",
    opts = {
      handlers = {
        ["python"] = {}
      }
    }
  },
  {
    "nvim-neotest/neotest",
    dependencies = {
      "nvim-neotest/neotest-python",
    },
    opts = {
      adapters = {
        ["neotest-python"] = {
          dap = { justMyCode = false }
        }
      }
    }
  }
}
