local lsp = require("util.lsp")

-- Register Ruff's organize-imports on a FileType autocmd. The custom LSP loader
-- (lua/plugin/lsp/lsp.lua) does not honor a per-server `keys` field, so binding
-- it here is the working equivalent of go.lua's organize-imports mapping.
vim.api.nvim_create_autocmd("FileType", {
  pattern = "python",
  group = vim.api.nvim_create_augroup("python_keymaps", { clear = true }),
  callback = function(ev)
    vim.keymap.set("n", "<leader>co", lsp.action["source.organizeImports"],
      { buffer = ev.buf, desc = "Organize Imports" })
  end,
})

-- <leader>cx runner (dispatched centrally by util.run; keymap in mappings.lua).
require("util.run").register("python", function(path)
  return "python3 " .. vim.fn.shellescape(path)
end)

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
        },
      },
      tools = {
        ["black"] = {},
        -- debugpy is the Python debug adapter consumed by nvim-dap-python.
        ["debugpy"] = {},
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
    ft = "python",
    dependencies = {
      "neovim/nvim-lspconfig",
      "folke/snacks.nvim",
    },
    opts = function()
      -- Resolve the conda/anaconda root portably instead of hardcoding the
      -- Apple-Silicon Homebrew path. If none is found the anaconda searches are
      -- simply omitted (venv-selector keeps its defaults for plain venvs).
      local function conda_root()
        local exe = vim.env.CONDA_EXE
        if exe and exe ~= "" then
          local root = vim.fs.dirname(vim.fs.dirname(exe)) -- <root>/bin/conda -> <root>
          if root and vim.fn.isdirectory(root) == 1 then return root end
        end
        -- Note: keep this a hole-free array — a nil element (e.g. an unset env
        -- var) would truncate ipairs and skip the rest, so CONDA_PREFIX is
        -- inserted separately only when it is actually set.
        local candidates = {
          "/opt/homebrew/anaconda3", -- Apple Silicon Homebrew
          "/usr/local/anaconda3",    -- Intel Homebrew
          vim.fn.expand("~/anaconda3"),
          vim.fn.expand("~/miniconda3"),
          vim.fn.expand("~/miniforge3"),
          "/opt/anaconda3",
        }
        if vim.env.CONDA_PREFIX and vim.env.CONDA_PREFIX ~= "" then
          table.insert(candidates, 1, vim.env.CONDA_PREFIX)
        end
        for _, dir in ipairs(candidates) do
          if vim.fn.isdirectory(dir) == 1 then return dir end
        end
        return nil
      end

      local root = conda_root()
      if not root then return {} end
      return {
        search = {
          anaconda_envs = {
            command = "$FD 'bin/python$' " .. root .. "/envs --no-ignore-vcs --full-path --color never",
            type = "anaconda",
          },
          anaconda_base = {
            command = "$FD '/python$' " .. root .. "/bin --full-path --color never",
            type = "anaconda",
          },
        },
      }
    end,
    keys = {
      { "<leader>cv", "<cmd>VenvSelect<cr>", desc = "Select virtualenv", ft = "python" },
    },
  },
  {
    -- Python debugging is owned by nvim-dap-python (single source). It loads on
    -- Python files so the debugpy adapter/configs are ready. debugpy is
    -- installed via the `tools` list above; the mason-nvim-dap `python` handler
    -- is intentionally dropped to avoid double registration.
    "mfussenegger/nvim-dap-python",
    ft = "python",
    config = function()
      local debugpy = vim.fn.stdpath("data") .. "/mason/packages/debugpy/venv/bin/python"
      require("dap-python").setup(debugpy)
    end,
    dependencies = {
      "mfussenegger/nvim-dap",
    },
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
