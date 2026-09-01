-- Which-key spec data: group labels plus spec-registered keymaps, consumed by
-- plugin/editor/whichkey.lua via require("whichkey_spec").
--
-- Pure data. The imperative vim.keymap.set() bindings (and mapleader) live in
-- lua/mappings.lua, which init.lua requires for its side effects.

-- Hide noisy individual keymaps from the which-key popup. They still work,
-- just not listed (Harpoon numeric jumps are reviewed through the ;h menu;
-- <leader>? is the standalone keybinding-guide popup).
local hidden = {
  { "<leader>?", hidden = true },
  { "<leader>gB", hidden = true }, -- legacy alias; GitHub file browse is <leader>Gf
  { ";1", hidden = true }, { ";2", hidden = true }, { ";3", hidden = true },
  { ";4", hidden = true }, { ";5", hidden = true }, { ";6", hidden = true },
  { ";7", hidden = true }, { ";8", hidden = true }, { ";9", hidden = true },
}

local spec = {
  -- Which-key group labels
  -- Everything about the editor rather than the code in it: look something up
  -- (help, man, keymaps, commands, Noice history) or administer it (Lazy,
  -- Mason, LSP status/restart). Splitting those across a Reference group and a
  -- Manage group meant guessing which half a key was in; both answer "the
  -- editor, not my project". `m` came free when line-moving went to `,`.
  { "<leader>m",     group = "Manage",          mode = { "n", "v" } },
  -- `,` is the twin of `;`: where `;` answers "which file do I want to be in?",
  -- `,` answers "what do I do to the code in front of me?" -- LSP actions,
  -- format, refactor, replace, move lines. Both are two keys because both are
  -- high-frequency; <leader> keeps the rest.
  --
  -- ,a and ,r exist only where an LSP is attached (lua/plugin/lsp/lsp.lua sets
  -- them on LspAttach); the rest are global.
  { ",",             group = "Code",            mode = { "n", "x" } },
  { ",e",            group = "Extract",         mode = { "n", "x" } },
  -- Just sessions now; the tooling half moved to <leader>m.
  { "<leader>s",     group = "Session",         mode = "n" },
  { "<leader>G",     group = "GitHub",          mode = { "n", "v" } },
  { "<leader>b",     group = "Buffer" },
  { "<leader>d",     group = "Debug",           mode = { "n", "v" } },
  { "<leader>g",     group = "Git",             mode = { "n", "v" } },
  { "<leader>t",     group = "Test",            mode = { "n", "v" } },
  { "<leader>u",     group = "Toggle/UI" },
  { "<leader>x",     group = "Diagnostics",     mode = "n" },
  { "<leader>a",     group = "AI",              mode = { "n", "v" } },
  { "<leader>ap",    group = "CodeCompanion",   mode = { "n", "v" } },
  { "<leader>q",     group = "Quit",            mode = "n" },
  { "s",             group = "Window",          mode = "n" },
  -- Yank/paste in one place. <leader>y and <leader>Y used to mean two unrelated
  -- things depending on mode -- a file path in Normal, the selection in Visual
  -- -- which read as one key with two meanings rather than a group.
  { "<leader>y",     group = "Yank",            mode = { "n", "v" } },
  { "<leader>mn",    group = "Noice" },
  { "<leader><tab>", group = "Tab" },
  { "gr",            group = "LSP" },
  -- Prefixes that exist outside <leader>. Without a label which-key renders
  -- them as a bare "+11 keymaps", which says how many but not what -- and these
  -- show up in operator-pending too (the popup after `d`, `c`, `y`), where an
  -- unnamed count is least useful.
  { "[",             group = "Prev",            mode = { "n", "x", "o" } },
  { "]",             group = "Next",            mode = { "n", "x", "o" } },
  -- One wording for every [ / ] pair. The keys come from four places -- Nvim's
  -- 0.11 defaults (":lprevious", ":cpfile"), mini.bracketed ("Undo backward"),
  -- treesitter-textobjects ("@function.outer") and our own ("Prev hunk") --
  -- and each names things its own way. These are desc-only entries: which-key
  -- shows them instead of the mapping's desc, and the mappings are untouched.
  -- See BRACKET_DESCS below.
  { "g",             group = "Goto",            mode = { "n", "x", "o" } },
  { "z",             group = "Fold/Spell",      mode = { "n", "x" } },
  -- <localleader> is per-filetype only: VimTeX compile/view, diffview's panel
  -- and conflict actions, gopls/venv/source-header. Nothing global lives here,
  -- so the same letter can mean different things in a .tex and a .go buffer.
  { "<localleader>", group = "This filetype",   mode = "n" },

  -- The marks plugin labels all four jump-to-mark prefixes identically as
  -- "marks". Disambiguate line-vs-exact and the jumplist-preserving g-variants.
  -- node.plugin stays "marks", so the dynamic mark list still expands.
  { "'",  desc = "marks: line" },
  { "`",  desc = "marks: exact pos" },
  { "g'", desc = "marks: line (keep jumplist)" },
  { "g`", desc = "marks: exact pos (keep jumplist)" },

  -- Top-level shortcuts
  { "<leader>ml", "<cmd>Lazy<cr>",       desc = "Lazy",  mode = "n" },
  { "<leader>?", function()
    local lines = {
      "  Trigger Key Reference",
      "  ══════════════════════════════════════════",
      "",
      "  ── Which prefix? (intent → key) ─────────",
      "  go somewhere               ;",
      "  act on this code           ,",
      "  run a command / manage     <leader>",
      "  next / prev thing          ] / [",
      "  goto this symbol           g",
      "  instant action             Ctrl",
      "  cycle buffers              Shift (H/L)",
      "  move / indent a line       , (j/k/h/l)",
      "  fly to visible spot        f (flash, no leader)",
      "",
      "  ── ; — go to a file ─────────────────────",
      "  ;<space>         Smart find (buffers/recent/files)",
      "  ;;               Resume last picker",
      "  ;f / ;F          Find file (cwd / buffer dir)",
      "  ;r / ;b / ;g     Recent / Buffers / Git files",
      "  ;n / ;p          Nvim config / Switch project",
      "  ;c               LSP incoming calls (who calls this)",
      "  ;e / ;E / ;d     Tree / Explorer+ignored / Browse dir",
      "  ;o               Oil (edit dir as a buffer)",
      "  ;h / ;H          Harpoon menu / add file",
      "  ;1 .. ;9         Jump to pinned file 1-9",
      "  ;/ / ;w          Grep project / word under cursor",
      "  ;s / ;S          Symbol in buffer / workspace",
      "  ;l / ;D          Lines here / grep current dir",
      "  ;j / ;m          Jumps / Marks",
      "  ;a               Alternate file (toggle back+forth)",
      "  ;t / ;T          Todos / Todo+Fixme",
      "",
      "  <leader>ya / yr  Yank file path (absolute / project)",
      "  <leader>yy / yc  Yank selection (register / clipboard)",
      "  <leader>yh / y\"  Yank history / Registers",
      "",
      "  ── , — act on this code ─────────────────",
      "  ,a / ,f / ,r     Code action / Format / Rename",
      "  ,j ,k / ,h ,l    Move line / Dedent, Indent",
      "  ,n / ,x          Annotations / Run this file",
      "  ,i / ,R          Inline var / Select refactor",
      "  ,e{f,F,b,B,x}    Extract fn / block / variable",
      "  ,w / ,F          Replace word / Search & replace",
      "  ,O               Code outline",
      "",
      "  ── <leader> groups ──────────────────────",
      -- filled in below from the spec itself
      "",
      "  ── Full reference ───────────────────────",
      "  <leader>        Main command palette",
      "  g               Goto / LSP (gd gr gI gy gD K gK gS)",
      "  f / F           Flash jump / Treesitter jump",
      "  [ / ]           Prev / Next navigation",
      "                    b:buffer  d:diag  e:error  w:warn",
      "                    h:hunk  q:qfix  t:todo  y:yank  B:move",
      "  z               Folds / Spelling (zR zM zK)",
      "  <C-w>           Window operations",
      "  r / R           Flash remote (operator mode)",
      "",
      "  ── Ctrl ─────────────────────────────────",
      "  <C-/>            Open/close terminal (the one you are in)",
      "  <C-1> .. <C-9>   Switch to terminal 1-9 (works from",
      "                   terminal input too)",
      "  <leader>md       Fix terminal TUI drift",
      "",
      "  ── <leader>m — the editor itself ────────",
      "  mh / mM / mk     Help / Man / Keymaps",
      "  mC / mc          Commands / Command history",
      "  ml / mm          Lazy / Mason",
      "  mi / mr          LSP info / LSP restart",
      "  mn*              Noice history & messages",
      "",
      "  ── <leader>s — sessions ─────────────────",
      "  ss / sl / s.     Save / load last / load cwd",
      "  <C-]> / <C-\\>    Repeatable Escape (Insert / terminal)",
      "  <C-h/j/k/l>      Window navigation",
      "  <C-,>            Editor window / return (se)",
      "  <C-S-l>          Redraw TUI (terminal mode)",
      "  <C-Up/Down/L/R>  Window resize",
      "",
      "  ── s — windows (bare key, no leader) ────",
      "  ss / sv          Split below / right",
      "  sw / se          Other window / editor window",
      "  sd / so          Close this / close others",
      "  s= / sm          Equalize / toggle zoom",
      "  (<C-h/j/k/l> still moves between windows)",
      "  <C-a> / <C-x>    Increment / Decrement",
      "",
      "  ── Alt / Shift ──────────────────────────",
      "  (Alt belongs to tmux -- see huiyu/nvim#12)",
      "  <S-h> / <S-l>    Prev / Next buffer",
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
    for _, entry in ipairs(require("whichkey_spec")) do
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
    local width = math.max(1, math.min(50, vim.o.columns - 4))
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
    vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, silent = true })
    vim.keymap.set("n", "<Esc>", "<cmd>close<cr>", { buffer = buf, silent = true })
  end, desc = "Keybinding guide", mode = "n" },

  -- Alternate file: toggle between this buffer and the last one *this window*
  -- held. Distinct from cycling the buffer list (<S-h>/<S-l>) -- it is
  -- two files ping-ponging, which is the impl/test loop. Lives on `;` because
  -- it answers the same question as the rest of that prefix, and `a` because
  -- the native <C-^> is Ctrl+Shift+6 on this keyboard.
  { ";a",  "<C-^>",  desc = "Alternate file (toggle)",  mode = "n" },

  -- Quit/Session
  -- Not <cmd>qall<cr>: run from inside a Snacks terminal that only closes the
  -- terminal and leaves Nvim running. See util.window.quit_all.
  { "<leader>qq", function() require("util.window").quit_all() end,     desc = "Quit all",       mode = "n" },
  { "<leader>qQ", function() require("util.window").quit_all(true) end, desc = "Force quit all", mode = "n" },

  -- Window management
  -- Windows on bare `s`, two keys instead of three. `s` was flash's jump key
  -- and is otherwise near-worthless in Vim (it is `cl`); flash moved to `f`.
  --
  -- Deliberately no sh/sj/sk/sl: <C-h/j/k/l> already moves between windows in
  -- one key, from terminal input as well, so adding a two-key twin would only
  -- be slower.
  { "ss", "<cmd>split<cr>",               desc = "Split below",         mode = "n" },
  { "sv", "<cmd>vsplit<cr>",              desc = "Split right",         mode = "n" },
  { "sw", "<C-w>p",                       desc = "Other window",        mode = "n" },
  -- Plain-key twin of <C-,>. That chord needs the extended-key protocol, which
  -- a bare Terminal.app, an ssh session, or a tmux without `extended-keys`
  -- never negotiates -- and it is the only key that reaches the editor area.
  { "se", "<cmd>WindowFocusEditor<cr>",  desc = "Editor window (toggle back)", mode = "n" },
  { "sd", "<cmd>WindowCloseCurrent<cr>", desc = "Delete window",       mode = "n" },
  { "so", "<cmd>WindowCloseOthers<cr>",  desc = "Close other windows", mode = "n" },
  { "s=", function() require("util.window").equalize_respecting_fixed() end, desc = "Equalize windows", mode = "n" },
  { "sm", function()
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
  -- "Rightmost", not "Last": last-used (MRU) is the `a` entry below.
  { "<leader><tab>l",     "<cmd>tablast<cr>",    desc = "Rightmost tab" },
  { "<leader><tab>f",     "<cmd>tabfirst<cr>",   desc = "First tab" },
  -- `a` for alternate, matching `;a` for the alternate *file*: same idea, one
  -- level up. The backtick this replaced is awkward to reach on this keyboard.
  { "<leader><tab>a",     "g<Tab>",              desc = "Last used tab (alternate)" },
  { "<leader><tab>o",     "<cmd>tabonly<cr>",     desc = "Close other tabs" },
  { "<leader><tab>s",     "<cmd>tabs<cr>",        desc = "List all tabs" },

  -- Toggle/UI
  { "<leader>uf", function()
    vim.g.autoformat = not vim.g.autoformat
    vim.notify("Autoformat " .. (vim.g.autoformat and "enabled" or "disabled"))
  end, desc = "Toggle autoformat (global)" },
  { "<leader>uF", function()
    local enabled = vim.b.autoformat ~= false
    vim.b.autoformat = not enabled
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

-- suffix -> { prev, next }. A single string means "Prev X" / "Next X".
-- Motions (usable after an operator) are listed for n/x/o; the rest are
-- Normal-only commands, and listing them in o-mode would advertise entries
-- that do nothing there.
local NXO, N = { "n", "x", "o" }, "n"
local BRACKET_DESCS = {
  -- motions
  { NXO, "m",       "function start" },      { NXO, "M",       "function end" },
  { NXO, "c",       "class start" },         { NXO, "C",       "class end" },
  { NXO, "i",       "indent change" },       { NXO, "I",       { "First indent change", "Last indent change" } },
  { NXO, "x",       "conflict" },            { NXO, "X",       { "First conflict", "Last conflict" } },
  { NXO, "s",       "misspelling" },
  { NXO, "%",       "unmatched group" },     { NXO, "(",       "unmatched (" },
  { NXO, "{",       "unmatched {" },         { NXO, "<",       "unmatched <" },
  -- Normal-only
  { N, "a",         "arg-list file" },       { N, "A",         { "First arg-list file", "Last arg-list file" } },
  { N, "l",         "location" },            { N, "L",         { "First location", "Last location" } },
  { N, "Q",         { "First quickfix", "Last quickfix" } },
  { N, "T",         { "First tag", "Last tag" } },
  { N, "D",         { "First diagnostic", "Last diagnostic" } },
  { N, "j",         "jump" },                { N, "J",         { "First jump", "Last jump" } },
  { N, "o",         "oldfile" },             { N, "O",         { "First oldfile", "Last oldfile" } },
  { N, "u",         "undo state" },          { N, "U",         { "First undo state", "Last undo state" } },
  { N, "y",         { "Prev yank (older)", "Next yank (newer)" } },
  { N, "p",         { "Put above (indented)", "Put below (indented)" } },
  { N, "<space>",   { "Blank line above", "Blank line below" } },
  { N, "<C-l>",     "location file" },       { N, "<C-q>",     "quickfix file" },
  { N, "<C-t>",     "tag (preview window)" },
}
for _, row in ipairs(BRACKET_DESCS) do
  local mode, suffix, d = row[1], row[2], row[3]
  local prev, nxt
  if type(d) == "table" then prev, nxt = d[1], d[2] else prev, nxt = "Prev " .. d, "Next " .. d end
  spec[#spec + 1] = { "[" .. suffix, desc = prev, mode = mode }
  spec[#spec + 1] = { "]" .. suffix, desc = nxt,  mode = mode }
end

-- Text objects the manual documents, worded like which-key's own presets
-- ("inner word" / "word with ws"). Two reasons these need spelling out:
--   * mini.ai maps `i` and `a` as one expr key each and reads the object
--     letter itself, so which-key never sees `ia`/`aa`/`io`/`ao` -- after
--     `di` the popup listed the builtin objects and none of mini.ai's.
--   * treesitter-textobjects registers `if`/`af`/`ic`/`ac` with its own desc
--     ("Select inner part of a function region"), which reads nothing like
--     the rest of the list.
-- Desc-only, like BRACKET_DESCS: which-key shows these and feeds the keys
-- through to whichever plugin owns the object, so behaviour is untouched.
local XO = { "x", "o" }
local TEXTOBJ_DESCS = {
  -- suffix, around, inner (defaults to "inner " .. around)
  { "f", "function" },
  { "c", "class" },
  { "a", "argument with separator", "inner argument" },
  { "o", "block/conditional/loop" },
}
for _, row in ipairs(TEXTOBJ_DESCS) do
  local suffix, around, inner = row[1], row[2], row[3] or ("inner " .. row[2])
  spec[#spec + 1] = { "a" .. suffix, desc = around, mode = XO }
  spec[#spec + 1] = { "i" .. suffix, desc = inner,  mode = XO }
end

return vim.list_extend(spec, hidden)
