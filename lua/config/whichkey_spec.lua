-- Which-key spec data: group labels plus spec-registered keymaps, the
-- same-level section layout for the popup, and descs for keys filetype
-- plugins map without one. Consumed by plugins/editor/whichkey.lua via
-- require("config.whichkey_spec").{spec,sections,filetype_descs}.
--
-- Pure data. The imperative vim.keymap.set() bindings (and mapleader) live in
-- lua/config/keymaps.lua, a startup step of lua/config/init.lua.

-- Hide noisy individual keymaps from the which-key popup. They still work,
-- just not listed (Harpoon numeric jumps are reviewed through the ;h menu;
-- <leader>? is the standalone keybinding-guide popup).
local hidden = {
  { "<leader>?", hidden = true },
  -- Not an alias of <leader>Gf: on a commit hash (blame or log output) it
  -- opens that commit's page; elsewhere it opens the file like <leader>Gf.
  { "<leader>gB", hidden = true },
  { ";1", hidden = true }, { ";2", hidden = true }, { ";3", hidden = true },
  { ";4", hidden = true }, { ";5", hidden = true }, { ";6", hidden = true },
  { ";7", hidden = true }, { ";8", hidden = true }, { ";9", hidden = true },
}

local spec = {
  -- Which-key group labels
  -- Manage covers the editor itself: config/plugin files, help, man, keymaps,
  -- commands, message and notification history, Lazy, Mason, and LSP
  -- status/restart.
  --
  -- Groups that hold Visual keys say "x", never "v": "v" adds Select mode,
  -- where which-key would make <Space> a prefix inside a snippet placeholder
  -- (tests/select_mode_spec.lua). Manage and Test hold no Visual key at all.
  { "<leader>m",     group = "Manage",          mode = "n" },
  -- `,` is the twin of `;`: where `;` answers "which file do I want to be in?",
  -- `,` answers "what can I do in this file or view?" -- general editing,
  -- language tools and view actions share a menu with contextual headings.
  -- Both keep frequent actions short; <leader> keeps global domains.
  --
  -- ,a/,r/,c attach with LSP; filetype/view keys stay buffer-local.
  -- <localleader> is also comma; it contributes to this same menu. "File",
  -- not "Buffer": buffer names the buffer list (<leader>b).
  { ",",             group = "File/view actions", mode = { "n", "x" } },
  { ",e",            group = "Extract",         mode = { "n", "x" } },
  -- Sessions only; config and tooling live under <leader>m.
  { "<leader>s",     group = "Session",         mode = "n" },
  { "<leader>G",     group = "GitHub",          mode = { "n", "x" } },
  { "<leader>b",     group = "Buffer" },
  { "<leader>d",     group = "Debug",           mode = { "n", "x" } },
  { "<leader>g",     group = "Git",             mode = { "n", "x" } },
  { "<leader>t",     group = "Test",            mode = "n" },
  { "<leader>u",     group = "Toggle/UI" },
  { "<leader>x",     group = "Diagnostics",     mode = "n" },
  { "<leader>a",     group = "AI",              mode = { "n", "x" } },
  { "<leader>q",     group = "Quit",            mode = "n" },
  { "s",             group = "Window",          mode = "n" },
  -- Yank/paste in one place. <leader>y and <leader>Y used to mean two unrelated
  -- things depending on mode -- a file path in Normal, the selection in Visual
  -- -- which read as one key with two meanings rather than a group.
  { "<leader>y",     group = "Yank",            mode = { "n", "x" } },
  -- Two histories (snacks.lua): Vim's messages and the snacks notifier's.
  { "<leader>mn",    group = "Messages/notifications" },
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
  -- One wording for every [ / ] pair. The keys come from three places -- Nvim's
  -- 0.11 defaults (":lprevious", ":cpfile"), mini.bracketed ("Undo backward")
  -- and our own ("Prev hunk") -- and each names things its own way. These are
  -- desc-only entries: which-key shows them instead of the mapping's desc, and
  -- the mappings are untouched. See BRACKET_DESCS below.
  --
  -- A desc-only entry outranks every desc, buffer-local ones included, so it
  -- is only for a key no buffer gives another meaning. Where one does, the
  -- global mapping carries the desc itself and the buffer's own shows: the
  -- treesitter moves ]m/]c (lua/plugins/ui/treesitter.lua) beside CodeDiff's
  -- "Next hunk" and Python's and VimTeX's motions, and Nvim's gO
  -- (lua/config/keymaps.lua) beside the outline of markdown, help and man buffers.
  -- "g" is Vim's catch-all extra-command prefix (":help g" calls it exactly
  -- that), not a go-to namespace. Labelling it "Goto" mislabelled two thirds of
  -- what is under it: gu/gU/g~/gw/gq are operators, gp/gP paste, gv reselects,
  -- gS splits. Name the three largest groups instead of the smallest one.
  { "g",             group = "Go to / case / misc", mode = { "n", "x", "o" } },
  { "z",             group = "Fold/spell",      mode = { "n", "x" } },

  -- The marks plugin labels all four jump-to-mark prefixes identically as
  -- "marks". Disambiguate line-vs-exact and the jumplist-preserving g-variants.
  -- node.plugin stays "marks", so the dynamic mark list still expands.
  { "'",  desc = "Marks: line" },
  { "`",  desc = "Marks: exact position" },
  { "g'", desc = "Marks: line (keep jumplist)" },
  { "g`", desc = "Marks: exact position (keep jumplist)" },

  -- mini.ai's own descs read "Move to left/right \"around\"", which invites
  -- reading these as prev/next and reaching for [ / ] instead. They are edge
  -- motions on the *current* textobject and take one after the prefix:
  -- `g[f` lands on this function's start, `g]f` on its end.
  { "g[", desc = "Textobject edge: left (g[f = function start)" },
  { "g]", desc = "Textobject edge: right (g]f = function end)" },

  -- Top-level shortcuts
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
      "  <C-s>/<C-v>/<C-t> Open below / beside / tab",
      "  <M-p> / <M-.>    Preview / hidden files",
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
    for _, entry in ipairs(require("config.whichkey_spec").spec) do
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

  -- Nvim's alternate buffer is normally the last buffer this window held.
  -- `;a` follows builtin <C-^>: A -> B -> ;a returns to A, then ;a returns to B.
  -- This is file navigation, so it stays under `;`; `a` means "alternate".
  { ";a",  "<C-^>",  desc = "Last used buffer (alternate)",  mode = "n" },

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
  { "sw", "<C-w>p",                       desc = "Previous window",     mode = "n" },
  -- Plain-key twin of <C-,>. That chord needs the extended-key protocol, which
  -- a bare Terminal.app, an ssh session, or a tmux without `extended-keys`
  -- never negotiates -- and it is the only key that reaches the editor area.
  { "se", "<cmd>WindowFocusEditor<cr>",  desc = "Editor window (toggle back)", mode = "n" },
  { "sd", "<cmd>WindowCloseCurrent<cr>", desc = "Close window",        mode = "n" },
  { "so", "<cmd>WindowCloseOthers<cr>",  desc = "Close other windows", mode = "n" },
  { "s=", function() require("util.window").equalize_respecting_fixed() end, desc = "Equalize windows", mode = "n" },
  { "sm", function() require("util.window").toggle_zoom() end, desc = "Toggle zoom", mode = "n" },

  -- Tab management
  -- `n` is new, as <leader>an starts a chat. <tab><tab> is LazyVim's spelling,
  -- kept for the hand that knows it and hidden so the popup lists one key.
  { "<leader><tab>n",     "<cmd>tabnew<cr>",     desc = "New tab" },
  { "<leader><tab><tab>", "<cmd>tabnew<cr>",     desc = "New tab", hidden = true },
  { "<leader><tab>d",     "<cmd>tabclose<cr>",   desc = "Close tab" },
  { "<leader><tab>]",     "<cmd>tabnext<cr>",    desc = "Next tab" },
  { "<leader><tab>[",     "<cmd>tabprev<cr>",    desc = "Prev tab" },
  -- First/last as in [Q/]Q; the last-used (MRU) tab is the `a` entry below.
  { "<leader><tab>l",     "<cmd>tablast<cr>",    desc = "Last tab" },
  { "<leader><tab>f",     "<cmd>tabfirst<cr>",   desc = "First tab" },
  -- `a` for alternate, matching `;a` for the alternate *file*: same idea, one
  -- level up. The backtick this replaced is awkward to reach on this keyboard.
  { "<leader><tab>a",     "g<Tab>",              desc = "Last used tab (alternate)" },
  { "<leader><tab>o",     "<cmd>tabonly<cr>",     desc = "Close other tabs" },
  { "<leader><tab>s",     "<cmd>tabs<cr>",        desc = "List all tabs" },

  -- Toggle/UI
  -- Lowercase is this file, uppercase every file, as ;s/;S and <leader>gc/gC
  -- widen.
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
  end, desc = "Toggle dark/light background" },
}

