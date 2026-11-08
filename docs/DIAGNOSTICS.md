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
| LSP not attaching / misbehaving | `:checkhealth vim.lsp` (`<leader>mi`) · `:lsp restart` (`<leader>mr`) |
| No completion | `:checkhealth blink.cmp` · verify LSP attached (`:checkhealth vim.lsp`) |
| No / wrong highlight | `:checkhealth nvim-treesitter` · `:checkhealth config` (tree-sitter CLI) · `:InspectTree` · `:Inspect` |
| Formatting does nothing | `:ConformInfo` · then `:checkhealth conform` |
| CodeCompanion chat refuses or fails | `:AI info` · `:checkhealth config` · `<leader>mnh` (notification history) |
| No grey AI suggestions | `:checkhealth config` (inline completion) · `~/.local/state/nvim/llama/server.log` |
| GitHub picker/status fails | `gh auth status` · `:checkhealth config` · `<leader>mnh` (notification history) |
| File search / terminal starts in an unexpected directory | `:pwd` · `:verbose pwd` · `:cd /path/to/project` |
| Mason tool missing | `:Mason` (`<leader>mm`) · `:checkhealth mason` |
| Error flashed by | `:messages` / `g<` (Vim's own messages) · `<leader>mnh` (plugin notifications) |
| "Where did this keymap/option come from?" | `:verbose map <lhs>` · `:verbose set <opt>?` |
| Config won't load cleanly | headless self-check (below) |

## Startup performance

```sh
nvim --startuptime /tmp/st.log +qa && sort -k2 -n -r /tmp/st.log | head -20
```

`:Lazy profile` breaks down per-plugin load cost interactively and is the source
of truth for eager/lazy state. Some core UI and language infrastructure loads at
startup; the rest is event-, command-, key-, or filetype-triggered.

Lua modules are byte-compiled and cached by `vim.loader`, switched on by the
first line of `init.lua` (lazy.nvim alone would only do it from its bootstrap
on). A cache entry is reused only while the file's size and modification time
are unchanged; `:lua vim.loader.reset()` clears it if a module ever seems to
run old code.

## Working directory

Opening a file sets cwd once at `VimEnter`: its nearest Git root, or its parent
outside Git. Worktrees and submodules use their own root; symlinks use the target.
Missing parents use the nearest existing ancestor. With several file arguments,
the first chooses cwd. Opening a directory uses it exactly; no arguments or
stdin keep the shell directory. Startup commands and sessions that have changed
cwd take precedence, and later buffer switches leave it alone.

Check `:pwd` (or `:verbose pwd` for global/tab/window scope) when `;f`, `;/`, a
terminal or a runner uses an unexpected project. Use `:cd /path/to/project` to
set it manually; `;F` and `;D` instead search from the current buffer's directory.

## Plugins

`:Lazy` is the source of truth: load order, load time, and any spec/load errors.
`:Lazy log` shows recent updates. Plugin versions are pinned in `lazy-lock.json`;
the update checker runs silently once a day (`bootstrap.lua`).

## Health: `:checkhealth config`

`lua/config/health.lua` checks the things specific to this configuration:

- Neovim version floor (>= 0.12.5, refactoring.nvim's minimum)
- External CLI tools on `PATH` (git, gh, rg, fd, node, tmux, go, python3, cc, lazygit, macism) and
  what each one is needed for
- The tree-sitter CLI and its version: nvim-treesitter's `main` builds every
  parser with `tree-sitter build`, so a missing CLI or one below its 0.26.1
  floor is an error — no parser can install or update
- The macOS Normal-mode input source and whether it came from
  `NVIM_ENGLISH_INPUT_SOURCE` or the system keyboard-layout fallback
- Active AI provider and HTTP key profile, and what each started as; both
  providers' native CLIs and ACP bridges (missing ones are an error for the
  active provider, a warning for the other); every key profile's variable
  (`NVIM_ANTHROPIC_API_KEY` / `NVIM_OPENAI_API_KEY`; unset is a warning for the
  active profile, information for the rest); and a warning while either CLI's
  own `ANTHROPIC_API_KEY` / `OPENAI_API_KEY` is set
- Inline completion: `llama-server`, whether its model is in the Hugging Face
  cache (the server starts `--offline`, so a missing model is a failed start),
  and whether the shared server is answering
- Whether `scripts/agent-editor` is executable. Both agent TUIs bind `ctrl+g` to
  "edit this prompt in `$EDITOR`", and that wrapper is what makes the prompt open
  in this Nvim rather than in a second one nested inside the `:terminal`. It
  degrades to the nested editor silently, so the check is a warning, not an
  error — `chmod +x` is the fix.
- Oversized LSP logs (warns above 10 MiB)
- A few key Mason packages

Run the full suite with plain `:checkhealth` (includes the above plus every
plugin's own checks).

### macOS input-source switching

- **A Chinese input method was selected while already in Normal mode** — press
  `<C-\>` or, outside `help`/`man`, `<C-]>`. Nvim stays in Normal mode, switches
  to its detected Latin layout, and restores the captured source on the next
  Insert only if that switch succeeded. Repeating the chord is harmless.
- **Ghostty's window chrome flashes when returning to input mode** — macism's
  default CJK workaround creates a temporary key window, so Ghostty briefly
  loses and regains focus. Set `NVIM_MACISM_WAIT_TIME_MS=0` before starting Nvim
  to skip that window.
- **The first Chinese characters arrive as English after disabling the flash** —
  the macism workaround was needed on this machine. Unset
  `NVIM_MACISM_WAIT_TIME_MS` (or set it to `150`) and restart Nvim to restore the
  reliable path.

## LSP

- `:checkhealth vim.lsp` (mapped to `<leader>mi`) — attached clients, root dir,
  capabilities
- `:lsp restart` (mapped to `<leader>mr`) — restart the servers attached to the
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

Empty reference results can mean a stale project graph or a consumer project
that has not been loaded. `checktime` refreshes buffers, not language-server
state. After files move across packages, workspace symlinks change, or project
configs are added, try `<leader>mr`. In Go buffers prefer `,G`, which also
clears the gopls cache before restarting.

For TypeScript/JavaScript workspaces, `lang/typescript.lua` preloads projects
when vtsls first attaches. It recognizes a root `pnpm-workspace.yaml` or
`package.json` with `workspaces` (npm/Yarn), asynchronously finds visible,
non-ignored `tsconfig.json`/`jsconfig.json` files with `rg`, and registers them
with tsserver when at least two configs exist. Dependencies and common build
directories are excluded. Each config keeps its own compiler options; no
source buffers or config files are created. This lets `gr` / `grr` find callers
in other packages without opening their files first. Loading more projects
uses more server memory, and references become available when loading finishes.

Preloading runs once per LSP client. After adding/removing projects, use
`<leader>mr` to restart the server and rescan. After editing the Neovim configuration
itself, restart Neovim first so the new callback is installed. A preload failure
is a notification (`<leader>mnh`). Projects outside those workspace roots, ignored
configs, and configs with custom names are not automatically discovered.
`gC` queries incoming calls, which still has tsserver project-scope limitations;
preloading does not make it equivalent to Find References.

If the log has grown large, inspect its path with
`:lua print(vim.lsp.log.get_filename())`. After finishing diagnosis, restart
Neovim and truncate that file rather than leaving debug logging enabled.

## Treesitter

- `:checkhealth nvim-treesitter` — installed parsers, ABI
- `:InspectTree` — the syntax tree for the current buffer
- `:Inspect` — highlight groups under the cursor
- Parsers: editor-core list in `plugin/ui/treesitter.lua`, language parsers in
  each `lua/lang/*.lua`. Missing ones auto-install on first open.
- Every parser is compiled here, by the tree-sitter CLI (>= 0.26.1) and a C
  compiler; `:checkhealth config` reports the CLI's version. Without it, a new
  machine fails every install and `:TSUpdate` after a plugin update cannot
  rebuild. Install it from a package manager (`brew install tree-sitter-cli`),
  not npm. When nvim-treesitter raises that floor, raise `TREE_SITTER_MIN` in
  `lua/config/health.lua` and the version CI installs.

## Formatting & linting

- `:ConformInfo` — which formatter runs for this buffer and why
- `:checkhealth conform` (run `:ConformInfo` first on a fresh process to load it)
- Toggle autoformat: `<leader>uf` (global) / `<leader>uF` (buffer)
- Java and Rust have no conform formatter: `lsp_format = "fallback"` hands
  them to the server (jdtls; rust-analyzer, which runs the toolchain's
  `rustfmt`, installed with `rustup component add rustfmt`). `:ConformInfo`
  lists them under LSP.

## AI and CodeCompanion

- **`nvim --claude` / `nvim --codex` reports an unknown option.** These are
  leading options of the Zsh `vi` launcher in `~/.config/zsh/functions.zsh`,
  not native Neovim flags: use `vi --claude` / `vi --codex`. Open a new shell
  after changing that file. In another shell, use
  `NVIM_AI_PROVIDER=claude nvim` or
  `NVIM_AI_PROVIDER=codex CODEX_HOME="$HOME/.codex" nvim`. Put native options
  after the provider flag, for example `vi --codex -c 'set number' file.lua`.
- `:AI info` (or `:AIInfo`) — active provider and key profile and what they
  started as, the resolved adapters (native CLI, agent chat over ACP, API chat
  and Inline over HTTP), whether each profile's variable and each CLI's own key
  variable is set (never the value), each native agent's state, and — once
  CodeCompanion is loaded — its chats per adapter. It loads no plugin to
  answer.
- `:AI provider` / `:AI key` (`<leader>ax`) switch in-process. A switch moves
  only what the *next* session uses: running agents, open chats and their
  adapters stay as they are.
- **The agent panel vanished after `:AI provider`.** It was hidden, not
  stopped: opening the active provider's panel hides the other agent's panel in
  that tabpage, and `<leader>ab` / `as` / `am` open it to deliver as well.
  `:AI info` lists it as *running, not shown here*; switch back and press
  `<leader>ac`.
- **The agent session is alive, but its panel disappeared after clicking a file
  tab.** bufferline's default `:buffer` ran in the focused panel; Snacks' window
  protection could close that window when no ordinary file window was available
  to receive the file. File-tab clicks now focus the current tabpage's editor
  area first, creating a split if needed, so Claude, Codex and chat panels stay
  visible. In an older running Nvim, `<leader>af` restores the native panel;
  restart Nvim to load the fix.
- **`<leader>aa` / `<leader>ad` are missing.** They answer Claude's diffs and
  exist while Claude is active or once claudecode.nvim has loaded. In a
  Codex-started Nvim that never used Claude there is no diff to answer.
- **The statusline shows `󰚩 … · 󰌆 …`.** Either setting differs from how this
  Nvim started; click it (or `<leader>ax`) to switch again. It disappears once
  both are back where they started.
- **API chat or inline prompts use the "wrong" key after a provider switch.**
  The key profile was pinned with `:AI key <name>`; `:AI key auto` makes it
  follow the provider again.
- `:checkhealth config` — native CLI plus `claude-agent-acp`/`codex-acp`
- Keys: `<leader>ag` / `<leader>aG` agent chat (ACP, the provider, on the
  subscription); `<leader>ah` / `<leader>aH` API chat (HTTP, the key profile,
  on API credits); `<leader>ae` inline; `<leader>ap` actions; `<leader>ao` /
  `:CodeCompanionHistory` auto-saved history (also `gh` inside a chat). The
  old `<leader>ap…` two-key forms are gone: `<leader>apc` now opens the action
  palette with `c` typed into its filter.
- History restores the local transcript; use `/resume` in a fresh agent chat
  to reload a stateful agent session.
- **`<leader>ah` / `aH` / `ae` say `NVIM_… is not set` and nothing opens.**
  The active key profile's variable is unset, so the request is refused before
  it is sent rather than answered with a 401. Set it as in
  [README → API keys](../README.md#api-keys) and restart Nvim from a new
  shell, or `:AI key <profile>` to one whose key is set (`:AI info` lists
  which). Agent chat is unaffected: it uses the agent's own login. A chat
  restored from history, the action palette (`<leader>ap`, whose *Inline
  prompt* runs on the key profile) and `:CodeCompanion` / `:CodeCompanionCmd`
  typed by hand skip this check and can still end in a 401.
- **`<leader>ag` / `aG` say `claude-agent-acp not found` (or `codex-acp`).**
  The active provider's ACP bridge is not on `PATH`; reinstall it (last item
  of this section). Codex's ACP adapter always uses the ChatGPT login,
  whichever provider started Nvim.
- **`<leader>ah` opened a different chat than the one on screen.** Each key
  reaches the chat of its own kind for the *current* provider or key profile;
  after `:AI key`, the previous profile's chat is still there under that
  profile. The reply header says which one you are in:
  `CodeCompanion (Claude Code · ACP)` or `CodeCompanion (Anthropic · API)`.
- **A warning says `Companion toggle fell back to :CodeCompanionChat Toggle`.**
  `lua/ai/companion.lua` reaches into CodeCompanion's chat internals, and an
  update changed one; the key used the upstream command instead, which only
  knows the last chat of either kind. The warning carries the error to fix.
- **Nvim refuses to start: `AI key profile "…" must read an NVIM_* variable`.**
  A `key_profiles` entry in `lua/ai/config.lua` names a CLI's own variable (or
  something not `NVIM_*`). Give it an `NVIM_*` variable of its own.
- **The agent bills the API although you have a subscription.** Check
  `:checkhealth config` for *ANTHROPIC_API_KEY is set* (or `OPENAI_API_KEY`).
  Those are the CLIs' own variables and can take precedence over the login;
  this config never needs them, so unset them in the shell that starts Nvim.
- Native Claude and Codex TUIs use provider-specific tmux wrappers when tmux is
  installed. Set `CLAUDE_WRAP_TMUX=0` or `CODEX_WRAP_TMUX=0` for an A/B test.
- Both wrappers keep tmux mouse support enabled for scrolling, but disable its
  pane menu on right-click and Alt-right-click.
- Quitting Nvim or closing the panel tears the wrapper server down through
  `scripts/agent-teardown`, which also ends the processes the agent spawned into
  their own groups (Codex `exec_command` sessions, background Bash jobs). If a
  dev server the agent started is still running after Nvim exits, check
  `~/.local/state/nvim/agent-teardown.log`; if something you wanted kept was
  killed, add it to `NVIM_AGENT_TEARDOWN_IGNORE` (awk regex; the default spares
  emulator/qemu, Gradle/Kotlin daemons, adb, OrbStack/Docker, CoreSimulator).
- Native Codex uses `--yolo`, bypassing Codex approvals and its built-in
  sandbox. It also uses `--no-alt-screen` so its wrapper tmux retains the
  transcript. In terminal-input mode, the mouse wheel or `<PageUp>` enters tmux
  copy-mode; use `q` or `<Esc>` to return. Leaving terminal input and entering
  it again through `i`, `a`, or any other input-mode transition also cancels
  copy-mode and follows the live bottom. Scroll keys pressed from
  terminal-Normal mode are forwarded to tmux automatically. With
  `CODEX_WRAP_TMUX=0`, leave terminal input first and use Nvim's normal scroll
  commands.
- **Text from an agent panel is left painted over the window to its left** —
  typically after scrolling the panel's history over Devanagari (Hindi i18n
  strings). Nvim gives every Devanagari grapheme cluster one cell, while
  Ghostty widens any cluster containing a spacing vowel sign (gc=Mc) or a
  virama conjunct to two cells (`grapheme-width-method = legacy` is no
  closer). The TUI does not reposition the cursor within a row, so the row
  drifts right, overflows the screen edge and wraps onto column 0 of the next
  row, where Nvim never redraws it. Return the panel to live output (`q` in
  copy-mode), then press `<leader>ur` (`:mode`); while the Devanagari rows are
  still on screen the repaint spills them again. `:redraw!` does not help:
  it re-sends only cells Nvim thinks changed. `<C-S-l>` and `<leader>md`
  repair the panel's own content, not these cells.
