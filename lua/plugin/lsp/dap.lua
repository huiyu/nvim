return {
	"mfussenegger/nvim-dap",
	dependencies = {
		{
			"rcarriga/nvim-dap-ui",
			opts = {},
			config = function(_, opts)
				local dap = require("dap")
				local dapui = require("dapui")
				dapui.setup(opts)

				dap.listeners.after.event_initialized["dapui_config"] = function()
					dapui.open({})
				end
				dap.listeners.before.event_terminated["dapui_config"] = function()
					dapui.close({})
				end
				dap.listeners.before.event_exited["dapui_config"] = function()
					dapui.close({})
				end
			end,
		},
		{
			"theHamsta/nvim-dap-virtual-text",
			opts = {},
		},
    {
      "nvim-neotest/nvim-nio",
    },
		{
			"jay-babu/mason-nvim-dap.nvim",
			dependencies = "mason.nvim",
			opts = {
				handlers = {},
			},
		},
	},
}
