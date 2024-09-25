--- Keybindings
--- see https://neovim.io/doc/user/intro.html#vim-modes-intro
vim.g.mapleader = " "
vim.g.maplocalleder = "\\"

-- Normal mode
vim.keymap.set("n", "j", "v:count == 0 ? 'gj' : 'j'", { expr = true, desc = "Move cursor down" })
vim.keymap.set("n", "k", "v:count == 0 ? 'gk' : 'k'", { expr = true, desc = "Move cursor up" })

-- Insert mode mapping
vim.keymap.set("i", "jk", "<ESC>", { desc = "Exit insert mode", noremap = true, silent = true })
vim.keymap.set("i", "<C-c>", "<ESC>", { desc = "Exit insert mode", noremap = true, silent = true })

-- Visual & Select mode mappings
vim.keymap.set("v", "<", "<gv", { desc = "Indent left", noremap = true, silent = true })
vim.keymap.set("v", ">", ">gv", { desc = "Indent right", noremap = true, silent = true })
vim.keymap.set({ "v", "x" }, "<A-j>", ":m .+1<CR>==", { desc = "Move text down", noremap = true, silent = true })
vim.keymap.set({ "v", "x" }, "<A-k>", ":m .-2<CR>==", { desc = "Move text up", noremap = true, silent = true })
vim.keymap.set("v", "p", '"_dP', { desc = "Paste without yanking", noremap = true, silent = true })
vim.keymap.set("x", "J", ":m '>+1<cr>gv=gv", { desc = "move text down", noremap = true, silent = true })
vim.keymap.set("x", "K", ":m '<-2<cr>gv=gv", { desc = "move text up", noremap = true, silent = true })

