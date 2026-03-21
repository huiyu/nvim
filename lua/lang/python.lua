local lsp = require("util.lsp")
return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = { ensure_installed = { "python", "ninja", "rst" } }
  },
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        basedpyright = {
          settings = {
            basedpyright = {
              analysis = {
                typeCheckingMode = "basic",
                autoImportCompletions = true,
                diagnosticSeverityOverrides = {
                  reportMissingImports = "error",
                  reportUndefinedVariable = "error",
                },
              },
            },
          },
        },
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
        ["basedpyright"] = {},
        ["black"] = {},
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
    "linux-cultist/venv-selector.nvim",
    branch = "regexp",
    ft = "python",
    dependencies = {
      "neovim/nvim-lspconfig",
      "nvim-telescope/telescope.nvim",
    },
    opts = {},
    keys = {
      { "<leader>cv", "<cmd>VenvSelect<cr>", desc = "Select virtualenv", ft = "python" },
    },
  },
  {
    "mfussenegger/nvim-dap-python",
    lazy = true,
    config = function()
      local python = vim.fn.expand("~/.local/share/nvim/mason/packages/debugpy/venv/bin/python")
      require("dap-python").setup(python)
    end,
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
