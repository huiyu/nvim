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
    { "<leader>f",  function() require("telescope.builtin").find_files() end,                                                   desc = "Find file",                         mode = { "n", "v" } },
    { "<leader>b",  function() require("telescope.builtin").buffers() end,                                                      desc = "Find buffer",                       mode = { "n", "v" } },
    { "<leader>r",  function() require("telescope.builtin").oldfiles({ dir = vim.uv.cwd() }) end,                              desc = "Recent files",                      mode = { "n", "v" } },
    { "<leader>\\", function() require("telescope.builtin").live_grep() end,                                                    desc = "Search",                            mode = { "n", "v" } },
    -- Search
    { "<leader>ss", function() require("telescope.builtin").live_grep({ search_dirs = { vim.fn.expand("%:p") } }) end,          desc = "Search buffer",                     mode = { "n", "v" } },
    { "<leader>sp", "<cmd>Telescope live_grep<cr>",                                                                             desc = "Search project",                    mode = { "n", "v" } },
    { "<leader>sm", "<cmd>Telescope lsp_document_symbols<cr>",                                                                  desc = "Search buffer symbols",             mode = { "n", "v" } },
    { "<leader>sM", "<cmd>Telescope lsp_workspace_symbols<cr>",                                                                 desc = "Search workspace symbols",          mode = { "n", "v" } },
    { "<leader>st", "<cmd>Telescope treesitter<cr>",                                                                            desc = "Current buffer treesitter symbols", mode = { "n", "v" } },
    -- Code (telescope LSP pickers)
    { "<leader>cg", "<cmd>Telescope lsp_definitions<cr>",                                                                       desc = "Goto definition",                   mode = { "n", "v" } },
    { "<leader>ct", "<cmd>Telescope lsp_typedefs<cr>",                                                                          desc = "Type definition",                   mode = { "n", "v" } },
    { "<leader>ce", "<cmd>Telescope lsp_references<cr>",                                                                        desc = "Show references",                   mode = { "n", "v" } },
    { "<leader>ci", "<cmd>Telescope lsp_implementations<cr>",                                                                   desc = "Show implementations",              mode = { "n", "v" } },
    { "<leader>cd", function() require("telescope.builtin").diagnostics({ bufnr = 0 }) end,                                    desc = "Buffer diagnostics",                mode = { "n", "v" } },
    { "<leader>cD", "<cmd>Telescope diagnostics<cr>",                                                                           desc = "Workspace diagnostics",             mode = { "n", "v" } },
    { "<leader>cI", "<cmd>Telescope lsp_incoming_calls<cr>",                                                                    desc = "Incoming calls",                    mode = { "n", "v" } },
    { "<leader>co", "<cmd>Telescope lsp_outgoing_calls<cr>",                                                                    desc = "Outgoing calls",                    mode = { "n", "v" } },
    { "<leader>cq", "<cmd>Telescope quickfix<cr>",                                                                              desc = "Quickfix",                          mode = { "n", "v" } },
    -- Git (telescope git pickers)
    { "<leader>gf", "<cmd>Telescope git_files<cr>",                                                                             desc = "List files",                        mode = { "n", "v" } },
    { "<leader>go", "<cmd>Telescope git_status<cr>",                                                                            desc = "Status",                            mode = { "n", "v" } },
    { "<leader>gb", "<cmd>Telescope git_branches<cr>",                                                                          desc = "Branches",                          mode = { "n", "v" } },
    { "<leader>gc", "<cmd>Telescope git_bcommits<cr>",                                                                          desc = "Buffer commits",                    mode = { "n", "v" } },
    { "<leader>gC", "<cmd>Telescope git_commits<cr>",                                                                           desc = "Project commits",                   mode = { "n", "v" } },
    -- Help (telescope pickers)
    { "<leader>hh", "<cmd>Telescope helptags<cr>",                                                                              desc = "Help tags",                         mode = { "n", "v" } },
    { "<leader>hm", "<cmd>Telescope manpages<cr>",                                                                              desc = "Man pages",                         mode = { "n", "v" } },
    { "<leader>hk", "<cmd>Telescope keymaps<cr>",                                                                               desc = "Keymaps",                           mode = { "n", "v" } },
    { "<leader>hr", "<cmd>Telescope registers<cr>",                                                                             desc = "Registers",                         mode = { "n", "v" } },
    { "<leader>hj", "<cmd>Telescope jumplist<cr>",                                                                              desc = "Jumps",                             mode = { "n", "v" } },
    { "<leader>hx", "<cmd>Telescope commands<cr>",                                                                              desc = "Commands",                          mode = { "n", "v" } },
    { "<leader>hX", "<cmd>Telescope commands_history<cr>",                                                                      desc = "Commands history",                  mode = { "n", "v" } },
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
        prompt_prefix = " ",
        selection_caret = " ",
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
        -- Default configuration for builtin pickers goes here:
        -- picker_name = {
        --   picker_config_key = value,
        --   ...
        -- }
        -- Now the picker_config_key will be applied every time you call this
        -- builtin picker
        find_files = {
          find_command = { "rg", "--files", "--hidden", "--no-ignore", "--glob", "!**/.git/*" },
        },
        live_grep = {
          additional_args = function(_)
            return { "--hidden" }
          end,
        },
      },
      extensions = {
        -- Your extension configuration goes here:
        -- extension_name = {
        --   extension_config_key = value,
        -- }
        -- please take a look at the readme of the extension you want to configure
        fzf = {
          fuzzy = true,                   -- false will only do exact matching
          override_generic_sorter = true, -- override the generic sorter
          override_file_sorter = true,    -- override the file sorter
          case_mode = "smart_case",       -- or "ignore_case" or "respect_case"
        },
        file_browser = {
          hijack_netrw = true,
          hidden = true,
          mappings = {
            ["i"] = {
              -- Custom insert mode key mappings
            },
            ["n"] = {
              -- Custom normal mode key mappings
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
          require("telescope.themes").get_dropdown({
            -- even more opts
          }),
        },
      },
    }
  end,
}
