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
- Keep mappings discoverable with a `desc` and within the existing leader group.
  Do not force-delete ordinary buffers from terminal-specific mappings.
- `<leader>` carries global semantics only, so which-key popups stay truthful
  everywhere. Buffer-local leader maps may add keys inside an existing group
  (e.g. `<leader>cR` for gopls) but never repurpose an existing key. Standalone
  panels put view-local actions on single letters (quickfix, aerial, neotest);
  real file-editing contexts use `<localleader>` (VimTeX). A multi-window view
  keeps one vocabulary across every buffer it owns, so diffview's own actions
  live on `<localleader>` in the diff windows and its file panel alike, and
  single letters there stay reserved for that panel's list operations. Only
  layout-fragile multi-window views (currently diffview) block the global file
  openers, with `nowait` and a visible disabled hint.
- Window commands should normally affect the current tab only. Be deliberate
  before using global APIs such as `nvim_list_wins()`.
- Neovim's built-in `gc`/`gcc` commenting is the default; do not reintroduce a
  comment plugin without a concrete missing capability.
- Add or remove plugins through lazy.nvim specs and include the resulting
  `lazy-lock.json` change.

## Documentation

- Keep `README.md` and `README_CN.md` behaviorally synchronized.
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
