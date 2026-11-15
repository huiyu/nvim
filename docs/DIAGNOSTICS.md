# Diagnostics & Debugging Manual

How to diagnose problems with this Neovim configuration.

**Philosophy:** lean on Neovim's built-in tooling (`:checkhealth`, `:Lazy`,
`:lsp`, `--startuptime`) — it is more accurate and better maintained than
anything bespoke. The only config-specific gap (is *this setup* wired up — deps,
servers, versions?) is filled by a native health provider: `:checkhealth config`.

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
| `<leader>an` lists no backend, or an AI key acts somewhere unexpected | `:AI info` (open chats and where they are) · `:checkhealth config` (AI backends) · [AI and CodeCompanion](#ai-and-codecompanion) |
| No grey AI suggestions | `:checkhealth config` (inline completion) · `~/.local/state/nvim/llama/server.log` |
| GitHub picker/status fails | `gh auth status` · `:checkhealth config` · `<leader>mnh` (notification history) |
| A diff view (`<leader>gv`, `gm`, `gk`, …) errors or never opens | `:checkhealth config` (CodeDiff) · `:CodeDiff install!` · [Diff views](#diff-views-codediff) |
| `<leader>av` finds no round, or delivering feedback refuses | `:checkhealth config` (review) · `git for-each-ref refs/nvim-review/` · [Review rounds](#review-rounds-and-agent-hooks) |
| File search / terminal starts in an unexpected directory | `:pwd` · `:verbose pwd` · `:cd /path/to/project` |
| Mason tool missing | `:Mason` (`<leader>mm`) · `:checkhealth mason` |
| Error flashed by | `<leader>mnh` (every popup: plugin notifications and Vim's messages) · `:messages` / `g<` (Vim's own messages) |
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
first line of `init.lua` (lazy.nvim alone would only do it from its own setup
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
the update checker runs silently once a day (`lua/config/lazy.lua`).

## Health: `:checkhealth config`

`local-plugin/editor-core.nvim/lua/editor_core/health.lua` checks the things specific to this configuration:

- Neovim version floor (>= 0.12.5, refactoring.nvim's minimum)
- External CLI tools on `PATH` (git, gh, rg, fd, node, tmux, go, java, cargo, dart, flutter, python3, cc, lazygit, curl, and macism on macOS) and
  what each one is needed for
- The tree-sitter CLI and its version: nvim-treesitter's `main` builds every
  parser with `tree-sitter build`, so a missing CLI or one below its 0.26.1
  floor is an error — no parser can install or update
- The macOS Normal-mode input source and whether it came from
  `NVIM_ENGLISH_INPUT_SOURCE` or the system keyboard-layout fallback
- *config: AI backends*: the HTTP key profile; every native CLI, then every
  ACP bridge, that the providers of `lua/config/ai.lua` offer, in their order
  (a missing one is a warning: the new-chat picker leaves it out and the rest
  still work); every key profile's variable
  (`NVIM_ANTHROPIC_API_KEY` / `NVIM_OPENAI_API_KEY` by default; unset is a
  warning for the current profile, information for the rest); an error only
  when nothing at all is available -- no agent CLI, ACP bridge or API key; and
  a warning while a provider's own CLI variable (`ANTHROPIC_API_KEY` /
  `OPENAI_API_KEY`) is set
- Inline completion: `llama-server`, whether its model is in the Hugging Face
  cache (the server starts `--offline`, so a missing model is a failed start),
  and whether the shared server is answering
- Whether `local-plugin/agent-workbench.nvim/scripts/agent-editor` is executable. Both agent TUIs bind `ctrl+g` to
  "edit this prompt in `$EDITOR`", and that wrapper is what makes the prompt open
  in this Nvim rather than in a second one nested inside the `:terminal`. It
  degrades to the nested editor silently, so the check is a warning, not an
  error — `chmod +x` is the fix.
- *CodeDiff*: whether codediff.nvim is installed and is the release
  `local-plugin/git-review.nvim/lua/git_review/view.lua` was written against (4.0.6; another one turns its
  patches off); whether its native library is there and loads, and reports the
  plugin's version; the two `NO_AUTO_INSTALL` variables when set; and which
  file watcher the views would use — `CODEDIFF_WATCHER_PATH`, the downloaded
  one, or one on `PATH` — or that they poll instead. This check loads the
  plugin and its library to ask, and never downloads.
- *git*: its version. Review baselines need 2.26 or later.
- *Review hooks*: whether `local-plugin/agent-workbench.nvim/scripts/agent-hook` is executable and `nvim` is on
  `PATH` (the hook calls back with `nvim --server`); whether the
  `-c hooks=` value native Codex receives carries the hook, with Codex's trust hash checked against the command it
  covers; which `sources` are off. Static only: no agent is started, so
  whether the installed CLIs run the hooks is checked as the hook steps below
  describe.
- *Review baselines*, for the worktree of the working directory: how many
  round and saved baselines it has (and its worktree id); refs of worktrees
  that no longer exist, named by the root they were taken in, with the command
  that deletes them; refs CodeCompanion's own code review left under
  `refs/worktree/codecompanion/`, likewise; and where the feedback drafts are:
  how many still hold feedback (a non-empty file, which keeps its round from
  retention), how many last-sent copies, and any conflict files.
- *Review settings*: every `vim.g.ai_review` setting with the value in effect
  and whether it is the default or yours, and each one of yours that was not
  applied.
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
- Servers are declared per language in `lua/plugin/lang/*.lua` (`opts.servers`) and
  installed by mason-lspconfig (derived from that list). Verbose logging:
  `:lua vim.lsp.log.set_level("debug")`.

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

For TypeScript/JavaScript workspaces, `plugins/lang/typescript.lua` preloads projects
when vtsls first attaches. It recognizes a root `pnpm-workspace.yaml` or
`package.json` with `workspaces` (npm/Yarn), asynchronously finds visible,
non-ignored `tsconfig.json`/`jsconfig.json` files with `rg`, and registers them
with tsserver when at least two configs exist. Dependencies and common build
directories are excluded. Each config keeps its own compiler options; no
source buffers or config files are created. This lets `gr` find callers
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
- Parsers: editor-core list in `plugins/ui/treesitter.lua`, language parsers in
  each `lua/plugin/lang/*.lua`. Missing ones auto-install on first open.
- Every parser is compiled here, by the tree-sitter CLI (>= 0.26.1) and a C
  compiler; `:checkhealth config` reports the CLI's version. Without it, a new
  machine fails every install and `:TSUpdate` after a plugin update cannot
  rebuild. Install it from a package manager (`brew install tree-sitter-cli`),
  not npm. When nvim-treesitter raises that floor, raise `TREE_SITTER_MIN` in
  `local-plugin/editor-core.nvim/lua/editor_core/health.lua` and the version CI installs.

## Formatting & linting

- `:ConformInfo` — which formatter runs for this buffer and why
- `:checkhealth conform` (run `:ConformInfo` first on a fresh process to load it)
- Toggle autoformat: `<leader>uf` (current file) / `<leader>uF` (global)
- Java and Rust have no conform formatter: `lsp_format = "fallback"` hands
  them to the server (jdtls; rust-analyzer, which runs the toolchain's
  `rustfmt`, installed with `rustup component add rustfmt`). `:ConformInfo`
  lists them under LSP.

## Diff views (CodeDiff)

The `<leader>g` diff views and the review view are CodeDiff's
(`lua/plugin/git/codediff.lua`). `local-plugin/git-review.nvim/lua/git_review/view.lua` is the one module that
reaches into its internals, for the `,` keys, the `;`/`s` blocks, the tab
labels and the listing; its header lists what it depends on. Besides it, only
`:checkhealth config` (`local-plugin/editor-core.nvim/lua/editor_core/health.lua`) reads two values: the
library's version and the watcher release CodeDiff wants. for the `,` keys, the `;`/`s` blocks, the tab
labels and the listing; its header lists what it depends on.

- **The native library.** CodeDiff computes diffs in a C library,
  `libvscode_diff_<version>.dylib` (`.so` on Linux), kept in its plugin
  directory, `~/.local/share/nvim/lazy/codediff.nvim`, beside a file watcher,
  `codediff-watcher_<version>`. It downloads each from its GitHub release when
  first needed — the library when the plugin loads (the first `<leader>g` diff
  key or `:CodeDiff`), the watcher at the first view — and again after an
  update changes the version. That needs `curl` or `wget` and github.com.
  CodeDiff does not verify what it downloads; CI checks the library against
  the release's `SHA256SUMS` (`.github/workflows/tests.yml`).
- **`libvscode-diff not found and automatic installation failed`** — the
  download failed, and the error lists CodeDiff's own steps. `:CodeDiff
  install!` downloads it again. Offline, take
  `libvscode_diff_<os>_<arch>_<version>.<ext>` (for example
  `libvscode_diff_macos_arm64_4.0.6.dylib`) from the release matching the
  plugin's `VERSION` file and save it in the plugin directory as
  `libvscode_diff_<version>.<ext>`. `:checkhealth config` says whether the
  library is installed and which version it is.
- **Not downloading.** `VSCODE_DIFF_NO_AUTO_INSTALL` set to any non-empty value
  stops the library download (set but empty, it does not): a missing library
  is then an error when the plugin loads.
  `CODEDIFF_WATCHER_NO_AUTO_INSTALL=1` stops the watcher download, and the views
  poll the repository instead; `CODEDIFF_WATCHER_PATH` names a watcher binary
  of your own. `tests/run.sh` exports both `NO_AUTO_INSTALL` variables, so the
  spec suite never downloads, and `tests/codediff_spec.lua` fails with a
  pointer here when the library is missing. "Failed to install codediff-watcher;
  using polling fallback" means the watcher download failed and the views still
  work.
- **`CodeDiff X is not the 4.0.6 this config was written against`** — the
  plugin moved past the pin in `lazy-lock.json`. Plain CodeDiff still works
  (the upstream keys that could harm a review are off in the spec), but the
  revision listing, the non-ASCII path fix and the history limit are off.
  `:Lazy restore codediff.nvim` goes back to the pin; moving the pin (`commit` in
  `lua/plugin/git/codediff.lua`, then `VERSION` in `local-plugin/git-review.nvim/lua/git_review/view.lua`)
  means running `tests/codediff_spec.lua`, `tests/codediff_listing_spec.lua`
  and `tests/hunk_actions_spec.lua` against the new version first.
- **`CodeDiff's revision listing fell back to upstream's`** — the listing (below)
  failed once in this Nvim, for the reason in parentheses. Until a restart a
  revision view can show a path as both `D` and `??`.
- **A revision view lists something unexpected.** A view of a revision or a
  baseline against the working tree lists what the two trees differ in, taken
  from a snapshot of the working tree (the one the review baselines use): a
  file the revision tracks and the index does not shows as `M`, a plain `mv` as
  `R`. Ignored files never show, so an agent's edit to `.env` is not there. A
  path that is still on disk is never listed as deleted; such paths are named
  once per view in a `Not compared (…)` notice, by reason —
  `untracked, over 10 MiB; vim.g.ai_review.max_file_size`, `ignored, still on
  disk`, or `still on disk, so not listed as deleted` (an unreadable file, a
  directory where a file was, a case-only rename on macOS).
- **`<file>: unsaved changes here, and the file changed on disk since`** —
  CodeDiff never reloads a buffer you have modified, so the view shows your
  text, not the disk's. `:e!` takes the disk's version; `:w` keeps yours and
  overwrites the disk's.
- **`; is disabled in CodeDiff` / `s is disabled in CodeDiff`** — intended, in
  every window of a view: a `;` picker opens its file in the working-tree pane,
  which desynchronises the view, and `s` keys close or reshape panes. `gf` opens
  the file in the previous tab, `<C-w>` still moves between windows. A key
  typed right after the blocked one is swallowed with it, so `so` cannot fall
  through to `o`.
- **`H is disabled in CodeDiff`** (also `L`, `[b`, `]b`, `[B`, `]B`, `<C-^>`, `-`) —
  intended, in every window of a view: each puts another buffer in the window
  (bufferline's cycling and first / last, the alternate buffer, oil's parent
  directory), as a `;` picker would. `-` is blocked everywhere except the status view's file
  panel, where it stages or unstages a file. `gf` opens the file in the
  previous tab and `<leader>gq` closes the view. These are whole keys: the key
  typed after one is not swallowed.
- **`<file> cannot replace a CodeDiff pane`** — intended: `:e`, `:b`, `<C-o>`,
  a quickfix or location jump, `[o`/`[j` or an LSP jump tried to put another
  file in a pane or the file panel, and the view's buffer was put back (with
  its scroll position). `gf` opens the pane's file in the previous tab and
  `<leader>gq` closes the view. A swap under `:noautocmd` is not seen.
- **`The diff view lost a pane, so its tab was closed`** — closing one pane
  ends CodeDiff's session and leaves a dead tab behind; this config closes it.
  Use `gf` to edit the file.
- **`This tab already shows a CodeDiff view; <leader>gq closes it`** —
  `<leader>gv` in a CodeDiff tab: a bare `:CodeDiff` there would close the view
  instead.
- **`,S`/`,U`/`,X` refuse** — each says why (unsaved edits, the file changed on
  disk, the index differs from the view's left side, a symlink or LFS file, …)
  and changes nothing. [The manual](MANUAL.md#git) lists which view has which
  key. A stage that warns `the index did not come out as planned` ran while the
  index or the file changed; check the index in `<leader>gv`.
- **History stops at 100 commits** — `:CodeDiff history` without a range lists
  the newest 100 non-merge commits. `vim.g.ai_review.history_limit` changes
  that (`false` for all); a range, `:CodeDiff history origin/main..HEAD`, has
  no limit.
- **Only one diff pane follows the mouse wheel** — native Nvim ignores
  `scrollbind` when scrolling an unfocused window (see
  [scrollbind-quickadj](https://neovim.io/doc/user/scroll/#scrollbind-quickadj)).
  `local-plugin/git-review.nvim/lua/git_review/view.lua` maps the wheel in both panes to scroll in the hovered
  pane's context and restore focus, so filler and folds stay aligned; the file
  and history panels scroll on their own. Restart Nvim after updating.
## AI and CodeCompanion

This release enables native Codex only. Claude's CLI plugin, IDE proposal/diff
commands and Oil-specific actions are removed. Historical Claude transcripts and
baseline labels remain readable. Do not reinstall claudecode.nvim to satisfy an
old fixture or document; Claude protocol support is a later extension.

- **Inspect configuration.** User declarations are `config/ai.lua`,
  `config/review.lua`, `config/git.lua`, `config/keymaps.lua`; effective copied
  plugin options are `require("agent_workbench").options()`. `:AI info` /
  `:AIInfo` show provider order, transport/billing, availability, open chats,
  HTTP profile and CLI billing keys. `:checkhealth config` aggregates owner checks.
- **No backend is offered.** Native Codex needs its executable. ACP needs
  `codex-acp`; HTTP needs `NVIM_OPENAI_API_KEY`. Omitted provider parts are not
  offered. The ordered picker groups native/ACP/HTTP and hides unavailable
  entries. With no configured HTTP API, inline/cmd prompts refuse with a notice.
- **Selected terminal cannot open.** `terminal.provider` is native, Snacks, or a
  custom embedded provider. Snacks is required only when explicitly selected;
  missing adapters fail clearly with no fallback. The independent native path
  needs no Snacks. tmux wrapping is a separate preference. Check an unavailable
  executable, malformed provider contract or invalid cwd before changing UI code.
- **Which chat receives context?** The one visibly on the right of this tab;
  from CodeDiff, the origin tab. Otherwise a picker asks. ac/af may restore this
  tab's last hidden chat; delivery never silently selects one. Another tab's
  visible target is gone to with a notice; an unowned terminal copy here stays
  the target here. The owner elsewhere is not hidden. A last-normal-window
  refusal is deliberate; notification/preview floats do not make it closeable.
- **Agent not recognized / Edgy ignores it.** Identity is plugin-owned
  `vim.b[buf].agent_workbench`, not the Snacks command or object. The provider
  reports `on_buffer` before TermOpen and sets filetype `agent_terminal`. Raw
  test terminals must explicitly declare this metadata; a shell executable
  called codex is not automatically an agent panel. Statusline and Edgy use
  `session_of_buffer`, not terminal-provider internals.
- **Context/unsaved changes.** Saved Codex selections become file/range
  references. Unsaved selections send the exact selected text, with a notice.
  ab/native and ACP contexts read disk and warn about unsaved buffers; HTTP
  contexts carry buffer text. No context path presses Enter. Directory listings
  are unsupported in this release; use a file or actual code selection.
- **Resume/model changes seem ignored.** There is one native session. ar/aR/am
  focus/reuse a running one and explain the operation; they type no command
  into an existing draft/approval. Exit it before resuming another. am can submit
  /model only into a fresh session. Cold launches always use the editor file's
  root, even if an old exited terminal remains on screen.
- **HTTP billing/profile.** `NVIM_*` variables are HTTP keys. `OPENAI_API_KEY`
  belongs to the CLI and may override subscription billing; health/pickers warn.
  Codex ACP uses chat-gpt auth. A nonempty NVIM_AI_KEY_PROFILE wins over vim.g
  then config; auto resolves the first configured key that is set. AI key auto
  re-resolves. No key or provider choice persists or writes environment values.
  A profile switch changes inline/cmd adapters only; existing chats stay fixed.
- **Chat busy / draft not delivered.** Tool-loop intervals are still busy even
  when current_request is nil. Refusals retain drafts. Native delivery waits
  for the exact prompt editor consumption, with seed_ttl_ms expiry. A cancel or
  replaced seed keeps the draft. Use the review notices, not a successful keypress,
  as evidence of delivery.
- **History/resume.** codecompanion-history stores local conversation text;
  resuming a stateful ACP session with /resume is separate. CodeCompanion's own
  code review is disabled so it cannot create a second baseline system.
- **Rendering/scrolling/cleanup.** The Codex wrapper composes TUI synchronized
  updates in tmux; CODEX_WRAP_TMUX=0 gives a direct comparison. Renderer and
  terminal provider are independent. Keep EDITOR/VISUAL/NVIM forwarding,
  agent-run, agent-teardown, exit-empty and destroy-unattached off. A nonzero
  startup stays visible; stop/quitting cleans the owned server and descendants.
  A hide preserves the PTY. Follow exact buffer/session generation when debugging
  stale exit callbacks. Never kill shared daemons to clean a fixture.

Public native APIs/provider lifecycle and a minimal host example are documented
in [agent-workbench.nvim](../local-plugin/agent-workbench.nvim/README.md).

### Inline completion (ghost text)

minuet (`lua/plugin/ai/minuet.lua`) draws the grey suggestions; they come from
a local `llama-server` that `llama_service` starts on the first Insert in a
buffer that can show them, and that every Nvim shares. None of it depends on
the providers in `lua/config/ai.lua` or on the chat on the right.

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
- **Nothing until the first Insert has loaded the model.** The first Insert
  starts the server, and requests are held back for the few seconds it takes
  to load. Once it answers (`User LlamaReady`), the position the cursor waits
  at gets its suggestion without another keystroke; if none appears, check
  `:checkhealth config` as above.
- **Memory.** Loaded, the server shows ~8 GB resident, which is mostly the
  memory-mapped model file; its own footprint is ~0.6 GB. Asleep it is ~70 MB.
- **Lifecycle.** Each Nvim registers as `~/.local/state/nvim/llama/clients/<pid>`;
  the copy of `local-plugin/llama-service.nvim/scripts/llama-supervise` holding `lock/` runs the server and
  stops it about five seconds after the last registered Nvim is gone, crashed
  ones included. To stop it by hand, signal that copy:
  `kill "$(cat ~/.local/state/nvim/llama/lock/pid)"` (not `pkill -f`, which
  also hits any editor that has the script open). It stops within a few
  seconds, and the next Insert, or the next suggestion in any Nvim, starts it
  again: each request rechecks a server that has not been checked in five
  seconds.
- **Port.** The server listens on `127.0.0.1:8012`. If something else holds
  that port, the server cannot start, while whatever does answer there gets
  the requests; change `port` in `local-plugin/llama-service.nvim/lua/llama_service/init.lua`.
- **Updating the model.** `--offline` never fetches; `llama-server
  --fim-qwen-7b-default` without it checks Hugging Face for a newer revision.
- **Request-level detail.** `:lua require("minuet").config.notify = "debug"`
  makes minuet report every request and reply.

### Transcript viewer (`<leader>at`, `<leader>aT`)

The viewer reads the CLI's own JSONL records, not the terminal:

| Provider | Location |
|----------|----------|
| Claude (historical records only) | `~/.claude/projects/<cwd-slug>/*.jsonl`, slug = cwd with `/` and `.` both replaced by `-` |
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
  real file against the mapping in `local-plugin/agent-workbench.nvim/lua/agent_workbench/transcript/<provider>.lua`:
  ```sh
  jq -r '.type' ~/.claude/projects/<slug>/<id>.jsonl | sort | uniq -c
  jq -r '.payload.type' ~/.codex/sessions/<date>/<file>.jsonl | sort | uniq -c
  ```
- **A baseline in `<Space>gM` / `<Space>gk` shows no session name or end** —
  the labels read the same records (`agent_workbench.transcript.marks`): Claude's
  `ai-title` / `custom-title` and `turn_duration` records in
  `~/.claude/projects/*/<session>.jsonl`, Codex's `thread_name` in
  `~/.codex/session_index.jsonl` and `task_complete` / `turn_aborted` in its
  rollout (`$CLAUDE_CONFIG_DIR` / `$CODEX_HOME` when set). A round's session
  is its `Conversation` trailer (`git log -1 --format=%B <sha>`). No file
  there, a session with no title yet, or records taking longer than 300 ms to
  read the first time leave the label at its source and start; the next
  picker has what was read meanwhile. Codex compresses a rollout it has not
  touched for about ten days to `rollout-*.jsonl.zst` in place; its turns are
  read through `zstd -dc`, so without `zstd` on `PATH` those rounds show their
  name and start only (`brew install zstd`).
- **A round shows no `…` though its session is working** — `…` needs the
  session alive: its terminal running in this Nvim, or its records written in
  the last 30 minutes. A session in another Nvim on a long step that writes
  nothing (a long build) loses the `…` until it writes again.
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

### Prompt editor (`<leader>ai`, `ctrl+g`)

`agent-editor` is the CLI's $EDITOR and sends an RPC request into its originating
Nvim. `<leader>ai` and native ctrl+g follow this exact path. EDITOR, VISUAL and
NVIM must be injected at terminal creation and explicitly forwarded through
tmux new-session -e. Missing variables silently create a nested Nvim terminal.
The script resolves from the plugin package, so a separate checkout never calls
the original configuration's helper.

`<C-d>` saves/returns the draft, cancellation preserves the previous input.
`<C-v>` captures a clipboard image for this prompt and attaches through Codex's
own paste path after closing. Owner recognition uses `$CODEX_HOME/editor/*.md`;
a git-commit or other unowned editor request has a plain Prompt title and takes
no agent seed/image. Unsaved selection seeds are captured before any picker.

If Codex is mid-turn, it may not accept ctrl+g. Staged review text expires after
seed_ttl_ms and its draft stays intact. A plain compose that replaces a pending
review seed also keeps that draft. Never submit /model or an Enter into a running
box to recover an editor request; it may contain an approval or another draft.
The editor/feedback specs reproduce exact consumption, cancellation and timeout.

### Review rounds and agent hooks

Codex gets a per-process `-c hooks=...` UserPromptSubmit hook and matching trust
hash. The bundled agent-hook hands JSON to this Nvim over NVIM and waits for the
baseline up to hook_wait_ms. It never prints and always exits 0. User config,
notify and other hooks are preserved. CodeCompanion uses a submit callback.

1. Check `:checkhealth config`: bundled scripts executable, enabled source,
   injected command and trust hash. `/hooks` in Codex lists the hook under
   Session flags / Trusted. An upstream trust-key/hash change is diagnosed by
   `tests/agent_hook_spec.lua`, including its offline installed-CLI check.
2. Check the conversation root, fixed at native launch/chat creation. A prompt
   from another cwd still records the original root. `av` from another repo
   checks that repo; list refs with
   `git -C <repo> for-each-ref --format='%(refname) %(subject)' refs/nvim-review/`.
3. Only a native session started by this Nvim receives the hook. sources.codex
   and hook_wait_ms changes apply at next launch; disabling the source drops
   received events immediately. A shell CLI has no hook. Spawned threads with
   agent_id and repeated steers open no extra round.
4. Outside a Git worktree, in bare repositories, or with GIT_DIR/GIT_WORK_TREE
   set, snapshots are refused. Oversized untracked files and current ignored
   files are excluded before hashing.

**Late** means the snapshot outlasted the wait and could include the earliest
writes. **Missed a Codex prompt submit (Nvim was busy)** means the hook gave up
before delivery; no baseline is taken after the fact. `aV` captures one now.
A busy Nvim can drop the late RPC without a notice. Snapshot/receiver failures
show their reason on a new line and do not cancel the user's prompt.

A CLI override may make Codex report it is running without its shared background
server. Disabling sources.codex omits this hook override (other configured
native-plugin overrides may still require embedded mode). Never bypass trust
for every hook as a workaround.

Drafts live under `state/ai-review/<root hash>/`: `<id>.md`, `unowned.md`,
`<id>.last-sent.md`, and conflict copies for concurrent overlapping edits.
Root/owner headers are mandatory. Delivery checks root, exact session/chat,
busy state and explicit redirects in order; every refusal keeps the draft.
A pending nonempty draft exempts its round from retention. Default rounds are
20 in config.review; saved baselines 10, maximum file size and history limit
are Git policy in config.git. Legacy live Git overrides in vim.g.ai_review remain.
Claude-specific source/cwd options are removed. Historical Claude refs/labels
are readable without enabling a backend.

### What review baselines leave in a repository

Baselines never touch HEAD, the index, branches or the stash, and these are
the only traces:

- **Refs in every view of all refs.** About 30 parentless commits per worktree
  (20 rounds and 10 saved baselines, plus any round a draft keeps), with
  subjects such as `nvim review: Claude round 11:22:33` and
  `saved · before refactor`, show in `git log --all`, `gitk --all` and
  lazygit's all-branches graph. Leave them out with `--exclude`, which has to come
  before `--all`:
  ```sh
  git log --exclude='refs/nvim-review/*' --all --oneline --graph
  ```
  For lazygit, add the same option to the commands in `git.allBranchesLogCmds`
  in its `config.yml`. A baseline has no parent, so it never keeps old
  history alive.
- **Mirrors and `ls-remote`.** `git ls-remote <this repository>`,
  `git clone --mirror` and `git push --mirror` carry `refs/nvim-review/*`;
  `git push`, `--all` and `--tags` do not. A snapshot holds every untracked
  file `.gitignore` does not exclude — a `.env` missing from it included — so
  mind a mirror push.
- **A temporary index**, `nvim-review-index.XXXXXX` in the Git directory
  (`.git/`, or `.git/worktrees/<name>/` in a linked worktree), for the length of
  one snapshot. Each snapshot has its own; none is shared between Nvims.
- **No hooks, no locks.** These git calls run with `--no-optional-locks` and
  `core.hooksPath=/dev/null`: none of your hooks runs, and an agent's own
  `git add` or `commit` never waits on them. CodeDiff's own `git status`, like
  any `git status`, refreshes the index's cached file stats; its content does
  not change.
- **Worktrees that are gone.** After `git worktree remove`, that worktree's
  refs stay and keep their objects alive; nothing deletes them automatically.
  `:checkhealth config` names such ids by the `Root` they were taken in, and
  prints the command that deletes them. By hand, one worktree id's refs, or
  every worktree's:
  ```sh
  git for-each-ref --format='delete %(refname)' refs/nvim-review/<wtid>/ | git update-ref --stdin
  git for-each-ref --format='delete %(refname)' refs/nvim-review/ | git update-ref --stdin
  # The current worktree's id:
  printf %s "$(cd "$(git rev-parse --absolute-git-dir)" && pwd -P)" | shasum -a 256 | cut -c1-12
  ```
  Drafts in `~/.local/state/nvim/ai-review/` are not touched by this.
- **CodeCompanion's own review refs.** CodeCompanion's code review, which this
  config turns off so that there is one baseline system, kept its snapshots
  under `refs/worktree/codecompanion/`, one set per worktree. Nothing reads
  them any more; `:checkhealth config` counts them and gives the command, the
  same `for-each-ref … | git update-ref --stdin` with that prefix, run in each
  worktree.

## Debugging (DAP)

- nvim-dap-ui opens automatically on session start (`<leader>dc`); `<leader>du`
  reopens it. Panels close when the last root session ends.
- **Open tabpages are invisible / the `1`/`2` indicators are missing** -- the
  tabline is permanent (`showtabline = 2` in `local-plugin/editor-core.nvim/lua/editor_core/options.lua`, kept by
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
  `lua/plugin/coding/dap.lua` beside the `sign_define` calls that name it. A
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
JDK it exits with code 13 right after starting. `lua/plugin/lang/java.lua` takes the
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

`<leader>tM` / `<leader>tF` debug the nearest test / class. A missing debug bundle or setup
failure is reported instead of swallowed. After installing bundles, use
`:JdtRestart`.

- **`jdtls came up without its debug commands … restarting it`** — jdtls's
  first start on a fresh configuration area (right after Mason installs or
  updates `jdtls`, `java-debug-adapter` or `java-test`) races its own bundle
  loading and can answer `initialize` without the debug or test bundle's
  commands. It never lists them later, and every debug request then fails
  with `No LSP client found that supports vscode.java.resolveMainClass`. The
  bundles are installed by then, so `lua/plugin/lang/java.lua` restarts that client
  once and the second start has them. A second miss for the same project
  only warns: run `:JdtRestart`.

For project-import failures inspect `:checkhealth vim.lsp` and
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

The direct entries are `<leader>df` (file), `<leader>tM` (nearest test), and
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

### React Native

No React Native/Hermes DAP adapter is enabled in this configuration. Earlier
checks against `@react-native/dev-middleware@0.87.1` verified inspector target
discovery, the required WebSocket Origin header and message routing with a
synthetic device. They did not verify a real Hermes application's TSX source
breakpoints, source maps, stepping, reload/reconnect or DevTools coexistence.
Use React Native DevTools until that complete workflow has been verified.

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
- `<leader>tM` selects a `test`/`it` declaration using Treesitter and Vitest's
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
upstream. Install it and `plugins/lang/typescript.lua` picks it up automatically:

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
- Earlier checks paused an MV3 service worker through raw CDP. The extension
  configurations here use the `js-debug-webext` build described above to
  provide the DAP integration, source mapping and worker handling.
- mason-nvim-dap ships no adapter definition for js-debug, so `pwa-node` and
  `pwa-chrome` are registered in `lua/plugin/lang/typescript.lua`. Its `["js"]` handler
  only makes mason install the package.

## Runtime errors & messages

- **`;f` from Oil or a GitHub issue** — the file picker reuses an unmodified
  Oil or GitHub issue/PR window: confirming replaces the view with the file,
  cancelling keeps the layout. A view with pending edits stays visible and gets
  a separate file target, so no blank split appears.
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
- **A long link in agent output opens or yanks only up to the panel's edge**
  — Codex prints a link longer than the pane as one line and leaves the wrap
  to the terminal, so the rest continues in column 0 of the next row (on
  GitHub a `blob/<sha>` cut there redirects to `tree/<sha>`). A terminal
  buffer has one line per row and Nvim exposes no wrap flag.

  `gx` and every multi-row yank from a terminal buffer now treat a full row
  followed by text in column 0 as one wrapped line
  (`util.terminal_text.soft_wraps`). That covers `yi(`, `V…y`, `v…$y`, any
  register, the system clipboard and yanky's ring.

  These keep their newlines, because they fill a row on purpose:
  - rows the program indented;
  - frames and rules, `─│╭` or ASCII ones such as pytest's `====`;
  - progress bars (a tree's `└──` is no bar and still joins);
  - rows padded with blanks to the edge;
  - an emoji-led next row;
  - counters at the edge: tmux copy-mode's position, pytest -v's `[ 37%]`.

  Known limits:
  - A newline written at exactly the full width is joined like a wrap. So is
    a program's own unindented word wrap at exactly the width (rich,
    textwrap), which glues two words. A file path whose joined form does not
    exist falls back to its first row.
  - A one-row motion (`yiW`, `y$`) stops at the row's end, so use `yi(` or
    `V` there.
  - Blockwise and appending (`"A`) yanks are left as they were.
  - Rows that scrolled off before a resize keep their old width and are not
    joined.
  - A `:terminal` opened from a window with 'number' on keeps a narrower pty
    until the window is next resized, so its rows are not joined until then.

  tmux's own copy-mode selection (a mouse drag in terminal input) joins the
  rows the terminal wrapped, such as a Codex link, but not the ones a TUI
  wraps itself: Claude's classic renderer cuts a long line into separate rows
  and tells no one, so a long command copied from it keeps those breaks. Its
  `/copy` (or `/copy N`) copies the response as written, with a picker for
  each code block.
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
- **Where a message went** — Vim's own messages (`:echomsg`, `:echoerr`,
  errors such as `E492`, Lua `print()` and tracebacks) are in `:messages`
  (`<leader>mna`). Plain `:echo` is never kept there: only `g<`
  (`<leader>mnl`) shows it again, and only while it is still the last
  command's output. noice (`lua/plugin/ui/noice.lua`) shows both in a split,
  where `q` closes. noice also pops those messages up through the snacks
  notifier, where anything sent through `vim.notify` -- plugins, LSP
  `window/showMessage`, this config's own warnings -- goes directly. Its
  history (`<leader>mnh`, or `<leader>mnt` to search it) keeps every
  notification and each of Vim's errors and warnings, but Vim's ordinary
  messages (`:echo`, `:echomsg`, `print()`, `:!` output) share one *Messages*
  entry that the next one updates in place: `:messages` keeps the `:echomsg`
  and `print()` ones, while `:echo` and `:!` output are kept in neither.
  `:w`'s "written", `u`'s undo summary and `]q`'s "(2 of 9)" show small at the
  bottom right for two seconds and stay out of the notification history;
  `:messages` still has them. `<leader>un`
  dismisses. Under `--headless` neither noice nor the
  notifier is loaded -- noice waits for VeryLazy, which lazy.nvim fires on the
  first `UIEnter` -- so messages and `vim.notify` print to stderr as usual. A
  UI attached later (`nvim --headless --listen`, then `nvim --remote-ui`) gets
  both on its first `UIEnter`.
- **A message opens a split at the bottom** — noice sends a message of 20
  lines or more to a split instead of a popup (`long_message_to_split`). It
  does not take the cursor; `q` inside it, or `<leader>un`, closes it.
- **A notification line ends at the window's edge** — the snacks notifier
  makes its windows at most 40% of the screen wide and cuts a longer line
  there instead of wrapping it. `<leader>mnh` shows the whole text. This
  config's own review and diff-view notices are written as short lines for
  that reason, with paths and git's messages on lines of their own.
- **noice misbehaves** (a stuck popup, a cmdline drawn in the wrong place,
  messages that never show) — `:checkhealth noice` first: a GUI that draws
  its own cmdline or messages (`ext_cmdline`, `ext_messages`) and
  'lazyredraw' both break it. `:Noice disable` switches the running Nvim back
  to the builtin cmdline and message grid, `:Noice enable` back again. Do not
  also turn on Nvim's ui2 (`vim._core.ui2`): it takes over the same message
  grid. A message that never shows at all is one noice has no route for:
  Nvim 0.11+ gives messages kinds of their own (`:help ui-messages`), and
  noice drops a kind neither its defaults nor `routes` in
  `lua/plugin/ui/noice.lua` name. Add it there; `g<` still shows it meanwhile.
- **A pending `2d` or a Visual selection's size is not under the cursor's
  line** — noice skips 'showcmd', so it is in the statusline (`showcmdloc`,
  lualine's `%S`), to the left of the language servers.
- `K` on whitespace or a keyword stays quiet: hover runs with `silent = true`
  (`lua/plugin/coding/lsp.lua`), which drops both "No information available" and
  "Empty hover response". The hover and `gK` popups have a rounded border, and
  `<C-f>` / `<C-b>` scroll them from the code window. Only those two: with the
  diagnostic float from `]d` / `<leader>xd` open, the keys still page the
  buffer. Signature help while
  typing is blink.cmp's (`signature` in `lua/plugin/coding/cmp.lua`).
- LSP progress (indexing, workspace loading) is a spinner next to the server's
  name in the statusline (lualine's `lsp_status`); there is no progress
  message any more.
- **Color previews are missing** — `:ColorizerAttachToBuffer` reattaches the
  current buffer; `:ColorizerToggle` toggles previews. Hex/RGB/HSL and CSS
  variable references are enabled; variable definitions must be in the same
  buffer. Tailwind previews are limited to the frontend filetypes in
  `lua/plugin/lang/frontend.lua`; custom project colors also need an attached
  `tailwindcss` LSP (`:checkhealth vim.lsp`).
- **A file is missing from search** — `;i` / `;?` respect `.gitignore` and have
  no extra directory exclusions; `;f` / `;/` include ignored files but exclude
  common build/dependency directories. Choose the appropriate scope.
- **Zen mode** — `sz` toggles the current file's centered view. It leaves
  terminal/special buffers alone. Returning to a regular split exits zen mode;
  file edits remain in the original buffer. `scrolloff` is eight for editing
  and zero for terminals; keep `splitkeep=screen` for Edgy's layout handling.
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
- **A filetype or view section is missing from `,`** — check
  `:setlocal filetype? buftype?`, then `:verbose nmap ,v` (replace `,v` with the expected key).
  Headings classify existing mappings; they do not create actions. Python and
  LaTeX share `,v` with different meanings, and terminal digits require a terminal
  buffer in Normal mode. `[LSP]` entries require a server; use
  `:checkhealth vim.lsp` if those actions are unavailable. The
  [manual](MANUAL.md#filetype-and-view-actions) lists every filetype and view
  action.
  A CodeDiff view adds its panel, layout and conflict keys and the review keys
  (`,C`, and `,S`/`,U`/`,X` where the view can do them) beside the language
  section, and gives every key back on close. Section metadata lives in
  `lua/config/whichkey_spec.lua`; the rendering code in
  `lua/plugin/editor/whichkey.lua` reads it generically.
  grug-far's `,S` subgroup appears only inside its search-and-replace panel;
  open it with `,F`, then use `g?` to inspect its action mappings.
- **A popup row shows code instead of words** (`:<C-U>call
  <SNR>27_Python_jump(...)`, `vimtex-][)`, `vim.lsp.buf.references()`) — the
  mapping has no desc of its own. `:verbose nmap <lhs>` says who set it. A
  filetype plugin's motion gets its desc from `filetype_descs` in
  `lua/config/whichkey_spec.lua`, written onto the buffer's mapping on `FileType`;
  add the filetype and key there. Nvim's LSP defaults (`gO`, `gr*`) are
  described in `local-plugin/editor-core.nvim/lua/editor_core/keymaps.lua`.
- **A row shows a global label where the buffer means something else** (`]c`
  read "Next class start" in a diff view, `gO` "[LSP] Document symbols" in
  markdown) — a description-only `whichkey_spec` entry outranks every
  buffer-local desc. A key that some buffer remaps carries its desc on the
  global mapping instead (`tests/whichkey_popup_spec.lua` lists them). In a
  diff window `]c` reads "Next class start (diff: next hunk)"; in a CodeDiff
  view CodeDiff's own "Next hunk" shows.
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
nvim --headless -u init.lua -i NONE -c "lua print('errmsg=['..vim.v.errmsg..']')" +qa
```

A clean run prints `errmsg=[]` and no tracebacks. One startup covers every
provider: none is chosen at launch.

## Environment variables

| Variable | Effect |
|----------|--------|
| `NVIM_AI_PLUGIN_DIR` | Comma-separated plugin directories or host distribution roots for native Codex. It refreshes a local marketplace and enables plugins for that invocation, without changing global configuration. `config.ai.plugin_dirs` is the data-file alternative; CodeCompanion ACP/API plugin injection is deferred |
| `NVIM_AI_KEY_PROFILE` | Startup HTTP key profile (`auto` by default: the first profile in `lua/config/ai.lua` whose `NVIM_*` key is set, else the first); an unknown name warns and falls back to `auto`; `:AI key` switches it |
| `NVIM_ANTHROPIC_API_KEY` / `NVIM_OPENAI_API_KEY` | Key of the default `anthropic` / `openai` profile, and of CodeCompanion's built-in `anthropic` / `openai` adapters even when no provider lists them, for CodeCompanion API chat and Inline/command prompts; unset, those keys refuse instead of sending |
| `NVIM_ENGLISH_INPUT_SOURCE` | Override the macOS keyboard layout used in Normal and Terminal-Normal modes |
| `NVIM_MACISM_WAIT_TIME_MS` | Set macism's CJK workaround wait; `0` disables its temporary focus window |
| `NVIM_LOG_LEVEL` | `editor_core.logger` threshold (`DEBUG`/`INFO`/`WARN`/`ERROR`) |
| `NVIM_DEV=1` | `editor_core.logger` defaults to `DEBUG` (more verbose) |
| `VSCODE_DIFF_NO_AUTO_INSTALL` | Any non-empty value: CodeDiff never downloads its native library; a missing one is an error when the plugin loads. `tests/run.sh` sets it |
| `CODEDIFF_WATCHER_NO_AUTO_INSTALL=1` | CodeDiff never downloads its file watcher; the views poll instead. `tests/run.sh` sets it |
| `CODEDIFF_WATCHER_PATH` | A `codediff-watcher` binary to use instead of the downloaded one |