- Reinstall ACP bridges with
  `npm install -g @agentclientprotocol/claude-agent-acp @agentclientprotocol/codex-acp`.

### Inline completion (ghost text)

minuet (`lua/plugin/lsp/minuet.lua`) draws the grey suggestions; they come from
a local `llama-server` that `util.llama` starts on the first Insert in a
buffer that can show them, and that every Nvim shares. None of it depends on
`NVIM_AI_PROVIDER`.

- **No suggestions anywhere.** `:checkhealth config` → *inline completion*
  names the missing piece: `llama-server` itself (`brew install llama.cpp`) or
  its model (`llama-server --fim-qwen-7b-default` once, then Ctrl-C). Then
  `curl -s localhost:8012/health` should print `{"status":"ok"}`. A server that
  never comes up is reported once — *Inline completion is off: …* — with the
  log, `~/.local/state/nvim/llama/server.log` (rewritten at each start), and
  that Nvim does not try again, so restart it after the fix. A server that
  crashes after it has served is simply started again.
- **None in this buffer.** Only file buffers (`buftype` empty) whose filetype
  is known qualify — minuet turns suggestions on from the `FileType` event, so
  `:enew` and unrecognised files get none until `:setf` — and markdown, text,
  gitcommit and gitrebase are excluded. `:Minuet virtualtext toggle` turns them
  on or off for the current buffer, filetype or not; it cannot reach terminals,
  pickers or panels. Such buffers do not start the server either, and a
  headless Nvim (`--headless`, the spec suite) never starts it at all.
