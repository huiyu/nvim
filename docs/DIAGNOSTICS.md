# Diagnostics & Debugging Manual

How to diagnose problems with this Neovim configuration.

**Philosophy:** lean on Neovim's built-in tooling (`:checkhealth`, `:Lazy`,
`:lsp`, `--startuptime`) — it is more accurate and better maintained than
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
| LSP not attaching / misbehaving | `:checkhealth vim.lsp` (`<leader>cl`) · `:lsp restart` (`<leader>cL`) |
| No completion | `:checkhealth blink.cmp` · verify LSP attached (`:checkhealth vim.lsp`) |
| No / wrong highlight | `:checkhealth nvim-treesitter` · `:InspectTree` · `:Inspect` |
| Formatting does nothing | `:ConformInfo` · then `:checkhealth conform` |
| CodeCompanion Chat fails | `:checkhealth config` · `:CodeCompanionChat` · `:messages` |
| GitHub picker/status fails | `gh auth status` · `:checkhealth config` · `:messages` |
| Mason tool missing | `:Mason` (`<leader>cm`) · `:checkhealth mason` |
| Error flashed by | `:messages` · `:Noice errors` |
| "Where did this keymap/option come from?" | `:verbose map <lhs>` · `:verbose set <opt>?` |
| Config won't load cleanly | headless self-check (below) |

## Startup performance

```sh
nvim --startuptime /tmp/st.log +qa && sort -k2 -n -r /tmp/st.log | head -20
```

`:Lazy profile` breaks down per-plugin load cost interactively and is the source
of truth for eager/lazy state. Some core UI and language infrastructure loads at
startup; the rest is event-, command-, key-, or filetype-triggered.

## Plugins

`:Lazy` is the source of truth: load order, load time, and any spec/load errors.
`:Lazy log` shows recent updates. Plugin versions are pinned in `lazy-lock.json`;
the update checker runs silently once a day (`bootstrap.lua`).

## Health: `:checkhealth config`

`lua/config/health.lua` checks the things specific to this configuration:

- Neovim version floor (>= 0.11)
- External CLI tools on `PATH` (git, gh, rg, fd, node, tmux, go, python3, cc, lazygit) and
  what each one is needed for
- Active AI provider, native CLI, selected ACP bridge, and optional
  CodeCompanion HTTP inline/command credentials
- Oversized LSP logs (warns above 10 MiB)
- A few key Mason packages

