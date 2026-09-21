# Repository Instructions

## Purpose

This is a personal Neovim configuration for Neovim 0.11+ written in Lua and
managed by lazy.nvim. Keep changes small, reversible, lazy-loaded where
practical, and consistent with the existing LazyVim-style key namespaces.

## Architecture

- `init.lua` loads options, core mappings, autocommands, lazy.nvim, and the AI
  facade.
- `lua/plugin/{editor,lsp,ui,vcs}/` contains editor-wide plugin specs.
- `lua/lang/*.lua` owns language contributions: LSP servers, Mason tools,
  formatters, linters, Treesitter parsers, DAP adapters, tests, and runners.
  Add language-specific behavior there instead of expanding a core plugin spec.
- `lua/util/` contains small reusable helpers. Avoid introducing frameworks for
  behavior already covered by Neovim or a maintained plugin.
- `lua/ai/config.lua` selects one provider per Nvim process. `lua/ai/init.lua`
  exposes provider-neutral mappings; `lua/ai/backend/` owns native-agent details.

## AI Provider Invariants

- `vi` uses the default provider, `vic` selects Claude, and `vix` selects Codex.
  Provider selection happens at startup through `NVIM_AI_PROVIDER`; do not add
  runtime switching without an explicit session/UI design.
- Native Claude and Codex must retain the same core `<leader>a` shortcuts and
  should open or refocus in terminal input mode.
- CodeCompanion Chat follows the selected provider through ACP. Inline and
  command prompts use the selected HTTP adapter. Keep these responsibilities
  distinct and keep `change_adapter` disabled for Chat.
- codecompanion-history stores the local transcript; continuing the agent's
  stateful ACP session is a separate `/resume` workflow. Preserve that
  distinction in implementation and documentation.
- CodeCompanion is an additional chat/inline workflow, not a second native
  terminal facade. Do not stack overlapping native integrations.
- Preserve the Claude tmux wrapper and watchdog unless a replacement is tested
  against terminal flicker, CJK rendering, cleanup, resume, and appended CLI
  arguments.
- Both tmux wrappers run the agent through `scripts/agent-run`, not directly.
  Their teardown (`exit-empty` plus the `client-detached` hook) makes the tmux
  client exit 0 however the pane's command ended, so nvim sees success and
  Snacks' `auto_close` closes the panel -- an agent that fails on startup
  otherwise just disappears, error and all. The launcher holds the pane on a
  non-zero exit so the agent's own diagnostics stay readable. Treat it as part
  of the pane command, not decoration.
- Both wrappers end their server through `scripts/agent-teardown` -- from the
  `client-detached` hook (`editor.teardown_hook`) and from the watchdog -- with
  `destroy-unattached off`. tmux only signals the pane's own process, so a bare
  `kill-server` left everything the agent had spawned into a process group of
  its own running with ppid 1 (a Codex `exec_command` dev server lived three
  days). The script records each pane's process tree before killing the server,
  then SIGTERMs and SIGKILLs the survivors, sparing shared daemons from the
  agent's children down (`NVIM_AGENT_TEARDOWN_IGNORE`). Keep
  `destroy-unattached` off: with it on, the server was gone before the hook ran
  and the hook was dead code.
- `<leader>ai` and the TUI's own `ctrl+g` are the same path: `$EDITOR` points at
  `scripts/agent-editor`, which brings the prompt into this Nvim. It needs
  `EDITOR`, `VISUAL` and `NVIM` in the agent terminal's environment, injected at
  creation time and forwarded explicitly through `new-session -e` under both tmux
  wrappers. Dropping any of them degrades silently to a nested Nvim inside
  `:terminal`, so treat them as part of the terminal command, not as decoration.

## Editing Conventions

- Preserve unrelated user changes and avoid destructive Git operations.
- Use Lua tables/list-form process APIs when possible. Shell fragments must
  escape user-controlled paths with `vim.fn.shellescape`.
- Lazy plugin setup belongs in `config`/`opts`, not an `init` callback that
  requires the plugin early. Add a command, key, event, or filetype trigger that
  matches the feature's first use.
