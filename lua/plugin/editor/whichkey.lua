return {
  "folke/which-key.nvim",
  event = "VeryLazy",
  dependencies = {
    "echasnovski/mini.nvim",
    "echasnovski/mini.icons",
    "nvim-tree/nvim-web-devicons",
  },
  opts = {
    -- the presets plugin, adds help for a bunch of default keybindings in Neovim
    -- No actual key bindings are created
    preset = "classic",
    presets = {
      operators = true,    -- adds help for operators like d, y, ... and registers them for motion / text object completion
      motions = true,      -- adds help for motions
      text_objects = true, -- help for text objects triggered after entering an operator
      windows = true,      -- default bindings on <c-w>
      nav = true,          -- misc bindings to work with windows
      z = true,            -- bindings for folds, spelling and others prefixed with z
      g = true,            -- bindings for prefixed with g
    },
    -- Custom order: groups (+xxx) first, then alphanum (lowercase before
    -- uppercase), special chars last. which-key's built-in `group` sorter
    -- returns 1 for groups → groups come last under default a<b sort, so we
    -- invert it here.
    sort = {
      function(item) return item.group and 0 or 1 end, -- groups first
      "alphanum",                                       -- alphanum before symbols
      "case",                                           -- lowercase before uppercase
      "natural",                                        -- natural order of remaining
    },
  },
  init = function()
    local whichkey = require("which-key")
    -- Spec data lives in lua/whichkey_spec.lua; the imperative keymaps are in
    -- lua/mappings.lua (required for side effects by init.lua).
    whichkey.add(require("whichkey_spec"))
  end,
}
