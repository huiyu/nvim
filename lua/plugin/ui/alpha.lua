return {
  "goolord/alpha-nvim",
  config = function()
    local alpha = require("alpha")
    local dashboard = require("alpha.themes.dashboard")
    local icons = require("util.nerd-font")
    dashboard.section.header.val = {

      [[ ███████╗ █████╗ ███╗   ██╗ █████╗ ██╗ ]],
      [[ ╚══███╔╝██╔══██╗████╗  ██║██╔══██╗██║ ]],
      [[   ███╔╝ ███████║██╔██╗ ██║███████║██║ ]],
      [[  ███╔╝  ██╔══██║██║╚██╗██║██╔══██║██║ ]],
      [[ ███████╗██║  ██║██║ ╚████║██║  ██║██║ ]],
      [[ ╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝╚═╝ ]],
    }
    dashboard.section.buttons.val = {
      dashboard.button("<SPC> e  ", icons.FolderOpen .. " Explore files", ":ExploreWorkingDirectory<cr>"),
      dashboard.button("<SPC> t  ", icons.FileTree .. " File tree", ":NvimTreeToggle<cr>"),
      dashboard.button("<SPC> f  ", icons.Search .. " Find files", ":FindFiles<cr>"),
      dashboard.button("<SPC> r  ", icons.Fils .. " Recent files", ":FindRecentFiles<cr>"),
      dashboard.button("<SPC> s w", icons.WordFile .. " Search word", ":SearchWord<cr>"),
      dashboard.button("<SPC> q .", icons.Session .. " Load session", ":SessionLoadCurrent<cr>"),
    }
    alpha.setup(dashboard.config)
  end,
}