- Keep mappings discoverable with a `desc`, and place them by *what the user is
  doing*, not by which plugin provides the feature. Five prefixes, each with a
  one-sentence meaning; a key belongs to exactly one of them:

  | Prefix | Question it answers | Examples |
  |--------|---------------------|----------|
  | `;` | "Which file/symbol/position do I want to be at?" (fuzzy search, no starting point) | `;f` find file, `;s` symbol, `;1`-`;9` harpoon |
  | `,` | "What do I do to the code in front of me?" | `,a` code action, `,f` format, `,j` move line |
  | `s` | "What about this window?" | `ss` split, `sd` close, `se` editor window |
  | `<localleader>` (`\`) | "What does *this filetype* offer?" | `\o` organize imports, VimTeX, diffview; `\1`-`\9` only in terminal buffers |
  | `<leader>` | Everything else, grouped by domain | `<leader>g` git, `<leader>d` debug |

  High frequency earns two keys, so anything reached constantly belongs on one
  of the first three rather than three keys deep under `<leader>`.
- LSP navigation that starts from the symbol under the cursor belongs on `g`,
  not on `;`: `gd`, `gr`, `gb` (implementation), `gy`, `gD`, `gC` (incoming
  calls) and `gK`. The dividing line is whether the key needs a symbol to start
  from -- `;s`/`;S` fuzzy-search a symbol list and need no cursor context, so
  they stay on `;`. Mnemonic letters lose to builtins here: `gi`/`gI` are Vim's
  insert commands and `gc` is Nvim's comment operator, so implementation and
  incoming calls take free letters rather than displace them.
- Every mapping that requires a language server carries a `[LSP]` prefix in its
  `desc`. A which-key popup on `g` mixes LSP jumps with lexical motions like
  `gf` and `ge`; the prefix is what tells a reader which ones stop working when
  no server is attached.
- The buffer-local `gr` (References) sets `nowait`. Nvim 0.11's default
  `grr`/`gri`/`grt`/`gra`/`grn`/`grx` are longer candidates, so without it every
  `gr` press waits out `timeoutlen` before firing. The cost is that `gr*` takes
  no second key in an LSP buffer; that is acceptable only because each default
  has a shorter equivalent here -- `gb`, `gy`, `,a`, `,r`, and `,c` for codelens,
  which exists specifically to replace the unreachable `grx`. Adding a new
  `gr`-prefixed mapping, or removing one of those replacements, breaks this
  arrangement.
- `;` and `,` stay unmapped as bare keys, so the builtin repeat-f/t still runs
  after `timeoutlen`. Flash owns `f`/`F` in Normal and Visual only -- never
  operator-pending, where the builtin motions must survive so `df-` and `ct)`
  keep working.
- `<leader>` carries global semantics only, so which-key popups stay truthful
  everywhere. A buffer-local map may add a key inside an existing group, but
  never repurpose one that already means something else. Anything meaningful in
  only one filetype belongs on `<localleader>`, not in a global group.
- Standalone panels put view-local actions on single letters (quickfix, aerial,
  neotest). A multi-window view keeps one vocabulary across every buffer it
  owns, so diffview's own actions live on `<localleader>` in the diff windows
  and its file panel alike, and single letters there stay reserved for that
  panel's list operations. Only layout-fragile multi-window views (currently
  diffview) block the global prefixes, with `nowait` and a visible disabled
  hint.
- The debug view is the other multi-window view with a tabpage of its own, and
  it is deliberately the opposite case: its keys stay global. Debugging has an
  event stream, so `<leader>d` has to work from the editor tabpage too -- you
  set a breakpoint and step from the source you are editing, not only from
  inside the view. Nothing there blocks a global prefix.
- The tabline stays on (`always_show_bufferline`). bufferline's own toggle
  counts buffers and never tabpages, so more than one tabpage with at most
  one listed buffer hid the tabline and the `1`/`2` tabpage indicators with
  it -- while diffview, the view most likely to be in that second tabpage,
  disables the global prefixes. Re-enabling the toggle and overriding
  `showtabline` afterwards does not work: it re-runs from the tabline's own
  redraw and undoes the override on the next draw. Because it is permanent,
  an empty one must be invisible: bufferline's `fill` asks for a transparent
  background, but an unset background there inherits `TabLineFill`, which the
  colorscheme leaves opaque even under `transparent`. Both are cleared --
  `fill` in the bufferline spec, `TabLineFill` in `lua/plugin/ui/solarized.lua`
  -- and clearing only one puts the theme's teal band back across the top.
- Window sizing goes through `util.window.resize` and `toggle_zoom`, not
  `:resize` or `wincmd _` directly. edgy re-applies its panels' geometry on
  `WinResized` and every panel is winfix, so beside one a bare `:resize` is
  a no-op and `wincmd _` is undone a tick later. An edgy window's thickness
  (a left/right bar's width, a bottom bar's height) is the edgebar's own
  `size` and can only be grown through `Window:resize`, so shrinking goes
  through the edgebar. Never collapse panels with edgy's `hide` or
  `edgebar:close()` to make room: both drop a non-pinned window for good,
  and `open()` restores only pinned views, of which this config has none.
- The first tabpage stays a page the global prefixes work in
  (`util.window.protect_first_tab`, driven by `TabClosed` and
  `SessionLoadPost`). Views open after it on their own -- `tab split`
  inserts after the current tabpage -- so the guard only repairs the state
  where the pages in front of a view are gone. It keys on the view, not on
  window contents: diffview's diff windows hold ordinary file buffers, so
  every window-level check calls its tabpage editable while `;f` is mapped
  to a disabled hint throughout it. A new prefix-blocking view has to be
  added to `PREFIX_BLOCKING_FILETYPES`.
- Both paths that place a stopped frame -- nvim-dap's `switchbuf`
  (`util.dap.jump`) and nvim-dap-ui's `select_window` -- must stay scoped to the
  current tabpage. `usetab`, or anything else that hunts across tabpages, turns
  the debug view into something that steals focus from an editor tabpage on
  every step, which is more intrusive than the split layout it replaced.
- Do not force-delete ordinary buffers from terminal-specific mappings.
- Popup sections are declared as data in `lua/whichkey_spec.lua` (`sections`,
  keyed by prefix then suffix) and only read by `lua/plugin/editor/whichkey.lua`.
  Adding a key or a whole section is a data edit; no Lua in the plugin spec
  knows what "files" or "search" means. Match by key, never by `desc` text -- an
  earlier version matched description patterns, where a reworded `desc` silently
  changed a key's colour and position and every new pattern risked catching
  someone else's entry. Every prefix worth sectioning is declared: `;`, `g`,
  `,`, `[`/`]` (one table, mirrored), `<leader>` itself, and the `<leader>`
  groups with more than a screenful (`g`, `G`, `d`, `a`, `m`, `b`, `x`, `t`).
  In a sectioned popup, undeclared keys sort last under `others`, styled by
  `fallback_section` in the same data file. Even one remaining key gets this
  heading, so it never appears to belong to the preceding section. Explicit
  sections need at least two keys; do not invent a separate section for a
  group row such as `+Noice` or `+CodeCompanion` -- it can fall under `others`.
  Popups with no declared entries keep which-key's default layout.
  Sectioning sorts *before* which-key's groups-first rule; the other
  order lets an undeclared group row jump ahead of every heading.
- `s` is declared as a manual which-key trigger. Automatic triggers refuse
  every bare lowercase letter but `g` and `z` (`which-key/buf.lua`,
  `is_safe`), because a trigger on a letter makes that letter wait out
  'timeoutlen' before its builtin runs -- so the window prefix was the one
  prefix with no popup. Declaring it manually skips that check, and the
  builtin it defers is `s` = `cl`, already given up when windows took the
  key. Normal mode only: Visual `s` changes the selection.
- Key lookup goes through `keytrans(keycode(...))`, which is which-key's own
  normalisation (`util.lua`, `M.norm`). Do not call `keytrans` on a raw
  `nvim_get_keymap` lhs: that value is half-converted -- control keys are
  already the literal string `<C-A>` while a space is still a raw byte -- so
  keytrans alone turns `g<C-A>` into `g<lt>C-A>` and the lookup misses.
- which-key's own `group` is a sub-prefix (`<leader>g` + `l` = `<leader>gl`), so
  it cannot slice a single level. The `;` headings therefore come from replacing
  which-key's `View.sort` and inserting display-only rows: the popup body is a
  table whose rows *are* the items, and its render loop reads only `key`, `sep`,
  `icon`, `desc`, `group` and `icon_hl`. This is the only place here that
  depends on plugin internals. It is guarded (a renamed `sort` drops headings
  and colours, ordering still works through the supported `sort` option,
  nothing errors) and covered by `tests/whichkey_popup_spec.lua`, which also
  fails on a declared suffix that maps to nothing. It assumes the single-column
  `helix` preset: a multi-column preset would split a heading from its items.
- which-key keeps description-only spec entries in its own trie, so `maparg()`
  cannot see those. Entries with an RHS are created through `vim.keymap.set`
  after which-key's scheduled loader runs; assert those with `maparg()` after
  `VimEnter`, and assert description-only entries against `whichkey_spec`.
- Window commands should normally affect the current tab only. Be deliberate
  before using global APIs such as `nvim_list_wins()`.
- Neovim's built-in `gc`/`gcc` commenting is the default; do not reintroduce a
  comment plugin without a concrete missing capability.
- Add or remove plugins through lazy.nvim specs and include the resulting
  `lazy-lock.json` change. Update the lock from a Claude-provider Nvim: a Codex
  process has no `claudecode.nvim` spec, so lazy prunes that line from the lock.

## Documentation

- `README.md` / `README_CN.md` are the quick start: what this is, how to install
  it, what is in it, and a keymap summary. Keep the two behaviorally
  synchronized.
- `docs/MANUAL.md` / `docs/MANUAL_CN.md` is the long-form guide for someone new
  to Vim or to this config: the prefix model, then each workflow end to end.
  Detail belongs there rather than growing the README.
- Update `docs/DIAGNOSTICS.md` when dependency, health, provider, formatter, or
  troubleshooting behavior changes.
- Update `docs/UTILITIES.md` when a public utility contract changes.
- Document actual mappings and dependencies, not planned behavior.

## Validation

Run checks proportional to the change. At minimum, verify both providers and
the working-tree whitespace check:

```sh
./tests/run.sh
NVIM_AI_PROVIDER=claude nvim --headless -u init.lua -i NONE +qa
NVIM_AI_PROVIDER=codex CODEX_HOME="$HOME/.codex-oauth" nvim --headless -u init.lua -i NONE +qa
git diff --check
```

`tests/*_spec.lua` run against the real configuration (`-u init.lua`), so they
catch what a startup check cannot. Each spec exits through `cquit`: a plain
`-c qa` returns 0 even after an uncaught Lua error, which would make a broken
spec read as a passing one.

For CodeCompanion changes, load it under both providers and confirm the resolved
ACP adapter plus `:CodeCompanionHistory`. For formatting changes, trigger
`BufWritePre` before checking Conform. For keymap, terminal, window, or deletion
changes, reproduce the exact edge case rather than relying only on startup.

Use `:checkhealth config` as the config-specific dependency check and
`:ConformInfo`, `:checkhealth vim.lsp`, `:Mason`, and `:Lazy profile` as the
primary diagnostic sources. Do not reach for `:LspInfo` — nvim-lspconfig stops
defining the `Lsp*` commands once Nvim 0.12's builtin `:lsp` exists.

## Code Review Rules

- Flag provider behavior that works for Claude but not Codex, or vice versa.
- Flag force deletion, cross-tab window mutation, unescaped shell paths, and
  lazy specs that load a plugin earlier than their declared trigger.
- Flag README/README_CN claims that disagree with the active Lua configuration.
