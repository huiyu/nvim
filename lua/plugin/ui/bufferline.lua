return {
  "akinsho/bufferline.nvim",
  event = "VeryLazy",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  keys = {
    { "<S-h>",      "<cmd>BufferLineCyclePrev<cr>",            desc = "Prev buffer" },
    { "<S-l>",      "<cmd>BufferLineCycleNext<cr>",            desc = "Next buffer" },
    { "[b",         "<cmd>BufferLineCyclePrev<cr>",            desc = "Prev buffer" },
    { "]b",         "<cmd>BufferLineCycleNext<cr>",            desc = "Next buffer" },
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
  opts = function()
    -- Pull accent colors from the active theme so the tabpage indicators
    -- (far-right `1`/`2` numbers, shown via show_tab_indicators) are readable.
    -- bufferline's defaults render them in near-background tones (comment_fg /
    -- tabline_sel_bg), which are nearly invisible on the solarized-osaka teal.
    -- Make the active tab an orange badge and the rest a bright bold number.
    local c = require("solarized-osaka.colors").setup()
    return {
      highlights = {
        tab                    = { fg = c.base0, bg = c.bg_highlight, bold = true },
        tab_selected           = { fg = c.bg, bg = c.orange, bold = true },
        tab_separator          = { fg = c.bg_highlight, bg = c.bg_highlight },
        tab_separator_selected = { fg = c.orange, bg = c.orange, bold = true },
        tab_close              = { fg = c.red, bg = c.bg_highlight, bold = true },
      },
      options = {
        diagnostics = "nvim_lsp",
        always_show_bufferline = false,
        show_tab_indicators = true,
        -- Keep diffview's internal buffers (incl. phantom diffview://null) out of
        -- the bufferline, so BufferLinePick / buffer cycling can't land on them.
        custom_filter = function(buf_number)
          return not vim.api.nvim_buf_get_name(buf_number):match("diffview://")
        end,
        offsets = {
          {
            filetype = "snacks_layout_box",
            text = "File Explorer",
            highlight = "Directory",
            text_align = "left",
          },
        },
      },
    }
  end,
}
