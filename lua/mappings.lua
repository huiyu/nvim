--- Keybindings
--- see https://neovim.io/doc/user/intro.html#vim-modes-intro
vim.g.mapleader = " "
vim.g.maplocalleder = "\\"

-- Normal mode
vim.keymap.set('n', 'j', "v:count == 0 ? 'gj' : 'j'", { expr = true, desc = "Move cursor down" })
vim.keymap.set('n', 'k', "v:count == 0 ? 'gk' : 'k'", { expr = true, desc = "Move cursor up" })

-- Insert mode mapping
vim.keymap.set('i', 'jk', '<ESC>', { desc = "Exit insert mode", noremap = true, silent = true })
vim.keymap.set('i', '<C-c>', '<ESC>', { desc = "Exit insert mode", noremap = true, silent = true })

-- Visual & Select mode mappings
vim.keymap.set('v', '<', '<gv', { desc = "Indent left", noremap = true, silent = true })
vim.keymap.set('v', '>', '>gv', { desc = "Indent right", noremap = true, silent = true })
vim.keymap.set({ 'v', 'x' }, '<A-j>', ":m .+1<CR>==", { desc = "Move text down", noremap = true, silent = true })
vim.keymap.set({ 'v', 'x' }, '<A-k>', ":m .-2<CR>==", { desc = "Move text up", noremap = true, silent = true })
vim.keymap.set('v', 'p', '"_dP', { desc = "Paste without yanking", noremap = true, silent = true })
vim.keymap.set('x', 'J', ":m '>+1<cr>gv=gv", { desc = "move text down", noremap = true, silent = true })
vim.keymap.set('x', 'K', ":m '<-2<cr>gv=gv", { desc = "move text up", noremap = true, silent = true })


