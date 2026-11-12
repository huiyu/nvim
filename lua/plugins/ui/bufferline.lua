-- Panels are reached through their own focus keys. A listed terminal (often
-- named `env` by the agent wrapper) would replace the editor buffer on cycling
-- or picking, then edgy would move that editor window into the terminal edge.
-- Keep CodeDiff's revision buffers (codediff://) out too: util.codediff
-- unlists them once shown, and this covers the moment before.
local function shown_in_bufferline(buf)
  return vim.bo[buf].buftype ~= "terminal"
    and not vim.api.nvim_buf_get_name(buf):match("^codediff://")
end

-- The window a buffer from the list goes into: the current one when it shows
-- a file, else the editor area's. bufferline opens a buffer in the current
-- window, so from a panel the file landed in the panel's own window: a
-- CodeCompanion chat (or aerial, quickfix, help) simply took it, and in a
-- Snacks panel :buffer invokes fixbuf, whose fallback closes the panel (not
-- the job) when no file window remains.
local function editor_target()
  local win = vim.api.nvim_get_current_win()
  if vim.bo.buftype == "terminal" then vim.cmd.stopinsert() end
  if vim.bo.buftype ~= "" or vim.api.nvim_win_get_config(win).relative ~= "" then
    win = require("util.window").ensure_editor_win()
  end
  return win
end

local function open_file(buf)
  -- Match bufferline's scheduled default, but choose the file's destination
  -- before switching buffers.
  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(buf) then return end
    vim.api.nvim_set_current_win(editor_target())
    vim.api.nvim_set_current_buf(buf)
  end)
end

-- A buffer-list key, run from the editor window. Pressed in a panel, whose
-- own buffer is not in the list, [b/]b found nothing to cycle from while [B/]B
-- opened the file in the panel's window; both now act on the editor's list.
local function in_editor(fn)
  return function()
    vim.api.nvim_set_current_win(editor_target())
    fn()
  end
end

-- ;B picks in the editor window too. bufferline's pick takes no callback, so
-- a pick that changed nothing there (a cancel, or the buffer already shown)
-- goes back to the panel, closing the editor window it had to open for the
-- pick when the panel was alone in the tabpage.
local function pick()
  local from = vim.api.nvim_get_current_win()
  local had = {}
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do had[w] = true end
  local win = editor_target()
  vim.api.nvim_set_current_win(win)
  local before = vim.api.nvim_win_get_buf(win)
  require("bufferline").pick()
  if win ~= from and vim.api.nvim_win_is_valid(from) and vim.api.nvim_get_current_win() == win
    and vim.api.nvim_win_get_buf(win) == before then
    vim.api.nvim_set_current_win(from)
    if not had[win] then
      -- ensure_editor_win's `:new` left an empty buffer there: it goes too,
      -- or it would stay in the list as [No Name].
      pcall(vim.api.nvim_win_close, win, false)
      if vim.api.nvim_buf_is_valid(before) and vim.api.nvim_buf_get_name(before) == ""
        and not vim.bo[before].modified and vim.api.nvim_buf_line_count(before) == 1
        and vim.api.nvim_buf_get_lines(before, 0, 1, false)[1] == "" then
        pcall(vim.api.nvim_buf_delete, before, {})
      end
    end
  end
end

return {
  "akinsho/bufferline.nvim",
  event = "VeryLazy",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  keys = {
    { "<S-h>",      in_editor(function() vim.cmd("BufferLineCyclePrev") end), desc = "Prev buffer" },
    { "<S-l>",      in_editor(function() vim.cmd("BufferLineCycleNext") end), desc = "Next buffer" },
    -- Keep Tab available for its native <C-I> jumplist meaning in terminals
    -- that cannot distinguish the two. Shift-H/L are the fast pair; [b/]b
    -- retain the standard previous/next vocabulary and which-key discovery.
    { "[b",         in_editor(function() vim.cmd("BufferLineCyclePrev") end), desc = "Prev buffer" },
    { "]b",         in_editor(function() vim.cmd("BufferLineCycleNext") end), desc = "Next buffer" },
    -- Uppercase is the first/last of the same list, as [Q/]Q and [L/]L are.
    -- go_to(_, true) counts every buffer, not only those the bar has room to
    -- show, so it is the order [b/]b cycle through.
    { "[B",         in_editor(function() require("bufferline").go_to(1, true) end),  desc = "First buffer" },
    { "]B",         in_editor(function() require("bufferline").go_to(-1, true) end), desc = "Last buffer" },
    -- Picking a buffer by its tab letter answers "where do I want to be", so
    -- it sits on `;` beside ;b, and a CodeDiff view's `;` block covers it.
    { ";B",         pick,                                      desc = "Pick buffer" },
    { "<leader>bd", function() Snacks.bufdelete() end,         desc = "Delete buffer" },
    { "<leader>bD", "<cmd>:bd<cr>",                            desc = "Delete buffer and window" },
    { "<leader>bo", function() Snacks.bufdelete.other() end,   desc = "Delete other buffers" },
    { "<leader>bl", "<cmd>BufferLineCloseLeft<cr>",            desc = "Delete buffers to left" },
    { "<leader>br", "<cmd>BufferLineCloseRight<cr>",           desc = "Delete buffers to right" },
    { "<leader>b<", "<cmd>BufferLineMovePrev<cr>",             desc = "Move buffer left" },
    { "<leader>b>", "<cmd>BufferLineMoveNext<cr>",             desc = "Move buffer right" },
    { "<leader>bp", "<cmd>BufferLineTogglePin<cr>",            desc = "Toggle pin" },
    { "<leader>bP", "<cmd>BufferLineGroupClose ungrouped<cr>", desc = "Delete unpinned buffers" },
    { "<leader>bx", function() require("util.buffer").delete_missing() end, desc = "Delete buffers of missing files" },
    -- Unlike <leader>bo this leaves every visible split alone, in this
    -- tabpage and the others.
    { "<leader>bh", function() require("util.buffer").delete_hidden() end,  desc = "Delete hidden buffers" },
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
        -- blur, and an opaque strip across the top would cut a hole in it. An
        -- unset background inherits the tabline's default rather than reaching
        -- the terminal, so `TabLineFill` is cleared alongside this in
        -- lua/plugins/ui/solarized.lua; without that this line drew the theme's
        -- teal instead of nothing.
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
      },
      options = {
        diagnostics = "nvim_lsp",
        -- The tabline is permanent. Left to itself bufferline hides it whenever
        -- it has at most one buffer to show, counting buffers only --
        -- `toggle_bufferline` reads `get_buf_count()` outside "tabs" mode, so
        -- tabpages never enter the decision. Opening a diff with no files
        -- loaded then hid the far-right `1`/`2` tabpage indicators along with
        -- the buffer list, at the one moment they matter most: CodeDiff
        -- disables the global prefixes inside its tabpage, and knowing another
        -- tabpage exists is the way out.
        --
        -- Keeping it on costs a blank strip above an empty dashboard and buys a
        -- layout that never shifts a row as buffers and tabpages come and go.
        always_show_bufferline = true,
        separator_style = "slant",
        show_tab_indicators = true,
        custom_filter = shown_in_bufferline,
        left_mouse_command = open_file,
      },
    }
  end,
}
