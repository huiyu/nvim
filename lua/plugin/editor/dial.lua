return {
  "monaqa/dial.nvim",
  keys = {
    { "<C-a>",  function() return require("dial.map").inc_normal() end,  expr = true, desc = "Increment" },
    { "<C-x>",  function() return require("dial.map").dec_normal() end,  expr = true, desc = "Decrement" },
    { "g<C-a>", function() return require("dial.map").inc_gnormal() end, expr = true, desc = "Increment" },
    { "g<C-x>", function() return require("dial.map").dec_gnormal() end, expr = true, desc = "Decrement" },
    { "<C-a>",  function() return require("dial.map").inc_visual() end,  mode = "v",  expr = true, desc = "Increment" },
    { "<C-x>",  function() return require("dial.map").dec_visual() end,  mode = "v",  expr = true, desc = "Decrement" },
    { "g<C-a>", function() return require("dial.map").inc_gvisual() end, mode = "v",  expr = true, desc = "Increment" },
    { "g<C-x>", function() return require("dial.map").dec_gvisual() end, mode = "v",  expr = true, desc = "Decrement" },
  },
  config = function()
    local augend = require("dial.augend")
    require("dial.config").augends:register_group({
      default = {
        augend.integer.alias.decimal,
        augend.integer.alias.hex,
        augend.date.alias["%Y/%m/%d"],
        augend.date.alias["%Y-%m-%d"],
        augend.constant.alias.bool,
        augend.semver.alias.semver,
        augend.constant.new({ elements = { "&&", "||" }, word = false, cyclic = true }),
        augend.constant.new({ elements = { "==", "!=" }, word = false, cyclic = true }),
        augend.constant.new({ elements = { "yes", "no" }, word = true, cyclic = true }),
        augend.constant.new({ elements = { "and", "or" }, word = true, cyclic = true }),
        augend.constant.new({ elements = { "True", "False" }, word = true, cyclic = true }),
      },
    })
  end,
}
