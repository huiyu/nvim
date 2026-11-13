return {
  "ThePrimeagen/harpoon",
  branch = "harpoon2",
  dependencies = { "nvim-lua/plenary.nvim" },
  opts = { settings = { save_on_toggle = true } },
  keys = function()
    -- Harpoon opens its file in the current window, so the menu and the
    -- file keys run from the editor (util.buffer): from a chat or an agent
    -- panel the file took the panel's window.
    local in_editor = require("util.buffer").in_editor
    local keys = {
      { ";H", function() require("harpoon"):list():add() end,                                    desc = "Add file to Harpoon" },
      { ";h", in_editor(function() local harpoon = require("harpoon") harpoon.ui:toggle_quick_menu(harpoon:list()) end), desc = "Harpoon menu" },
    }
    -- `;` .. i, not <leader> .. i: jumping to a Harpoon file is the same question
    -- the rest of the `;` prefix answers ("which file do I want to be in?"),
    -- and it frees nine single-key slots under <leader>.
    for i = 1, 9 do
      table.insert(keys, {
        ";" .. i,
        in_editor(function() require("harpoon"):list():select(i) end),
        desc = "Harpoon file " .. i,
      })
    end
    return keys
  end,
}
