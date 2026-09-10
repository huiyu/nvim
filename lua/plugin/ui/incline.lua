-- Filename labels in each file window's top-right corner.
-- The focused window gets a pink background; other splits use a muted label.
return {
  "b0o/incline.nvim",
  event = { "BufReadPre", "BufNewFile" },
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
      -- Hide only when the cursor or a Visual selection would sit underneath.
      hide = { cursorline = "smart" },
      render = function(props)
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
