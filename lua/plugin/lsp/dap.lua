---Wrap a configuration so `<leader>da` prompts for its arguments.
---@param config table Debug adapter configuration containing args and type
---@return table Copy of the configuration whose `args` prompts before launch
local function get_args(config)
  -- Existing args seed the prompt: a function, a list, or a plain string.
  local args = type(config.args) == "function" and (config.args() or {}) or config.args or {}
  local args_str = type(args) == "table" and table.concat(args, " ") or args --[[@as string]]

  -- Copy so the prompt never rewrites the registered configuration.
  config = vim.deepcopy(config)

  config.args = function()
    local input = vim.fn.input("Run with args: ", args_str)

    -- java-debug takes one string; every other adapter takes a list. Splitting
    -- and rejoining would drop the quoting the user typed, so the string is
    -- passed through untouched.
    if config.type == "java" then
      return input
    end

    -- expand() resolves one file name, not an args string: it returns the
    -- first result and discards the rest, so "% --port 3000" collapsed to the
    -- buffer's name and a bare "#" became "". Split first, expand each token,
    -- which is also what makes `~/...` work in any position rather than only
    -- as the whole input.
    return vim.tbl_map(vim.fn.expand, require("dap.utils").splitstr(input))
  end
  return config
end

return {
  {
    "mfussenegger/nvim-dap",
    lazy = true,
    cmd = { "DapAttach" },
    keys = {
      { "<leader>dA", function() require("util.dap").attach() end, desc = "Attach to Running Target" },
      { "<leader>df", function() require("util.dap").run_target("file") end, desc = "Debug Current File" },
      { "<leader>td", function() require("util.dap").run_target("test") end, desc = "Debug Nearest Test", mode = { "n", "v" } },
      { "<leader>tF", function() require("util.dap").run_target("test_file") end, desc = "Debug Current Test File", mode = { "n", "v" } },
      { "<leader>dB", function() require("dap").set_breakpoint(vim.fn.input("Breakpoint condition: ")) end, desc = "Breakpoint Condition",    mode = { "n", "v" } },
      { "<leader>db", function() require("dap").toggle_breakpoint() end,                                    desc = "Toggle Breakpoint",       mode = { "n", "v" } },
      -- Breakpoints live in memory across files; without a list the only way to
      -- find one set in a buffer you have since closed is to remember it.
      { "<leader>dq", function() require("dap").list_breakpoints(true) end,                                 desc = "List Breakpoints (quickfix)", mode = { "n", "v" } },
      { "<leader>dx", function() require("dap").clear_breakpoints() end,                                    desc = "Clear All Breakpoints",   mode = { "n", "v" } },
      { "<leader>dL", function() require("util.dap").logpoint() end, desc = "Logpoint" },
      { "<leader>de", function() require("util.dap").exceptions() end, desc = "Exception Breakpoints" },
      { "<leader>dR", function() require("util.dap").restart() end, desc = "Restart Session" },
      { "<leader>dD", function() require("util.dap").disconnect() end, desc = "Disconnect (Keep Target Running)" },
      { "<leader>du", function() require("dapui").toggle() end, desc = "Toggle Debug Panels" },
      { "<leader>dW", function() require("util.dap").watch() end, desc = "Add Watch Expression", mode = { "n", "x" } },
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
      { "<leader>ds", function() local w = require("dap.ui.widgets"); w.centered_float(w.sessions) end, desc = "Debug Sessions" },
      -- js-debug and Electron own a session tree: a root plus one child per
      -- target. Bare terminate() defaults to hierarchy=false and kills only
      -- dap.session(), which is usually a child -- the root stays attached and
      -- the panels stay open, so the key reads as dead. `hierarchy` walks up to
      -- the root and terminates the whole tree. Not `all`: a second, unrelated
      -- session (a backend alongside a browser) is not this key's business.
      { "<leader>dt", function() require("dap").terminate({ hierarchy = true }) end,                       desc = "Terminate",               mode = { "n", "v" } },
      { "<leader>dw", function() require("util.dap").evaluate() end, desc = "Evaluate Expression / Selection", mode = { "n", "x" } },
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
      require("util.dap").targets = opts.targets or {}
      vim.api.nvim_create_user_command("DapAttach", function() require("util.dap").attach() end,
        { desc = "Choose an attach configuration for this filetype or project" })
      local dapui = require("dapui")
      dapui.setup({
        -- Placement belongs to edgy (lua/plugin/editor/edgy.lua), which claims
        -- these filetypes like every other panel here. dapui still decides when
        -- the elements exist; its own `layouts` only says where the windows
        -- start before edgy re-homes them, so it stays at the upstream default.
        --
        -- select_window is not optional under that arrangement. dapui's
        -- fallback asks the user to pick a target window whenever the tab holds
        -- more than one file window (dapui/util.lua, select_win), which is the
        -- normal shape here. ensure_editor_win answers the question every
        -- picker in this config already asks, and creates a window when the tab
        -- has only panels left.
        select_window = require("util.window").ensure_editor_win,
      })

      dap.listeners.after.event_initialized["dapui_config"] = function(session)
        -- An adapter that owns several targets initializes one child session
        -- per target, and every one of them fires this. dapui.open is not a
        -- no-op once the panels are up: it re-runs update_sizes, open and
        -- resize for every layout, so opening per target re-applied the whole
        -- layout mid-session while edgy was re-applying its own sizes on the
        -- same events. The root opens them; children inherit.
        if session and session.parent then return end
        dapui.open({})
      end
      local function close_when_done()
        -- dap.sessions() holds root sessions only -- set_session registers a
        -- session solely when it has no parent. That is the right unit: a child
        -- belongs to its root and goes down with it (`<leader>dt` terminates
        -- the tree), and a root disappearing is what ends a debug session.
        -- Scheduled because several roots can finish in the same tick.
        vim.schedule(function()
          if next(dap.sessions()) == nil then dapui.close({}) end
        end)
      end
      dap.listeners.after.event_terminated["dapui_config"] = close_when_done
      dap.listeners.after.disconnect["dapui_config"] = close_when_done

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
      local tbl = require("util.common").table
      -- Guard against a base startup with no language module injecting handlers
      -- (util.common.table errors on a nil argument).
      local table_handlers = tbl(opts.handlers or {}):map(function(k, v)
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

      -- Adapters mason-nvim-dap cannot supply, contributed as data by the
      -- language modules. Its `handlers` list only decides which package mason
      -- installs; an entry with no definition under its own
      -- `mappings/adapters/` (js-debug is the case here) downloads a binary and
      -- registers nothing. Applied after the mason setup so a language module
      -- stays the last word on its own adapter.
      for name, adapter in pairs(opts.adapters or {}) do
        dap.adapters[name] = adapter
      end
      -- Extend rather than assign: a language whose plugin already registered
      -- configurations keeps them, and `<leader>dc` lists both sets.
      for ft, configs in pairs(opts.configurations or {}) do
        dap.configurations[ft] = vim.list_extend(dap.configurations[ft] or {}, configs)
      end

      -- setup dap config by VsCode launch.json file
      local vscode = require("dap.ext.vscode")
      local json = require("plenary.json")
      vscode.json_decode = function(str)
        return vim.json.decode(json.json_strip_comments(str))
      end
    end,
  },
}
