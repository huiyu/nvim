-- Which-key spec data: group labels plus spec-registered keymaps, and the
-- same-level section layout for the popup. Consumed by
-- plugin/editor/whichkey.lua via require("whichkey_spec").{spec,sections}.
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
  -- Manage covers the editor itself: config/plugin files, help, man, keymaps,
  -- commands, Noice history, Lazy, Mason, and LSP status/restart.
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
  -- Nvim 0.11's own LSP prefix, left unmodified. It is only reachable where no
  -- client is attached, though: in an LSP buffer the buffer-local `gr`
  -- (References) carries <nowait> so it fires without waiting out 'timeoutlen',
  -- which also means gr* never gets a second key there. Every action has a
  -- shorter binding anyway (gd, gr, gb, gy, ,a, ,r, ,c, ;s).
  { "gr",            group = "LSP (Nvim default, no client attached)" },
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
  -- "g" is Vim's catch-all extra-command prefix (":help g" calls it exactly
  -- that), not a goto namespace. Labelling it "Goto" mislabels two thirds of
  -- what is under it: gu/gU/g~/gw/gq are operators, gp/gP paste, gv reselects,
  -- gS splits. Name the three largest groups instead of the smallest one.
  { "g",             group = "Goto/Case/Misc",  mode = { "n", "x", "o" } },
  { "z",             group = "Fold/Spell",      mode = { "n", "x" } },
  -- <localleader> is per-filetype: VimTeX compile/view, diffview's panel and
  -- conflict actions, gopls/venv/source-header, so the same letter can mean
  -- different things in a .tex and a .go buffer. Terminal buffers add their
  -- own digit row, `\1`..`\9`, on TermOpen (lua/autocmds.lua).
  { "<localleader>", group = "This filetype",   mode = "n" },

  -- The marks plugin labels all four jump-to-mark prefixes identically as
  -- "marks". Disambiguate line-vs-exact and the jumplist-preserving g-variants.
  -- node.plugin stays "marks", so the dynamic mark list still expands.
  { "'",  desc = "marks: line" },
  { "`",  desc = "marks: exact pos" },
  { "g'", desc = "marks: line (keep jumplist)" },
  { "g`", desc = "marks: exact pos (keep jumplist)" },

  -- mini.ai's own descs read "Move to left/right \"around\"", which invites
  -- reading these as prev/next and reaching for [ / ] instead. They are edge
  -- motions on the *current* textobject and take one after the prefix:
  -- `g[f` lands on this function's start, `g]f` on its end.
  { "gO", desc = "[LSP] Document symbols (Nvim default)" },

  { "g[", desc = "textobject edge: left (g[f = fn start)" },
  { "g]", desc = "textobject edge: right (g]f = fn end)" },

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
      "  ;p               Switch project",
      "  ;i / ;?          Files / grep respecting gitignore",
      "  ;o / -           Oil float / Oil parent dir (edit dir as text)",
      "  ;h / ;H          Harpoon menu / add file",
      "  ;1 .. ;9         Jump to pinned file 1-9",
      "  ;/ / ;w          Grep project / word under cursor",
      "  ;s / ;S          Symbol in buffer / workspace",
      "  ;l / ;D          Lines here / grep current dir",
      "  ;j / ;m          Jumps / Marks",
      "  ;a               Last used buffer (toggle)",
      "  ;t / ;T          Todos / Todo+Fixme",
      "",
      "  <leader>ya / yr  Yank file path (absolute / project)",
      "  <leader>yy / yc  Yank selection (register / clipboard)",
      "  <leader>yh / y\"  Yank history / Registers",
      "",
      "  ── g — jump from the symbol here ────────",
      "  gd / gr          Definition / References",
      "  gb / gy          Implementation / Type definition",
      "  gD / gC          Declaration / Incoming calls",
      "  K / gK           Hover / Signature help",
      "  gO               Document symbols (Nvim default)",
      "",
      "  ── , — act on this code ─────────────────",
      "  ,a / ,f / ,r     Code action / Format / Rename",
      "  ,c               Run codelens",
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
      "  g               Goto / case / misc (see the g section above)",
      "  f / F           Flash jump / Treesitter jump",
      "  [ / ]           Prev / Next navigation",
      "                    diag: d e w    git: h x",
      "                    lists: q l t   files: b a o",
      "                    history: j u y (jump/undo/yank)",
      "  z               Folds / Spelling (zR zM zK)",
      "  s               Window operations (see the s section)",
      "  r / R           Flash remote (operator mode)",
      "",
      "  ── Terminals ────────────────────────────",
      "  <C-/>            Open/close terminal (the one you are in)",
      "  3<C-/>           Open terminal 3 from a file",
      "  \\1 .. \\9         Switch terminal (terminal buffers only;",
      "                   from terminal input: jk first)",
      "  <leader>md       Fix terminal TUI drift",
      "",
      "  ── <leader>m — the editor itself ────────",
      "  mf / mF          Nvim config / Plugin source",
      "  mh / mM / mk     Help / Man / Keymaps",
      "  mC / mc          Commands / Command history",
      "  ml / mm          Lazy / Mason",
      "  mi / mr          LSP info / LSP restart",
      "  mn*              Noice history & messages",
      "",
      "  ── <leader>s — sessions ─────────────────",
      -- Spelled out: bare `ss` is the window split two sections below.
      "  <leader>ss       Save the session",
      "  <leader>sl / s.  Load last / load cwd",
      "",
      "  ── s — windows (bare key, no leader) ────",
      "  ss / sv          Split below / right",
      "  sw / se          Other window / editor window",
      "  sd / so          Close this / close others",
      "  s= / sm          Equalize / toggle zoom",
      "  sz               Toggle zen mode (file window)",
      "",
      "  ── Ctrl ─────────────────────────────────",
      "  <C-h/j/k/l>      Window navigation",
      "  <C-Up/Down/L/R>  Window resize",
      "  <C-,>            Editor window / return (se)",
      "  <C-a> / <C-x>    Increment / Decrement",
      "  <C-]> / <C-\\>    Repeatable Escape (Insert / terminal)",
      "  <C-S-l>          Redraw TUI (terminal mode)",
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
    for _, entry in ipairs(require("whichkey_spec").spec) do
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

  -- Nvim's alternate buffer is normally the last buffer this window held.
  -- `;a` follows builtin <C-^>: A -> B -> ;a returns to A, then ;a returns to B.
  -- This is file navigation, so it stays under `;`; `a` means "alternate".
  { ";a",  "<C-^>",  desc = "Last used buffer (toggle)",  mode = "n" },

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

