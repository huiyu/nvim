--- Keybindings
--- see https://neovim.io/doc/user/intro.html#vim-modes-intro
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- Save file
vim.keymap.set({ "i", "x", "n", "s" }, "<C-s>", "<cmd>w<cr><esc>", { desc = "Save file" })

-- Open URL under cursor or on current line with system default app
vim.keymap.set("n", "gx", function()
  -- First try <cfile> (works when cursor is directly on a URL/path)
  local cfile = vim.fn.expand("<cfile>")
  if cfile:match("^https?://") then
    vim.ui.open(cfile)
    return
  end
  -- Search the current line for a URL (find the nearest one to cursor)
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1 -- 1-indexed
  local best_url, best_dist = nil, math.huge
  for url, s, e in line:gmatch("()(https?://[%w%-%._~:/?#%[%]@!$&'()*+,;%%=]+)()") do
    ---@diagnostic disable-next-line: param-type-mismatch
    local dist = (col < url) and (url - col) or (col > e - 1) and (col - e + 1) or 0
    if dist < best_dist then
      best_url, best_dist = s, dist
    end
  end
  if best_url then
    vim.ui.open(best_url)
  else
    -- Fallback: open current file with system app
    local file = vim.fn.expand("%:p")
    if file ~= "" then
      vim.ui.open(file)
    end
  end
end, { desc = "Open URL or file with system app" })

-- Clear search highlight on Escape
vim.keymap.set({ "i", "n" }, "<Esc>", "<cmd>nohlsearch<cr><Esc>", { desc = "Escape and clear hlsearch" })

-- Better up/down on wrapped lines
vim.keymap.set({ "n", "x" }, "j", "v:count == 0 ? 'gj' : 'j'", { expr = true, desc = "Down" })
vim.keymap.set({ "n", "x" }, "k", "v:count == 0 ? 'gk' : 'k'", { expr = true, desc = "Up" })

-- Move lines
vim.keymap.set("n", "<A-j>", "<cmd>execute 'move .+' . v:count1<cr>==", { desc = "Move down" })
vim.keymap.set("n", "<A-k>", "<cmd>execute 'move .-' . (v:count1 + 1)<cr>==", { desc = "Move up" })
vim.keymap.set("i", "<A-j>", "<esc><cmd>m .+1<cr>==gi", { desc = "Move down" })
vim.keymap.set("i", "<A-k>", "<esc><cmd>m .-2<cr>==gi", { desc = "Move up" })
vim.keymap.set("v", "<A-j>", ":m '>+1<cr>gv=gv", { desc = "Move down", silent = true })
vim.keymap.set("v", "<A-k>", ":m '<-2<cr>gv=gv", { desc = "Move up", silent = true })

-- Insert mode
vim.keymap.set("i", "jk", "<ESC>", { desc = "Exit insert mode", noremap = true, silent = true })
vim.keymap.set("i", "<C-c>", "<ESC>", { desc = "Exit insert mode", noremap = true, silent = true })

-- Terminal mode
vim.keymap.set("t", "<Esc><Esc>", "<C-\\><C-n>", { desc = "Exit terminal mode", noremap = true, silent = true })
vim.keymap.set("t", "jk", "<C-\\><C-n>", { desc = "Exit terminal mode", noremap = true, silent = true })
vim.keymap.set("t", "<C-q>", function()
  vim.cmd("bdelete!")
end, { desc = "Close terminal", noremap = true, silent = true })
vim.keymap.set("n", "<leader>Tx", "<cmd>bdelete!<cr>", { desc = "Close terminal" })
vim.keymap.set("t", "<S-CR>", function()
  vim.fn.chansend(vim.b.terminal_job_id, "\x1b[13;2u")
end, { noremap = true, silent = true })

-- Visual & Select mode
vim.keymap.set("v", "<", "<gv", { desc = "Indent left", noremap = true, silent = true })
vim.keymap.set("v", ">", ">gv", { desc = "Indent right", noremap = true, silent = true })
vim.keymap.set("v", "<leader>y", "y", { desc = "Yank to register" })
vim.keymap.set("v", "<leader>Y", '"+y', { desc = "Yank to clipboard" })
-- Note: visual paste handled by yanky.nvim (provides yank history cycling)

-- Window navigation (Ctrl+hjkl)
vim.keymap.set("n", "<C-h>", "<C-w>h", { desc = "Go to left window" })
vim.keymap.set("n", "<C-j>", "<C-w>j", { desc = "Go to lower window" })
vim.keymap.set("n", "<C-k>", "<C-w>k", { desc = "Go to upper window" })
vim.keymap.set("n", "<C-l>", "<C-w>l", { desc = "Go to right window" })

