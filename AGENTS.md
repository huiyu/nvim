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
  Their teardown (`exit-empty` plus the `client-detached -> kill-server` hook)
  makes the tmux client exit 0 however the pane's command ended, so nvim sees
  success and Snacks' `auto_close` closes the panel -- an agent that fails on
  startup otherwise just disappears, error and all. The launcher holds the pane
  on a non-zero exit so the agent's own diagnostics stay readable. Treat it as
  part of the pane command, not decoration.
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
  | `;` | "Which file/symbol/position do I want to be at?" | `;f` find file, `;s` symbol, `;1`-`;9` harpoon |
  | `,` | "What do I do to the code in front of me?" | `,a` code action, `,f` format, `,j` move line |
  | `s` | "What about this window?" | `ss` split, `sd` close, `se` editor window |
  | `<localleader>` (`\`) | "What does *this filetype* offer?" | `\o` organize imports, VimTeX, diffview |
  | `<leader>` | Everything else, grouped by domain | `<leader>g` git, `<leader>d` debug |

  High frequency earns two keys, so anything reached constantly belongs on one
  of the first three rather than three keys deep under `<leader>`.
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
- Do not force-delete ordinary buffers from terminal-specific mappings.
- which-key registers spec entries in its own trie and never calls
  `vim.keymap.set`, so `maparg()` cannot see them. Assert against the
  `whichkey_spec` table instead when a test needs to check one.
- Window commands should normally affect the current tab only. Be deliberate
  before using global APIs such as `nvim_list_wins()`.
- Neovim's built-in `gc`/`gcc` commenting is the default; do not reintroduce a
  comment plugin without a concrete missing capability.
- Add or remove plugins through lazy.nvim specs and include the resulting
  `lazy-lock.json` change.

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
