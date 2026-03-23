return {
  "luukvbaal/statuscol.nvim",
  event = "BufReadPost",
  opts = function()
    local builtin = require("statuscol.builtin")
    return {
      relculright = true,
      segments = {
        { sign = { namespace = { "diagnostic" }, maxwidth = 1 }, click = "v:lua.ScSa" },
        { sign = { namespace = { "gitsign" }, maxwidth = 1 },    click = "v:lua.ScSa" },
        { text = { builtin.lnumfunc, " " },                      click = "v:lua.ScLa" },
        { text = { builtin.foldfunc, " " },                       click = "v:lua.ScFa" },
      },
    }
  end,
}
