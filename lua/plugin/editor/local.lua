local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h:h")
return {
  {
    dir = root .. "/local-plugin/editor-core.nvim", name = "editor-core.nvim", main = "editor_core",
    lazy = false, priority = 10000,
    opts = function()
      return {
        options = require("config.options"), theme = require("config.theme"), formatting = require("config.formatting"),
        keymaps = require("config.keymaps"), behaviors = require("config.behaviors"),
        url = { buffer_dir = require("util.cwd").buffer_dir },
      }
    end,
  },
}
