---Processes debug adapter configuration arguments
---Handles both function and table argument types, with special handling for Java.
---Prompts user for input and processes arguments appropriately for different language types.
---@param config table Debug adapter configuration containing args and type
---@return table Modified configuration with interactive argument processing
---@example
---local modified_config = get_args({
---  type = "python",
---  args = {"--verbose", "--debug"}
---})
local function get_args(config)
  -- Extract existing args (function, table, or default to empty)
  local args = type(config.args) == "function" and (config.args() or {}) or config.args or
      {} --[[@as string[] | string ]]
  
  -- Convert args to string for display in input prompt
  local args_str = type(args) == "table" and table.concat(args, " ") or args --[[@as string]]

  -- Create a deep copy to avoid modifying original config
  config = vim.deepcopy(config)
  ---@cast args string[]
  
  -- Replace args with interactive function
  config.args = function()
    local new_args = vim.fn.expand(vim.fn.input("Run with args: ", args_str)) --[[@as string]]
    
    -- Java requires string args, other languages need split args
    if config.type and config.type == "java" then
      ---@diagnostic disable-next-line: return-type-mismatch
      return new_args
    end
    
    -- Split string into array for other languages
    return require("dap.utils").splitstr(new_args)
  end
  return config
end

return {
  {
    "mfussenegger/nvim-dap",
    lazy = true,
    keys = {
      { "<leader>dB", function() require("dap").set_breakpoint(vim.fn.input("Breakpoint condition: ")) end, desc = "Breakpoint Condition",    mode = { "n", "v" } },
      { "<leader>db", function() require("dap").toggle_breakpoint() end,                                    desc = "Toggle Breakpoint",       mode = { "n", "v" } },
      { "<leader>dc", function() require("dap").continue() end,                                             desc = "Run/Continue",            mode = { "n", "v" } },
      { "<leader>da", function() require("dap").continue({ before = get_args }) end,                        desc = "Run with Args",           mode = { "n", "v" } },
      { "<leader>dC", function() require("dap").run_to_cursor() end,                                        desc = "Run to Cursor",           mode = { "n", "v" } },
      { "<leader>dg", function() require("dap").goto_() end,                                                desc = "Go to Line (No Execute)", mode = { "n", "v" } },
      { "<leader>di", function() require("dap").step_into() end,                                            desc = "Step Into",               mode = { "n", "v" } },
      { "<leader>dj", function() require("dap").down() end,                                                 desc = "Down",                    mode = { "n", "v" } },
      { "<leader>dk", function() require("dap").up() end,                                                   desc = "Up",                      mode = { "n", "v" } },
      { "<leader>dl", function() require("dap").run_last() end,                                             desc = "Run Last",                mode = { "n", "v" } },
      { "<leader>do", function() require("dap").step_out() end,                                             desc = "Step Out",                mode = { "n", "v" } },
      { "<leader>dO", function() require("dap").step_over() end,                                            desc = "Step Over",               mode = { "n", "v" } },
      { "<leader>dP", function() require("dap").pause() end,                                                desc = "Pause",                   mode = { "n", "v" } },
      { "<leader>dr", function() require("dap").repl.toggle() end,                                          desc = "Toggle REPL",             mode = { "n", "v" } },
      { "<leader>ds", function() require("dap").session() end,                                              desc = "Session",                 mode = { "n", "v" } },
      { "<leader>dt", function() require("dap").terminate() end,                                            desc = "Terminate",               mode = { "n", "v" } },
      { "<leader>dw", function() require("dap.ui.widgets").hover() end,                                     desc = "Widgets",                 mode = { "n", "v" } },
    },
    dependencies = {
      { "rcarriga/nvim-dap-ui",            dependencies = { "nvim-neotest/nvim-nio" }, config = function() end },
      { "theHamsta/nvim-dap-virtual-text", opts = {} },
      { "jay-babu/mason-nvim-dap.nvim",    dependencies = { "mason.nvim" },            config = function() end },
    },
    opts = {},

    config = function(_, opts)
      -- Config dap & dap UI
      local dap = require("dap")
      local dapui = require("dapui")
      dapui.setup()

      dap.listeners.after.event_initialized["dapui_config"] = function()
        dapui.open({})
      end
      dap.listeners.before.event_terminated["dapui_config"] = function()
        dapui.close({})
      end
      dap.listeners.before.event_exited["dapui_config"] = function()
        dapui.close({})
      end

      -- Define signs for different debugging states:
      vim.fn.sign_define(
        "DapStopped",
        { text = "󰁕", texthl = "DiagnosticWarn", linehl = "DapStoppedLine", numhl = "DapStoppedLine" }
      )
      vim.fn.sign_define("DapBreakpoint", { text = "", texthl = "DiagnosticInfo" })
      vim.fn.sign_define("DapBreakpointCondition", { text = "", texthl = "DiagnosticInfo" })
      vim.fn.sign_define("DapBreakpointRejected", { text = "", texthl = "DiagnosticError" })
      vim.fn.sign_define("DapLogPoint", { text = ".>", texthl = "DiagnosticInfo" })

      -- Config nvim mason
      local table = require("util.common").table
      local table_handlers = table(opts.handlers):map(function(k, v)
        if type(v) == "table" then
          return k,
              function(config)
                config = vim.tbl_extend("force", config, v)
                require("mason-nvim-dap").default_setup(config)
              end
        elseif type(v) == "function" then
          return k,
              function(config)
                require("mason-nvim-dap").default_setup(vim.tbl_extend("force", config, v()))
              end
        else
          error("Unsupported type error: " .. type(v))
        end
      end)

      require("mason-nvim-dap").setup({
        automatic_installation = true,
        ensure_installed = table_handlers:keys():get(),
        handlers = table_handlers:get(),
      })

      -- setup dap config by VsCode launch.json file
      local vscode = require("dap.ext.vscode")
      local json = require("plenary.json")
      vscode.json_decode = function(str)
        return vim.json.decode(json.json_strip_comments(str))
      end
    end,
  },
}
