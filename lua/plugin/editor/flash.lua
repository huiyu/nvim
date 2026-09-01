return {
  "folke/flash.nvim",
  event = "VeryLazy",
  -- Jump moved off `s` so the bare `s` prefix can carry window commands
  -- (lua/whichkey_spec.lua). `f`/`F` take its place -- and only in Normal and
  -- Visual.
  --
  -- Operator-pending is left alone on purpose. flash's own `modes.char` already
  -- maps f/F/t/T in { n, x, o }, and with `jump_labels = false` its o-mode path
  -- runs `jump()` and returns without entering the label loop
  -- (flash/plugins/char.lua:238-242) -- i.e. it behaves exactly like the builtin
  -- motion. So `df-`, `cf-`, `dt(` and `dF,` keep working unchanged; only a bare
  -- `f`/`F` in Normal/Visual becomes a labelled jump.
  --
  -- What this does cost: `S` used to offer treesitter selection in o-mode
  -- (`dS`). `R` below still does that (`dR`), so the capability moves rather
  -- than disappears.
  keys = {
    { "f",     mode = { "n", "x" },      function() require("flash").jump() end,              desc = "Flash", },
    { "F",     mode = { "n", "x" },      function() require("flash").treesitter() end,        desc = "Flash Treesitter", },
    { "r",     mode = "o",               function() require("flash").remote() end,            desc = "Remote Flash", },
    { "R",     mode = { "o", "x" },      function() require("flash").treesitter_search() end, desc = "Treesitter Search", },
    { "<c-s>", mode = { "c" },           function() require("flash").toggle() end,            desc = "Toggle Flash Search", },
  },

  config = function()
    require("flash").setup({
      modes = {
        char = {
          -- f and F are deliberately absent. char mode maps its keys in
          -- { n, x, o } from its own setup(), which runs after lazy installs
          -- the `keys` above and overwrites them -- so leaving f/F here would
          -- silently undo the jump bindings. Dropping them hands Normal and
          -- Visual to flash.jump/treesitter, and operator-pending straight back
          -- to the builtin motions: `df-`, `cf-`, `dF,` behave exactly as Vim
          -- ships them. t and T stay enhanced in all three modes.
          keys = { "t", "T" },
        }
      }
    })
  end
}
