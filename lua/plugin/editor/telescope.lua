return {
  "nvim-telescope/telescope.nvim",
  cmd = "Telescope",
  dependencies = {
    { "nvim-lua/plenary.nvim" },
    { "nvim-telescope/telescope-file-browser.nvim" },
    { "nvim-telescope/telescope-fzf-native.nvim",  build = "make" },
    { "nvim-telescope/telescope-ui-select.nvim" },
  },

  keys = {
    -- Top-level shortcuts
    { "<leader><space>", function() require("telescope.builtin").find_files() end,  desc = "Find files" },
    { "<leader>/",       function() require("telescope.builtin").live_grep() end,   desc = "Grep" },
    { "<leader>,",       function() require("telescope.builtin").buffers() end,     desc = "Buffers" },
    { "<leader>:",       function() require("telescope.builtin").command_history() end, desc = "Command history" },

    -- Find/Files
    { "<leader>ff", function() require("telescope.builtin").find_files() end,                                     desc = "Find files" },
    { "<leader>fb", function() require("telescope.builtin").buffers() end,                                        desc = "Buffers" },
    { "<leader>fr", function() require("telescope.builtin").oldfiles({ cwd_only = true }) end,                    desc = "Recent files" },
    { "<leader>fg", "<cmd>Telescope git_files<cr>",                                                               desc = "Git files" },
    { "<leader>fc", function() require("telescope.builtin").find_files({ cwd = vim.fn.stdpath("config") }) end,   desc = "Config files" },
    { "<leader>fn", "<cmd>enew<cr>",                                                                              desc = "New file" },
    { "<leader>ft", function() Snacks.terminal() end,                                                             desc = "Terminal (root)" },
    { "<leader>fT", function() Snacks.terminal(nil, { cwd = vim.uv.cwd() }) end,                                 desc = "Terminal (cwd)" },
    { "<leader>fp", function() Snacks.dashboard.pick("projects") end,                                             desc = "Projects" },

    -- Search
    { "<leader>sg", "<cmd>Telescope live_grep<cr>",                                                               desc = "Grep (root)" },
    { "<leader>sG", function() require("telescope.builtin").live_grep({ cwd = vim.uv.cwd() }) end,               desc = "Grep (cwd)" },
    { "<leader>sB", function() require("telescope.builtin").live_grep({ grep_open_files = true }) end,            desc = "Grep open buffers" },
    { "<leader>sw", function() require("telescope.builtin").grep_string() end,                                    desc = "Word under cursor",     mode = { "n", "v" } },
    { "<leader>sb", function() require("telescope.builtin").current_buffer_fuzzy_find() end,                      desc = "Buffer lines" },
    { "<leader>sm", "<cmd>Telescope marks<cr>",                                                                   desc = "Marks" },
    { "<leader>sR", "<cmd>Telescope resume<cr>",                                                                  desc = "Resume" },
    { "<leader>sh", "<cmd>Telescope help_tags<cr>",                                                               desc = "Help pages" },
    { "<leader>sk", "<cmd>Telescope keymaps<cr>",                                                                 desc = "Keymaps" },
    { "<leader>sM", "<cmd>Telescope man_pages<cr>",                                                               desc = "Man pages" },
    { "<leader>s\"", "<cmd>Telescope registers<cr>",                                                              desc = "Registers" },
    { "<leader>sj", "<cmd>Telescope jumplist<cr>",                                                                desc = "Jumps" },
    { "<leader>sc", "<cmd>Telescope command_history<cr>",                                                         desc = "Command history" },
    { "<leader>sC", "<cmd>Telescope commands<cr>",                                                                desc = "Commands" },
    { "<leader>sd", function() require("telescope.builtin").diagnostics({ bufnr = 0 }) end,                      desc = "Buffer diagnostics" },
    { "<leader>sD", "<cmd>Telescope diagnostics<cr>",                                                             desc = "Workspace diagnostics" },
    { "<leader>ss", "<cmd>Telescope lsp_document_symbols<cr>",                                                    desc = "Symbols (buffer)" },
    { "<leader>sS", "<cmd>Telescope lsp_workspace_symbols<cr>",                                                   desc = "Symbols (workspace)" },

    -- Git (telescope git pickers)
    { "<leader>gs", "<cmd>Telescope git_status<cr>",   desc = "Status" },
    { "<leader>gb", "<cmd>Telescope git_branches<cr>", desc = "Branches" },
    { "<leader>gc", "<cmd>Telescope git_bcommits<cr>", desc = "Buffer commits" },
    { "<leader>gC", "<cmd>Telescope git_commits<cr>",  desc = "Project commits" },
  },

  opts = function()
    local telescope = require("telescope")
    local actions = require("telescope.actions")
    local fb_actions = require("telescope._extensions.file_browser.actions")

    telescope.load_extension("fzf")
    telescope.load_extension("file_browser")
    telescope.load_extension("ui-select")

    return {
      defaults = {
        prompt_prefix = " ",
        selection_caret = " ",
        entry_prefix = " ",
        cwd_only = true,
        path_display = { "truncate" },
        layout_strategy = "vertical",
        layout_config = {
          vertical = {
            width = 120
          },
        },
        file_ignore_patterns = {
          "./node_modules/*",
          "node_modules",
          "^node_modules/*",
          "node_modules/*",
          "./.git/*",
        },

        mappings = {
          i = {
            ["<C-n>"] = actions.cycle_history_next,
            ["<C-p>"] = actions.cycle_history_prev,
            ["<C-j>"] = actions.move_selection_next,
            ["<C-k>"] = actions.move_selection_previous,
            ["<C-c>"] = actions.close,
            ["<Down>"] = actions.move_selection_next,
            ["<Up>"] = actions.move_selection_previous,
            ["<CR>"] = actions.select_default,
            ["<C-s>"] = actions.select_horizontal,
            ["<C-v>"] = actions.select_vertical,
            ["<C-t>"] = actions.select_tab,
            ["<C-u>"] = actions.preview_scrolling_up,
            ["<C-d>"] = actions.preview_scrolling_down,
            ["<PageUp>"] = actions.results_scrolling_up,
            ["<PageDown>"] = actions.results_scrolling_down,
            ["<C-q>"] = actions.send_to_qflist + actions.open_qflist,
            ["<M-q>"] = actions.send_selected_to_qflist + actions.open_qflist,
            ["<C-l>"] = actions.complete_tag,
            ["<C-_>"] = actions.which_key, -- keys from pressing <C-/>
          },

          n = {
            ["<esc>"] = actions.close,
            ["<C-c>"] = actions.close,
            ["<CR>"] = actions.select_default,
            ["<C-s>"] = actions.select_horizontal,
            ["<C-v>"] = actions.select_vertical,
            ["<C-t>"] = actions.select_tab,
            ["<C-q>"] = actions.send_to_qflist + actions.open_qflist,
            ["<M-q>"] = actions.send_selected_to_qflist + actions.open_qflist,

            ["-"] = actions.select_horizontal,
            ["\\"] = actions.select_vertical,

            ["j"] = actions.move_selection_next,
            ["k"] = actions.move_selection_previous,
            ["H"] = actions.move_to_top,
            ["M"] = actions.move_to_middle,
            ["L"] = actions.move_to_bottom,

            ["<Down>"] = actions.move_selection_next,
            ["<Up>"] = actions.move_selection_previous,
            ["gg"] = actions.move_to_top,
            ["G"] = actions.move_to_bottom,
            ["<C-u>"] = actions.preview_scrolling_up,
            ["<C-d>"] = actions.preview_scrolling_down,
            ["<PageUp>"] = actions.results_scrolling_up,
            ["<PageDown>"] = actions.results_scrolling_down,
            ["?"] = actions.which_key,
          },
        },
      },
      pickers = {
        find_files = {
          find_command = { "rg", "--files", "--hidden", "--no-ignore", "--glob", "!**/.git/*" },
        },
        live_grep = {
          additional_args = function(_)
            return { "--hidden" }
          end,
        },
        lsp_document_symbols = {
          symbol_width = 50,
          symbol_type_width = 12,
        },
      },
      extensions = {
        fzf = {
          fuzzy = true,
          override_generic_sorter = true,
          override_file_sorter = true,
          case_mode = "smart_case",
        },
        file_browser = {
          hijack_netrw = true,
          hidden = true,
          mappings = {
            ["i"] = {},
            ["n"] = {
              ["c"] = fb_actions.create,
              ["r"] = fb_actions.rename,
              ["m"] = fb_actions.move,
              ["y"] = fb_actions.copy,
              ["d"] = fb_actions.remove,
              ["u"] = fb_actions.goto_parent_dir,
              ["U"] = fb_actions.goto_cwd,
              ["/"] = function()
                vim.cmd("startinsert")
              end,
            },
          },
        },
        ["ui-select"] = {
          require("telescope.themes").get_dropdown({}),
        },
      },
    }
  end,
}
