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
        -- Breakpoints first: while debugging they matter more than a lint hint,
        -- and `auto` keeps the column out of the gutter when none are set, so a
        -- non-debugging buffer looks exactly as it did before.
        --
        -- Matched by sign name rather than namespace: nvim-dap places classic
        -- signs in its own `dap_breakpoints` group (DapBreakpoint, DapStopped,
        -- DapLogPoint …), not through an extmark namespace, so a namespace
        -- filter never sees them.
        { sign = { name = { "Dap" }, maxwidth = 1, auto = true }, click = "v:lua.ScSa" },
        { sign = { namespace = { "diagnostic" }, maxwidth = 1 }, click = "v:lua.ScSa" },
        { sign = { namespace = { "gitsigns" }, maxwidth = 1 },   click = "v:lua.ScSa" },
        { text = { builtin.lnumfunc, " " },                      click = "v:lua.ScLa" },
        { text = { builtin.foldfunc, " " },                       click = "v:lua.ScFa" },
      },
    }
  end,
}