return {
  { "<leader>f",  function() require("telescope.builtin").find_files() end,                               desc = "Find file",                         mode = { "n", "v" }, },
  { "<leader>b",  function() require("telescope.builtin").buffers() end,                                  desc = "Find buffer",                       mode = { "n", "v" }, },
  { "<leader>r",  function() require("telescope.builtin").oldfiles({ dir = vim.uv.cwd() }) end,           desc = "Recent files",                      mode = { "n", "v" }, },
  { "<leader>\\", function() require("telescope.builtin").live_grep() end,                                desc = "Search",                            mode = { "n", "v" }, },
  { "<leader>e",  function() Snacks.explorer() end,                                                       desc = "File tree",                         mode = { "n", "v" }, },
  { "<leader>E",  function() Snacks.explorer({ layout = { preset = "default" }, auto_close = true }) end, desc = "File explorer",                     mode = { "n", "v" }, },

  -- Search
  { "<leader>s",  group = "Search",                                                                       mode = { "n", "v" }, },
  { "<leader>ss", "<cmd>lua require'telescope.builtin'.live_grep{ search_dirs={'%:p'}}<cr>",              desc = "Search buffer",                     mode = { "n", "v" }, },
  { "<leader>sp", "<cmd>Telescope live_grep<cr>",                                                         desc = "Search project",                    mode = { "n", "v" }, },
  { "<leader>sm", "<cmd>Telescope lsp_document_symbols<cr>",                                              desc = "Search buffer symbols",             mode = { "n", "v" }, },
  { "<leader>sM", "<cmd>Telescope lsp_workspace_symbols<cr>",                                             desc = "Search workspace symbols",          mode = { "n", "v" }, },
  { "<leader>st", "<cmd>Telescope treesitter<cr>",                                                        desc = "Current buffer treesitter symbols", mode = { "n", "v" }, },

  -- AI
  { "<leader>a",  group = "AI",                                                                           mode = { "n", "v" } },
  { "<leader>ap", "<cmd>CodeCompanion<cr>",                                                               desc = "Inline",                            mode = { "n", "v" } },
  { "<leader>aa", "<cmd>CodeCompanionAction<cr>",                                                         desc = "Actions",                           mode = { "n", "v" } },
  { "<leader>ac", "<cmd>CodeCompanionChat<cr>",                                                           desc = "Chat",                              mode = { "n", "v" } },

  -- Code
  { "<leader>c",  group = "Code",                                                                         mode = { "n", "v" } },
  { "<leader>ca", function() vim.lsp.buf.code_action() end,                                               desc = "Code action",                       mode = { "n", "v" }, },
  { "<leader>cf", function() require("conform").format() end,                                             desc = "Format",                            mode = { "n", "v" }, },
  { "<leader>cr", function() vim.lsp.buf.rename() end,                                                    desc = "Rename",                            mode = { "n", "v" }, },
  { "<leader>cg", "<cmd>Telescope lsp_definitions<cr>",                                                   desc = "Goto definition",                   mode = { "n", "v" } },
  { "<leader>ct", "<cmd>Telescope lsp_typedefs<cr>",                                                      desc = "Type definition",                   mode = { "n", "v" }, },
  { "<leader>ce", "<cmd>Telescope lsp_references<cr>",                                                    desc = "Show references",                   mode = { "n", "v" }, },
  { "<leader>ci", "<cmd>Telescope lsp_implementions<cr>",                                                 desc = "Show implementations",              mode = { "n", "v" }, },
  { "<leader>cd", function() require("telescope.builtin").diagnostics({ bufnr = 0 }) end,                 desc = "Buffer diagnostics",                mode = { "n", "v" }, },
  { "<leader>cD", "<cmd>Telescope diagnostics<cr>",                                                       desc = "Workspace diagnostics",             mode = { "n", "v" }, },
  { "<leader>ci", "<cmd>Telescope lsp_incoming_calls<cr>",                                                desc = "Incoming calls",                    mode = { "n", "v" }, },
  { "<leader>co", "<cmd>Telescope lsp_outgoing_calls<cr>",                                                desc = "Outgoing calls",                    mode = { "n", "v" }, },
  { "<leader>cq", "<cmd>Telescope quickfix<cr>",                                                          desc = "Quickfix",                          mode = { "n", "v" }, },
  { "<leader>ch", function() vim.lsp.buf.hover() end,                                                     desc = "Hover doc",                         mode = { "n", "v" }, },
  { "<leader>cH", function() vim.lsp.buf.signature_help() end,                                            desc = "Signature help",                    mode = { "n", "v" }, },

  { ",a",         function() vim.lsp.buf.code_action() end,                                               desc = "Code action",                       mode = { "n", "v" }, },
  { ",f",         function() require("conform").format() end,                                             desc = "Format",                            mode = { "n", "v" }, },
  { ",r",         function() vim.lsp.buf.rename() end,                                                    desc = "Rename",                            mode = { "n", "v" }, },
  { ",g",         "<cmd>Telescope lsp_definitions<cr>",                                                   desc = "Goto definition",                   mode = { "n", "v" }, },
  { ",t",         "<cmd>Telescope lsp_typedefs<cr>",                                                      desc = "Type definition",                   mode = { "n", "v" }, },
  { ",e",         "<cmd>Telescope lsp_references<cr>",                                                    desc = "Show references",                   mode = { "n", "v" }, },
  { ",i",         "<cmd>Telescope lsp_implementions<cr>",                                                 desc = "Show implementations",              mode = { "n", "v" }, },
  { ",d",         function() require("telescope.builtin").diagnostics({ bufnr = 0 }) end,                 desc = "Buffer diagnostics",                mode = { "n", "v" }, },
  { ",D",         "<cmd>Telescope diagnostics<cr>",                                                       desc = "Workspace diagnostics",             mode = { "n", "v" }, },
  { ",i",         "<cmd>Telescope lsp_incoming_calls<cr>",                                                desc = "Incoming calls",                    mode = { "n", "v" }, },
  { ",o",         "<cmd>Telescope lsp_outgoing_calls<cr>",                                                desc = "Outgoing calls",                    mode = { "n", "v" }, },
  { ",q",         "<cmd>Telescope quickfix<cr>",                                                          desc = "Quickfix",                          mode = { "n", "v" }, },
  { ",h",         function() vim.lsp.buf.hover() end,                                                     desc = "Hover doc",                         mode = { "n", "v" }, },
  { ",H",         function() vim.lsp.buf.signature_help() end,                                            desc = "Signature help",                    mode = { "n", "v" }, },

  -- Debug
  { "<leader>d",  group = "Debug",                                                                        mode = { "n", "v" } },
  { "<leader>dB", function() require("dap").set_breakpoint(vim.fn.input("Breakpoint condition: ")) end,   desc = "Breakpoint Condition",              mode = { "n", "v" }, },
  { "<leader>db", function() require("dap").toggle_breakpoint() end,                                      desc = "Toggle Breakpoint",                 mode = { "n", "v" }, },
  { "<leader>dc", function() require("dap").continue() end,                                               desc = "Run/Continue",                      mode = { "n", "v" }, },
  { "<leader>da", function() require("dap").continue({ before = get_args }) end,                          desc = "Run with Args",                     mode = { "n", "v" }, },
  { "<leader>dC", function() require("dap").run_to_cursor() end,                                          desc = "Run to Cursor",                     mode = { "n", "v" }, },
  { "<leader>dg", function() require("dap").goto_() end,                                                  desc = "Go to Line (No Execute)",           mode = { "n", "v" }, },
  { "<leader>di", function() require("dap").step_into() end,                                              desc = "Step Into",                         mode = { "n", "v" }, },
  { "<leader>dj", function() require("dap").down() end,                                                   desc = "Down",                              mode = { "n", "v" }, },
  { "<leader>dk", function() require("dap").up() end,                                                     desc = "Up",                                mode = { "n", "v" }, },
  { "<leader>dl", function() require("dap").run_last() end,                                               desc = "Run Last",                          mode = { "n", "v" }, },
  { "<leader>do", function() require("dap").step_out() end,                                               desc = "Step Out",                          mode = { "n", "v" }, },
  { "<leader>dO", function() require("dap").step_over() end,                                              desc = "Step Over",                         mode = { "n", "v" }, },
  { "<leader>dP", function() require("dap").pause() end,                                                  desc = "Pause",                             mode = { "n", "v" }, },
  { "<leader>dr", function() require("dap").repl.toggle() end,                                            desc = "Toggle REPL",                       mode = { "n", "v" }, },
  { "<leader>ds", function() require("dap").session() end,                                                desc = "Session",                           mode = { "n", "v" }, },
  { "<leader>dt", function() require("dap").terminate() end,                                              desc = "Terminate",                         mode = { "n", "v" }, },
  { "<leader>dw", function() require("dap.ui.widgets").hover() end,                                       desc = "Widgets",                           mode = { "n", "v" }, },

  -- Git
  { "<leader>g",  group = "Git",                                                                          mode = { "n", "v" } },
  { "<leader>gj", "<cmd>Gitsign next_hunk<cr>",                                                           desc = "Next hunk",                         mode = { "n", "v" } },
  { "<leader>gk", "<cmd>Gitsign prev_hunk<cr>",                                                           desc = "Prev hunk",                         mode = { "n", "v" } },
  { "<leader>gl", "<cmd>Gitsign blame_line<cr>",                                                          desc = "Blame line",                        mode = { "n", "v" } },
  { "<leader>gL", "<cmd>Gitsign blame<cr>",                                                               desc = "Blame buffer",                      mode = { "n", "v" } },
  { "<leader>gp", "<cmd>Gitsign preview_hunk<cr>",                                                        desc = "Preview hunk",                      mode = { "n", "v" } },
  { "<leader>gr", "<cmd>Gitsign reset_hunk<cr>",                                                          desc = "Reset hunk",                        mode = { "n", "v" } },
  { "<leader>gR", "<cmd>Gitsign reset_buffer<cr>",                                                        desc = "Reset buffer",                      mode = { "n", "v" } },
  { "<leader>gs", "<cmd>Gitsign stage_hunk<cr>",                                                          desc = "Stage hunk",                        mode = { "n", "v" } },
  { "<leader>gu", "<cmd>Gitsign undo_stage_hunk<cr>",                                                     desc = "Undo stage hunk",                   mode = { "n", "v" } },
  { "<leader>gf", "<cmd>Telescope git_files<cr>",                                                         desc = "List files",                        mode = { "n", "v" } },
  { "<leader>go", "<cmd>Telescope git_status<cr>",                                                        desc = "Status",                            mode = { "n", "v" } },
  { "<leader>gb", "<cmd>Telescope git_branches<cr>",                                                      desc = "Branches",                          mode = { "n", "v" } },
  { "<leader>gc", "<cmd>Telescope git_bcommits<cr>",                                                      desc = "Buffer commits",                    mode = { "n", "v" } },
  { "<leader>gC", "<cmd>Telescope git_commits<cr>",                                                       desc = "Project commits",                   mode = { "n", "v" } },
  { "<leader>gd", "<cmd>Gitsign diffthis<cr>",                                                            desc = "Diff",                              mode = { "n", "v" } },

  { "<leader>t",  group = "Toggle/Test", },
  { "<leader>ts", "<cmd>ASToggle<cr>",                                                                    desc = "Toggle AutoSave",                   mode = { "n", "v" } },
  { "<leader>tm", function() require("neotest").run.run() end,                                            desc = "Test current method",               mode = { "n", "v" } },
  { "<leader>td", function() require("neotest").run.run({ strategy = "dap" }) end,                        desc = "Debug current method",              mode = { "n", "v" } },
  { "<leader>tf", function() require("neotest").run.run(vim.fn.expand("%")) end,                          desc = "Test current file",                 mode = { "n", "v" } },
  { "<leader>tS", function() require("neotest").summary.toggle() end,                                     desc = "Toggle test summary",               mode = { "n", "v" } },
  { "<leader>to", function() require("neotest").output.open() end,                                        desc = "Toggle test output",                mode = { "n", "v" } },
  { "<leader>td", function() require("neotest").diagnostic.show() end,                                    desc = "Show test diagnostic",              mode = { "n", "v" } },
  { "<leader>tD", function() require("neotest").diagnostic.hide() end,                                    desc = "Hide test diagnostic",              mode = { "n", "v" } },


  -- Help
  { "<leader>h",  group = "Help",                                                                         mode = { "n", "v" } },
  { "<leader>hn", "<cmd>nohlsearch<cr>",                                                                  desc = "No hightlight" },
  { "<leader>hh", "<cmd>Telescope helptags<cr>",                                                          desc = "Help tags",                         mode = { "n", "v" } },
  { "<leader>hm", "<cmd>Telescope manpages<cr>",                                                          desc = "Man pages",                         mode = { "n", "v" } },
  { "<leader>ht", "<cmd>TodoTelescope<cr>",                                                               desc = "Todos",                             mode = { "n", "v" } },
  { "<leader>hm", "<cmd>Telescope keymaps<cr>",                                                           desc = "Keymaps",                           mode = { "n", "v" } },
  { "<leader>hr", "<cmd>Telescope registers<cr>",                                                         desc = "Registers",                         mode = { "n", "v" } },
  { "<leader>hj", "<cmd>Telescope jumplist<cr>",                                                          desc = "Jumps",                             mode = { "n", "v" } },
  { "<leader>hx", "<cmd>Telescope commands<cr>",                                                          desc = "Commands",                          mode = { "n", "v" } },
  { "<leader>hX", "<cmd>Telescope commands_history<cr>",                                                  desc = "Commands history",                  mode = { "n", "v" } },

  -- Quit/Session
  { "<leader>q",  group = "Quit/Session",                                                                 mode = { "n" } },
  { "<leader>qu", "<cmd>Lazy update<cr>",                                                                 desc = "Update plugins ",                   mode = "n" },
  { "<leader>qw", "<cmd>w<cr>",                                                                           desc = "Save",                              mode = "n" },
  { "<leader>qW", "<cmd>wall<cr>",                                                                        desc = "Save all",                          mode = "n" },
  { "<leader>qq", "<cmd>qall<cr>",                                                                        desc = "Quit",                              mode = "n" },
  { "<leader>qQ", "<cmd>qa!<cr>",                                                                         desc = "Save and quit all",                 mode = "n" },
  { "<leader>ql", function() require("persistent").load({ last = true }) end,                             desc = "Load last session",                 mode = "n", },
  { "<leader>q.", function() require("persistent").load() end,                                            desc = "Load current sessions",             mode = "n", },
  { "<leader>qs", function() require("persistent").save() end,                                            desc = "Save the session",                  mode = "n", },

  -- Window
  { "<leader>w",  group = "Window",                                                                       mode = "n" },
  { "<leader>w+", "<C-w>+",                                                                               desc = "Increase height",                   mode = "n" },
  { "<leader>w-", "<C-w>-",                                                                               desc = "Descrease height",                  mode = "n" },
  { "<leader>w=", "<C-w>=",                                                                               desc = "Increase height",                   mode = "n" },
  { "<leader>w<", "<C-w><",                                                                               desc = "Descrease width",                   mode = "n" },
  { "<leader>w>", "<C-w>>",                                                                               desc = "Increase width",                    mode = "n" },
  { "<leader>w|", "<C-w>|",                                                                               desc = "Max out the width",                 mode = "n" },
  { "<leader>wv", "<cmd>vsplit<cr>",                                                                      desc = "Split window vertically",           mode = "n" },
  { "<leader>ws", "<cmd>split<cr>",                                                                       desc = "Split window horizontally",         mode = "n" },
  { "<leader>wc", "<cmd>WindowCloseCurrent<cr>",                                                          desc = "Close current window",              mode = "n" },
  { "<leader>wo", "<cmd>WindowCloseOthers<cr>",                                                           desc = "Close other windows",               mode = "n" },
  { "<leader>wh", "<C-w>h",                                                                               desc = "Go to the up window",               mode = "n" },
  { "<leader>wj", "<C-w>j",                                                                               desc = "Go to the down window",             mode = "n" },
  { "<leader>wk", "<C-w>k",                                                                               desc = "Go to the up window",               mode = "n" },
  { "<leader>wl", "<C-w>l",                                                                               desc = "Go to the right window",            mode = "n" },
  { "<leader>ww", "<C-w>w",                                                                               desc = "Switch window",                     mode = "n" },

  { "s+",         "<C-w>+",                                                                               desc = "Increase height",                   mode = "n" },
  { "s-",         "<C-w>-",                                                                               desc = "Descrease height",                  mode = "n" },
  { "s=",         "<C-w>=",                                                                               desc = "Increase height",                   mode = "n" },
  { "s<",         "<C-w><",                                                                               desc = "Descrease width",                   mode = "n" },
  { "s>",         "<C-w>>",                                                                               desc = "Increase width",                    mode = "n" },
  { "s|",         "<C-w>|",                                                                               desc = "Max out the width",                 mode = "n" },
  { "sv",         "<cmd>vsplit<cr>",                                                                      desc = "Split window vertically",           mode = "n" },
  { "ss",         "<cmd>split<cr>",                                                                       desc = "Split window horizontally",         mode = "n" },
  { "sc",         "<cmd>WindowCloseCurrent<cr>",                                                          desc = "Close current window",              mode = "n" },
  { "so",         "<cmd>WindowCloseOthers<cr>",                                                           desc = "Close other windows",               mode = "n" },
  { "sh",         "<C-w>h",                                                                               desc = "Go to the up window",               mode = "n" },
  { "sj",         "<C-w>j",                                                                               desc = "Go to the down window",             mode = "n" },
  { "sk",         "<C-w>k",                                                                               desc = "Go to the up window",               mode = "n" },
  { "sl",         "<C-w>l",                                                                               desc = "Go to the right window",            mode = "n" },
  { "sw",         "<C-w>w",                                                                               desc = "Switch window",                     mode = "n" },

  -- Jump
  { "[b",         "<cmd>bprev<cr>",                                                                       desc = "Previous buffer",                   mode = "n" },
  { "]b",         "<cmd>bnext<cr>",                                                                       desc = "Next buffer",                       mode = "n" },
  {
    "[t",
    function()
      require("todo-comments").jump_prev()
    end,
    desc = "Previous todo",
    mode = "n",
  },
  {
    "]t",
    function()
      require("todo-comments").jump_next()
    end,
    desc = "Next todo",
  },
  {
    "[d",
    function()
      vim.diagnostics.goto_prev()
    end,
    desc = "Prev diagnostic",
    mode = "n",
  },
  {
    "]d",
    function()
      vim.diagnostics.goto_next()
    end,
    desc = "Next diagnostic",
    mode = "n",
  },
  { "]m", "<cmd>TSTextobjectGotoNextStart @function.outer<cr>",     desc = "Goto next method start",    mode = "n" },
  { "[m", "<cmd>TSTextobjectGotoPreviousStart @function.outer<cr>", desc = "Goto privous method start", mode = "n" },
  { "[M", "<cmd>TSTextobjectGotoPreviousEnd @function.outer<cr>",   desc = "Goto privous method end",   mode = "n" },
  { "]M", "<cmd>TSTextobjectGotoNextEnd @function.outer<cr>",       desc = "Goto next method end",      mode = "n" },
  { "]c", "<cmd>TSTextobjectGotoNextStart @class.outer<cr>",        desc = "Goto next class start",     mode = "n" },
  { "[c", "<cmd>TSTextobjectGotoPreviousStart @class.outer<cr>",    desc = "Goto privous class start",  mode = "n" },
  { "]C", "<cmd>TSTextobjectGotoNextEnd @class.outer<cr>",          desc = "Goto next class end",       mode = "n" },
  { "[C", "<cmd>TSTextobjectGotoPreviousEnd @class.outer<cr>",      desc = "Goto privous class end",    mode = "n" },
}