- **Slow.** Expect ~0.35 s per suggestion while typing along a line and
  ~0.8 s at a new position, plus ~0.5 s for the first one after five idle
  minutes, when the server has released the model. Several Nvims share the
  one slot, so requests from two editors at once queue.
- **Memory.** Loaded, the server shows ~8 GB resident, which is mostly the
  memory-mapped model file; its own footprint is ~0.6 GB. Asleep it is ~70 MB.
- **Lifecycle.** Each Nvim registers as `~/.local/state/nvim/llama/clients/<pid>`;
  the copy of `scripts/llama-supervise` holding `lock/` runs the server and
  stops it about five seconds after the last registered Nvim is gone, crashed
  ones included. To stop it by hand, signal that copy:
  `kill "$(cat ~/.local/state/nvim/llama/lock/pid)"` (not `pkill -f`, which
  also hits any editor that has the script open). It stops within a few
  seconds, and the next Insert, or the next suggestion in any Nvim, starts it
  again: each request rechecks a server that has not been checked in five
  seconds.
- **Port.** The server listens on `127.0.0.1:8012`. If something else holds
  that port, the server cannot start, while whatever does answer there gets
  the requests; change `port` in `lua/util/llama.lua`.
- **Updating the model.** `--offline` never fetches; `llama-server
  --fim-qwen-7b-default` without it checks Hugging Face for a newer revision.
