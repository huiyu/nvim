# Diagnostics & Debugging Manual

How to diagnose problems with this Neovim configuration.

**Philosophy:** lean on Neovim's built-in tooling (`:checkhealth`, `:Lazy`,
`:LspInfo`, `--startuptime`) — it is more accurate and better maintained than
anything bespoke. The only config-specific gap (is *this setup* wired up — deps,
servers, versions?) is filled by a native health provider: `:checkhealth config`.

> History: a custom `util.dev` / `util.performance` / `util.validate` /
> `util.test` framework (`:Dev*` / `:Perf*`, ~1350 lines, gated behind
> `NVIM_DEV=1`) previously covered this. It duplicated the built-ins and was
> removed in favor of the table below.

## Quick reference

| Symptom | Use |
|---------|-----|
| Slow startup | `nvim --startuptime /tmp/st.log` · `:Lazy profile` |
| Plugin missing / errored | `:Lazy` (load times, errors, status) · `:Lazy log` |
| "Is my setup OK?" (deps/servers/version) | **`:checkhealth config`** |
| Anything broken (LSP/TS/providers) | `:checkhealth` |
| LSP not attaching / misbehaving | `:LspInfo` (`<leader>cl`) · `:LspLog` · `:checkhealth vim.lsp` |
| No completion | `:checkhealth blink` · verify LSP attached (`:LspInfo`) |
| No / wrong highlight | `:checkhealth nvim-treesitter` · `:InspectTree` · `:Inspect` |
| Formatting does nothing | `:checkhealth conform` · `:ConformInfo` |
| Mason tool missing | `:Mason` (`<leader>cm`) · `:checkhealth mason` |
| Error flashed by | `:messages` · `:Noice errors` |
| "Where did this keymap/option come from?" | `:verbose map <lhs>` · `:verbose set <opt>?` |
| Config won't load cleanly | headless self-check (below) |

## Startup performance

```sh
nvim --startuptime /tmp/st.log +qa && sort -k2 -n -r /tmp/st.log | head -20
```

`:Lazy profile` breaks down per-plugin load cost interactively. Most plugins are
lazy-loaded; the eager ones are treesitter (no lazy support on `main`), the
colorscheme, and snacks (dashboard).

## Plugins

`:Lazy` is the source of truth: load order, load time, and any spec/load errors.
`:Lazy log` shows recent updates. Plugin versions are pinned in `lazy-lock.json`;
the update checker runs silently once a day (`bootstrap.lua`).

## Health: `:checkhealth config`

`lua/config/health.lua` checks the things specific to this configuration:

- Neovim version floor (>= 0.11)
- External CLI tools on `PATH` (git, rg, fd, node, go, python3, cc, lazygit) and
  what each one is needed for
- A few key Mason packages

Run the full suite with plain `:checkhealth` (includes the above plus every
plugin's own checks).

## LSP

- `:LspInfo` (mapped to `<leader>cl`) — attached clients, root dir, capabilities
- `:LspLog` — server stderr / protocol log
- `:checkhealth vim.lsp` — client/server health
- Servers are declared per language in `lua/lang/*.lua` (`opts.servers`) and
  installed by mason-lspconfig (derived from that list). Verbose logging:
  `:lua vim.lsp.set_log_level("debug")`.

## Treesitter

- `:checkhealth nvim-treesitter` — installed parsers, ABI
- `:InspectTree` — the syntax tree for the current buffer
- `:Inspect` — highlight groups under the cursor
- Parsers: editor-core list in `plugin/ui/treesitter.lua`, language parsers in
  each `lua/lang/*.lua`. Missing ones auto-install on first open.

## Formatting & linting

- `:ConformInfo` — which formatter runs for this buffer and why
- `:checkhealth conform`
- Toggle autoformat: `<leader>uf` (global) / `<leader>uF` (buffer)

## Debugging (DAP)

- nvim-dap-ui opens automatically on session start (`<leader>dc`)
- Per-language adapters: Go (`nvim-dap-go`), Python (`nvim-dap-python`), JS/TS
  (`js-debug-adapter`), C (`codelldb`), Java (`nvim-jdtls`)
- Adapter binaries install via mason; confirm with `:Mason`

## Runtime errors & messages

- `:messages` — message history
- `:Noice` / `:Noice errors` — noice handles notifications (the snacks notifier
  is disabled); `<leader>n` opens history, `<leader>un` dismisses

## Inspecting keymaps & options

- `:verbose map <lhs>` / `:verbose nmap <lhs>` — where a mapping was set
- `:verbose set <option>?` — where an option was last set
- which-key popup (press a prefix and wait); `<leader>?` is the trigger cheatsheet

## Config self-check (headless)

Confirm the config loads with no errors — the same check used while developing it:

```sh
nvim --headless -u init.lua -c "lua print('errmsg=['..vim.v.errmsg..']')" +qa
```

A clean run prints `errmsg=[]` and no tracebacks.

## Environment variables

| Variable | Effect |
|----------|--------|
| `NVIM_LOG_LEVEL` | `util.logger` threshold (`DEBUG`/`INFO`/`WARN`/`ERROR`) |
| `NVIM_DEV=1` | `util.logger` defaults to `DEBUG` (more verbose) |