--- Same-level sections for the which-key popup.
---
--- which-key's own `group` is a *sub-prefix*: `<leader>g` plus `l` is the
--- three-key `<leader>gl`, one more keystroke deep. A section slices a single
--- level instead -- the two-key mappings under `;` -- which which-key has no
--- concept of, so plugin/editor/whichkey.lua renders them by inserting heading
--- rows into the popup.
---
--- Keyed by prefix; a section's position in the list is its position in the
--- popup. `keys` are the suffixes after that prefix, matched against the
--- mapping itself, so renaming a `desc` can never silently reclassify a key --
--- which is the whole reason these are keys and not description patterns.
---
--- A key listed in no section sorts after every section and gets no heading, so
--- adding a mapping never *requires* touching this table. A key listed here
--- that no longer exists is inert. Both are checked by
--- tests/whichkey_popup_spec.lua, which fails on a suffix that maps to nothing.
---
--- `color` is a which-key colour name (see the list at the top of
--- which-key/icons.lua): azure, blue, cyan, green, grey, orange, purple, red,
--- yellow.
local sections = {
  -- <leader> is all groups, so these section the domains themselves rather
  -- than individual keys. `item.keys` exists on group rows too, which is what
  -- makes this work at all.
  ["<leader>"] = {
    { "dev",     icon = "󰅱 ", color = "azure",  keys = { "a", "d", "t", "x" } },
    { "vcs",     icon = "󰘬 ", color = "orange", keys = { "g", "G" } },
    { "editor",  icon = "󰈔 ", color = "cyan",   keys = { "b", "y", "<tab>", "u" } },
    { "system",  icon = "󰒓 ", color = "grey",   keys = { "m", "s", "q" } },
  },

  ["<leader>g"] = {
    { "repo",    icon = "󰘬 ", color = "orange", keys = { "s", "b" } },
    { "hunk",    icon = "󰏫 ", color = "green",  keys = { "p", "r", "R", "S" } },
    { "blame",   icon = "󰈈 ", color = "cyan",   keys = { "l", "L", "T" } },
    { "diff",    icon = "󰓡 ", color = "azure",  keys = { "d", "v", "m", "M", "q" } },
    { "history", icon = "󰓫 ", color = "purple", keys = { "c", "C", "H", "V", "f" } },
    { "tools",   icon = "󰏌 ", color = "yellow", keys = { "g", "B" } },
  },

  ["<leader>G"] = {
    { "browse", icon = "󰖟 ", color = "cyan",   keys = { "r", "f", "F" } },
    { "pr",     icon = "󰘩 ", color = "green",  keys = { "c", "p", "P" } },
    { "issues", icon = "󰀦 ", color = "orange", keys = { "i", "I" } },
    { "activity", icon = "󰗟 ", color = "purple", keys = { "a", "s", "n" } },
  },

  ["<leader>d"] = {
    { "run",         icon = "󰐊 ", color = "green",  keys = { "c", "a", "l", "t", "P" } },
    { "step",        icon = "󰑙 ", color = "azure",  keys = { "i", "o", "O", "C", "g" } },
    { "breakpoints", icon = "󰃤 ", color = "red",    keys = { "b", "B" } },
    { "inspect",     icon = "󰈈 ", color = "purple", keys = { "r", "s", "w", "j", "k" } },
  },

  ["<leader>a"] = {
    { "session",   icon = "󰚩 ", color = "green",  keys = { "c", "f", "r", "R", "m" } },
    { "context",   icon = "󰈔 ", color = "cyan",   keys = { "b", "i" } },
    { "review",    icon = "󰄹 ", color = "orange", keys = { "a", "d" } },
    { "history",   icon = "󰓫 ", color = "purple", keys = { "t", "T" } },
    -- `p` is the +CodeCompanion group row: it labels itself, so a heading over
    -- a single entry would say the same thing twice.
  },

  ["<leader>m"] = {
    { "config",   icon = "󰒓 ", color = "cyan",   keys = { "f", "F" } },
    { "packages", icon = "󰏕 ", color = "yellow", keys = { "l", "m" } },
    -- Runtime state and the two things you reach for when it goes wrong.
    { "runtime",  icon = "󰗟 ", color = "azure",  keys = { "i", "r", "d" } },
    { "help",     icon = "󰉹 ", color = "green",  keys = { "h", "k", "M", "C", "c" } },
    -- `n` is the +Noice group row; see <leader>a above.
  },

  ["<leader>b"] = {
    { "pin",    icon = "󰐃 ", color = "cyan", keys = { "p", "P" } },
    { "delete", icon = "󰈆 ", color = "red",  keys = { "d", "D", "o", "l", "r" } },
    -- `j` (Pick buffer) is the only one left; it trails with no heading.
  },

  ["<leader>x"] = {
    { "diagnostics", icon = "󰀦 ", color = "red",   keys = { "x", "X", "d" } },
    { "lists",       icon = "󰉹 ", color = "azure", keys = { "q", "Q", "l", "L" } },
  },

  ["<leader>t"] = {
    { "run",  icon = "󰐊 ", color = "green", keys = { "f", "m", "d" } },
    { "view", icon = "󰈈 ", color = "cyan",  keys = { "S", "o", "D", "h" } },
  },

  ["<leader>u"] = {
    { "display", icon = "󰈈 ", color = "cyan",   keys = { "l", "L", "w", "c", "b", "C", "T" } },
    -- Diagnostics, inlay hints and spelling are all editing-time hints.
    { "hints",   icon = "󰅱 ", color = "azure",  keys = { "d", "h", "s" } },
    { "format",  icon = "󰉢 ", color = "green",  keys = { "f", "F" } },
    -- `n` (dismiss notifications) is the only action here rather than a toggle,
    -- so it trails the toggles instead of heading a section of one.
  },

  ["<leader><tab>"] = {
    { "navigate", icon = "󰓡 ", color = "cyan",  keys = { "[", "]", "f", "l", "a", "s" } },
    { "manage",   icon = "󰎓 ", color = "green", keys = { "<tab>", "d", "o" } },
  },

  ["<leader>y"] = {
    { "path",    icon = "󰆏 ", color = "cyan",   keys = { "a", "r" } },
    { "history", icon = "󰓫 ", color = "purple", keys = { "h", "\"" } },
  },

  -- s is the window prefix (ss split, sd close, se editor window).
  ["s"] = {
    { "split",  icon = "󰯎 ", color = "green",  keys = { "s", "v" } },
    { "focus",  icon = "󰱑 ", color = "cyan",   keys = { "w", "e" } },
    { "layout", icon = "󰊕 ", color = "azure",  keys = { "=", "m", "z" } },
    { "close",  icon = "󰈆 ", color = "red",    keys = { "d", "o" } },
  },

  [";"] = {
    { "files",   icon = "󰈔 ", color = "cyan",
      keys = { "<space>", "f", "F", "i", "r", "b", "g", "a", "o", "P", "p" } },
    { "search",  icon = "󰍉 ", color = "green",
      keys = { "/", "?", "w", "D", "l" } },
    { "symbols", icon = "󰅱 ", color = "azure",  keys = { "s", "S" } },
    { "marks",   icon = "󰃀 ", color = "purple", keys = { "j", "m" } },
    { "harpoon", icon = "󰛢 ", color = "yellow",
      keys = { "h", "H", "1", "2", "3", "4", "5", "6", "7", "8", "9" } },
    { "todo",    icon = "󰄹 ", color = "orange", keys = { "t", "T" } },
    -- `;;` (resume last picker) is a meta action, not a destination: it trails
    -- the sections with no heading of its own.
  },

  -- g mixes our LSP jumps with Vim's own commands. Only ours are declared;
  -- the builtins sort after them with no heading, which is the right shape --
  -- gf/ge/gg are not a "section", they are the rest of Vim.
  ["g"] = {
    { "LSP",        icon = "󰅱 ", color = "azure",
      keys = { "d", "r", "b", "y", "D", "C", "K", "O" } },
    { "edit",       icon = "󰏫 ", color = "yellow",
      keys = { "c", "S", "p", "P", "<C-a>", "<C-x>" } },
    { "textobject", icon = "󰃀 ", color = "purple", keys = { "[", "]" } },
    -- g' and g` jump to a mark without touching the jumplist.
    { "marks",      icon = "󰃀 ", color = "blue",   keys = { "'", "`" } },
    -- `gx` trails with Vim's own g commands rather than heading a list of one.
  },

  [","] = {
    { "LSP",      icon = "󰅱 ", color = "azure",  keys = { "a", "r", "c" } },
    { "refactor", icon = "󰏫 ", color = "orange", keys = { "e", "i", "R", "n" } },
    { "format",   icon = "󰉢 ", color = "cyan",   keys = { "f", "F", "w" } },
    { "lines",    icon = "󰓡 ", color = "green",  keys = { "j", "k", "h", "l" } },
    { "file",     icon = "󰈔 ", color = "purple", keys = { "x", "O" } },
  },
}

