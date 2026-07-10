-- dial writes to the buffer unconditionally (nvim_buf_set_text), so a
-- mis-hit in a read-only window (dashboard/help/quickfix) raises E5108/E21.
-- Guard: no-op the expr mapping when the buffer is not modifiable.
local function dial(fn)
  return function()
    if not vim.bo.modifiable then
      return ""
    end
    return require("dial.map")[fn]()
  end
end

return {
  "monaqa/dial.nvim",
  keys = {
    { "<C-a>",  dial("inc_normal"),  expr = true, desc = "Increment" },
    { "<C-x>",  dial("dec_normal"),  expr = true, desc = "Decrement" },
    { "g<C-a>", dial("inc_gnormal"), expr = true, desc = "Increment" },
    { "g<C-x>", dial("dec_gnormal"), expr = true, desc = "Decrement" },
    { "<C-a>",  dial("inc_visual"),  mode = "v",  expr = true, desc = "Increment" },
    { "<C-x>",  dial("dec_visual"),  mode = "v",  expr = true, desc = "Decrement" },
    { "g<C-a>", dial("inc_gvisual"), mode = "v",  expr = true, desc = "Increment" },
    { "g<C-x>", dial("dec_gvisual"), mode = "v",  expr = true, desc = "Decrement" },
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