- **Request-level detail.** `:lua require("minuet").config.notify = "debug"`
  makes minuet report every request and reply.

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
- **`ctrl+v` in the agent TUI attaches nothing** — the clipboard holds text, not
  an image. The agent CLIs read the clipboard themselves; Nvim is not involved.
  Check with:
  ```sh
  osascript -e 'clipboard info'   # an image shows «class PNGf»
  ```
- **The Claude pane clears while the prompt buffer is open** — expected, not a
  hang. The CLI clears the terminal before handing it to `$EDITOR`, the way
  `git commit` does, and this editor draws in a float instead of on that canvas.
  `scripts/agent-editor` prints a note into the cleared pane so it says what is
  happening; the TUI redraws itself when the prompt is returned.

  Neither `/tui` nor `CLAUDE_CODE_NO_FLICKER` changes this — measured blank with
  the env var set, unset, and on the `default` main-screen renderer alike, so it
  is the handoff and not the alternate screen. It is also specific to Claude
  Code: across the same edit its pane went 17 non-blank lines → 0 → 17, while
  Codex held at 18 → 18 → 18 and kept its TUI on screen throughout.
- **`<leader>ai` appears to do nothing** — the agent was not running. It starts
  the CLI and notifies instead of firing the keystroke, because a `ctrl+g` aimed
  at a TUI that is still booting is swallowed silently. Press `<leader>ai` again
  once the prompt appears.
- **The prompt opens in a second Nvim inside the terminal** — the `$EDITOR`
  handoff did not reach the pane, so the CLI fell back to running `nvim` itself.
  Check `:checkhealth config` for the wrapper, then inside the agent terminal:
  ```sh
  echo "$EDITOR"   # should be <config>/scripts/agent-editor
  echo "$NVIM"     # should be the host's RPC socket
  ```
  Under the tmux wrappers both are forwarded explicitly with `new-session -e`; a
  tmux pane does not inherit them otherwise.
- **The agent TUI stays blocked after the prompt buffer closes** — the wrapper
  waits on a sentinel file next to the CLI's temp `.md`. Every exit path writes
  it, including `VimLeavePre`, and the wrapper gives up on its own once the host
  stops answering RPC. A genuine hang means the buffer is still open somewhere —
  find it with `:ls` and close it.

## Debugging (DAP)

- nvim-dap-ui opens automatically on session start (`<leader>dc`); `<leader>du`
  reopens it. Panels close when the last root session ends.
- **Open tabpages are invisible / the `1`/`2` indicators are missing** -- the
  tabline is permanent (`showtabline = 2` in `lua/options.lua`, kept by
  `always_show_bufferline` in `lua/plugin/ui/bufferline.lua`). bufferline
  hides it on its own whenever
  it has at most one buffer to list, counting buffers only, so a diff opened
  with no files loaded used to take the tabpage indicators down with the
  buffer list.
- The debug view owns its own tabpage, opened by `util.dap.open_panels` and
  closed with the last root session. `<leader>du` hides and restores it. A
  tabpage left behind means `close_panels` could not close it -- it refuses on
  the last remaining tabpage, since `tabclose` would fail there.
- edgy places the debug panels (`lua/plugin/editor/edgy.lua`): scopes,
  breakpoints, stacks and watches on the left, `dap-repl` and `dapui_console`
  along the bottom with the terminal and quickfix. dapui still opens and
  closes them; only placement moved. A panel appearing in the wrong place
  means its filetype is not declared there -- dapui names every element
  separately and there is no `dapui` filetype.
- **The stopped line is not highlighted** -- `DapStoppedLine` is defined in
  `lua/plugin/lsp/dap.lua` beside the `sign_define` calls that name it. A
  sign naming a highlight group nothing creates fails silently: the sign
  places, the `linehl` does nothing, and only the gutter arrow marks the
  pause. `tests/dap_actions_spec.lua` asserts every dap sign's `texthl`,
  `linehl` and `numhl` resolve.
- **A stack frame opens over a panel, or dapui asks which window to use** --
  two different paths place a frame, and both go through
  `util.window.ensure_editor_win`. Stopping at a breakpoint uses
  `dap.defaults.fallback.switchbuf`, set to `util.dap.jump`; opening a frame
  from the Stacks panel uses dapui's `select_window`. Both are scoped to the
  current tabpage, which is what keeps stepping from the editor tab in the
  editor tab. nvim-dap's own `uselast` default would use the previously
  focused window, usually a panel in this layout.
- Per-language adapters: Go (`nvim-dap-go`), Python (`nvim-dap-python`), JS/TS
  (`js-debug-adapter`), C/Rust (`codelldb`), Java (`nvim-jdtls`), Dart/Flutter (SDK DAP)
- Mason supplies the adapters except Dart/Flutter, which use the installed SDK.
- `<leader>dA` / `:DapAttach` selects only attach configurations, including
  project `.vscode/launch.json` entries. Check `:pwd` if project entries are
  missing; use `:cd` to choose the project. The command starts a new session,
  so it also works when another session is paused. Use a source buffer of the
  matching language; wait for jdtls in Java.
- `<leader>de` chooses exception filters advertised by the active adapter;
  `<leader>dL` creates a logpoint with `{expression}` interpolation.
- `<leader>dw` evaluates a cursor expression or character/line/block selection;
  `<leader>dW` adds an editable watch expression.
- `<leader>dR` restarts; `<leader>dD` disconnects with `terminateDebuggee=false`.
  Both resolve the root of the current session tree first. Use `<leader>ds` to
  select a session when debugging multiple, independent processes.
- **`<leader>dt`, `<leader>dR` or `<leader>dD` appears to do nothing** — an
  adapter that owns several targets (js-debug with a browser, Electron) builds a
  session tree, and nvim-dap's `terminate()`, `restart()` and `disconnect()` all
  default to the current session alone, which is usually a child. All three
  mappings resolve the root first: `dt` passes `hierarchy = true`, `dR` selects
  the root before restarting, and `dD` walks the tree depth first. If panels still linger, sessions
  survive outside that tree: `:lua print(vim.tbl_count(require('dap').sessions()))`,
  then `<leader>ds` to select one, or `:lua require('dap').terminate({ all = true, hierarchy = true })`.