return {
  { "<leader>e",  "<cmd>ExploreCurrentDirectory<cr>",                       desc = "Explore current directory" },
  { "<leader>E",  "<cmd>ExploreWorkingDirectory<cr>",                       desc = "Explore working directory" },
  { "<leader>t",  "<cmd>NvimTreeToggle<cr>",                                desc = "File true", },
  { "<leader>h",  "<cmd>nohlsearch<cr>",                                    desc = "No hightlight" },
  { "<leader>f",  "<cmd>FindFiles<cr>",                                     desc = "File files" },
  { "<leader>F",  "<cmd>FindFiles hidden=true<cr>",                         desc = "File files(include hidden)" },
  { "<leader>r",  "<cmd>FindRecentFiles<cr>",                               desc = "Recent files" },
  { "<C-T>",      "<cmd>ToggleTerm<cr>",                                    desc = "ToggleTerm",                  mode = { "n", "i", "v" } },
  { "<leader>b",  "<cmd>FindBuffers<cr>",                                   desc = "Find buffers",                mode = "n" },
  { "[b",         "<cmd>bprev<cr>",                                         desc = "Previous buffer",             mode = "n" },
  { "]b",         "<cmd>bnext<cr>",                                         desc = "Next buffer",                 mode = "n" },

  -- Quit / Save /Session
  { "<leader>q",  group = "Quit/Session", },
  { "<leader>qw", "<cmd>w<cr>",                                             desc = "Save",                        mode = "n" },
  { "<C-s>",      "<cmd>w<cr>",                                             desc = "Save",                        mode = "n" },
  { "<C-s>",      "<cmd>w<cr>",                                             desc = "Save",                        mode = "i" },
  { "<leader>qW", "<cmd>wall<cr>",                                          desc = "Save all",                    mode = "n" },
  { "<leader>qq", "<cmd>qa<cr>",                                            desc = "Quit all",                    mode = "n" },
  { "<leader>qQ", "<cmd>wqa!<cr>",                                          desc = "Save and quit all",           mode = "n" },
  { "<leader>ql", "<cmd>SessionLoadLast<cr>",                               desc = "Load last session",           mode = "n" },
  { "<leader>q.", "<cmd>SessionLoadCurrent<cr>",                            desc = "Load current sessions",       mode = "n" },
  { "<leader>qs", "<cmd>SessionSave<cr>",                                   desc = "Save the session",            mode = "n" },


  { "<leader>s",  group = "Search",                                         desc = "Search",                      mode = "n" },
  { "<leader>ss", "<cmd>SearchBuffer<cr>",                                  desc = "Search buffer",               mode = "n" },
  { "<leader>sw", "<cmd>SearchWord<cr>",                                    desc = "Search word",                 mode = "n" },
  { "<leader>sc", "<cmd>SearchWordUnderCursor<cr>",                         desc = "Search word under cursor",    mode = "n" },
  { "<leader>sh", "<cmd>HelpTags<cr>",                                      desc = "Help tags",                   mode = "n" },
  { "<leader>sm", "<cmd>ManPages<cr>",                                      desc = "Man pages",                   mode = "n" },
  { "<leader>st", "<cmd>TodoTelescope<cr>",                                 desc = "Todos",                       mode = "n" },
  { "[t",         function() require("todo-comments").jump_prev() end,      desc = "Previous todo",               mode = "n" },
  { "]t",         function() require("todo-comments").jump_next() end,      desc = "Next todo",                   mode = "n" },

  { "<leader>w",  group = "Window",                                         mode = "n" },
  { "<leader>w+", "<C-w>+",                                                 desc = "Increase height",             mode = "n" },
  { "<leader>w-", "<C-w>-",                                                 desc = "Descrease height",            mode = "n" },
  { "<leader>w=", "<C-w>=",                                                 desc = "Increase height",             mode = "n" },
  { "<leader>w<", "<C-w><",                                                 desc = "Descrease width",             mode = "n" },
  { "<leader>w>", "<C-w>>",                                                 desc = "Increase width",              mode = "n" },
  { "<leader>w|", "<C-w>|",                                                 desc = "Max out the width",           mode = "n" },
  { "<leader>wv", "<cmd>vsplit<cr>",                                        desc = "Split window vertically",     mode = "n" },
  { "<leader>ws", "<cmd>split<cr>",                                         desc = "Split window horizontally",   mode = "n" },
  { "<leader>wc", "<cmd>WindowCloseCurrent<cr>",                            desc = "Close current window",        mode = "n" },
  { "<leader>wo", "<cmd>WindowCloseOthers<cr>",                             desc = "Close other windows",         mode = "n" },
  { "<leader>wh", "<C-w>h",                                                 desc = "Go to the up window",         mode = "n" },
  { "<leader>wj", "<C-w>j",                                                 desc = "Go to the down window",       mode = "n" },
  { "<leader>wk", "<C-w>k",                                                 desc = "Go to the up window",         mode = "n" },
  { "<leader>wl", "<C-w>l",                                                 desc = "Go to the right window",      mode = "n" },
  { "<leader>ww", "<C-w>w",                                                 desc = "Switch window",               mode = "n" },

  { "s+",         "<C-w>+",                                                 desc = "Increase height",             mode = "n" },
  { "s-",         "<C-w>-",                                                 desc = "Descrease height",            mode = "n" },
  { "s=",         "<C-w>=",                                                 desc = "Increase height",             mode = "n" },
  { "s<",         "<C-w><",                                                 desc = "Descrease width",             mode = "n" },
  { "s>",         "<C-w>>",                                                 desc = "Increase width",              mode = "n" },
  { "s|",         "<C-w>|",                                                 desc = "Max out the width",           mode = "n" },
  { "sv",         "<cmd>vsplit<cr>",                                        desc = "Split window vertically",     mode = "n" },
  { "ss",         "<cmd>split<cr>",                                         desc = "Split window horizontally",   mode = "n" },
  { "sc",         "<cmd>WindowCloseCurrent<cr>",                            desc = "Close current window",        mode = "n" },
  { "so",         "<cmd>WindowCloseOthers<cr>",                             desc = "Close other windows",         mode = "n" },
  { "sh",         "<C-w>h",                                                 desc = "Go to the up window",         mode = "n" },
  { "sj",         "<C-w>j",                                                 desc = "Go to the down window",       mode = "n" },
  { "sk",         "<C-w>k",                                                 desc = "Go to the up window",         mode = "n" },
  { "sl",         "<C-w>l",                                                 desc = "Go to the right window",      mode = "n" },
  { "sw",         "<C-w>w",                                                 desc = "Switch window",               mode = "n" },

  { ",",          group = "LSP",                                            mode = { "n", "v" } },
  { ",a",         "<cmd>LspCodeAction<cr>",                                 desc = "Code action",                 mode = { "n", "v" } },
  { ",f",         "<cmd>LspFormatCode<cr>",                                 desc = "Code format",                 mode = { "n", "v" } },
  { ",r",         "<cmd>LspRename<cr>",                                     desc = "Rename",                      mode = { "n", "v" } },
  { ",g",         "<cmd>LspDefinitions<cr>",                                desc = "Goto definition",             mode = { "n", "v" } },
  { ",t",         "<cmd>LspTypeDefinitions<cr>",                            desc = "Type definition",             mode = { "n", "v" } },
  { ",e",         "<cmd>LspReferences<cr>",                                 desc = "Show references",             mode = { "n", "v" } },
  { ",i",         "<cmd>LspImplementations<cr>",                            desc = "Show implementations",        mode = { "n", "v" } },

  { ",d",         group = "Diagnostics",                                    mode = "n" },
  { ",dd",        "<cmd>LspBufferDiagnostics<cr>",                          desc = "Buffer diagnostics",          mode = "n" },
  { ",dw",        "<cmd>LspWorkspaceDiagnostics<cr>",                       desc = "Workspace diagnostics",       mode = "n" },
  { ",dh",        "<cmd>LspHoverDiagnostic<cr>",                            desc = "Hover diagnostic",            mode = "n" },
  { "[d",         "<cmd>LspPrevDiagnostic<cr>",                             desc = "Prev diagnostic",             mode = "n" },
  { ",dk",        "<cmd>LspPrevDiagnostic<cr>",                             desc = "Prev diagnostic",             mode = "n" },
  { "]d",         "<cmd>LspNextDiagnostic<cr>",                             desc = "Next diagnostic",             mode = "n" },
  { ",dj",        "<cmd>LspNextDiagnostic<cr>",                             desc = "Next diagnostic",             mode = "n" },
  { ",q",         "<cmd>LspQuickfix<cr>",                                   desc = "Quickfix",                    mode = "n" },
  { ",h",         "<cmd>LspHoverDoc<cr>",                                   desc = "Hover Doc",                   mode = "n" },
  { ",,",         "<cmd>LspSignatureHelp<cr>",                              desc = "Signature help",              mode = "n" },

  { ",s",         group = "Lsp search",                                     mode = "n" },
  { ",ss",        "<cmd>LspBufferSymbols<cr>",                              desc = "Search buffer symbols",       mode = "n" },
  { ",sw",        "<cmd>LspWorkspaceSymbols<cr>",                           desc = "Search workspace symbols",    mode = "n" },
  { "]m",         "<cmd>TSTextobjectGotoNextStart @function.outer<cr>",     desc = "Goto next method start",      mode = "n" },
  { "[m",         "<cmd>TSTextobjectGotoPreviousStart @function.outer<cr>", desc = "Goto privous method start",   mode = "n" },
  { "[M",         "<cmd>TSTextobjectGotoPreviousEnd @function.outer<cr>",   desc = "Goto privous method end",     mode = "n" },
  { "]M",         "<cmd>TSTextobjectGotoNextEnd @function.outer<cr>",       desc = "Goto next method end",        mode = "n" },
  { "]c",         "<cmd>TSTextobjectGotoNextStart @class.outer<cr>",        desc = "Goto next class start",       mode = "n" },
  { "[c",         "<cmd>TSTextobjectGotoPreviousStart @class.outer<cr>",    desc = "Goto privous class start",    mode = "n" },
  { "]C",         "<cmd>TSTextobjectGotoNextEnd @class.outer<cr>",          desc = "Goto next class end",         mode = "n" },
  { "[C",         "<cmd>TSTextobjectGotoPreviousEnd @class.outer<cr>",      desc = "Goto privous class end",      mode = "n" },

  { "<leader>a",  group = "Avante" },

  { "<leader>c",  group = "Copilot",                                        mode = { "n", "v" } },
  { "<leader>cc", "<cmd>CopilotChat<cr>",                                   desc = "Chat",                        mode = { "n", "v" } },
  { "<leader>ce", "<cmd>CopilotChatExplain<cr>",                            desc = "Explain",                     mode = { "n", "v" } },
  { "<leader>cf", "<cmd>CopilotChatFix<cr>",                                desc = "Fix bugs",                    mode = { "n", "v" } },
  { "<leader>co", "<cmd>CopilotChatOptimize<cr>",                           desc = "Optimize code",               mode = { "n", "v" } },
  { "<leader>cd", "<cmd>CopilotChatDocs<cr>",                               desc = "Docs",                        mode = { "n", "v" } },
  { "<leader>ct", "<cmd>CopilotChatTests<cr>",                              desc = "Add Testing",                 mode = { "n", "v" } },
  { "<leader>cd", "<cmd>CopilotChatFixDiagnostic<cr>",                      desc = "Diagnostic",                  mode = { "n", "v" } },
  { "<leader>cm", "<cmd>CopilotChatCommit<cr>",                             desc = "Write Commit Message",        mode = { "n", "v" } },
  { "<leader>cM", "<cmd>CopilotChatCommit<cr>",                             desc = "Write Commit Message Staged", mode = { "n", "v" } },

  { "<leader>g",  group = "Git",                                            mode = "n" },
  { "<leader>gj", "<cmd>Gitsign next_hunk<cr>",                             desc = "Next hunk",                   mode = "n" },
  { "<leader>gk", "<cmd>Gitsign prev_hunk<cr>",                             desc = "Prev hunk",                   mode = "n" },
  { "<leader>gl", "<cmd>Gitsign blame_line<cr>",                            desc = "Blame line",                  mode = "n" },
  { "<leader>gp", "<cmd>Gitsign preview_hunk<cr>",                          desc = "Preview hunk",                mode = "n" },
  { "<leader>gr", "<cmd>Gitsign reset_hunk<cr>",                            desc = "Reset hunk",                  mode = "n" },
  { "<leader>gR", "<cmd>Gitsign reset_buffer<cr>",                          desc = "Reset buffer",                mode = "n" },
  { "<leader>gs", "<cmd>Gitsign stage_hunk<cr>",                            desc = "Stage hunk",                  mode = "n" },
  { "<leader>gu", "<cmd>Gitsign undo_stage_hunk<cr>",                       desc = "Undo stage hunk",             mode = "n" },
  { "<leader>go", "<cmd>Telescope git_status<cr>",                          desc = "Status",                      mode = "n" },
  { "<leader>gb", "<cmd>Telescope git_branches<cr>",                        desc = "Branches",                    mode = "n" },
  { "<leader>gc", "<cmd>Telescope git_commits<cr>",                         desc = "Commits",                     mode = "n" },
  { "<leader>gC", "<cmd>Telescope bcommits<cr>",                            desc = "Buffer commits",              mode = "n" },
  { "<leader>gd", "<cmd>Gitsign diffthis<cr>",                              desc = "Diff",                        mode = "n" },

  { "<leader>P",  group = "Plugin",                                         mode = "n" },
  { "<leader>Pi", "<cmd>PluginInstall<cr>",                                 desc = "Plugin install",              mode = "n" },
  { "<leader>Ps", "<cmd>PluginStatus<cr>",                                  desc = "Plugin status",               mode = "n" },
  { "<leader>PS", "<cmd>PluginSync<cr>",                                    desc = "Plugin sync",                 mode = "n" },
  { "<leader>Pu", "<cmd>PluginUpdate<cr>",                                  desc = "Plugin update",               mode = "n" },
  { "<leader>Pc", "<cmd>PluginCheck<cr>",                                   desc = "Plugin check",                mode = "n" },
  { "<leader>PU", "<cmd>PluginUpdateAll<cr>",                               desc = "Update plugins and packages", mode = "n" },
}
