-- Actual editor actions, independent from which-key's renderer.
local M = {}
function M.setup(display, keys)
  local spec = vim.deepcopy(display.spec or {})
  local function open_key(action)
    local choice = keys and keys.open and keys.open[action]
    return choice and choice.key or "disabled"
  end
  local bindings = {
{ "<leader>ml", "<cmd>Lazy<cr>",       desc = "Lazy",  mode = "n" },
{ "<leader>?", function()
    local lines = {
      "  Trigger Key Reference",
      "  ══════════════════════════════════════════",
      "",
      "  ── Which prefix? (intent → key) ─────────",
      "  go somewhere               ;",
      "  act on this file / view    ,",
      "  arrange windows            s",
      "  run command / manage       <leader>",
      "  next / prev thing          ] / [",
      "  jump from this symbol      g",
      "  instant action             Ctrl",
      "  cycle buffers              Shift (H/L)",
      "  move / indent lines        , (j/k/h/l)",
      "  fly to visible spot        f (flash, no leader)",
      "",
      "  ── ; — go to a file ─────────────────────",
      "  ;<space>         Smart find (buffers/recent/files)",
      "  ;;               Resume last picker",
      "  ;f / ;F          Find file (cwd / from here)",
      "  ;r / ;b / ;g     Recent / Buffers / Git files",
      "  ;B               Pick buffer by its tab letter",
      "  ;p               Switch project",
      "  ;i / ;?          Find / search respecting gitignore",
      "  ;o / -           File manager / parent dir (oil)",
      "  ;h / ;H          Harpoon menu / add file",
      "  ;1 .. ;9         Harpoon file 1-9",
      "  ;/ / ;w          Search in cwd / word under cursor",
      "  ;s / ;S          Symbol in file / workspace",
      "  ;l / ;D          Lines in file / search from here",
      "  ;j / ;m / ;c     Jumps / Marks / Git hunks",
      "  ;a               Last used buffer (alternate)",
      "  ;t / ;T          Todos / Todo+Fixme",
      "",
      "  <leader>ya / yr  Yank file path (absolute / repo-relative)",
      "  <leader>yl / yg  Yank path:line / Git permalink",
      "  <leader>yy / yc  Yank selection (register / clipboard)",
      "  <leader>yh / y\"  Yank history / Registers",
      "",
      "  ── g — jump from symbol under cursor ────",
      "  gd / gr          Definition / References",
      "  gb / gy          Implementation / Type definition",
      "  gD / gC          Declaration / Incoming calls",
      "  gs               Source definition (JS/TS)",
      "  K / gK           Hover / Signature help",
      -- markdown, help, checkhealth and man map their own gO: the outline.
      "  gO               Document symbols / doc outline",
      "",
      "  ── , — current file / view actions ──────",
      "  ,a / ,f / ,r     Code action / Format / Rename",
      "  ,c               Run codelens",
      "  ,j ,k / ,h ,l    Move line / Dedent, Indent",
      "  ,n / ,x          Annotations / Run file",
      "  ,i / ,R          Inline var / Select refactor",
      "  ,e{f,F,x}        Extract fn / to file / variable",
      "  ,w / ,F          Replace word / Search & replace",
      "  ,O               Toggle code outline",
      "  Context sections (only in matching buffers):",
      "  Go: ,o imports / ,G rebuild index",
      "  Python: ,o imports / ,v virtualenv",
      "  C/C++: ,H source/header",
      "  Markdown: ,p preview / ,m render",
      "  Chat: ,s save / ,X clear / ,q close",
      "        ,z fold code / ,m render",
      "  Search panel: ,S* actions / g? help",
      "  Dart/Flutter: ,dr reload / ,dR restart",
      "  LaTeX: ,b build / ,s stop / ,K clean",
      "         ,E errors / ,v PDF / ,t TOC",
      "         ,L* full VimTeX commands",
      -- CodeDiff's own descriptions name these (its keymaps take an lhs
      -- only), so the guide uses its words: explorer, diff layout, and
      -- current/incoming for the ours/theirs sides.
      "  CodeDiff: ,P / ,B focus / toggle explorer",
      "            ,z compact / ,I diff layout (inline)",
      "            ,g{o,t,b,a} accept current (ours) /",
      "              incoming (theirs) / base / both",
      "            ,g{O,T,B,A} the same, whole file",
      "  Review: ,C feedback / ,S ,U stage, unstage hunk",
      "          ,X discard hunk back to baseline",
      "  View and language sections can coexist.",
      "  [LSP] actions need a language server.",
      "  , is also <localleader>.",
      "",
      "  ── <leader> groups ──────────────────────",
      -- filled in below from the spec itself
      "",
      "  ── Full reference ───────────────────────",
      "  <leader>        Main command palette",
      "  g               Go to / case / misc (see g section above)",
      "  f / F           Flash jump / Treesitter jump",
      "  x               Delete char, no yank (swap: dlp)",
      "  [ / ]           Prev / Next navigation",
      "                    diag: d e w    git: h x",
      "                    lists: q l t   files: b a o",
      "                    code: r m c i (ref/function/class/indent)",
      "                    history: j u y (jump/undo/yank)",
      "  z               Folds / spelling (zR zM zK)",
      "  s               Window operations (see s section)",
      "  r / R           Flash remote (operator mode)",
      "",
      "  ── Terminals ────────────────────────────",
      "  <C-/>            Toggle terminal (current one)",
      "  3<C-/>           Open terminal 3 (from file)",
      "  ,1 .. ,9         Switch terminal (terminal buffers only;",
      "                   from terminal input: jk first)",
      "  <leader>md       Fix terminal TUI drift",
      "",
      "  ── <leader>m — the editor itself ────────",
      "  mf / mF          Nvim config / Plugin source",
      "  mh / mM / mk     Help / Man / Keymaps",
      "  mC / mc          Commands / Command history",
      "  ml / mm          Lazy / Mason",
      "  mi / mr          LSP info / Restart servers",
      "  mn*              Messages/notifications",
      "",
      "  ── <leader>s — sessions ─────────────────",
      -- Spelled out: bare `ss` is the window split two sections below.
      "  <leader>ss       Save session",
      "  <leader>sl / s.  Load last / load cwd",
      "",
      "  ── s — windows (bare key, no leader) ────",
      "  ss / sv          Split below / right",
      "  sw / se          Previous window / editor window",
      "  sd / so          Close this / close others",
      "  s= / sm          Equalize / toggle zoom",
      "  sz               Toggle zen mode (file window)",
      "",
      "  ── Ctrl ─────────────────────────────────",
      "  <C-h/j/k/l>      Window navigation",
      "  <C-Up/Down/L/R>  Window resize",
      "  <C-,>            Editor window, toggle back (se)",
      "  <C-a> / <C-x>    Increment / Decrement",
      "  <C-]> / <C-\\>    Repeatable Escape (Insert / terminal)",
      "  <C-S-l>          Redraw TUI (terminal mode)",
      "",
      "  ── Alt / Shift ──────────────────────────",
      "  (tmux takes M-1..9, M-n, M-h/j/k/l: #12)",
      "  <S-h> / <S-l>    Prev / Next buffer",
      "",
      "  ── In a list view / panel ───────────────",
      "  q / g?           Close / list its keys",
      "  " .. open_key("split") .. " / " .. open_key("vsplit") .. " / " .. open_key("tab") .. "  Open below / beside / tab",
      "  " .. open_key("preview") .. " / <M-.>    Preview / hidden files",
      "  dd / <C-x>       Delete item (list / typing)",
      "  R                Refresh (gR in oil)",
      "  <C-c> / <C-d>    Stop AI request / deliver draft",
      "",
      "  ── Yanky ────────────────────────────────",
      "  y / p / P        Yank / Put (with history)",
      "  [y / ]y          Cycle yank history",
      "",
      "  Press prefix key + wait → which-key popup",
      "  Press q or <Esc> to close",
    }
    -- Derive the group list from this spec rather than restating it. Hand-written
    -- copies of it drifted every time a group moved; reading the table means the
    -- popup cannot disagree with what which-key actually registers.
    local groups = {}
    for _, entry in ipairs(spec) do
      local lhs = type(entry[1]) == "string" and entry[1] or nil
      local suffix = lhs and lhs:match("^<leader>(.+)$")
      if entry.group and suffix then
        groups[#groups + 1] = { suffix, entry.group }
      end
    end
    table.sort(groups, function(a, b) return a[1]:lower() < b[1]:lower() end)
    for i = 1, #groups, 2 do
      local a, b = groups[i], groups[i + 1]
      local cell = ("%-8s %-16s"):format(a[1], a[2])
      if b then cell = cell .. ("%-8s %s"):format(b[1], b[2]) end
      -- insert just before the "Full reference" divider
      for idx, line in ipairs(lines) do
        if line:find("Full reference", 1, true) then
          table.insert(lines, idx - 1, "  " .. cell:gsub("%s+$", ""))
          break
        end
      end
    end

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    vim.bo[buf].bufhidden = "wipe"
    -- As wide as the longest row: a fixed 50 wrapped the longer ones (the
    -- derived group table's "mn Messages/notifications", the yank rows) and
    -- broke the columns. Narrow screens still cap it.
    local width = 50
    for _, line in ipairs(lines) do width = math.max(width, vim.fn.strdisplaywidth(line) + 1) end
    width = math.max(1, math.min(width, vim.o.columns - 4))
    local height = math.max(1, math.min(#lines, vim.o.lines - 4))
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
    vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, silent = true, desc = "Close keybinding guide" })
    vim.keymap.set("n", "<Esc>", "<cmd>close<cr>", { buffer = buf, silent = true, desc = "Close keybinding guide" })
  end, desc = "Keybinding guide", mode = "n" },
{ ";a",  "<C-^>",  desc = "Last used buffer (alternate)",  mode = "n" },
{ "<leader>qq", function() require("editor_core.quit").all() end,     desc = "Quit all",       mode = "n" },
{ "<leader>qQ", function() require("editor_core.quit").all(true) end, desc = "Force quit all", mode = "n" },
{ "ss", "<cmd>split<cr>",               desc = "Split below",         mode = "n" },
{ "sv", "<cmd>vsplit<cr>",              desc = "Split right",         mode = "n" },
{ "sw", "<C-w>p",                       desc = "Previous window",     mode = "n" },
{ "se", "<cmd>WindowFocusEditor<cr>",  desc = "Editor window (toggle back)", mode = "n" },
{ "sd", "<cmd>WindowCloseCurrent<cr>", desc = "Close window",        mode = "n" },
{ "so", "<cmd>WindowCloseOthers<cr>",  desc = "Close other windows", mode = "n" },
{ "s=", function() require("editor_core.window").equalize_respecting_fixed() end, desc = "Equalize windows", mode = "n" },
{ "sm", function() require("editor_core.window").toggle_zoom() end, desc = "Toggle zoom", mode = "n" },
{ "<leader><tab>n",     "<cmd>tabnew<cr>",     desc = "New tab" },
{ "<leader><tab><tab>", "<cmd>tabnew<cr>",     desc = "New tab", hidden = true },
{ "<leader><tab>d",     "<cmd>tabclose<cr>",   desc = "Close tab" },
{ "<leader><tab>]",     "<cmd>tabnext<cr>",    desc = "Next tab" },
{ "<leader><tab>[",     "<cmd>tabprev<cr>",    desc = "Prev tab" },
{ "<leader><tab>l",     "<cmd>tablast<cr>",    desc = "Last tab" },
{ "<leader><tab>f",     "<cmd>tabfirst<cr>",   desc = "First tab" },
{ "<leader><tab>a",     "g<Tab>",              desc = "Last used tab (alternate)" },
{ "<leader><tab>o",     "<cmd>tabonly<cr>",     desc = "Close other tabs" },
{ "<leader><tab>s",     "<cmd>tabs<cr>",        desc = "List all tabs" },
{ "<leader>uf", function()
    local enabled = vim.b.autoformat ~= false
    vim.b.autoformat = not enabled
    vim.notify("File autoformat " .. (vim.b.autoformat and "enabled" or "disabled"))
  end, desc = "Toggle autoformat (file)" },
{ "<leader>uF", function()
    vim.g.autoformat = not vim.g.autoformat
    vim.notify("Autoformat " .. (vim.g.autoformat and "enabled" or "disabled"))
  end, desc = "Toggle autoformat (global)" },
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
  end, desc = "Toggle Treesitter highlight" },
{ "<leader>uc", function()
    local level = vim.o.conceallevel == 0 and 2 or 0
    vim.opt_local.conceallevel = level
    vim.notify("Conceallevel: " .. level)
  end, desc = "Toggle conceal level" },
{ "<leader>ub", function()
    vim.o.background = vim.o.background == "dark" and "light" or "dark"
  end, desc = "Toggle dark/light background" }  }
  vim.list_extend(spec, bindings)
  for _, entry in ipairs(bindings) do
    local opts = { desc = entry.desc, silent = entry.silent ~= false, expr = entry.expr, remap = entry.remap }
    vim.keymap.set(entry.mode or "n", entry[1], entry[2], opts)
  end
end
return M