-- suffix -> { prev, next }. A single string means "Prev X" / "Next X".
-- Motions (usable after an operator) are listed for n/x/o; the rest are
-- Normal-only commands, and listing them in o-mode would advertise entries
-- that do nothing there.
--
-- Not here: the treesitter moves m/M/c/C, which carry their own descs
-- (lua/plugins/ui/treesitter.lua) because buffers remap them -- CodeDiff's
-- ]c is "Next hunk", Python's and VimTeX's ]m their own motions -- and a
-- desc-only row would outrank every one of those. Nor ]r/[r, the references
-- (lua/plugins/coding/lsp.lua), which are VimTeX's frames in a tex buffer.
local NXO, NO, N, X = { "n", "x", "o" }, { "n", "o" }, "n", "x"
local BRACKET_DESCS = {
  -- motions
  { NXO, "i",       "indent change" },       { NXO, "I",       { "First indent change", "Last indent change" } },
  { NXO, "x",       "conflict" },            { NXO, "X",       { "First conflict", "Last conflict" } },
  { NXO, "s",       "misspelling" },
  { NXO, "%",       "unmatched group" },     { NXO, "(",       "unmatched (" },
  { NXO, "{",       "unmatched {" },         { NXO, "<",       "unmatched <" },
  -- mini.bracketed maps its jumplist motions in Operator-pending mode but not
  -- in Visual, where its own "Jump forward" otherwise showed.
  { NO, "j",        "jump" },                { NO, "J",        { "First jump", "Last jump" } },
  -- Visual-only: Nvim's incremental selection ("Select next node"). ]N grows
  -- the selection over the sibling rather than moving to it. VimTeX's own
  -- ]n/]N (math zones) are Normal and Operator-pending only.
  { X, "n",         "node" },
  { X, "N",         { "Prev sibling (extend)", "Next sibling (extend)" } },
  -- Normal-only
  { N, "a",         "arg-list file" },       { N, "A",         { "First arg-list file", "Last arg-list file" } },
  { N, "l",         "location" },            { N, "L",         { "First location", "Last location" } },
  { N, "Q",         { "First quickfix", "Last quickfix" } },
  { N, "T",         { "First tag", "Last tag" } },
  { N, "D",         { "First diagnostic", "Last diagnostic" } },
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
-- ("inner word" / "word with ws"): lowercase nouns, the one popup whose
-- house style is not sentence case. Two reasons these need spelling out:
--   * mini.ai maps `i` and `a` as one expr key each and reads the object
--     letter itself, so which-key never sees `ia`/`aa`/`io`/`ao` -- after
--     `di` the popup listed the builtin objects and none of mini.ai's.
--   * mini.ai's `al`/`il` ("Around last textobject") and Nvim's `an`/`in`
--     ("Select parent (outer) node") read nothing like the rest of the list.
--     `al`/`il` take an object key of their own (`dal)`, `vilf`).
-- Desc-only, like BRACKET_DESCS: which-key shows these and feeds the keys
-- through to whichever plugin owns the object, so behaviour is untouched.
-- `af`/`if`/`ac`/`ic` are treesitter-textobjects maps that carry these words
-- as real descs (lua/plugins/ui/treesitter.lua): VimTeX maps its own `ac`/`ic`
-- in TeX buffers, which a desc-only row here would mislabel "class".
local XO = { "x", "o" }
local TEXTOBJ_DESCS = {
  -- suffix, around, inner (defaults to "inner " .. around)
  { "a", "argument with separator", "inner argument" },
  { "o", "block/conditional/loop" },
  { "l", "last textobject (al + object key)", "inner last textobject (il + object key)" },
  { "n", "parent node", "child node" },
}
for _, row in ipairs(TEXTOBJ_DESCS) do
  local suffix, around, inner = row[1], row[2], row[3] or ("inner " .. row[2])
  spec[#spec + 1] = { "a" .. suffix, desc = around, mode = XO }
  spec[#spec + 1] = { "i" .. suffix, desc = inner,  mode = XO }
end

--- { next lhs, prev lhs, what } -> { [next] = "Next what", [prev] = "Prev what" }
local function motions(rows)
  local descs = {}
  for _, row in ipairs(rows) do
    descs[row[1]], descs[row[2]] = "Next " .. row[3], "Prev " .. row[3]
  end
  return descs
end

--- { suffix, around[, inner] } -> text-object descs, as TEXTOBJ_DESCS words them.
local function objects(rows)
  local descs = {}
  for _, row in ipairs(rows) do
    descs["a" .. row[1]], descs["i" .. row[1]] = row[2], row[3] or ("inner " .. row[2])
  end
  return descs
end

--- Descs for keys a filetype plugin maps in its own buffers: Nvim's runtime
--- ftplugins and VimTeX. Most carry none, so the popup showed their code
--- (`:<C-U>call <SNR>27_Python_jump('n', ...)`, `vimtex-][)`); the rest word
--- them their own way ("Jump to next section", "Show an Outline of the
--- current buffer").
---
--- plugins/editor/whichkey.lua writes these onto the buffer's own mapping, per
--- mode, and only where that buffer maps the key itself. VimTeX skips a key a
--- global map already holds (Nvim's Visual ]n), so a label on the key would
--- misname the global one there; its Normal ]r/[r, which the references hold,
--- lua/plugins/lang/tex.lua maps back. Being the mapping's own desc, it goes when the
--- filetype unmaps the key.
---
--- Python's ]m/]M are its own class/def motions, not treesitter's function
--- moves; VimTeX's are environments.
local OUTLINE = { gO = "Show outline" }
local SECTIONS = motions({ { "]]", "[[", "section" } })
local FILETYPE_DESCS = {
  python = motions({
    { "]]", "[[", "top-level class/def start" }, { "][", "[]", "top-level class/def end" },
    { "]m", "[m", "class/def start" },           { "]M", "[M", "class/def end" },
  }),
  go = motions({ { "]]", "[[", "type/func start" }, { "][", "[]", "type/func end" } }),
  rust = motions({ { "]]", "[[", "top-level block" } }),
  vim = motions({
    { "]]", "[[", "function start" }, { "][", "[]", "function end" },
    { ']"', '["', "comment" },
  }),
  tex = vim.tbl_extend("error",
    motions({
      { "]]", "[[", "section start" },     { "][", "[]", "section end" },
      { "]m", "[m", "environment start" }, { "]M", "[M", "environment end" },
      { "]n", "[n", "math zone start" },   { "]N", "[N", "math zone end" },
      { "]r", "[r", "frame start" },       { "]R", "[R", "frame end" },
      { "]/", "[/", "comment start" },     { "]*", "[*", "comment end" },
    }),
    objects({
      { "c", "command" }, { "d", "delimiter" }, { "e", "environment" },
      { "$", "math zone" }, { "P", "section" }, { "m", "item" },
    })),
  -- Nvim's runtime outline: a location list of the headings.
  markdown = vim.tbl_extend("error", SECTIONS, OUTLINE),
  help = vim.tbl_extend("error", SECTIONS, OUTLINE),
  checkhealth = vim.tbl_extend("error", SECTIONS, OUTLINE),
  man = OUTLINE,
}

--- Same-level sections for the which-key popup.
---
--- which-key's own `group` is a *sub-prefix*: `<leader>g` plus `l` is the
--- three-key `<leader>gl`, one more keystroke deep. A section slices a single
--- level instead -- the two-key mappings under `;` -- which which-key has no
--- concept of, so plugins/editor/whichkey.lua renders them by inserting heading
--- rows into the popup.
---
--- Keyed by prefix; a section's position in the list is its position in the
--- popup. `keys` are the suffixes after that prefix, matched against the
--- mapping itself, so renaming a `desc` can never silently reclassify a key --
--- which is the whole reason these are keys and not description patterns.
--- Optional `filetype` (list) and `buftype` filters select a contextual section
--- in the source buffer. The first matching section owns a key; e.g. ,v has
--- separate Python and LaTeX entries. `labels` names implicit subgroup rows
--- without creating placeholder mappings. Only actual mappings appear.
---
--- A key listed in no section sorts last under the shared fallback section, so
--- adding a mapping never *requires* touching this table. A key listed here
--- that no longer exists is inert. tests/whichkey_popup_spec.lua covers the
--- headings and global declarations; tests/context_actions_spec.lua exercises
--- real filetype menus, shared suffixes, and preserved general editing keys.
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
    { "diff",    icon = "󰓡 ", color = "azure",  keys = { "d", "D", "v", "m", "M", "q", "k", "K" } },
    -- c/C and h/H are this file / the repository, commits and history alike.
    { "history", icon = "󰓫 ", color = "purple", keys = { "c", "C", "h", "H", "f" } },
    { "tools",   icon = "󰏌 ", color = "yellow", keys = { "g", "B" } },
  },

  ["<leader>G"] = {
    { "browse", icon = "󰖟 ", color = "cyan",   keys = { "r", "f", "F" } },
    { "pr",     icon = "󰘩 ", color = "green",  keys = { "c", "p", "P" } },
    { "issues", icon = "󰀦 ", color = "orange", keys = { "i", "I" } },
    { "activity", icon = "󰗟 ", color = "purple", keys = { "a", "s", "n" } },
  },

  ["<leader>d"] = {
    { "run",         icon = "󰐊 ", color = "green",  keys = { "c", "f", "a", "A", "l", "R", "D", "t", "P" } },
    { "step",        icon = "󰑙 ", color = "azure",  keys = { "i", "o", "O", "C", "g" } },
    { "breakpoints", icon = "󰃤 ", color = "red",    keys = { "b", "B", "L", "e", "q", "x" } },
    { "inspect",     icon = "󰈈 ", color = "purple", keys = { "r", "s", "w", "W", "u", "j", "k" } },
  },

  ["<leader>a"] = {
    -- The chat on the right, whatever it is (lua/ai/slot.lua): open a new one,
    -- switch to another, hide or bring it back, go into it. Billing is named
    -- in the new-chat picker's entries and the switcher's labels.
    { "chats",     icon = "󰍩 ", color = "blue",   keys = { "n", "l", "c", "f" } },
    -- What goes to the chat on the right. `s` only exists in Visual mode and
    -- `S` only in oil buffers.
    { "context",   icon = "󰈔 ", color = "cyan",   keys = { "b", "i", "s", "S" } },
    -- A native agent's own session: the one on the right, else the one asked
    -- for.
    { "native session", icon = "󰚩 ", color = "green", keys = { "r", "R", "m" } },
    { "history",   icon = "󰓫 ", color = "purple", keys = { "t", "T" } },
    -- Claude's own proposals, answered before they reach the disk.
    { "Claude diffs", icon = "󰓡 ", color = "orange", keys = { "a", "d" } },
    -- What changed since a round baseline, and starting a new round.
    { "review",    icon = "󰄹 ", color = "red",    keys = { "v", "V" } },
    -- Inline edits and the key profile they bill. The heading names the
    -- billing on purpose: these are the keys that spend API credits.
    { "HTTP · API credits", icon = "󰌆 ", color = "yellow", keys = { "e", "x" } },
    { "companion", icon = "󰒓 ", color = "azure",  keys = { "p", "o" } },
  },

  ["<leader>m"] = {
    { "config",   icon = "󰒓 ", color = "cyan",   keys = { "f", "F" } },
    { "packages", icon = "󰏕 ", color = "yellow", keys = { "l", "m" } },
    -- Runtime state and the two things you reach for when it goes wrong.
    { "runtime",  icon = "󰗟 ", color = "azure",  keys = { "i", "r", "d" } },
    { "help",     icon = "󰉹 ", color = "green",  keys = { "h", "k", "M", "C", "c" } },
    -- `n` (+Messages/notifications) goes under others, without a dedicated
    -- section.
  },

  ["<leader>b"] = {
    { "pin",    icon = "󰐃 ", color = "cyan", keys = { "p", "P" } },
    -- Moving the current buffer along the bar; going to its first or last
    -- buffer is [B/]B.
    { "move",   icon = "󰓡 ", color = "azure", keys = { "<", ">" } },
    { "delete", icon = "󰈆 ", color = "red",  keys = { "d", "D", "o", "h", "l", "r", "x" } },
    -- Picking a buffer is navigation, on ;B.
  },

  ["<leader>x"] = {
    { "diagnostics", icon = "󰀦 ", color = "red",   keys = { "x", "b", "d" } },
    { "lists",       icon = "󰉹 ", color = "azure", keys = { "q", "Q", "l", "L" } },
  },

  ["<leader>t"] = {
    -- Uppercase is the debug variant of the same run: tm/tM, tf/tF.
    { "run",  icon = "󰐊 ", color = "green", keys = { "m", "M", "f", "F" } },
    { "view", icon = "󰈈 ", color = "cyan",  keys = { "s", "o", "x" } },
  },

  ["<leader>u"] = {
    { "display", icon = "󰈈 ", color = "cyan",   keys = { "l", "L", "w", "c", "b", "C", "T", "r" } },
    -- Diagnostics, inlay hints and spelling are all editing-time hints.
    { "hints",   icon = "󰅱 ", color = "azure",  keys = { "d", "h", "s" } },
    { "format",  icon = "󰉢 ", color = "green",  keys = { "f", "F" } },
    -- `n` (dismiss notifications) is the only action here rather than a toggle,
    -- so it goes under others instead of a dedicated section of one.
  },

  ["<leader><tab>"] = {
    { "navigate", icon = "󰓡 ", color = "cyan",  keys = { "[", "]", "f", "l", "a", "s" } },
    { "manage",   icon = "󰎓 ", color = "green", keys = { "n", "d", "o" } },
  },

  ["<leader>y"] = {
    { "path",    icon = "󰆏 ", color = "cyan",   keys = { "a", "r", "l", "g" } },
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
      keys = { "<space>", "f", "F", "i", "r", "b", "B", "g", "a", "o", "P", "p" } },
    { "search",  icon = "󰍉 ", color = "green",
      keys = { "/", "?", "w", "D", "l" } },
    { "symbols", icon = "󰅱 ", color = "azure",  keys = { "s", "S" } },
    -- Places to be that a picker lists: the jumplist, marks, changed hunks.
    { "positions", icon = "󰃀 ", color = "purple", keys = { "j", "m", "c" } },
    { "harpoon", icon = "󰛢 ", color = "yellow",
      keys = { "h", "H", "1", "2", "3", "4", "5", "6", "7", "8", "9" } },
    { "todo",    icon = "󰄹 ", color = "orange", keys = { "t", "T" } },
    -- `;;` (resume last picker) is a meta action, not a destination: it trails
    -- the sections under others.
  },

  -- g mixes our LSP jumps with Vim's own commands. The remaining builtins,
  -- including gf/ge/gg, sort last under others.
  --
  -- Views and filetypes that put their own actions on g come first: the first
  -- matching section owns a key, and without them oil's gs (sort) or the
  -- chat's gd (debug info) sat under the LSP heading.
  ["g"] = {
    { "oil · listing", icon = "󰉋 ", color = "cyan", filetype = { "oil" },
      keys = { "?", ".", "\\", "~", "s", "R", "o" } },
    { "CodeDiff · panel", icon = "󰓡 ", color = "orange", filetype = { "codediff-explorer", "codediff-history" },
      keys = { "s", "u", "f", "?" } },
    -- Only the keys the chat really maps (lua/plugins/ai/codecompanion.lua):
    -- its clear moved to ,X and its file jump to gf, and Copilot stats are
    -- off, so gx, gR and gS there are the global ones and keep their headings.
    { "Chat · conversation/context", icon = "󰍔 ", color = "cyan", filetype = { "codecompanion" },
      keys = { "?", "b", "c", "d", "f", "h", "M", "m", "r", "s", "t", "y" } },
    { "Lazy · plugin", icon = "󰏕 ", color = "yellow", filetype = { "lazy" }, keys = { "b", "l", "x" } },
    -- gO is the heading outline there, needing no server (FILETYPE_DESCS).
    { "outline", icon = "󰉹 ", color = "green", filetype = { "markdown", "help", "checkhealth", "man" },
      keys = { "O" } },
    { "LSP",        icon = "󰅱 ", color = "azure",
      keys = { "d", "r", "b", "y", "D", "C", "s", "K", "O" } },
    { "edit",       icon = "󰏫 ", color = "yellow",
      keys = { "c", "S", "p", "P", "<C-a>", "<C-x>" } },
    { "textobject", icon = "󰃀 ", color = "purple", keys = { "[", "]" } },
    -- g' and g` jump to a mark without touching the jumplist.
    { "marks",      icon = "󰃀 ", color = "blue",   keys = { "'", "`" } },
    -- `gx` trails with Vim's own g commands rather than heading a list of one.
  },

  [","] = {
    -- Lazy's own ,l (lazygit log) and ,i (inspect) would otherwise fall under
    -- lines and refactor, which come first.
    { "Lazy · plugin", icon = "󰏕 ", color = "yellow", filetype = { "lazy" }, keys = { "l", "i", "t" } },
    { "LSP",      icon = "󰅱 ", color = "azure",  keys = { "a", "r", "c" } },
    { "refactor", icon = "󰏫 ", color = "orange", keys = { "e", "i", "R", "n" } },
    -- ,F and ,w open the search panel to search and replace; ,f formats.
    { "format/replace", icon = "󰉢 ", color = "cyan", keys = { "f", "F", "w" } },
    { "lines",    icon = "󰓡 ", color = "green",  keys = { "j", "k", "h", "l" } },
    { "file",     icon = "󰈔 ", color = "purple", keys = { "x", "O" } },
    -- Context selects the heading, while actual buffer mappings select the
    -- visible actions. View keys are distinct so a source buffer in CodeDiff
    -- can show both its language section and its view section.
    { "C/C++ · files", icon = "󰈔 ", color = "purple", filetype = { "c", "cpp" }, keys = { "H" } },
    { "Python · imports/environment", icon = "󰌠 ", color = "yellow", filetype = { "python" }, keys = { "o", "v" } },
    { "Go · imports/server", icon = "󰟓 ", color = "cyan", filetype = { "go" }, keys = { "o", "G" } },
    { "Dart/Flutter · runtime", icon = "󰐊 ", color = "cyan", filetype = { "dart" }, keys = { "d" },
      labels = { d = "Hot reload/restart" } },
    { "LaTeX · build", icon = "󰐊 ", color = "green", filetype = { "tex", "plaintex" }, keys = { "b", "s", "K", "E" } },
    { "LaTeX · preview/tools", icon = "󰈈 ", color = "purple", filetype = { "tex", "plaintex", "bib" }, keys = { "v", "t", "L" },
      labels = { L = "VimTeX" } },
    { "Markdown · preview", icon = "󰍔 ", color = "cyan", filetype = { "markdown" }, keys = { "p", "m" } },
    { "Chat · conversation/rendering", icon = "󰍔 ", color = "cyan", filetype = { "codecompanion" },
      keys = { "s", "X", "q", "z", "m" } },
    -- grug-far's own actions sit under ,S in its panel only; elsewhere a
    -- CodeDiff pane's ,S stages a hunk (Review, below).
    { "Search panel · actions", icon = "󰍉 ", color = "cyan", filetype = { "grug-far" }, keys = { "S" },
      labels = { S = "Search panel" } },
    { "CodeDiff · panels/layout/conflicts", icon = "󰓡 ", color = "orange", keys = { "P", "B", "g", "z", "I" } },
    -- S/U/X: stage, unstage, discard, as the status explorer's file keys.
    { "Review · feedback/stage/discard", icon = "󰄹 ", color = "red", keys = { "C", "S", "U", "X" } },
    { "Terminal · sessions", icon = "󰆍 ", color = "yellow", buftype = "terminal",
      keys = { "1", "2", "3", "4", "5", "6", "7", "8", "9" } },
  },
  [",S"] = {
    { "replace/sync", icon = "󰏫 ", color = "orange", keys = { "r", "s", "l", "v", "j", "k", "n", "p" } },
    { "results", icon = "󰈔 ", color = "purple", keys = { "o", "i", "q" } },
    { "history", icon = "󰋚 ", color = "yellow", keys = { "t", "a" } },
    { "search/panel", icon = "󰍉 ", color = "cyan", keys = { "f", "b", "e", "x", "w", "c" } },
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
  -- Sections ([[ ]] [] ][, the buffer's own), references, function and class
  -- moves, indent changes, and Visual mode's node selection (n/N).
  { "code",        icon = "󰅱 ", color = "green",
    keys = { "[", "]", "r", "m", "M", "c", "C", "i", "I", "n", "N" } },
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
  fallback_section = { "others", icon = "󰒔 ", color = "grey" },
  filetype_descs = FILETYPE_DESCS,
}
