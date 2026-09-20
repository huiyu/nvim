-- Keep diffview's internal buffers (incl. phantom diffview://null) out of the
-- bufferline, so BufferLinePick / buffer cycling can't land on them.
local function shown_in_bufferline(buf)
  return not vim.api.nvim_buf_get_name(buf):match("diffview://")
end

local function shown_buffer_count()
  local count = 0
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].buflisted and shown_in_bufferline(buf) then count = count + 1 end
  end
  return count
end

-- bufferline hides the whole tabline when it has at most one buffer to show,
-- and its own count never looks at tabpages: `toggle_bufferline` reads
-- `get_buf_count()` outside "tabs" mode (bufferline.lua). Opening a diff with
-- no files loaded therefore hid the far-right `1`/`2` tabpage indicators along
-- with the buffer list -- at the one moment they matter most, since diffview
-- disables the global prefixes inside its own tabpage and knowing another
-- tabpage exists is the way out.
--
-- Taking the toggle over rather than forcing the bufferline always on: an empty
-- dashboard should still start without one. Leaving bufferline's own toggle
-- enabled would not work anyway -- it re-runs from the tabline's own redraw, so
-- it would undo any override on the next draw.
local function sync_tabline()
  vim.o.showtabline = (shown_buffer_count() > 1 or #vim.api.nvim_list_tabpages() > 1) and 2 or 0
end

return {
  "akinsho/bufferline.nvim",
  event = "VeryLazy",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  keys = {
    { "<S-h>",      "<cmd>BufferLineCyclePrev<cr>",            desc = "Prev buffer" },
    { "<S-l>",      "<cmd>BufferLineCycleNext<cr>",            desc = "Next buffer" },
    -- Keep Tab available for its native <C-I> jumplist meaning in terminals
    -- that cannot distinguish the two. Shift-H/L are the fast pair; [b/]b
    -- retain the standard previous/next vocabulary and which-key discovery.
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

        -- The main bar in the same language as the tab badges above: the
        -- current entry is a filled yellow block, the rest sit on the muted
        -- teal. Without an explicit background the defaults only brighten the
        -- selected text, which leaves `separator_style = "slant"` invisible --
        -- the slant glyph is drawn by the separator's *foreground*, so with no
        -- colour there is a shape but nothing to see.
        --
        -- Slant colour rule (bufferline/config.lua:561): fg is the gap between
        -- entries, bg is the entry's own fill. Use the theme's darkest teal for
        -- that gap: a bright foreground turns both slants into white wedges.
        -- Transparent, not c.bg: Ghostty runs at background-opacity 0.85 with
        -- blur, and an opaque strip across the top would cut a hole in it.
        fill                   = { bg = "NONE" },
        background             = { fg = c.base01, bg = c.bg_highlight },
        buffer_visible         = { fg = c.base0, bg = c.bg_highlight },
        buffer_selected        = { fg = c.base4, bg = c.yellow, bold = true, italic = false },
        separator              = { fg = c.bg, bg = c.bg_highlight },
        separator_visible      = { fg = c.bg, bg = c.bg_highlight },
        separator_selected     = { fg = c.bg, bg = c.yellow },

        -- Everything drawn *inside* an entry needs the same background, or it
        -- keeps the derived default and punches a hole in the orange block.
        indicator_selected     = { fg = c.yellow, bg = c.yellow },
        modified               = { fg = c.green, bg = c.bg_highlight },
        modified_visible       = { fg = c.green, bg = c.bg_highlight },
        modified_selected      = { fg = c.base4, bg = c.yellow },
        close_button           = { fg = c.base01, bg = c.bg_highlight },
        close_button_visible   = { fg = c.base0, bg = c.bg_highlight },
        close_button_selected  = { fg = c.base4, bg = c.yellow },
        duplicate              = { fg = c.base01, bg = c.bg_highlight, italic = true },
        duplicate_visible      = { fg = c.base0, bg = c.bg_highlight, italic = true },
        duplicate_selected     = { fg = c.base4, bg = c.yellow, italic = true },
        numbers                = { fg = c.base01, bg = c.bg_highlight },
        numbers_visible        = { fg = c.base0, bg = c.bg_highlight },
        numbers_selected       = { fg = c.base4, bg = c.yellow, bold = true },
        -- diagnostics = "nvim_lsp" puts counts inside the entry too.
        error                  = { fg = c.red, bg = c.bg_highlight },
        error_visible          = { fg = c.red, bg = c.bg_highlight },
        error_selected         = { fg = c.base4, bg = c.yellow, bold = true },
        error_diagnostic       = { fg = c.red, bg = c.bg_highlight },
        error_diagnostic_visible = { fg = c.red, bg = c.bg_highlight },
        error_diagnostic_selected = { fg = c.base4, bg = c.yellow, bold = true },
        warning                = { fg = c.yellow, bg = c.bg_highlight },
        warning_visible        = { fg = c.yellow, bg = c.bg_highlight },
        warning_selected       = { fg = c.base4, bg = c.yellow, bold = true },
        warning_diagnostic     = { fg = c.yellow, bg = c.bg_highlight },
        warning_diagnostic_visible = { fg = c.yellow, bg = c.bg_highlight },
        warning_diagnostic_selected = { fg = c.base4, bg = c.yellow, bold = true },
        info                   = { fg = c.blue, bg = c.bg_highlight },
        info_visible           = { fg = c.blue, bg = c.bg_highlight },
        info_selected          = { fg = c.base4, bg = c.yellow, bold = true },
        info_diagnostic        = { fg = c.blue, bg = c.bg_highlight },
        info_diagnostic_visible = { fg = c.blue, bg = c.bg_highlight },
        info_diagnostic_selected = { fg = c.base4, bg = c.yellow, bold = true },
        hint                   = { fg = c.cyan, bg = c.bg_highlight },
        hint_visible           = { fg = c.cyan, bg = c.bg_highlight },
        hint_selected          = { fg = c.base4, bg = c.yellow, bold = true },
        hint_diagnostic        = { fg = c.cyan, bg = c.bg_highlight },
        hint_diagnostic_visible = { fg = c.cyan, bg = c.bg_highlight },
        hint_diagnostic_selected = { fg = c.base4, bg = c.yellow, bold = true },
        offset_separator       = { fg = c.bg_highlight, bg = c.bg },
      },
      options = {
        diagnostics = "nvim_lsp",
        always_show_bufferline = false,
        -- `sync_tabline` owns showtabline; see the note above it.
        auto_toggle_bufferline = false,
        separator_style = "slant",
        show_tab_indicators = true,
        custom_filter = shown_in_bufferline,
      },
    }
  end,

  config = function(_, opts)
    require("bufferline").setup(opts)
    -- Scheduled: BufDelete and TabClosed both fire while the thing they report
    -- is still present, so the count has to be taken after they settle.
    vim.api.nvim_create_autocmd(
      { "BufAdd", "BufDelete", "BufFilePost", "TabNew", "TabClosed", "TabEnter" },
      {
        group = vim.api.nvim_create_augroup("bufferline_tabline", { clear = true }),
        callback = function() vim.schedule(sync_tabline) end,
      })
    sync_tabline()
  end,
}
