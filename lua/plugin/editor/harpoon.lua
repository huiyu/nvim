return {
  "ThePrimeagen/harpoon",
  branch = "harpoon2",
  dependencies = { "nvim-lua/plenary.nvim" },
  -- opts is a function so the quick-menu width is computed when harpoon loads,
  -- not frozen at startup (when the current window is usually the dashboard).
  opts = function()
    return {
      menu = { width = math.max(1, vim.api.nvim_win_get_width(0) - 4) },
      settings = { save_on_toggle = true },
    }
  end,
  keys = function()
    local keys = {
      { ";H", function() require("harpoon"):list():add() end,                                    desc = "Add file to Harpoon" },
      { ";h", function() local harpoon = require("harpoon") harpoon.ui:toggle_quick_menu(harpoon:list()) end, desc = "Harpoon menu" },
    }
    -- `;` .. i, not <leader> .. i: jumping to a Harpoon file is the same question
    -- the rest of the `;` prefix answers ("which file do I want to be in?"),
    -- and it frees nine single-key slots under <leader>.
    for i = 1, 9 do
      table.insert(keys, {
        ";" .. i,
        function() require("harpoon"):list():select(i) end,
        desc = "Harpoon file " .. i,
      })
    end
    return keys
  end,
}
