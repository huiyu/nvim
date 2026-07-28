return {
  "luukvbaal/statuscol.nvim",
  event = "BufReadPost",
  opts = function()
    local builtin = require("statuscol.builtin")
    return {
      relculright = true,
      -- statuscol's setup() force-sets 'statuscolumn' on every window that is
      -- already open, overwriting the empty one snacks' `minimal` style put on
      -- terminal/scratch windows. Since this plugin lazy-loads on BufReadPost,
      -- opening Claude before the first file read leaves its window with a
      -- 6-column blank gutter -- which also shrinks the pty from 90 to 84
      -- columns, so Claude's whole TUI re-wraps narrower and offset right.
      bt_ignore = { "terminal", "nofile", "prompt" },
      segments = {
        { sign = { namespace = { "diagnostic" }, maxwidth = 1 }, click = "v:lua.ScSa" },
        { sign = { namespace = { "gitsigns" }, maxwidth = 1 },   click = "v:lua.ScSa" },
        { text = { builtin.lnumfunc, " " },                      click = "v:lua.ScLa" },
        { text = { builtin.foldfunc, " " },                       click = "v:lua.ScFa" },
      },
    }
  end,
}
