return {
  {
    "nvim-neotest/neotest",
    dependencies = {
      "nvim-neotest/nvim-nio",
      "nvim-lua/plenary.nvim",
      "antoinemadec/FixCursorHold.nvim",
      "nvim-treesitter/nvim-treesitter"
    },
    opts = {
    },
    config = function(_, opts)
      local adapters = opts.adapters

      if adapters ~= nil then
        for name, config in pairs(adapters) do
          require(name)(config)
        end
      end

      require("neotest").setup(opts)
    end
  }
}
