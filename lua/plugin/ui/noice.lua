return {
  "folke/noice.nvim",
  event = "VeryLazy",
  dependencies = {
    "MunifTanjim/nui.nvim",
    "rcarriga/nvim-notify",
  },
  keys = {
    { "<leader>snl", function() require("noice").cmd("last") end,    desc = "Noice last message" },
    { "<leader>snh", function() require("noice").cmd("history") end, desc = "Noice history" },
    { "<leader>sna", function() require("noice").cmd("all") end,     desc = "Noice all" },
    { "<leader>snd", function() require("noice").cmd("dismiss") end, desc = "Dismiss all" },
    { "<leader>snt", function() require("noice").cmd("pick") end,    desc = "Noice picker" },
    { "<C-f>", function() if not require("noice.lsp").scroll(4) then return "<C-f>" end end,  mode = { "i", "n", "s" }, expr = true, desc = "Scroll forward" },
    { "<C-b>", function() if not require("noice.lsp").scroll(-4) then return "<C-b>" end end, mode = { "i", "n", "s" }, expr = true, desc = "Scroll backward" },
  },
  opts = {
    lsp = {
      override = {
        ["vim.lsp.util.convert_input_to_markdown_lines"] = true,
        ["vim.lsp.util.stylize_markdown"] = true,
      },
    },
    presets = {
      bottom_search = true,
      command_palette = true,
      long_message_to_split = true,
      inc_rename = true,
      lsp_doc_border = false,
    },
  },
}
