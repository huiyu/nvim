local whichkey = require("which-key")

whichkey.setup({
  window = {
    border = "single",
  },
})

local mapping = {
  ["a"] = { "<cmd>Alpha<cr>", "Alpha" },
  ["b"] = {
    "<cmd>lua require('telescope.builtin').buffers(require('telescope.themes').get_dropdown{previewer = false})<cr>",
    "Buffers",
  },
  ["e"] = { "<cmd>NvimTreeToggle<cr>", "Explorer" },
  ["t"] = { "<cmd>ToggleTerm direction=float<cr>", "Terminal" }, -- direction = 'vertical' | 'horizontal' | 'tab' | 'float'
  ["T"] = { "<cmd>TodoTelescope<cr>", "Todos" },
  ["w"] = { "<cmd>w!<CR>", "Save" },
  ["W"] = { "<cmd>wa!<CR>", "Save All" },
  ["q"] = { "<cmd>q!<CR>", "Quit" },
  ["Q"] = { "<cmd>wqall!<CR>", "Save All & Quit" },
  ["c"] = { "<cmd>Bdelete!<CR>", "Close Buffer" },
  ["h"] = { "<cmd>nohlsearch<CR>", "No Highlight" },
  ["f"] = { "<cmd>Telescope find_files<cr>", "Find files" },
  ["F"] = { "<cmd>Telescope live_grep<cr>", "Find Text" },
  ["r"] = { "<cmd>Telescope oldfiles<cr>", "Recent File" },
  ["p"] = { "<cmd>Telescope project<cr>", "Projects" },
  ["H"] = { "<cmd>Telescope man_pages<cr>", "Man Pages" },

  g = {
    name = "Git",
    g = { "<cmd>lua _LAZYGIT_TOGGLE()<CR>", "Lazygit" },
    j = { "<cmd>lua require 'gitsigns'.next_hunk()<cr>", "Next Hunk" },
    k = { "<cmd>lua require 'gitsigns'.prev_hunk()<cr>", "Prev Hunk" },
    l = { "<cmd>lua require 'gitsigns'.blame_line()<cr>", "Blame" },
    p = { "<cmd>lua require 'gitsigns'.preview_hunk()<cr>", "Preview Hunk" },
    r = { "<cmd>lua require 'gitsigns'.reset_hunk()<cr>", "Reset Hunk" },
    R = { "<cmd>lua require 'gitsigns'.reset_buffer()<cr>", "Reset Buffer" },
    s = { "<cmd>lua require 'gitsigns'.stage_hunk()<cr>", "Stage Hunk" },
    u = {
      "<cmd>lua require 'gitsigns'.undo_stage_hunk()<cr>",
      "Undo Stage Hunk",
    },
    o = { "<cmd>Telescope git_status<cr>", "Open changed file" },
    b = { "<cmd>Telescope git_branches<cr>", "Checkout branch" },
    c = { "<cmd>Telescope git_commits<cr>", "Checkout commit" },
    d = {
      "<cmd>Gitsigns diffthis HEAD<cr>",
      "Diff",
    },
  },

  l = {
    name = "LSP",
    ---------- Code Action ----------
    -- a = { "<cmd>lua vim.lsp.buf.code_action()<cr>", "Code Action" },
    a = { "<cmd>Lspsaga code_action<cr>", "Code Action" },
    A = { "<cmd>Lspsaga range_code_action<cr>", "Range Code Action" },
    -- Format
    f = { "<cmd>lua vim.lsp.buf.formatting()<cr>", "Format" },

    -- Rename
    -- n = { "<cmd>lua vim.lsp.buf.rename<cr>", "Rename" },
    r = { "<cmd>Lspsaga rename<cr>", "Rename" },

    ---------- Go to ----------
    -- go to definition
    -- g = { "<cmd>lua vim.lsp.buf.definition<cr>", "Goto Definition" },
    -- g = { "<cmd>Lspsaga preview_definition<cr>", "Goto Definition" },
    g = { "<cmd>Telescope lsp_definitions<cr>", "Goto Definition" },
    -- go to type definition
    G = { "<cmd>Telescope lsp_type_definitions<cr>", "Goto Type Definition" },

    -- Go to implementation
    i = { "<cmd>Telescope lsp_implementations<cr>", "Goto Implementation" },

    -- Go to references
    -- r = { "<cmd>lua vim.lsp.buf.references<cr>", "Goto References" },
    -- r = { "<cmd>Lspsaga lsp_finder<cr>", "Goto References" },
    e = { "<cmd>Telescope lsp_references<cr>", "Goto References" },

    ---------- Symbols ----------
    s = { "<cmd>Telescope lsp_document_symbols<cr>", "Document Symbols" },
    S = {
      "<cmd>Telescope lsp_dynamic_workspace_symbols<cr>",
      "Workspace Symbols",
    },

    ---------- Diagnostic ----------
    d = { "<cmd>Telescope diagnostics<cr>", "Workspace Diagnostics" },
    k = {
      "<cmd>lua vim.lsp.diagnostic.goto_prev()<cr>",
      "Prev Diagnostic",
    },
    j = {
      "<cmd>lua vim.lsp.diagnostic.goto_next()<cr>",
      "Next Diagnostic",
    },
    q = { "<cmd>lua vim.lsp.diagnostic.set_loclist()<cr>", "Quickfix" },

    -- Hover
    h = { "<cmd>Lspsaga hover_doc<cr>", "Help" },
  },
}

local opts = {
  prefix = "<leader>",
}

whichkey.register(mapping, opts)
