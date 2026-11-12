---Show or hide the failures neotest publishes as diagnostics.
---
---neotest's diagnostic consumer has no interface (`diagnostic.show` and
---`diagnostic.hide` do not exist): it writes into the "neotest" diagnostic
---namespace, so the toggle is Nvim's own per-namespace enable, and the
---namespace's `disabled` flag is the state. The namespace may be empty when
---the key is pressed, so the new state is said.
local function toggle_diagnostics()
  local ns = vim.api.nvim_create_namespace("neotest")
  local show = vim.diagnostic.get_namespace(ns).disabled == true
  vim.diagnostic.enable(show, { ns_id = ns })
  vim.notify(show and "Test diagnostics shown" or "Test diagnostics hidden")
end

return {
  {
    "nvim-neotest/neotest",
    dependencies = {
      "nvim-neotest/nvim-nio",
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter"
    },
    -- Case marks the debug variant of the same run: tm/tM nearest, tf/tF the
    -- file (the debug keys live in lua/plugin/lsp/dap.lua).
    keys = {
      { "<leader>tm", function() require("neotest").run.run() end,                     desc = "Run nearest test" },
      { "<leader>tf", function() require("neotest").run.run(vim.fn.expand("%")) end,   desc = "Run tests in file" },
      { "<leader>ts", function() require("neotest").summary.toggle() end,              desc = "Toggle test summary" },
      { "<leader>to", function() require("neotest").output.open() end,                 desc = "Show test output" },
      { "<leader>tx", toggle_diagnostics,                                              desc = "Toggle test diagnostics" },
    },
    opts = {
      -- g? is help in every panel here (aerial, oil, CodeDiff); ? stays too.
      -- Each mapping takes a list of keys.
      summary = { mappings = { help = { "?", "g?" } } },
      consumers = {
        -- Explicit path/row prevents a buffer switch during discovery from
        -- changing the target. Never let "nearest" fall back to a whole file.
        debug_target = function(client)
          return function(ctx, file)
            require("nio").run(function()
              local tree, adapter
              if file then
                tree, adapter = client:get_position(ctx.path)
              else
                tree, adapter = client:get_nearest(ctx.path, ctx.line - 1)
              end
              if not tree or (not file and tree:data().type ~= "test") then
                vim.notify("No test found at this position", vim.log.levels.WARN)
                return
              end
              client:run_tree(tree, { strategy = "dap", adapter = adapter })
            end)
          end
        end,
      },
    },
    config = function(_, opts)
      -- neotest expects `adapters` to be a LIST of built adapter instances and
      -- iterates it with ipairs. The lang/ files contribute a name-keyed map
      -- (`{ ["neotest-python"] = {...} }`), so build each adapter and collect
      -- the results into a list before handing it to setup.
      if opts.adapters ~= nil then
        local built = {}
        for name, config in pairs(opts.adapters) do
          built[#built + 1] = require(name)(config)
        end
        opts.adapters = built
      end

      require("neotest").setup(opts)
    end
  }
}
