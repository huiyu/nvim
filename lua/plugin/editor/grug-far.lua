return {
  "MagicDuck/grug-far.nvim",
  cmd = "GrugFar",
  keys = {
    { ",F", function() require("grug-far").open() end,                                          desc = "Search and replace", mode = { "n", "v" } },
    { ",w", function() require("grug-far").open({ prefills = { search = vim.fn.expand("<cword>") } }) end, desc = "Replace current word", mode = "n" },
  },
  opts = {
    -- Its default <localleader>r/f/j/k/l/... would shadow general editing
    -- now that localleader is comma. Keep the editable results buffer's
    -- actions together under ,S; the plugin also uses these in its help.
    keymaps = {
      replace = { n = "<localleader>Sr" },
      qflist = { n = "<localleader>Sq" },
      syncLocations = { n = "<localleader>Ss" },
      syncLine = { n = "<localleader>Sl" },
      close = { n = "<localleader>Sc" },
      historyOpen = { n = "<localleader>St" },
      historyAdd = { n = "<localleader>Sa" },
      refresh = { n = "<localleader>Sf" },
      openLocation = { n = "<localleader>So" },
      abort = { n = "<localleader>Sb" },
      toggleShowCommand = { n = "<localleader>Sw" },
      swapEngine = { n = "<localleader>Se" },
      previewLocation = { n = "<localleader>Si" },
      swapReplacementInterpreter = { n = "<localleader>Sx" },
      applyNext = { n = "<localleader>Sj" },
      applyPrev = { n = "<localleader>Sk" },
      syncNext = { n = "<localleader>Sn" },
      syncPrev = { n = "<localleader>Sp" },
      syncFile = { n = "<localleader>Sv" },
    },
  },
}
