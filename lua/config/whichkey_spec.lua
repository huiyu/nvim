-- Which-key spec data: group labels plus spec-registered keymaps, the
-- same-level section layout for the popup, and descs for keys filetype
-- plugins map without one. Consumed by plugins/editor/whichkey.lua via
-- require("config.whichkey_spec").{spec,sections,filetype_descs}.
--
-- Pure data. The imperative vim.keymap.set() bindings (and mapleader) live in
-- local-plugin/editor-core.nvim/lua/editor_core/keymaps.lua, a startup step of lua/config/init.lua.

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
  -- treesitter moves ]m/]c (lua/plugin/ui/treesitter.lua) beside CodeDiff's
  -- "Next hunk" and Python's and VimTeX's motions, and Nvim's gO
  -- (local-plugin/editor-core.nvim/lua/editor_core/keymaps.lua) beside the outline of markdown, help and man buffers.
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



  -- Nvim's alternate buffer is normally the last buffer this window held.
  -- `;a` follows builtin <C-^>: A -> B -> ;a returns to A, then ;a returns to B.
  -- This is file navigation, so it stays under `;`; `a` means "alternate".


  -- Quit/Session
  -- Not <cmd>qall<cr>: run from inside a Snacks terminal that only closes the
  -- terminal and leaves Nvim running. See util.quit.all.



  -- Window management
  -- Windows on bare `s`, two keys instead of three. `s` was flash's jump key
  -- and is otherwise near-worthless in Vim (it is `cl`); flash moved to `f`.
  --
  -- Deliberately no sh/sj/sk/sl: <C-h/j/k/l> already moves between windows in
  -- one key, from terminal input as well, so adding a two-key twin would only
  -- be slower.



  -- Plain-key twin of <C-,>. That chord needs the extended-key protocol, which
  -- a bare Terminal.app, an ssh session, or a tmux without `extended-keys`
  -- never negotiates -- and it is the only key that reaches the editor area.






  -- Tab management
  -- `n` is new, as <leader>an starts a chat. <tab><tab> is LazyVim's spelling,
  -- kept for the hand that knows it and hidden so the popup lists one key.





  -- First/last as in [Q/]Q; the last-used (MRU) tab is the `a` entry below.


  -- `a` for alternate, matching `;a` for the alternate *file*: same idea, one
  -- level up. The backtick this replaced is awkward to reach on this keyboard.




  -- Toggle/UI
  -- Lowercase is this file, uppercase every file, as ;s/;S and <leader>gc/gC
  -- widen.











}

-- suffix -> { prev, next }. A single string means "Prev X" / "Next X".
-- Motions (usable after an operator) are listed for n/x/o; the rest are
-- Normal-only commands, and listing them in o-mode would advertise entries
-- that do nothing there.
--
-- Not here: the treesitter moves m/M/c/C, which carry their own descs
-- (lua/plugin/ui/treesitter.lua) because buffers remap them -- CodeDiff's
-- ]c is "Next hunk", Python's and VimTeX's ]m their own motions -- and a
-- desc-only row would outrank every one of those. Nor ]r/[r, the references
-- (lua/plugin/coding/lsp.lua), which are VimTeX's frames in a tex buffer.
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
-- as real descs (lua/plugin/ui/treesitter.lua): VimTeX maps its own `ac`/`ic`
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
--- lua/plugin/lang/tex.lua maps back. Being the mapping's own desc, it goes when the
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
    -- The chat on the right, whatever it is (local-plugin/agent-workbench.nvim/lua/agent_workbench/slot.lua): open a new one,
    -- switch to another, hide or bring it back, go into it. Billing is named
    -- in the new-chat picker's entries and the switcher's labels.
    { "chats",     icon = "󰍩 ", color = "blue",   keys = { "n", "l", "c", "f" } },
    -- What goes to the chat on the right. `s` only exists in Visual mode and
    -- `S` only in oil buffers.
    { "context",   icon = "󰈔 ", color = "cyan",   keys = { "b", "i", "s", "S" } },
    -- A native agent's own session: the one on the right, else the one asked
    -- for.
    { "native session", icon = "󰚩 ", color = "green", keys = { "r", "R", "m" } },
    -- Transcripts of the native agents, and the chats codecompanion-history
    -- saved.
    { "history",   icon = "󰓫 ", color = "purple", keys = { "t", "T", "o" } },
    -- Claude's own proposals, answered before they reach the disk.
    { "Claude diffs", icon = "󰓡 ", color = "orange", keys = { "a", "d" } },
    -- What changed since a round baseline, and starting a new round.
    { "review",    icon = "󰄹 ", color = "red",    keys = { "v", "V" } },
    -- Inline edits and the key profile they bill. The heading names the
    -- billing on purpose: these are the keys that spend API credits.
    { "HTTP · API credits", icon = "󰌆 ", color = "yellow", keys = { "e", "x" } },
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
    -- Only the keys the chat really maps (lua/plugin/ai/codecompanion.lua):
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
