return {
  "akinsho/bufferline.nvim",
  event = "VeryLazy",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  keys = {
    { "<S-h>",      "<cmd>BufferLineCyclePrev<cr>",            desc = "Prev buffer" },
    { "<S-l>",      "<cmd>BufferLineCycleNext<cr>",            desc = "Next buffer" },
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
