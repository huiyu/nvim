-- Per-window filename labels.
--
-- `laststatus = 3` gives one global statusline, which names only the *current*
-- window's file. With a tree on one side, an agent panel on the other and two
-- editor splits in the middle, every window but the focused one is unlabelled.
-- incline floats a small label in each window's top-right corner to fill that
-- gap.
return {
  "b0o/incline.nvim",
  event = "BufReadPre",
  opts = function()
    local colors = require("solarized-osaka.colors").setup()
    return {
      highlight = {
        groups = {
          InclineNormal = { guibg = colors.magenta500, guifg = colors.base04 },
          InclineNormalNC = { guifg = colors.violet500, guibg = colors.base03 },
        },
      },
      window = { margin = { vertical = 0, horizontal = 1 } },
      -- 'smart' only hides a label when the cursor or a Visual selection would
      -- sit underneath it. Not to be confused with hiding the focused window's
      -- label -- `hide.cursorline = true` is a row-collision check too, not a
      -- focus check, so the render function below owns that decision.
      hide = { cursorline = "smart" },
      render = function(props)
        -- The focused window is the one the global statusline already names.
        if props.focused then return "" end

        -- Label file windows only. A tree, an agent panel and a picker are
        -- identifiable by their own chrome, and their buffer names
        -- ("term://.../claude") say nothing useful in a corner label.
        local buf = props.buf
        if vim.bo[buf].buftype ~= "" then return "" end
        local name = vim.api.nvim_buf_get_name(buf)
        if name == "" then return "" end

        local filename = vim.fn.fnamemodify(name, ":t")
        local icon, icon_color = require("nvim-web-devicons").get_icon_color(filename)
        return {
          icon and { icon, guifg = icon_color } or "",
          icon and " " or "",
          vim.bo[buf].modified and "[+] " or "",
          filename,
        }
      end,
    }
  end,
}