Run the full suite with plain `:checkhealth` (includes the above plus every
plugin's own checks).

## LSP

- `:checkhealth vim.lsp` (mapped to `<leader>cl`) — attached clients, root dir,
  capabilities
- `:lsp restart` (mapped to `<leader>cL`) — restart the servers attached to the
  current buffer
- `:lua vim.lsp.log.get_filename()` — path to the server stderr / protocol log
- Servers are declared per language in `lua/lang/*.lua` (`opts.servers`) and
  installed by mason-lspconfig (derived from that list). Verbose logging:
  `:lua vim.lsp.set_log_level("debug")`.

On Nvim 0.12 the `:Lsp*` commands are gone: nvim-lspconfig's plugin file returns
early once the builtin `:lsp` exists, so `:LspInfo`, `:LspLog` and `:LspRestart`
all raise `E492`. Use `:lsp enable|disable|restart|stop` and the checkhealth
above instead. Buffer-local server commands such as
`:LspClangdSwitchSourceHeader` are unaffected — they come from `vim.lsp.config`
`on_attach`, not that plugin file.

Empty results from a working server (reference search returns nothing for a
symbol that clearly has callers) usually means a stale server project graph, not
a stale buffer. The two are distinguishable: buffers reload themselves and say
so — `checktime` runs on `CursorHold`/`BufEnter` among others, and a reload
prints `File changed on disk -- buffer reloaded`. Without that notification the
buffer was never behind, so the server is. Server state survives `checktime`, so
restart it with `<leader>cL`. Structural refactors trigger this: files moved
across packages, a new `tsconfig.json`/`package.json` root, or re-linked
workspace symlinks after a dependency install — project discovery does not
reliably pick those up. In Go buffers prefer `<leader>cR`, which also clears the
gopls cache before restarting.

If the log has grown large, inspect its path with
`:lua print(vim.lsp.log.get_filename())`. After finishing diagnosis, restart
Neovim and truncate that file rather than leaving debug logging enabled.

## Treesitter

- `:checkhealth nvim-treesitter` — installed parsers, ABI
- `:InspectTree` — the syntax tree for the current buffer
- `:Inspect` — highlight groups under the cursor
- Parsers: editor-core list in `plugin/ui/treesitter.lua`, language parsers in
  each `lua/lang/*.lua`. Missing ones auto-install on first open.

## Formatting & linting

- `:ConformInfo` — which formatter runs for this buffer and why
- `:checkhealth conform` (run `:ConformInfo` first on a fresh process to load it)
- Toggle autoformat: `<leader>uf` (global) / `<leader>uF` (buffer)

## AI and CodeCompanion

- `:AIInfo` — resolved Native, ACP Chat, and HTTP Inline adapter
- `:checkhealth config` — native CLI plus `claude-agent-acp`/`codex-acp`
- `<leader>apc` — new ACP chat; `<leader>aph` / `:CodeCompanionHistory` —
  auto-saved history (also `gh` inside a chat)
- History restores the local transcript; use `/resume` in a fresh ACP chat to
  reload a stateful agent session.
- ACP Chat uses the selected agent login. Missing `ANTHROPIC_API_KEY` or
  `OPENAI_API_KEY` only disables HTTP Inline/command prompts.
- Native Claude and Codex TUIs use provider-specific tmux wrappers when tmux is
  installed. Set `CLAUDE_WRAP_TMUX=0` or `CODEX_WRAP_TMUX=0` for an A/B test.
- Native Codex uses `--yolo`, bypassing Codex approvals and its built-in
  sandbox. It also uses `--no-alt-screen` so its wrapper tmux retains the
  transcript. In terminal-input mode, the mouse wheel or `<PageUp>` enters tmux
  copy-mode; use `q` or `<Esc>` to return. Scroll keys pressed from
  terminal-Normal mode are forwarded to tmux automatically. With
  `CODEX_WRAP_TMUX=0`, leave terminal input first and use Nvim's normal scroll
  commands.
- Reinstall ACP bridges with
  `npm install -g @agentclientprotocol/claude-agent-acp @agentclientprotocol/codex-acp`.

### Transcript viewer (`<leader>at`, `<leader>aT`)

The viewer reads the CLI's own JSONL records, not the terminal:

| Provider | Location |
|----------|----------|
| Claude | `~/.claude/projects/<cwd-slug>/*.jsonl`, slug = cwd with `/` and `.` both replaced by `-` |
| Codex | `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`, matched on `session_meta.payload.cwd` |

Both formats are undocumented implementation details of tools that ship often,
so a CLI update changing them is the expected failure — and it shows up as an
empty or partial transcript, never as an error. The adapters skip records they do
not recognise by design, so a partial schema change degrades to missing entries
rather than a broken viewer.

- **"No transcript found"** — the project has no recorded session yet, or the
  path derivation is wrong. Check the directory the notification names against
  the table above.
- **Buffer opens but content is missing** — the record shapes changed. Compare a
  real file against the mapping in `lua/ai/transcript/<provider>.lua`:
  ```sh
  jq -r '.type' ~/.claude/projects/<slug>/<id>.jsonl | sort | uniq -c
  jq -r '.payload.type' ~/.codex/sessions/<date>/<file>.jsonl | sort | uniq -c
  ```
- **Folded "thinking" sections never appear** — expected. Neither CLI persists
  reasoning text: Claude writes `thinking` blocks whose text is an empty string,
  and Codex keeps its reasoning in `encrypted_content`. Empty thinking is
  skipped rather than rendered blank.
- **A very long transcript reports truncation** — the viewer retains the newest
  5000 entries and states how many were dropped in the header. This exists so a
  pathological file cannot stall the editor; realistic sessions parse in under
  20 ms.
- **`Decoration provider "win" … Invalid node type "…"`, repeating on every
  redraw** — a stale Treesitter parser, not a viewer bug. Transcripts contain
  fenced code in many languages, and the markdown parser injects a parser for
  each one, so any language whose compiled parser is older than its query file
  fails here first. Find it and reinstall:
  ```vim
  " every installed parser, checked against its own queries
  :lua local n=require("nvim-treesitter") for _,l in ipairs(n.get_installed()) do
  \   if pcall(vim.treesitter.language.inspect,l) then
  \     for _,k in ipairs({"highlights","injections","folds","indents"}) do
  \       local ok,e=pcall(vim.treesitter.query.get,l,k)
  \       if not ok then print(l.."/"..k..": "..tostring(e)) end end end end
  :lua require("nvim-treesitter").install({ "<lang>" }, { force = true })
  ```
  `ecma`, `jsx` and `html_tags` always report "No parser for language" and are
  not broken — they are shared query modules other languages inherit from, and
  nothing queries them directly.

### Composer (`<leader>ai`)

- **`:q` refuses to close** — intended. `buftype=acwrite` plus a modified buffer
  raises `E37` so a half-written prompt is not lost by reflex. Use `<C-d>` or
  `:wq` to send, `<C-c>` or `:q!` to discard.
- **`<C-s>` does nothing anywhere in Nvim** — expected. `C-s` is the tmux prefix
  here (`~/.config/tmux/tmux.conf`), so tmux consumes it before Nvim can see it.
  A global `<C-s>` "Save file" mapping used to live in `lua/mappings.lua` and had
  never once fired; it was removed rather than left as a key that silently does
  nothing — use `:w`. Nvim's own Insert-mode default on that key,
  `i_CTRL-S` for `vim.lsp.buf.signature_help()`, is unreachable for the same
  reason; `gK` is the working path.
- **`<C-v>` says "No image on the clipboard"** — the clipboard holds text, not an
  image. Note that any yank or delete in the composer overwrites it, which is
  why an image is staged to a file the moment it is attached. Check with:
  ```sh
  osascript -e 'clipboard info'   # an image shows «class PNGf»
  ```
- **An attached image never reaches the agent** — attachment replays the TUI's
  own `ctrl+v`, so it depends on the agent still reading the clipboard on that
  key. Confirm by pressing `<C-v>` directly in the agent TUI; if that fails too,
  the CLI changed its binding.
- **Nothing was sent** — the buffer was blank, or it was never written. Only
  `BufWriteCmd` marks a draft for sending, which is what makes `:q!` an abort.
- **Send failed** — the draft is kept in memory; the next `<leader>ai` restores
  it. Delivery is asynchronous when the agent had to be started first.

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
NVIM_AI_PROVIDER=codex nvim --headless -u init.lua -i NONE +qa
```

A clean run prints `errmsg=[]` and no tracebacks.

## Environment variables

| Variable | Effect |
|----------|--------|
| `NVIM_AI_PROVIDER` | Select `claude` (default) or `codex` for Native AI, ACP Chat, and HTTP Inline |
| `NVIM_LOG_LEVEL` | `util.logger` threshold (`DEBUG`/`INFO`/`WARN`/`ERROR`) |
| `NVIM_DEV=1` | `util.logger` defaults to `DEBUG` (more verbose) |
