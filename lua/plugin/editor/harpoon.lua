return {
  "ThePrimeagen/harpoon",
  branch = "harpoon2",
  dependencies = { "nvim-lua/plenary.nvim" },
  opts = { settings = { save_on_toggle = true } },
  keys = function()
    local keys = {
      { ";H", function() require("harpoon"):list():add() end,                                    desc = "Harpoon File" },
      { ";h", function() local harpoon = require("harpoon") harpoon.ui:toggle_quick_menu(harpoon:list()) end, desc = "Harpoon Quick Menu" },
    }
    -- `;` .. i, not <leader> .. i: jumping to a pinned file is the same question
    -- the rest of the `;` prefix answers ("which file do I want to be in?"),
    -- and it frees nine single-key slots under <leader>.
    for i = 1, 9 do
      table.insert(keys, {
        ";" .. i,
        function() require("harpoon"):list():select(i) end,
        desc = "Harpoon to File " .. i,
      })
    end
    return keys
  end,
}
