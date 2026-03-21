return {
  "akinsho/bufferline.nvim",
  event = "VeryLazy",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  keys = {
    { "<S-h>",      "<cmd>BufferLineCyclePrev<cr>",            desc = "Prev buffer" },
    { "<S-l>",      "<cmd>BufferLineCycleNext<cr>",            desc = "Next buffer" },
    { "[B",         "<cmd>BufferLineMovePrev<cr>",             desc = "Move buffer left" },
    { "]B",         "<cmd>BufferLineMoveNext<cr>",             desc = "Move buffer right" },
    { "<leader>bd", function() Snacks.bufdelete() end,         desc = "Delete buffer" },
    { "<leader>bD", "<cmd>:bd<cr>",                            desc = "Delete buffer and window" },
    { "<leader>bo", function() Snacks.bufdelete.other() end,   desc = "Delete other buffers" },
    { "<leader>bl", "<cmd>BufferLineCloseLeft<cr>",            desc = "Delete buffers to the left" },
    { "<leader>br", "<cmd>BufferLineCloseRight<cr>",           desc = "Delete buffers to the right" },
    { "<leader>bj", "<cmd>BufferLinePick<cr>",                 desc = "Pick buffer" },
    { "<leader>bp", "<cmd>BufferLineTogglePin<cr>",            desc = "Pin buffer" },
    { "<leader>bP", "<cmd>BufferLineGroupClose ungrouped<cr>", desc = "Close unpinned buffers" },
  },
  opts = {
    options = {
      diagnostics = "nvim_lsp",
      always_show_bufferline = false,
      offsets = {
        {
          filetype = "snacks_layout_box",
          text = "File Explorer",
          highlight = "Directory",
          text_align = "left",
        },
      },
    },
  },
}
