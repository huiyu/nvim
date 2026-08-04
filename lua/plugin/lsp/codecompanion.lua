local ai = require("ai.config")

return {
  "olimorris/codecompanion.nvim",
  cmd = {
    "CodeCompanion",
    "CodeCompanionActions",
    "CodeCompanionChat",
    "CodeCompanionCmd",
    "CodeCompanionCodeReview",
  },
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-treesitter/nvim-treesitter",
  },
  keys = {
    { "<leader>apc", "<cmd>CodeCompanionChat<cr>",        desc = "New Companion chat" },
    { "<leader>apt", "<cmd>CodeCompanionChat Toggle<cr>", desc = "Toggle Companion chat" },
    { "<leader>apa", "<cmd>CodeCompanionActions<cr>",     desc = "Companion actions", mode = { "n", "x" } },
    { "<leader>api", ":CodeCompanion ",                   desc = "Companion inline prompt", mode = { "n", "x" } },
    { "<leader>apb", "<cmd>CodeCompanionChat Add<cr>",    desc = "Add selection to Companion", mode = "x" },
  },
  opts = {
    interactions = {
      chat = {
        adapter = ai.codecompanion.adapter,
        -- Provider selection belongs to NVIM_AI_PROVIDER for this Nvim process.
        keymaps = { change_adapter = false },
      },
      inline = {
        adapter = ai.codecompanion.adapter,
      },
      cmd = {
        adapter = ai.codecompanion.adapter,
      },
    },
    display = {
      action_palette = {
        provider = "snacks",
      },
      chat = {
        show_header_separator = false,
        start_in_insert_mode = false,
        window = {
          layout = "vertical",
          position = "right",
          full_height = true,
          width = 90,
        },
      },
    },
  },
}