Complete terminal commands and per-language `launch.json` examples are in the
[English guide](MANUAL.md#launch-attach-and-project-configuration) and
[中文指南](MANUAL_CN.md#launchattach-与项目配置). For a connection failure, enable
`:lua require('dap').set_log_level('DEBUG')`, retry, and inspect `:DapShowLog`;
restore `INFO` afterward. Check the target is still running and the transport
matches the preset: JDWP, Node Inspector, Chrome CDP, debugpy, Delve and Dart VM
service endpoints are not interchangeable. A connected session with an unbound
breakpoint usually needs the matching source path, debug symbols or source maps.

### Python and native processes

Python attach requires debugpy in the **target's** interpreter environment, even
if Mason already supplies the editor's adapter. Start with `python -m debugpy
--listen 127.0.0.1:5678 --wait-for-client app.py`, then select
**python: attach to debugpy**. A normal Python process without a debugpy
listener cannot use this host/port preset. Use `pathMappings` when target and
editor paths differ.

C/C++ and Rust attach use CodeLLDB's PID picker. Compile with debug symbols and
keep the program running until attachment. `sourceMap` maps compiled paths to
local sources. If the OS refuses attachment, check its process-debugging
permission; native PID attach operates on the CodeLLDB host, not a remote PID
behind an SSH tunnel. The native integration spec checks C, C++ and Rust
breakpoints, variable evaluation and continued output after disconnect.

### Java

JDK 25+ runs jdtls: since 1.63 its bundles require Java 25, and on an older
JDK it exits with code 13 right after starting. `lua/lang/java.lua` takes the
first JDK 25+ among `$JAVA_HOME`, SDKMAN!'s `current`, the newest other
SDKMAN! candidate and the `java` on PATH, so the default JDK may stay older;
projects still build at the release level their build files set. Mason
installs `jdtls`, `java-debug-adapter`, and `java-test`.
`<leader>dc` discovers main classes after jdtls attaches. Inspect the live
`dap.adapters.java` and `dap.providers.configs.jdtls` then. The static Java list
contains **java: attach to JDWP**; launch main classes are discovered dynamically.
The server loads all Java test dependency bundles except the standalone test
runner and JaCoCo agent. Each project uses a hashed workspace under the Nvim
cache directory, and subsequent Java buffers attach to the existing client.

`,dt` / `,dT` debug the nearest test / class. A missing debug bundle or setup
failure is reported instead of swallowed. After installing bundles, use
`:JdtRestart`. For project-import failures inspect `:checkhealth vim.lsp` and
`:JdtShowLogs`. JDWP targets must start with `-agentlib:jdwp=...`; the default
attach endpoint is `127.0.0.1:5005`. Attach bypasses launch-only main-class/path
enrichment, so the source buffer need not have a main method. The real Java
integration spec checks launch plus an external JDWP process, source
breakpoints, local variables and continued execution after disconnect.

### Rust / Go

Rust's language server is Mason's `rust-analyzer`; Mason's `bin` comes first on
`PATH`. rustup also puts a `rust-analyzer` on `PATH`, a proxy that fails
unless that component was added or another `rust-analyzer` is on `PATH`, so a
`.rs` file opened before Mason finished its first install can report *Client
rust_analyzer quit with exit code 1*; `:e` the file once `:Mason` shows it
installed. Diagnostics come from
rust-analyzer as you type and from `cargo check` (source `rustc`) on save. On a
rustup toolchain rust-analyzer adds the `rust-src` component it needs for the
standard library by itself.

Rust's Cargo configurations build from the nearest manifest, parse Cargo's JSON
artifact messages and offer a target picker. Install Cargo and Mason's codelldb.
Custom target directories and hashed test binaries are resolved automatically;
compilation failures abort rather than launch stale artifacts. Complex Cargo
feature/workspace selections can use a project launch.json and explicit binary.

The direct entries are `<leader>df` (file), `<leader>td` (nearest test), and
`<leader>tF` (test file). Rust target discovery needs the `rust` Treesitter parser
(`:TSInstall rust`) and standard libtest executables. It matches source functions
to `--list` names and uses `--exact`; `#[path]`, generated tests and custom
harnesses should use `dc` with explicit arguments. Go/Python reuse neotest;
Python's selected environment needs pytest for pytest functions (otherwise
neotest-python can use unittest). A "No test found" message does not fall back
to a full-file run.

On macOS, native debugging can wait for a system authentication prompt for
`system.privilege.taskport.debug`. Complete that prompt locally before retrying
CodeLLDB/Delve. An adapter process that exists but never answers initialize is
not by itself evidence of a bad DAP configuration. The Rust and Go integration
specs require this OS permission as well as their toolchains.

Go remote attach uses a separate `go_remote` adapter with no executable: it
connects to `host`/`port` in the configuration, prompting for missing values,
leaving local `nvim-dap-go` behavior intact.
Start Delve headless with `--accept-multiclient`; forward the port for remote
hosts. Configure `substitutePath` in launch.json if source paths differ.
Delve's multi-client server preserves both the paused state and breakpoints
on disconnect. The `go_remote` adapter's `<leader>dD` clears this editor's source
breakpoints on the server, resumes the target, then disconnects. Local
breakpoints survive for reattachment. A failed preparation keeps the session
connected and reports the error. This is covered by the real heartbeat test.
See [Delve's disconnect behavior](https://github.com/go-delve/delve/blob/master/Documentation/api/dap/README.md#multi-client-mode).

### Dart / Flutter

Install the SDK externally. Adapters prefer the nearest `.fvm/flutter_sdk/bin`
then `dart` / `flutter` on PATH, and run `debug_adapter` (plus `--test` for tests).
No `dart-debug-adapter` Mason package is required. `:checkhealth config` checks
PATH tools; a warning can be ignored when the project uses FVM instead.

Run `pub get` first; select a running device from `flutter devices` for app
launch/attach. Default app entrypoint is `lib/main.dart`, rooted at the nearest
`pubspec.yaml`. Use project launch.json for flavors, tool arguments or VM service
URIs. **flutter: attach to running app** prompts for an optional VM service URI;
an empty answer uses device discovery. **dart: attach to VM service** requires
the full HTTP(S)/WS(S) service URI printed by a Dart process started with
`--enable-vm-service`; keep its token/path, not the DevTools webpage URL. If the
VM starts paused without a source frame, use `dc` to continue to your breakpoint.
`,dr` hot-reloads, `,dR` hot-restarts Flutter; save changes first.
CLI/test program paths match Neovim's canonical buffer names so symlink aliases
such as macOS `/tmp` versus `/private/tmp` do not prevent breakpoints binding.

The direct keys choose Flutter for a pubspec containing `sdk: flutter`, otherwise
Dart. Nearest-test discovery needs `:TSInstall dart` and a `test`/`testWidgets`
call at the cursor. It passes the declaration line as a
[package:test path query](https://github.com/dart-lang/test/blob/master/pkgs/test/README.md#test-path-queries),
so nested and generated test descriptions need no name escaping. Update the
project's test dependencies if the runner rejects `?line=`. The direct `df`
uses the current file; the application configuration in `dc` uses `lib/main.dart`.

### Electron

The combined configuration launches the project's Electron executable and
attaches `pwa-chrome` after a successful main-process launch. Port 9222 must be
free. Build TypeScript/bundles first; custom build tasks and source-map mappings
belong to launch.json. Separate main and renderer sessions appear in `<leader>ds`.
If the main process stops before the first BrowserWindow is ready, continue it
to let renderer initialization finish. When the main process is paused, Chromium
may also defer renderer CDP requests; resume main before inspecting the renderer.

For an existing app, start Electron with `--inspect=127.0.0.1:9230` and
`--remote-debugging-port=9222`. Use `dA` → **electron: attach main**, continue
until a window exists, then `dA` → **electron: attach renderer (port 9222)**.
The first endpoint is Node Inspector, the second Chrome CDP. Disconnect each
session separately; custom endpoints belong in separate launch.json entries.
Both sessions were verified against an external Electron process, including
source breakpoints, values and disconnect without terminating the app. With
Electron 44.4.2 and the installed js-debug build, `--inspect-brk` stalled attach
initialization without exposing a paused frame; the guide therefore uses
`--inspect`. Use the combined launch configuration for startup breakpoints.

React Native findings and the runnable inspector transport probe are in
[`spikes/react-native-dap`](../spikes/react-native-dap/README.md). The probe does
not claim Hermes breakpoint/source-map support.

### JavaScript / TypeScript

`<leader>dc` offers these general configurations on a js/ts/jsx/tsx buffer,
plus the Electron entries above and Chrome extension entries below:

| Configuration | Notes |
|---|---|
| `vitest: current file` | Launch the current buffer as a vitest run |
| `node: run current file` | Launch the current buffer with Node |
| `node: attach to process` | Pick a running Node process |
| `node: attach by host/port` | Inspector endpoint; defaults to `127.0.0.1:9229` |
| `chrome: attach (port 9222)` | Attach to an already-running Chrome |

- **"vitest is not installed in any node_modules above …"** — the launch walks up
  from the current file looking for `node_modules/vitest/vitest.mjs`, so a
  workspace package gets its own vitest rather than a hoisted copy. Install
  dependencies in that package.
- `<leader>td` selects a `test`/`it` declaration using Treesitter and Vitest's
  [file:line filter](https://vitest.dev/guide/filtering.html#line-numbers).
  This needs Vitest 3+ and the matching JS/TS parser. `<leader>tF` runs the
  current test file on older Vitest too. Both resolve the nearest installed
  `node_modules/vitest/vitest.mjs`; suite/group positions and custom wrappers
  are not treated as individual test cases.
- The vitest run passes `--no-file-parallelism`. Vitest otherwise isolates test
  files in worker threads, where an editor breakpoint never binds.
- Chrome attach needs Chrome started with `--remote-debugging-port=9222` **and**
  its own `--user-data-dir`; without the latter a second Chrome hands the URL to
  the running instance and never opens the port.
### Chrome extensions

Ordinary Chrome debugging works everywhere, mason's build included — the
`chrome: attach` entry is unaffected by any of this. What no stock js-debug
does is pause inside a browser **extension**: it attaches to `page` targets
only, so an extension's service worker is invisible to it.

That is a position, not a technical limit. Upstream closed browser-extension
support as `*out-of-scope`
([vscode-js-debug#945](https://github.com/microsoft/vscode-js-debug/issues/945))
while calling the fix itself trivial:

> We need to attach to browser-level frames and service workers, currently we
> filter and only attach to `page` types. **This is easy to fix.** […] I don't
> plan to support this in the foreseeable future.

So do not wait on it. #2361 has been open since May with no maintainer comment,
and VS Code ships the upstream build, which is why a shared `launch.json` can
carry every other configuration but not this one.

`huiyu/vscode-js-debug` carries the community PR
[#2361](https://github.com/microsoft/vscode-js-debug/pull/2361) on top of
upstream. Install it and `lang/typescript.lua` picks it up automatically:

```sh
mkdir -p ~/.local/share/nvim/js-debug-webext
curl -L https://github.com/huiyu/vscode-js-debug/releases/latest/download/js-debug-dap-webext.tar.gz \
  | tar -xz -C ~/.local/share/nvim/js-debug-webext
```

It is a superset, so ordinary page and Node debugging are unchanged; without it
you simply lose the extension configuration's ability to bind.

Then, per session:

1. Run the build watcher (`wxt` dev mode or equivalent). A plain production
   build emits no sourcemaps, so breakpoints will not bind against one.
2. `<leader>dc` → **chrome: debug extension (launch)**. The debugger starts its
   own Chrome, installs the extension and attaches; it also reloads the
   extension when the build output changes.

**chrome: debug extension (attach)** is for a browser you started yourself —
`--remote-debugging-port=9222` plus its own `--user-data-dir`, extension loaded
by hand. Useful against a specific profile or an already-running session; there
is no auto-reload on this path.

Point `extensionPath` at the **build output** directory, not the source tree —
an unpacked extension's id is a hash of that path, and the id is what every
sourcemap mapping is derived from. Nothing else needs configuring; a hand-set
`webRoot` only gets in the way.

- PR #2361 as written launches via `--load-extension`, which Chrome removed in
  137, so its launch mode installs nothing on a current browser. The fork
  installs over CDP (`Extensions.loadUnpacked`) instead — the same call the PR
  already uses for hot reload, just applied to the initial load. That fix is
  offered back as [noorez/vscode-js-debug#1](https://github.com/noorez/vscode-js-debug/pull/1);
  until it lands, launch mode works here and nowhere else.
- Nothing about Chrome or CDP prevents extension debugging — raw CDP pauses an
  MV3 service worker fine. The walls were js-debug's. See
  `spikes/chrome-extension-dap/` for the measurements and the upstream history.
- mason-nvim-dap ships no adapter definition for js-debug, so `pwa-node` and
  `pwa-chrome` are registered in `lua/lang/typescript.lua`. Its `["js"]` handler
  only makes mason install the package.

## Runtime errors & messages

- **`;f` leaves a blank split below Oil or a GitHub issue** — the file-target
  guard used to exclude these `acwrite` views and create a split as soon as the
  picker opened, even if it was cancelled. It now reuses an unmodified Oil or
  GitHub issue/PR window: confirming replaces the view with the file, cancelling
  keeps the layout. A view with pending edits stays visible and gets a separate
  file target.
- **GitHub issues show repeated `2`/`3` digits at the left** — these are native
  fold depth markers, visible even when all folds are open. The reading view
  disables line numbers but inherited the global one-column fold gutter. Its
  `gh.wo.foldcolumn` is now explicitly `"0"`, hiding the gutter while retaining
  folding. Restart Nvim to load the view configuration.
- **Selecting `env` in the buffer list makes the editor disappear** — `env`
  can be the agent's `term://.../env` buffer, not a file. Opening it in the
  editor duplicates the terminal there; edgy then treats both windows as AI
  panels and moves them to the right edge. The file buffer is still loaded.
  The tabline and buffer pickers now exclude terminals, including listed ones
  and the buffer picker's hidden entries. Restart Nvim to load the fix; focus
  the AI panel with `<leader>af`. To recover an affected layout first, leave
  terminal input with `jk` or `Ctrl-\`, then use `;f` to reopen your file in an
  editor window.
- **`gx` cannot open a local report path in agent output** — existing file
  references now open in Nvim, reusing an editor window in the current tab and
  preserving the terminal. Parenthesized paths can wrap across terminal rows;
  press `Ctrl-\` or `jk`, then `gx` on either part. Paths must exist on this
  machine; an incomplete path or a directory prefix alone is not opened.
- **`gx` opens only the first half of a terminal table URL** — the mapping now
  reconstructs parenthesized or angle-bracket links across up to 16 rows in the
  same column. Leave terminal input with `Ctrl-\` or `jk`, then press `gx` on
  either part. The closing delimiter must be present in the terminal buffer;
  if the TUI has truncated the link, use the complete URL in `<leader>at`.
- **Oil opens from an agent panel but focus stays in the TUI, and `q` hides the
  terminal** — Snacks protects terminal windows from buffer replacement. The
  `-` and `;o` mappings now focus an editor window in the current tab before
  opening Oil, creating a blank editor split if needed. Leave terminal input
  first with `Ctrl-\` or `jk`; plain `-` in terminal input still goes to the TUI.
- **Dashboard GitHub sections show "GitHub unavailable"** — the original `gh`
  error appears in that section without a job-error popup. `EOF` and
  `connection reset by peer` indicate a failed connection; if the address is
  `127.0.0.1:7890`, check the local proxy used by Nvim's inherited proxy
  environment. Retry `gh api 'notifications?per_page=5'`, `gh issue list -L 3`,
  or `gh pr list -L 3` in a terminal. For authentication errors, use
  `gh auth status`. Dashboard results, including an unavailable message, are
  cached for five minutes and retried when the dashboard is opened after expiry.
  These background commands run without interactive prompts or terminal probes.
- **A directory-scoped picker reports "Not a directory: term:…"** — `;F` and
  `;D` resolve a local directory with `util.cwd.buffer_dir()`: the file's parent,
  the displayed Oil directory, or the current window/tab cwd for terminals and
  other virtual buffers. Restart Nvim after updating to replace the old mappings.
- **Where a message went** — two places, not one. Vim's own messages
  (`:echomsg`, `:echoerr`, errors such as `E492`, Lua `print()` and
  tracebacks) are in `:messages` (`<leader>mna`). Plain `:echo` is never kept
  there: only `g<` (`<leader>mnl`) shows it again, and only while it is still
  the last command's output. Both show in ui2's pager window, where `q`
  closes. Anything sent through `vim.notify` --
  plugins, LSP `window/showMessage`, this config's own warnings -- goes to the
  snacks notifier instead and is only in its history: `<leader>mnh`, or
  `<leader>mnt` to search it. `<leader>un` / `<leader>mnd` dismiss. Under
  `--headless` neither ui2 nor the notifier is enabled, so `vim.notify` prints
  to stderr as usual. A UI attached later (`nvim --headless --listen`, then
  `nvim --remote-ui`) gets both on its first `UIEnter`.
- **A message shows only its first line, with `[+N]`** — ui2 collapses output
  taller than 'cmdheight'. Press `g<` to read it in full. A multi-line error is
  not expanded at all, so its traceback is only reachable through `g<` or
  `:messages`.
- **ui2 itself misbehaves** (a stuck message window, a cmdline drawn in the
  wrong place) — it is experimental. `:lua require("vim._core.ui2").enable({ enable = false })`
  switches the running Nvim back to the legacy message grid; to keep it off,
  remove the `ui2.enable` call in `lua/options.lua`. If a future Nvim
  moves the module, that call is skipped (it is pcall'd) and the legacy UI
  comes back on its own.
- `K` on whitespace or a keyword stays quiet: hover runs with `silent = true`
  (`lua/plugin/lsp/lsp.lua`), which drops both "No information available" and
  "Empty hover response". The hover and `gK` popups have a rounded border, and
  `<C-f>` / `<C-b>` scroll them from the code window. Only those two: with the
  diagnostic float from `]d` / `<leader>xd` open, the keys still page the
  buffer. Signature help while
  typing is blink.cmp's (`signature` in `lua/plugin/lsp/cmp.lua`).
- LSP progress (indexing, workspace loading) is a spinner next to the server's
  name in the statusline (lualine's `lsp_status`); there is no progress
  message any more.
- **Color previews are missing** — `:ColorizerAttachToBuffer` reattaches the
  current buffer; `:ColorizerToggle` toggles previews. Hex/RGB/HSL and CSS
  variable references are enabled; variable definitions must be in the same
  buffer. Tailwind previews are limited to the frontend filetypes in
  `lua/lang/frontend.lua`; custom project colors also need an attached
  `tailwindcss` LSP (`:checkhealth vim.lsp`).
- **A file is missing from search** — `;i` / `;?` respect `.gitignore` and have
  no extra directory exclusions; `;f` / `;/` include ignored files but exclude
  common build/dependency directories. Choose the appropriate scope.
- **Zen mode** — `sz` toggles the current file's centered view. It leaves
  terminal/special buffers alone. Returning to a regular split exits zen mode;
  file edits remain in the original buffer. `scrolloff` is eight for editing
  and zero for terminals; keep `splitkeep=screen` for Edgy's layout handling.
- **Only one Diffview pane follows the mouse wheel** — native Nvim ignores
  `scrollbind` when scrolling an unfocused window (see
  [scrollbind-quickadj](https://neovim.io/doc/user/scroll/#scrollbind-quickadj)).
  Diffview's buffer-local wheel mappings execute vertical scrolling in the
  hovered diff window's context and restore focus, keeping diff filler and
  folds aligned. File/history panels still scroll independently. Reopen
  Diffview after reloading its configuration, or restart Nvim after updating.
  Check `:setlocal diff? scrollbind?` in the content panes if they still drift.
- **A refactor key (`,ef`, `,ex`, `,i`, `,R`) errors with
  `attempt to call field 'wrap'`** — on Nvim 0.12 refactoring.nvim needs the
  async runtime from `lewis6991/async.nvim`, which
  `lua/plugin/editor/refactoring.lua` hands it as `vim.async`. Its own fallback, `require("async")`, returns promise-async's
  module once nvim-ufo has loaded, and that API has no `wrap`. After the first
  refactor, `:lua =vim.async ~= nil` should print `true`; `:Lazy` should list
  async.nvim as loaded. `,i` asks the language server for the definition and
  references; with no server attached it changes nothing, and the warning
  `method "textDocument/definition" is not supported` is followed by an
  `await callback was discarded` error (`:checkhealth vim.lsp`).
  `tests/refactoring_spec.lua` drives `,ex`, `,ef` and `,R` (its menu answered
  by a stub) against a real file, and `,i` as well when lua-language-server is
  installed; `,eF` is not exercised.
- **"Working directory … no longer exists; started in … instead"** — the shell's
  directory was deleted under it (a pruned worktree, a removed temp dir). Nvim
  moved to the nearest surviving ancestor, or `~`. Without this, Snacks'
  dashboard terminal sections crash on the nil cwd at `UIEnter`
  (`util.cwd`).

## Inspecting keymaps & options

- `:verbose map <lhs>` / `:verbose nmap <lhs>` — where a mapping was set
- `:verbose set <option>?` — where an option was last set
- which-key popup (press a prefix and wait); `<leader>?` is the trigger cheatsheet
- **Old backslash shortcuts stopped working** — `<localleader>` is now comma.
  Restart Nvim to remove old live mappings, then press `,` in the relevant file
  or view. Headings separate general editing from filetype and view actions.
  Conflict-free replacements include C/C++ `,H`, Markdown `,m`, LaTeX `,K`/`,E`
  and `,L…`, Diffview `,P`/`,B`/`,g…`, and search-panel actions under `,S…`.
  `[LSP]` entries still require a server;
  use `:checkhealth vim.lsp` if those actions are unavailable.
  The [manual](MANUAL.md#filetype-and-view-actions) lists every migrated action.
- **A filetype or view section is missing from `,`** — check
  `:setlocal filetype? buftype?`, then `:verbose nmap ,v` (replace `,v` with the expected key).
  Headings classify existing mappings; they do not create actions. Python and
  LaTeX share `,v` with different meanings, and terminal digits require a terminal
  buffer in Normal mode. Java's `,dt`/`,dT` also need jdtls/debug initialization.
  Diffview adds `,P`/`,B`/`,g…` beside the language section and removes those
  actions on close. Section metadata lives in `lua/whichkey_spec.lua`; the
  rendering code in `lua/plugin/editor/whichkey.lua` reads it generically.
  grug-far's `,S` subgroup appears only inside its search-and-replace panel;
  open it with `,F`, then use `g?` to inspect its action mappings.
- **Which-key hints stop appearing while mappings still work** — check for the
  red `● REC @…` statusline indicator, or run `:echo reg_recording()`. Which-key
  pauses its triggers during macro recording; if a register is shown, press
  `q` in Normal mode to stop recording and restore the hints.
- **A Ctrl chord works in bare Ghostty but not under tmux** — see what actually
  reaches the pane. Run this inside the tmux pane, press the chord, then `<C-c>`:

  ```sh
  printf '\e[>4;2m'; cat -v
  ```

  `^[[27;5;44~` means the chord arrived (here `<C-,>`); a bare character or a
  control byte means the terminal never encoded it. tmux only relays
  modifyOtherKeys, and Ghostty's legacy table pre-empts that for Ctrl+digit
  (Ctrl+1 is a bare `1`, Ctrl+3 is Esc, Ctrl+7 is `<C-_>`), which is why the
  terminal numbers use buffer-local `,1`-`,9` in terminal-Normal mode.
  From a file, use `3<C-/>` to select terminal 3. The comma digit mappings do
  not exist in ordinary files, even when a terminal is visible; restart Nvim
  after updating to remove the old mappings from a running session.
- **Shift+Enter submits instead of inserting a newline in an agent panel** —
  the wrapper tmux has to keep the modifier. Inside the pane, `$TMUX` already
  points at the wrapper, so:

  ```sh
  tmux show-options -s | grep extended-keys
  ```

  Expected `extended-keys always` and `extended-keys-format csi-u`. With
  tmux's default `off`, the `ESC[13;2u` that `<S-CR>` sends arrives as a bare
  CR; the `cat -v` probe above prints `^[[13;2u` when it gets through.

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
| `NVIM_AI_PROVIDER` | Startup provider, `claude` (default) or `codex`, for Native AI and agent chat; `:AI provider` switches it |
| `NVIM_AI_KEY_PROFILE` | Startup HTTP key profile (`auto` by default, following the provider); an unknown name warns and falls back to `auto`; `:AI key` switches it |
| `NVIM_ANTHROPIC_API_KEY` / `NVIM_OPENAI_API_KEY` | Key of the `anthropic` / `openai` profile, for CodeCompanion API chat and Inline/command prompts; unset, those keys refuse instead of sending |
| `NVIM_ENGLISH_INPUT_SOURCE` | Override the macOS keyboard layout used in Normal and Terminal-Normal modes |
| `NVIM_MACISM_WAIT_TIME_MS` | Set macism's CJK workaround wait; `0` disables its temporary focus window |
| `NVIM_LOG_LEVEL` | `util.logger` threshold (`DEBUG`/`INFO`/`WARN`/`ERROR`) |
| `NVIM_DEV=1` | `util.logger` defaults to `DEBUG` (more verbose) |