-- Window resize (Ctrl+arrows)
vim.keymap.set("n", "<C-Up>", "<cmd>resize +2<cr>", { desc = "Increase window height" })
vim.keymap.set("n", "<C-Down>", "<cmd>resize -2<cr>", { desc = "Decrease window height" })
vim.keymap.set("n", "<C-Left>", "<cmd>vertical resize -2<cr>", { desc = "Decrease window width" })
vim.keymap.set("n", "<C-Right>", "<cmd>vertical resize +2<cr>", { desc = "Increase window width" })

-- Buffer navigation
vim.keymap.set("n", "[b", "<cmd>bprev<cr>", { desc = "Prev buffer" })
vim.keymap.set("n", "]b", "<cmd>bnext<cr>", { desc = "Next buffer" })

-- Diagnostic navigation
vim.keymap.set("n", "[d", function() vim.diagnostic.goto_prev() end, { desc = "Prev diagnostic" })
vim.keymap.set("n", "]d", function() vim.diagnostic.goto_next() end, { desc = "Next diagnostic" })
vim.keymap.set("n", "[e", function() vim.diagnostic.goto_prev({ severity = vim.diagnostic.severity.ERROR }) end, { desc = "Prev error" })
vim.keymap.set("n", "]e", function() vim.diagnostic.goto_next({ severity = vim.diagnostic.severity.ERROR }) end, { desc = "Next error" })
vim.keymap.set("n", "[w", function() vim.diagnostic.goto_prev({ severity = vim.diagnostic.severity.WARN }) end, { desc = "Prev warning" })
vim.keymap.set("n", "]w", function() vim.diagnostic.goto_next({ severity = vim.diagnostic.severity.WARN }) end, { desc = "Next warning" })

-- Quickfix navigation
vim.keymap.set("n", "[q", "<cmd>cprev<cr>zz", { desc = "Prev quickfix" })
vim.keymap.set("n", "]q", "<cmd>cnext<cr>zz", { desc = "Next quickfix" })