-- [ and ] are the same vocabulary in two directions, so they are declared once
-- and mirrored rather than kept in sync by hand.
local BRACKET_SECTIONS = {
  { "diagnostics", icon = "󰀦 ", color = "red",
    keys = { "d", "D", "e", "w" } },
  { "git",         icon = "󰘬 ", color = "orange",
    keys = { "h", "x", "X" } },
  { "lists",       icon = "󰉹 ", color = "azure",
    keys = { "q", "Q", "l", "L", "t", "T", "<C-q>", "<C-l>", "<C-t>" } },
  { "files",       icon = "󰈔 ", color = "cyan",
    keys = { "b", "B", "a", "A", "o", "O" } },
  { "code",        icon = "󰅱 ", color = "green",
    keys = { "[", "]", "i", "I" } },
  -- Jumplist, undo tree and yank ring are all "step through a history", which
  -- is a different question from "move through the code".
  { "history",     icon = "󰓫 ", color = "purple",
    keys = { "j", "J", "u", "U", "y" } },
  { "edit",        icon = "󰏫 ", color = "yellow",
    keys = { "<space>", "p" } },
}
sections["["] = BRACKET_SECTIONS
sections["]"] = BRACKET_SECTIONS

return {
  spec = vim.list_extend(spec, hidden),
  sections = sections,
}
