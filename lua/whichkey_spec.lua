-- Which-key spec data: group labels plus spec-registered keymaps, consumed by
-- plugin/editor/whichkey.lua via require("whichkey_spec").
--
-- Pure data. The imperative vim.keymap.set() bindings (and mapleader) live in
-- lua/mappings.lua, which init.lua requires for its side effects.

-- Hide noisy individual keymaps from the which-key popup. They still work,
-- just not listed (Harpoon numeric jumps are accessed via <leader>h menu;
-- <leader>? is the standalone keybinding-guide popup).
local hidden = {
  { "<leader>?", hidden = true },
  { "<leader>1", hidden = true }, { "<leader>2", hidden = true }, { "<leader>3", hidden = true },
  { "<leader>4", hidden = true }, { "<leader>5", hidden = true }, { "<leader>6", hidden = true },
  { "<leader>7", hidden = true }, { "<leader>8", hidden = true }, { "<leader>9", hidden = true },
}

local spec = {
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

  -- Alternate file (last buffer) — Doom's SPC `
  { "<leader>`",  "<C-^>",            desc = "Last buffer",  mode = "n" },

  -- Quit/Session
  { "<leader>qq", "<cmd>qall<cr>",  desc = "Quit all",       mode = "n" },
  { "<leader>qQ", "<cmd>qa!<cr>",   desc = "Force quit all", mode = "n" },

  -- Window management
  { "<leader>ww", "<C-w>p",                       desc = "Other window",        mode = "n" },
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
  { "<leader><tab>s",     "<cmd>tabs<cr>",        desc = "List all tabs" },

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

return vim.list_extend(spec, hidden)