return {
  -- Which-key group labels
  { "<leader>f",     group = "Find/Files" },
  { "<leader>s",     group = "Search",          mode = { "n", "v" } },
  { "<leader>c",     group = "Code",            mode = { "n", "v" } },
  { "<leader>b",     group = "Buffer" },
  { "<leader>d",     group = "Debug",           mode = { "n", "v" } },
  { "<leader>g",     group = "Git",             mode = { "n", "v" } },
  { "<leader>t",     group = "Test",            mode = { "n", "v" } },
  { "<leader>T",     group = "Terminal" },
  { "<leader>u",     group = "Toggle/UI" },
  { "<leader>x",     group = "Diagnostics",     mode = "n" },
  { "<leader>a",     group = "AI/Claude Code",  mode = { "n", "v" } },
  { "<leader>r",     group = "Refactor",        mode = { "n", "v" } },
  { "<leader>q",     group = "Quit/Session",    mode = "n" },
  { "<leader>w",     group = "Window",          mode = "n" },
  { "<leader>sn",    group = "Noice" },
  { "<leader><tab>", group = "Tab" },
  { "gr",            group = "LSP" },
  { "<leader>cR", function() require("util.lsp").rebuild_index() end, desc = "Rebuild LSP index", mode = "n" },

  -- Top-level shortcuts
  { "<leader>l",  "<cmd>Lazy<cr>",       desc = "Lazy",  mode = "n" },
  { "<leader>?", function()
    local lines = {
      "  Trigger Key Reference",
      "  ══════════════════════════════════════════",
      "",
      "  <leader>        Main command palette",
      "  g               Goto / LSP (gd gr gI gy gD K gK gS)",
      "  s / S           Flash jump / Treesitter jump",
      "  [ / ]           Prev / Next navigation",
      "                    b:buffer  d:diag  e:error  w:warn",
      "                    h:hunk  q:qfix  t:todo  y:yank  B:move",
      "  z               Folds / Spelling (zR zM zK)",
      "  <C-w>           Window operations",
      "  r / R           Flash remote (operator mode)",
      "",
      "  ── Ctrl ─────────────────────────────────",
      "  <C-/>            Toggle terminal",
      "  <leader>T1-9     Terminal 1-9 (create/switch)",
      "  <leader>Tx       Close terminal",
      "  <C-q>            Close terminal (in term mode)",
      "  <C-s>            Save file (all modes)",
      "  <C-h/j/k/l>     Window navigation",
      "  <C-Up/Down/L/R>  Window resize",
      "  <C-a> / <C-x>   Increment / Decrement",
      "",
      "  ── Alt / Shift ──────────────────────────",
      "  <A-j> / <A-k>   Move line (n, i, v)",
      "  <S-h> / <S-l>   Prev / Next buffer",
      "",
      "  ── Yanky ────────────────────────────────",
      "  y / p / P        Yank / Put (with history)",
      "  [y / ]y          Cycle yank history",
      "",
      "  Press prefix key + wait → which-key popup",
      "  Press q or <Esc> to close",
    }
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    vim.bo[buf].bufhidden = "wipe"
    local width = 50
    local height = #lines
    vim.api.nvim_open_win(buf, true, {
      relative = "editor",
      width = width,
      height = height,
      col = math.floor((vim.o.columns - width) / 2),
      row = math.floor((vim.o.lines - height) / 2),
      style = "minimal",
      border = "rounded",
      title = " Keybinding Guide ",
      title_pos = "center",
    })
    vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, silent = true })
    vim.keymap.set("n", "<Esc>", "<cmd>close<cr>", { buffer = buf, silent = true })
  end, desc = "Keybinding guide", mode = "n" },

  -- Quick splits
  { "<leader>-",  "<cmd>split<cr>",  desc = "Split below", mode = "n" },
  { "<leader>|",  "<cmd>vsplit<cr>", desc = "Split right",  mode = "n" },

  -- Quit/Session
  { "<leader>qq", "<cmd>qall<cr>",  desc = "Quit all",       mode = "n" },
  { "<leader>qQ", "<cmd>qa!<cr>",   desc = "Force quit all", mode = "n" },

  -- Window management
  { "<leader>wd", "<cmd>WindowCloseCurrent<cr>", desc = "Delete window",       mode = "n" },
  { "<leader>wo", "<cmd>WindowCloseOthers<cr>",  desc = "Close other windows", mode = "n" },
  { "<leader>w=", function() require("util.window").equalize_respecting_fixed() end, desc = "Equalize windows", mode = "n" },
  { "<leader>wm", function()
    local win = vim.api.nvim_get_current_win()
    local is_zoomed = vim.w[win].zoomed
    if is_zoomed then
      require("util.window").equalize_respecting_fixed()
      vim.w[win].zoomed = false
    else
      vim.cmd("wincmd _ | wincmd |")
      vim.w[win].zoomed = true
    end
  end, desc = "Toggle zoom", mode = "n" },

  -- Tab management
  { "<leader><tab><tab>", "<cmd>tabnew<cr>",     desc = "New tab" },
  { "<leader><tab>d",     "<cmd>tabclose<cr>",   desc = "Close tab" },
  { "<leader><tab>]",     "<cmd>tabnext<cr>",    desc = "Next tab" },
  { "<leader><tab>[",     "<cmd>tabprev<cr>",    desc = "Prev tab" },
  { "<leader><tab>l",     "<cmd>tablast<cr>",    desc = "Last tab" },
  { "<leader><tab>f",     "<cmd>tabfirst<cr>",   desc = "First tab" },
  { "<leader><tab>o",     "<cmd>tabonly<cr>",     desc = "Close other tabs" },

  -- Toggle/UI
  { "<leader>uf", function()
    vim.g.autoformat = not vim.g.autoformat
    vim.notify("Autoformat " .. (vim.g.autoformat and "enabled" or "disabled"))
  end, desc = "Toggle autoformat (global)" },
  { "<leader>uF", function()
    vim.b.autoformat = not vim.b.autoformat
    vim.notify("Buffer autoformat " .. (vim.b.autoformat and "enabled" or "disabled"))
  end, desc = "Toggle autoformat (buffer)" },
  { "<leader>us", function() vim.opt_local.spell = not vim.opt_local.spell:get() end,             desc = "Toggle spelling" },
  { "<leader>uw", function() vim.opt_local.wrap = not vim.opt_local.wrap:get() end,               desc = "Toggle word wrap" },
  { "<leader>ul", function() vim.opt_local.number = not vim.opt_local.number:get() end,           desc = "Toggle line numbers" },
  { "<leader>uL", function() vim.opt_local.relativenumber = not vim.opt_local.relativenumber:get() end, desc = "Toggle relative numbers" },
  { "<leader>ud", function() vim.diagnostic.enable(not vim.diagnostic.is_enabled()) end,          desc = "Toggle diagnostics" },
  { "<leader>uh", function() vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled()) end, desc = "Toggle inlay hints" },
  { "<leader>uT", function()
    if vim.b.ts_highlight then
      vim.treesitter.stop()
    else
      vim.treesitter.start()
    end
  end, desc = "Toggle treesitter highlight" },
  { "<leader>uc", function()
    local level = vim.o.conceallevel == 0 and 2 or 0
    vim.opt_local.conceallevel = level
    vim.notify("Conceallevel: " .. level)
  end, desc = "Toggle conceal level" },
  { "<leader>ub", function()
    vim.o.background = vim.o.background == "dark" and "light" or "dark"
  end, desc = "Toggle dark/light background" },
}
