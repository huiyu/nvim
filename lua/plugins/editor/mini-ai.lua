return {
  "echasnovski/mini.ai",
  event = "VeryLazy",
  dependencies = { "nvim-treesitter/nvim-treesitter-textobjects" },
  opts = function()
    local ai = require("mini.ai")
    return {
      n_lines = 500,
      -- mini.ai's "next" variants default to `an`/`in`, which shadow Nvim
      -- 0.12's builtin Visual/Operator-pending `an`/`in` (select the parent /
      -- child treesitter node). Plain `i(`/`a(` already search forward when
      -- the cursor is outside any match (`cover_or_next`), and `il`/`al` keep
      -- the "last" direction.
      mappings = { around_next = "", inside_next = "" },
      custom_textobjects = {
        o = ai.gen_spec.treesitter({
          a = { "@block.outer", "@conditional.outer", "@loop.outer" },
          i = { "@block.inner", "@conditional.inner", "@loop.inner" },
        }),
        -- `af`/`if`/`ac`/`ic` themselves are nvim-treesitter-textobjects maps
        -- (lua/plugins/ui/treesitter.lua). These two still matter: they are what
        -- `g[f`/`g]f` and `alf`/`ilc` resolve through. Without them `f` falls
        -- back to mini.ai's function *call* and `c` matches nothing.
        f = ai.gen_spec.treesitter({ a = "@function.outer", i = "@function.inner" }),
        c = ai.gen_spec.treesitter({ a = "@class.outer", i = "@class.inner" }),
        a = ai.gen_spec.treesitter({ a = "@parameter.outer", i = "@parameter.inner" }),
      },
    }
  end,
}
