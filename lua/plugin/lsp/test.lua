return {
  {
    "nvim-neotest/neotest",
    dependencies = {
      "nvim-neotest/nvim-nio",
      "nvim-lua/plenary.nvim",
      "antoinemadec/FixCursorHold.nvim",
      "nvim-treesitter/nvim-treesitter"
    },
    keys = {
      { "<leader>tm", function() require("neotest").run.run() end,                     desc = "Test current method",  mode = { "n", "v" } },
      { "<leader>td", function() require("neotest").run.run({ strategy = "dap" }) end, desc = "Debug current method", mode = { "n", "v" } },
      { "<leader>tf", function() require("neotest").run.run(vim.fn.expand("%")) end,   desc = "Test current file",    mode = { "n", "v" } },
      { "<leader>tS", function() require("neotest").summary.toggle() end,              desc = "Toggle test summary",  mode = { "n", "v" } },
      { "<leader>to", function() require("neotest").output.open() end,                 desc = "Toggle test output",   mode = { "n", "v" } },
      { "<leader>tD", function() require("neotest").diagnostic.show() end,             desc = "Show test diagnostic", mode = { "n", "v" } },
      { "<leader>th", function() require("neotest").diagnostic.hide() end,             desc = "Hide test diagnostic", mode = { "n", "v" } },
    },
    opts = {},
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
