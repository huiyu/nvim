# Repository Instructions

## Purpose

This is a personal Neovim configuration for Neovim 0.12.5+ written in Lua and
managed by lazy.nvim. Keep changes small, reversible, lazy-loaded where
practical, and consistent with the existing LazyVim-style key namespaces.

## Module Responsibilities

- Give each file one clear purpose and group code that changes for the same
  reason. File length and function count are not reasons to split it.
- Editable configuration declares values and overrides; runtime modules
  validate and resolve them and own live state. Startup modules and plugin
  specs wire features together instead of implementing unrelated workflows.
- Put behavior with its feature owner: native launch and teardown with the
  backends, review drafts with review, directory and terminal-text operations
  with their reusable utilities. Do not collect unrelated features under a
  plugin bundle's name or a generic `workflow` test.
- Preserve intentional aggregation: one language module owns its LSP,
  formatting, DAP and runners; health owns diagnostics; integration tests
  may exercise several modules to verify one shared contract or workflow.
- Keep each safety rule and upstream-internals boundary in one place. Small
  extractions should remove duplication and obsolete paths, not add forwarding
  layers, compatibility aliases or a new framework without a concrete need.
- Preserve observable behavior and lazy loading during responsibility changes.
  Review removed code against its callers, commands, hooks and tests; a
  documented or externally called API is not dead merely because Lua has no
  direct caller. Keep the documentation and tests aligned with the new owner.

## Architecture

- Runtime ownership has four categories: editable data/bootstrap in
  `lua/config/`, every lazy.nvim spec in `lua/plugin/`, cohesive runtime
  packages under `local-plugin/`, and small inert host helpers in `lua/util/`.
  Do not recreate legacy `lua/ai/`, `lua/git/` or `lua/plugins/` trees, nor
  compatibility forwarding aliases for the removed module names.
- Root `init.lua` first enables `vim.loader`, adds its checkout to rtp, then
  requires config. `config.init` recovers cwd, sets leaders from key data, and
  enters lazy.nvim. Cwd and leaders are the minimal bootstrap exceptions.
  `config.lazy` imports editor, coding, ai, ui, git, lang in that merge order;
  language modules own their LSP, formatting, DAP, parser and runner additions.
- A priority-10000, `lazy=false` editor-core spec calls `setup(opts)` to apply
  foundational values/keys/autocommands. The priority-9000 agent-workbench spec
  installs its cheap facade. Setup starts no agent, model, listener, baseline or
  plugin installer. Native providers, chats, review and views load on use.
  Other hosts may command/key-lazy-load the same local plugin normally.
- `config/options`, `behaviors`, `theme`, `formatting`, `keymaps`, `ai`, `review`,
  `git`, `completion`, `dashboard`, `whichkey_spec` return editable data.
  Values/overrides belong there; validation, state, compatibility constants and
  workflows belong to their runtime owner. Require of settings is inert.
- `local-plugin/editor-core.nvim` owns editor behavior, key application,
  windows/buffers, DAP/LSP helpers, errors/logging and dashboard rendering.
  `agent-workbench.nvim` owns Codex controllers, embedded terminal/session
  registry, prompt editing, routing, transcripts and review conversation logic.
  `git-review.nvim` owns snapshots/comparisons/CodeDiff. `llama-service.nvim`
  owns the local shared model lifecycle and bundled supervisor.
- Local plugins import no private host `config.*`/`util.*`. Pass host policies
  as options/callbacks; Git comparison accepts label/trailer/auxiliary-view
  callbacks, and editor terminal detection is injected by the host. A native
  agent host needs no lazy.nvim, CodeCompanion, Snacks or Git integration.
  The optional integrations are required only at their actual entry points.
- Baselines are implemented once in `git_review.baseline`; `git_review.view`
  is the CodeDiff internals boundary. AI round/delivery interpretation belongs
  to `agent_workbench.review`, not the storage layer. Scripts live in their
  owning package and resolve paths from source, not stdpath(config), so an
  isolated checkout/consumer executes its own scripts and lockfile.
- Shared key intent is data in config.keymaps. Core keyguide/keymaps install
  actual bindings without which-key; Oil/Snacks/Aerial translate supported
  open actions explicitly. Remove the competing old default on remap/disable;
  preserve Oil Visual block mode, Insert editing and terminal input. No
  universal key DSL or automatic conflict-resolution framework. Which-key
  receives display metadata only. The guide reads live maps/shared choices.
- `config.health` aggregates package-owned checks. Runtime ownership changes
  must preserve observable behavior and lazy loading; inspect commands,
  hooks, scripts, dynamic callers, docs and tests before removing an API.

## AI Provider Invariants

- This release enables native **Codex only**. No claudecode.nvim dependency,
  Claude backend, `:ClaudeCode`, `aa`/`ad` or Oil `aS` key exists. Native Claude
  IDE/proposal support is a later issue. Historical Claude transcript/label
  readers remain for old baselines; they do not enable a native backend.
- There is no default chat backend. `config.ai.providers` is ordered; each
  entry has unique name, label, optional cli_api_key, and one or more parts:
  `tui={kind="codex"}`, `acp={adapter,command,auth_method?}`, or
  `api={adapter,api_key,name?,label?,model?}`. Omitted parts are not offered.
  The shipped Codex entry offers native terminal, codex-acp with chat-gpt auth,
  and OpenAI HTTP with NVIM_OPENAI_API_KEY. A second HTTP key is another
  API-only provider. New native kinds need code and fixtures, not just config.
- Native options declare executable, argv and tmux preference. Keep the
  existing `--no-alt-screen --yolo` policy unless the user changes it.
  `terminal.provider` selects native (built in), Snacks (optional), or a custom
  embedded provider. An explicit missing provider fails, never falls back.
  External nonembedded terminals are unsupported in this release.
- Setup copies user data once; dictionaries partially override, ordered lists
  replace (including empty argv), false disables optional keys/integrations.
  `options()` is a copy; session state and HTTP key switches are separate live
  state. Env CODEX_WRAP_TMUX > vim.g.codex_wrap_tmux > setup preference.
- Session identity/generation belongs to terminal_provider and
  vim.b[buf].agent_workbench, never a Snacks object or command-name inference.
  Providers implement open/show/hide/send/alive/stop and report buffers before
  TermOpen, owned views, and exit through callbacks. Handles stay opaque.
  Exact send bytes never append Enter. Failed opens clean partial resources;
  stale-generation exits cannot remove replacement state. Nonzero startup
  exits keep diagnostics readable. Stop is explicit and idempotent.
- One AI window per tab: native Codex or a CodeCompanion chat. Showing one
  hides others through their own provider/UI hide, preserving sessions/buffers.
  Never use edgy hide/close or touch another tab. A terminal copy stays where
  it is, cannot hide the owner's other-tab window, and remains the target
  for deliveries here. Floats do not count toward last-normal-window safety.
  Hide first/show second unless that would leave E444; then show first.
- The BufWinEnter guard covers upstream chat/history/close-successor paths,
  captures the event's tab and ignores floats; latest entered AI window wins
  a tick. Chat-to-chat hands the window over in place; terminal transitions
  close/open their owned views, because Snacks fixes its terminal buffer.
- ac/af/ab/as/ai act on the chat on the right of this tab, or the CodeDiff
  origin tab via the injected origin callback. With none, ask among open chats
  and New chat; only ac/af may restore vim.t.ai_slot_last. an/al always ask.
  A chat visible elsewhere is gone to, never moved. Cancel returns to the
  source view. A delivery changing tab says so once. Never silently deliver
  to a hidden chat, another tab or the first provider.
- Capture a Visual selection through Neovim API before an asynchronous picker.
  Saved Codex context is a file/range reference; unsaved selection text is
  pasted exactly and announced. ab warns a native/ACP reader uses disk; HTTP
  chat context contains buffer text. Refuse nonfile buffers/directory listings.
  Native session keys ar/aR/am reuse/focus a running session and type nothing
  into a draft/approval. Cold starts use the editor window and file root,
  including when an exited terminal still remains visible.
- The facade owns agent-neutral AI mappings. Descriptions name no agent except
  HTTP inline ae's selected profile. Profile switches relabel ae and update
  CodeCompanion inline/cmd adapters only; never restart/move chats or terminals.
  ar/am keep their existing ellipsis descriptions; aR remains a leaf action.
  No ag/aG/ah/aH/ap mappings: new chat is an, palette remains a lazy command.
- A nonempty NVIM_AI_KEY_PROFILE > vim.g.ai_key_profile > opts.key_profile
  selects the startup HTTP profile. auto resolves the first API with a key,
  else the first API, at startup and each explicit auto selection. With no
  API, inline/cmd refuses with a notice. Nothing persists or writes vim.env.
  NVIM_AI_PROVIDER/vim.g.ai_provider are obsolete and warn once, not select a
  default backend. AI provider explains removal and points to AI new.
- CodeCompanion is optional chat/inline integration, not a native facade. The
  picker shows native, then ACP, then HTTP in provider order, with availability
  and billing. API key/missing ACP bridge preflights run before creation. A
  chat's adapter is fixed. Its own unnamed chats use first ACP else first API;
  key switching changes interactions.inline/cmd only, not chat or
  vim.g.codecompanion_adapter. API/ACP busy/tool-loop delivery checks remain.
- HTTP adapters read NVIM_* variables, never CLI billing variables. Always
  extend builtin Anthropic/OpenAI adapters with their NVIM_* keys, even if
  absent from providers, so restored history cannot bill CLI keys. Always set
  builtin codex ACP auth_method=chat-gpt; its default api-key bills OPENAI_API_KEY.
  A configured cli_api_key is warned about while set. Never write billing env.
- codecompanion-history transcript persistence and continuing an ACP session
  through /resume are distinct. Its separate code_review stays disabled,
  code_review context is not offered, and CodeCompanionCodeReview is deleted
  after setup and never a lazy trigger. There is one baseline system.
- Preserve the Codex tmux renderer, watchdog, agent-run and agent-teardown;
  validate flicker, resize/CJK, scrollback, resume, appended argv and cleanup.
  The watchdog starts on first native spawn, not startup. destroy-unattached
  stays off so client-detached can record/sweep the pane's process tree.
  agent-run preserves nonzero diagnostics because tmux teardown exits 0.
  agent-teardown SIGTERMs/SIGKILLs owned survivors, honoring
  NVIM_AGENT_TEARDOWN_IGNORE for shared daemons; bare kill-server is insufficient.
- ai and TUI ctrl+g use the bundled agent-editor via EDITOR/VISUAL/NVIM, set at
  terminal creation and explicitly forwarded by tmux new-session -e. Missing
  values silently start a nested Nvim. An unowned git-commit prompt takes no
  agent seed/image and has a plain Prompt title. Attachments use the owner of
  that prompt, never an arbitrary first provider.
- Ghost text is independent of chat providers. config.completion declares the
  local service and Minuet preferences; llama_service owns lifecycle. Start
  only with a UI attached and an eligible file. Headless tests never load a model.

## Review Baselines

- A baseline is an immutable snapshot of a worktree (`local-plugin/git-review.nvim/lua/git_review/baseline.lua`):
  a commit with no parent under `refs/nvim-review/<wtid>/{round,saved}/<id>`,
  `wtid` the first 12 hex digits of sha256 of the realpath'd gitdir. Taking
  one writes nothing of the user's: HEAD, the real index, branches, tags,
  stash and their reflogs stay byte for byte. The lasting writes are objects
  and those refs; while a snapshot runs, a temporary index
  `<gitdir>/nvim-review-index.XXXXXX` (and its `.lock`) made by `mkstemp` for
  that snapshot alone and deleted after it. Never a fixed file name: a shared
  index raced between Nvims, kept a file ignored after an earlier snapshot (a
  `.env` named in `.gitignore` too late), and failed after `gc --prune=now`.
- The temporary index is a copy of the real one stamped with the real
  index's mtime, 1 ms earlier and never later. git trusts an entry's cached
  stat only while the entry is older than the index file, so a copy stamped
  "now" missed a same-size edit made in the second before the real index was
  written (5 of 5 tries). A repository with no index yet gets no copy.
- Every git command `git_review.baseline` runs, and those of git_review.view's
  listing, `git_review.actions` and `agent_workbench.review`, goes through
  `git_review.baseline.git_cmd`: `--no-optional-locks` (no opportunistic index
  refresh racing an agent's `git add` for `index.lock`),
  `-c core.hooksPath=/dev/null` (the user's `post-index-change` and
  `reference-transaction` hooks are not ours to fire) and
  `-c core.splitIndex=false` (the temporary index is written whole), with
  `GIT_NO_LAZY_FETCH=1` so a missing object never becomes a fetch.
- The commit is `commit-tree --no-gpg-sign` without `-p`, under the fixed
  identity `nvim review <nvim-review@localhost>` with both dates set to now,
  so an inherited `GIT_*_DATE` cannot reorder baselines and a baseline never
  pins history a rebase or amend rewrote. A ref is made with
  `update-ref --stdin` `create` (an existing ref fails the call rather than
  being overwritten) under `-c core.logAllRefUpdates=false` (no reflog), and
  deleted by compare-and-swap; `delete()` refuses any ref outside
  `refs/nvim-review/`.
- Never move the refs back to `refs/worktree/*`. A per-worktree ref is a gc
  root only in its own worktree: a gc from another worktree deleted the
  commits and left `git log --all` fatal in the one that made them. The cost
  is visibility -- every worktree's `git log --all`, lazygit's all-branches
  graph, `ls-remote` and mirrors list them -- and `docs/DIAGNOSTICS.md` says
  how to exclude them.
- Untracked files over `max_file_size` are excluded by a
  `:(exclude,literal)` pathspec, passed to `git add` on stdin, so they are
  never hashed into `.git/objects`; ignored files follow the current
  `.gitignore` on every snapshot. `locate()` refuses a bare repository and an
  Nvim whose environment sets `GIT_DIR` or `GIT_WORK_TREE`.
- CodeDiff only displays baselines. It is given a baseline's sha, never its
  ref, since retention may delete the ref under an open view. Every
  revision-vs-working-tree listing goes through git_review.view's listing patch
  (a snapshot tree and `diff-tree -r -M -z`), so a path the revision has and
  the index lacks is no fake `D` plus `??`, and a path still on disk is never
  listed as deleted. Upstream's hunk stage, unstage and discard keys stay off
  in every view -- in a revision view they build the patch against the
  revision, not the index -- and only the status view's Staged group calls
  its unstage (`,U`), where the left side is HEAD and it is right. The
  explorer's `-`/`S`/`U`/`X` exist in the status view only: in a revision
  view upstream's `X` runs `git clean` on any file the index does not track.
- Retention runs after every save, per worktree and kind
  (`retention.rounds`, `retention.saved`, passed as the save's `keep`); a
  round whose feedback draft is a
  non-empty file is exempt (`rounds._exempt`, handed over through
  `git_review.baseline.set_exempt`). Objects are left to git's own gc. Exercised by
  `tests/baseline_spec.lua`.

## Agent Hooks

- Local native plugins use opts.plugin_dirs or NVIM_AI_PLUGIN_DIR. Codex gets
  invocation-local marketplace/enabled overrides, after plugin add refreshes
  local snapshots in a disposable CODEX_HOME sharing only the real plugin
  cache. Never change user config/global enablement or bypass native hook
  trust. Nothing installs at Nvim startup or for CodeCompanion.
- Inject UserPromptSubmit per native process with a single -c hooks={...} and
  trusted_hash in that same table. Preserve the user's own hooks and notify;
  never use --dangerously-bypass-hook-trust or write ~/.codex/config.toml.
  Codex gets no SessionStart: it runs only at first turn, after it could help
  identify a newly selected thread before its first prompt.
- review.hook uses sorted deterministic JSON with serde_json escapes for the
  trust identity and hashes the exact command it injects. Keep fixed vectors
  and installed-CLI offline trust checks in agent_hook_spec. A Codex upgrade
  changing trust keys/hashing must fail validation rather than be guessed at.
- scripts/agent-hook codex submit <wait-ms> never prints and always exits 0.
  It holds only a bounded wait, at most hook_wait_ms for the baseline and at
  least 0.5 s for delivery; a dead socket/raising receiver fails fast. Payload
  removal signals that the sender gave up, allowing Late/missed detection.
  It finds this Nvim through the existing NVIM; add no new env whitelist knob.
- hook.event answers RPC immediately, schedules work and releases on failure.
  Both receiver and rounds drop agent_id child events. Unsupported native
  kinds/events are refused; sources.codex is checked at injection and again
  per event. The command is rebuilt at every native spawn.
- Injected flags follow the executable so command identification and appended
  resume/continue argv remain correct. EDITOR/VISUAL/NVIM survive direct and
  tmux launches. Tests use absolute offline stand-ins and a usable TERM;
  never start a real AI turn to test forwarding.

## One Round Model

- Every source opens rounds through `rounds.submit`
  (`local-plugin/agent-workbench.nvim/lua/agent_workbench/review/rounds.lua`), where the round rules live once: the native
  UserPromptSubmit hooks (`rounds.native_event`), CodeCompanion's
  `on_before_submit` for agent and API chats (attached on
  `User CodeCompanionChatCreated`), and `<leader>aV` (`rounds.start`).
  `<leader>gK`'s saved baselines are no round and belong to no conversation.
  Outside an agent's or a chat's own buffer, `<leader>aV`'s owner and the
  round `<leader>av` prefers are the chat on the right's
  (`agent_workbench.slot.shown_here`: this tabpage's, or from a CodeDiff view the page it
  came from; of several, the current window's, else none -- it never asks
  and never moves), and `rounds.live_conversations` lists that one first.
  No provider stands in when nothing is on the right, the first one
  included.
- Active conversation ids are `codex:<session_id>` and
  `cc:<nonce>:<chat.id>`, with a nonce made once per process: CodeCompanion's
  `chat.id` comes from an unseeded `math.random`, so two Nvims, or one before
  and after a restart, hand out the same ids. The chat callback waits for the
  baseline with a bounded `vim.wait(hook_wait_ms)` and never returns false,
  which would cancel the user's submit. A baseline that lands after its
  source stopped waiting is recorded `Late`.
- A conversation's root is the Git toplevel of the agent's working
  directory, fixed when it starts: a native terminal's cwd at TermOpen, a
  chat's `getcwd()` at ChatCreated (CodeCompanion's ACP session and tools work
  there). Codex starts in the current file's Git root; an agent that
  `cd`s elsewhere later keeps its root.
- Delivery goes through `rounds.resolve_sink`, in order, and every refusal
  keeps the draft: (1) the view's root, the draft header's root and the
  target session's root are one realpath -- nothing bypasses this, and it
  asks nothing; (2) a native owner's terminal runs that session, and one
  typed into since it reported it, or that never reported one, asks first
  (or refuses, `unknown_session = "refuse"`), never passes silently; a chat
  owner is an open chat of this process; (3) a chat mid-turn is refused; (4)
  an owner that is gone is refused, with an offer (unless `redirect = false`)
  to pick a current session of the same root and confirm the change once.
  The registry it checks is in memory, per Nvim.
- Seeds are owned by a configured agent and exactly one of on_consumed /
  on_expired fires. A draft is copied to <id>.last-sent.md and emptied only
  when the prompt editor consumed it or companion.add_text succeeded. An
  expired/replaced seed keeps the pending draft. Historical Claude owner ids
  are readable and may be explicitly redirected under the same root rules.
- A round proves only that a change came after its baseline: the user or
  another agent in the same worktree is listed too. Messages say "changes
  since round HH:MM:SS", never "the agent's changes".
- There is one review tab per root. `<leader>av` reads every tabpage's
  `vim.t.ai_review` and closes only an older review of the same root, through
  CodeDiff's own close; it never changes another tabpage's windows.
- Exercised by `tests/review_round_spec.lua` (round rules, the
  `resolve_sink` matrix), `tests/review_view_spec.lua`,
  `tests/review_feedback_spec.lua` (drafts, sinks, seed slots),
  `tests/editor_spec.lua` (`<leader>ai`'s seeds) and
  `tests/review_loop_spec.lua` (submit to delivery, no agent started).

## Editing Conventions

- Preserve unrelated user changes and avoid destructive Git operations.
- Use Lua tables/list-form process APIs when possible. Shell fragments must
  escape user-controlled paths with `vim.fn.shellescape`.
- Lazy plugin setup belongs in `config`/`opts`, not an `init` callback that
  requires the plugin early. Add a command, key, event, or filetype trigger that
  matches the feature's first use.
- Keep mappings discoverable with a `desc`, and place them by *what the user is
  doing*, not by which plugin provides the feature. Four prefixes, each with a
  one-sentence meaning; a key belongs to exactly one of them:

  | Prefix | Question it answers | Examples |
  |--------|---------------------|----------|
  | `;` | "Which file/symbol/position do I want to be at?" (fuzzy search, no starting point) | `;f` find file, `;s` symbol, `;1`-`;9` harpoon |
  | `,` | "What can I do in this file or view?" | `,a` code action, `,f` format, `,o` organize imports; `,1`-`,9` only in terminal buffers |
  | `s` | "What about this window?" | `ss` split, `sd` close, `se` editor window |
  | `<leader>` | Everything else, grouped by domain | `<leader>g` git, `<leader>d` debug |

  High frequency earns two keys, so anything reached constantly belongs on one
  of the first three rather than three keys deep under `<leader>`.
- `<localleader>` is `,`, sharing the action menu with general editing keys.
  Filetype and view contributions stay buffer-local and must preserve general
  editing keys, including `,h`/`,l` dedent/indent, `,k` move up, `,r` rename,
  `,c` codelens and `,e...` extraction. VimTeX uses `,L...` to keep `,l`
  immediate. CodeDiff uses `,P`/`,B` for its explorer (focus, toggle),
  `,z`/`,I` for compact mode and diff layout (inline) and `,g...` for
  conflicts (`o` current/ours, `t` incoming/theirs, `b` base, `a` both,
  uppercase for the whole file), so language actions still work in its source
  buffers. Those are CodeDiff's own descs (its keymaps take an lhs only), and
  the `<leader>?` guide and the manual use the same words. Its defaults that
  would shadow this config's keys (`q`, `t`, `gc`, `-`, `gS`, `gm`,
  `<leader>b`, `<leader>e`, `<leader>h*`, `<leader>c*`) are moved or off. The
  review keys join them per view: `,C` (feedback) on every buffer of every Git
  view; `,S` (stage, through gitsigns; `S`/`U`/`X` as the status explorer's
  file keys) in the status view's Changes group and in any revision- or
  baseline-vs-working-tree file shown on both sides; `,U`
  (unstage) in the latter too, and in the Staged group as CodeDiff's own;
  `,X` (discard a hunk back to the baseline) only where the left end is a
  baseline (`vim.t.codediff_baseline`); for a file on one side only it just
  says what would do it -- the `git restore` command for a file deleted since
  the baseline (none when something is at that path again), nothing to run
  for a new one. Revision-vs-revision, `--staged`, history,
  conflict and single-file views get none of `,S`/`,U`/`,X`
  (`local-plugin/git-review.nvim/lua/git_review/actions.lua`). `]h`/`[h` in every view's panes are
  CodeDiff's own next/prev hunk (as its `]c`/`[c`, which stay), installed by
  git_review.view through `set_keys`. Terminal digits only map Normal mode.
  grug-far's editable search panel uses `,S...`, in its own panel only (its
  own which-key section, filetype `grug-far`); in a CodeDiff pane `,S` is the
  stage key. Its plugin defaults also use localleader and must not overwrite
  general comma actions.
  A CodeCompanion chat (`interactions.chat.keymaps` in
  `lua/plugin/ai/codecompanion.lua`) puts upstream's acts that took keys
  meaning something else everywhere on `,`: `,s` save (codecompanion-history),
  `,X` clear, `,q` end the chat, `,z` fold code blocks, beside `,m` render;
  `gx` and `gf` open what is under the cursor again, `s` stays the window
  prefix and `{`/`}` paragraph motions (`tests/companion_spec.lua`).
  CodeCompanion deep-merges these with its defaults, so the spec's `config`
  removes `close`'s Insert `<C-c>` from the live config after setup.
  Filetype scope and view scope can coexist; a shared suffix
  may differ between filetypes, but a view must not steal language/general keys.
- LSP navigation that starts from the symbol under the cursor belongs on `g`,
  not on `;`: `gd`, `gr`, `gb` (implementation), `gy`, `gD`, `gC` (incoming
  calls) and `gK`, plus `gs` (source definition) where vtsls attaches, from its
  `on_attach` in `lua/plugin/lang/typescript.lua`. The dividing line is whether the key
  needs a symbol to start from -- `;s`/`;S` fuzzy-search a symbol list and need
  no cursor context, so they stay on `;`. Mnemonic letters lose to builtins
  here: `gi`/`gI` are Vim's insert commands and `gc` is Nvim's comment
  operator, so implementation, incoming calls and source definition take free
  letters rather than displace them (`gs` gives up only `:sleep`).
- Every mapping that requires a language server carries a `[LSP]` prefix in its
  `desc`. A which-key popup on `g` mixes LSP jumps with lexical motions like
  `gf` and `ge`; the prefix is what tells a reader which ones stop working when
  no server is attached.
- AI mappings belong under `<leader>a`, whose heading already says AI. One
  that sits in any other prefix's popup carries an `[AI]` prefix in its `desc`
  -- today `,C` (review feedback) in the Git views' comma menu. Keys local to
  an AI buffer (the prompt editor's `<C-d>`, the agent panel's terminal keys)
  and Insert-mode `<C-l>` (ghost text) open no popup and need none; a chat's
  own comma keys (`,s`, `,X`, `,q`, `,z`) show only in the chat, under the
  `Chat ·` heading, which already names it, so they carry no `[AI]` either.
  Their descs are this config's (`description` in
  `lua/plugin/ai/codecompanion.lua`: "Save chat", "Clear chat messages",
  "Close chat (ends it)", "Fold code blocks"), and the chat's `gh` reads
  "Browse saved Companion chats", as `<leader>ao` does.
- Under a which-key popup the letter may be a mnemonic or an accident, but the
  `desc` is the interface: it is exact, and one act is worded one way
  everywhere (`tests/key_descriptions_spec.lua`, `<leader>a` included, and
  the view and LSP specs for theirs). Sentence case: the
  first word capitalised, the rest lowercase but for proper nouns and acronyms
  (LSP, DAP, REPL, AI, API, ACP, URL, PR, Git, GitHub, Claude, Codex,
  CodeCompanion, CodeDiff, Lazygit, Mason, Harpoon, Treesitter, Nvim, oil).
  No articles. Verbs: Close a window, tab, view, panel or float; Delete a
  buffer or a list item; Discard a change (`<leader>gr`/`gR`, the status
  explorer's `X`, `,X`), never Reset or Restore -- Restore is a session's;
  Toggle only where the key toggles, else Show, Hide or Open; "Go to", never
  "Goto"; bracket keys say "Next X"/"Prev X", never "Previous". LSP jumps on
  `g` are bare nouns, as in the `<leader>?` guide (`[LSP] Definition`,
  `[LSP] References`, `[LSP] Type definition`). Scope words: "file" is the
  current file, "buffer" only the buffer list (`<leader>b`), "cwd" Nvim's
  working directory, "repo" the Git repository, "here" the current file's
  directory; "project" names only the projects picker (`;p`). "/" joins
  single words without spaces ("Stage/unstage"), " / " phrases. A desc ends
  in "…" when the key asks something of its own -- a choice, typed input or a
  confirmation -- before it acts: `<leader>an`/`al`/`ar`/`am`/`ae`/`ax`,
  `<leader>gM`/`gk`/`gK`, `<leader>Gc`, `<leader>mM`,
  `<leader>dA`/`dB`/`dL`/`de`/`dW`/`da`, `,a`, `,r`, `,ef`/`,eF`/`,ex`, `,R`,
  Python's `,v`, the status explorer's `X`. A picker whose list is itself the
  destination gets none (the `;` pickers, `<leader>aT`, `<leader>ao`), nor
  does the shared which-agent or which-chat question a chat key asks when
  nothing is on the right (`<leader>aR` has none), nor a key that asks only
  sometimes (`<leader>dc`, `df`/`tM`/`tF` and `,c` ask only when there are
  several configurations, targets or lenses).
- Case inside a popup marks one thing: the uppercase key is the same act as
  its lowercase sibling, the same way but further -- wider scope or stronger
  (`;s`/`;S`, `<leader>gl`/`gL`, `gc`/`gC`, `gh`/`gH`, `uf`/`uF`, `tm`/`tM`,
  `tf`/`tF`, `bd`/`bD`, `qq`/`qQ`). A different object, or a scope narrower
  than the lowercase key's, gets a named letter (`<leader>xb`, not `xX`);
  `;F`/`;D` ("from here", the current file's directory) are the documented
  exception. Under `[`/`]` uppercase is the end of the same list: first/last
  (`[B`/`]B`, `[Q`/`]Q`) or a text object's end (`]M`). The manual's grammar
  (rule 4) says the same to the user. A few older pairs inside popups name two
  different acts (`gk`/`gK`, `bp`/`bP`, `dw`/`dW`, `mc`/`mC`, `;h`/`;H`,
  `;t`/`;T`): they stay, because the popup names both and moving them costs
  more than it buys (#30), but no new key may follow them.
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
- A Visual-mode mapping uses mode `"x"`, never `"v"`: `"v"` also maps Select
  mode, where a snippet placeholder (vim.snippet, blink.cmp) must be replaced
  by the first printable key typed -- with `"v"`, `<`/`>` indented the line
  and a leading `,` or `<Space>` started a mapping. A key that does not read
  the selection is Normal only (`<leader>t*`, `<leader>d*` but `dw`/`dW`).
  which-key groups likewise take `{ "n", "x" }` or `"n"`, never `"v"`.
  `tests/select_mode_spec.lua` holds every printable lhs to it.
- Keys no popup explains (Ctrl/Meta chords, single letters in a panel,
  Insert and terminal keys) are strict: one act, one key, in every view, and
  never shadowing window navigation `<C-h/j/k/l>`, Insert `<C-w>`/`<C-u>`,
  redo `<C-r>`, or macro `q` anywhere but a panel's own buffer. The
  lexicon: close or leave a panel `q` (a float also `<Esc>`); cancel an
  in-flight request `<C-c>` (a chat's reply, `<leader>ae`'s inline request
  -- never Insert `<C-c>`, which leaves Insert mode); submit a draft `<C-d>` (the prompt editor, the
  review draft, a chat and the `:CodeCompanion` prompt float from Insert
  mode; `<C-s>` is the tmux prefix); open below / beside / in a tab
  `<C-s>`/`<C-v>`/`<C-t>` (pickers, oil, aerial; oil's `<C-v>` Normal mode
  only, so `v<C-v>` still reaches blockwise Visual); delete a list item
  `<C-x>` in a picker's input, `dd` in a list (the buffer and saved-chat
  pickers); refresh `R` (`gR` in oil, whose listing is edited text); preview
  `<M-p>`; hidden files `<M-.>` (tmux takes `<M-h>`; oil keeps its `g.`);
  help `g?`, with `?` kept where it already was (a chat, the pickers,
  aerial, neotest's summary); next/prev on `]x`/`[x` families. `q` never
  ends a conversation: a chat's `q` is `<leader>ac`, and ending it is `,q`.
  `tests/panel_keys_spec.lua` pins oil, aerial, the picker and edgy;
  `tests/companion_spec.lua` the chat, the inline request, the prompt float
  and the saved-chat picker.
- `<leader>` carries global semantics only, so which-key popups stay truthful
  everywhere. A buffer-local map may add a key inside an existing group, but
  never repurpose one that already means something else. Anything meaningful in
  only one filetype belongs in the buffer-local comma menu, not in a global group.
- Standalone panels put view-local actions on single letters (quickfix, aerial,
  neotest). A multi-window view keeps one vocabulary across every buffer it
  owns, so CodeDiff's own actions live on `,` in its diff panes and its
  explorer or history panel alike, and single letters there stay reserved for
  that panel's list operations. The status view's explorer keeps upstream's
  `-`/`S`/`U`/`X` (stage/unstage a file, stage all, unstage all, discard a
  file's changes, which asks first); no other view gets them. `q` closes the
  view from the explorer and history panels only, and stays macro recording
  in a diff pane. Only layout-fragile
  multi-window views (currently CodeDiff) block layout-sensitive prefixes:
  `;` and `s` in every window of a CodeDiff tabpage, panels included, with
  `nowait` and a visible disabled hint. A `;` picker drops its file into the
  working-tree pane, which desynchronises the view, and `sd`/`so` close a
  pane, which ends the session. The block also swallows the next key when it
  comes within 'timeoutlen', so `so` opens no line and `;f` starts no flash
  jump; `<C-w>` stays available, and the comma action menu stays active.
  The keys off `;` that put another buffer in the window are blocked too,
  since neither the panes nor the panels are 'winfixbuf': `H`/`L`,
  `[b`/`]b`, `[B`/`]B` (first / last buffer) and `<C-^>` (so `<C-6>` too) in
  every window, panels included,
  and oil's `-` everywhere but the status view's explorer, where it stages.
  Same `nowait` and hint, through git_review.view's `set_keys`, handed back on
  close; only `;` and `s` swallow the next key, these are whole keys. Picking
  a buffer by its tab letter is `;B` (bufferline), so the `;` block covers it.
  Behind the keys, git_review.view's `guard_panes` puts back any swap of a
  pane's or panel's buffer that CodeDiff did not make -- `:e`/`:b` (and `!`),
  `<C-o>`/`<C-i>`, quickfix and location jumps, mini.bracketed's `[o`/`[j`,
  LSP jumps through Snacks or `vim.lsp.util.show_document` -- on the next tick,
  with the pane's view and a "cannot replace a CodeDiff pane" notice. It tells
  CodeDiff's own swaps by its modules' chunk names on the Lua stack; a pane's
  wipe-when-hidden buffer (a revision, the welcome page, a placeholder) is held
  with `bufhidden=hide` while shown and gets its own value back when CodeDiff
  swaps it out, the window closes or the view does. Not 'winfixbuf': CodeDiff
  swaps its own panes with `nvim_win_set_buf`/`:edit` from many modules and
  scheduled callbacks, which E1513 would break, and Snacks' and the LSP
  client's jumps would error. Swaps under `:noautocmd` fire no event and pass.
  The key blocks stay: they refuse before another buffer loads at all.
- The debug view is the other multi-window view with a tabpage of its own, and
  it is deliberately the opposite case: its keys stay global. Debugging has an
  event stream, so `<leader>d` has to work from the editor tabpage too -- you
  set a breakpoint and step from the source you are editing, not only from
  inside the view. Nothing there blocks a global prefix.
- The tabline stays on (`always_show_bufferline`, and `showtabline = 2` in
  `local-plugin/editor-core.nvim/lua/editor_core/options.lua` so the first frame, drawn before bufferline loads on
  `VeryLazy`, already has the row). bufferline's own toggle
  counts buffers and never tabpages, so more than one tabpage with at most
  one listed buffer hid the tabline and the `1`/`2` tabpage indicators with
  it -- while CodeDiff, the view most likely to be in that second tabpage,
  disables the global prefixes. Re-enabling the toggle and overriding
  `showtabline` afterwards does not work: it re-runs from the tabline's own
  redraw and undoes the override on the next draw. Because it is permanent,
  an empty one must be invisible: bufferline's `fill` asks for a transparent
  background, but an unset background there inherits `TabLineFill`, which the
  colorscheme leaves opaque even under `transparent`. Both are cleared --
  `fill` in the bufferline spec, `TabLineFill` in `lua/plugin/ui/solarized.lua`
  -- and clearing only one puts the theme's teal band back across the top.
- Window sizing goes through `editor_core.window.resize` and `toggle_zoom`, not
  `:resize` or `wincmd _` directly. edgy re-applies its panels' geometry on
  `WinResized` and every panel is winfix, so beside one a bare `:resize` is
  a no-op and `wincmd _` is undone a tick later. An edgy window's thickness
  (a left/right bar's width, a bottom bar's height) is the edgebar's own
  `size` and can only be grown through `Window:resize`, so shrinking goes
  through the edgebar. Never collapse panels with edgy's `hide` or
  `edgebar:close()` to make room: both drop a non-pinned window for good,
  and `open()` restores only pinned views, of which this config has none.
  No keystroke reaches them either: edgy's panel keys `<c-q>` (hide) and `Q`
  (close the edgebar) are off in `opts.keys` (`lua/plugin/editor/edgy.lua`),
  with its `]w`/`[w`/`]W`/`[W` window cycling, which took the global warning
  jumps; `q` and the `<c-w>` resizers stay.
- The first tabpage stays a page the global prefixes work in
  (`editor_core.window.protect_first_tab`, driven by `TabClosed` and
  `SessionLoadPost`). Views open after it on their own -- `tab split`
  inserts after the current tabpage -- so the guard only repairs the state
  where the pages in front of a view are gone. It keys on the view, not on
  window contents: CodeDiff's working-tree pane holds an ordinary file
  buffer, so every window-level check calls its tabpage editable while `;f`
  is mapped to a disabled hint throughout it. The view says so itself:
  git_review.view sets `vim.t.blocks_global_prefixes` on `CodeDiffOpen` and
  clears it on `CodeDiffClose`, which `editor_core.window.blocks_global_prefixes`
  reads first; `PREFIX_BLOCKING_FILETYPES` (`codediff-explorer`,
  `codediff-history`) is the second test, for a tabpage CodeDiff let go of
  with its panel still on screen. A single-file `:CodeDiff file` has no
  panel, so a new prefix-blocking view sets that tab variable (and adds its
  panel filetypes). `tests/tabline_panel_spec.lua` stands a view in with the
  variable alone.
- Both paths that place a stopped frame -- nvim-dap's `switchbuf`
  (`editor_core.dap.jump`) and nvim-dap-ui's `select_window` -- must stay scoped to the
  current tabpage. `usetab`, or anything else that hunts across tabpages, turns
  the debug view into something that steals focus from an editor tabpage on
  every step, which is more intrusive than the split layout it replaced.
- A buffer this config opens goes where `editor_core.buffer` says
  (`editor_target`, `leave_panel`, `in_editor`, `open`, `pick`, and
  `picker_on_show`, the Snacks pickers' `on_show`, which holds the list of
  location sources), never
  into whatever window is current: that may be a chat, an agent terminal or
  another panel, and the buffer replaced it -- a chat simply takes it, and
  Snacks' terminal fixbuf sends it back out and closes the panel when no plain
  file window is left. A new key, picker or callback that opens a buffer calls
  `editor_core.buffer`; a case it does not cover is added there, not patched at the
  call site (bufferline, `gx`, Oil and the picker hook each carried a copy of
  their own before, and Harpoon's keys had none). Which windows make up the editor area stays
  `editor_core.window`'s model (`editor_win`, `ensure_editor_win`), which
  `editor_core.dap`'s frame placement uses directly. Typed commands (`:e`, `:b`) and
  upstream plugins' own jumps are out of its reach and out of scope.
- Do not force-delete ordinary buffers from terminal-specific mappings.
- Popup sections are declared as data in `lua/config/whichkey_spec.lua` (`sections`,
  keyed by prefix then suffix) and only read by `lua/plugin/editor/whichkey.lua`.
  Adding a key or a whole section is a data edit; no Lua in the plugin spec
  knows what "files" or "search" means. Match by key, never by `desc` text -- an
  earlier version matched description patterns, where a reworded `desc` silently
  changed a key's colour and position and every new pattern risked catching
  someone else's entry. Every prefix worth sectioning is declared: `;`, `g`,
  `,` (and grug-far's `,S`), `s`, `[`/`]` (one table, mirrored), `<leader>`
  itself, and the `<leader>` groups `g`, `G`, `d`, `a`, `m`, `b`, `x`, `t`,
  `u`, `<tab>` and `y`.
  In a sectioned popup, undeclared keys sort last under `others`, styled by
  `fallback_section` in the same data file. Even one remaining key gets this
  heading, so it never appears to belong to the preceding section. Explicit
  sections need at least two keys; do not invent a separate section for a
  group row such as `+Messages/notifications` -- it can fall under `others`.
  Context sections are the exception: even one filetype action needs its own
  heading. Optional `filetype` (list) and `buftype` filters select the section;
  `labels` names implicit subgroups without creating global placeholder keys.
  A shared key such as `,v` can have one section per filetype. The first
  matching section owns a key, so a filetype section comes before any
  unfiltered one that declares the same suffix: `g`'s oil, CodeDiff panel,
  chat, Lazy and outline sections before LSP, and `,`'s Lazy section before
  refactor and lines (`tests/whichkey_popup_spec.lua`). Actual mappings
  determine which rows exist; headings never create keys or load plugin.
  See `docs/UTILITIES.md` for the section-data contract. Context/menu changes
  are exercised by `tests/context_actions_spec.lua`; combined language and
  view mappings, including cleanup, are exercised by `tests/codediff_spec.lua`.
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
  keytrans alone turns `g<C-A>` into `g<lt>C-A>` and the lookup misses. A
  section key is then compared with `<lt>` turned back into `<`, as
  which-key's `Util.keys` stores a node's keys; without that a declared `<`
  (`<leader>b<`) lands under `others`.
- which-key's own `group` is a sub-prefix (`<leader>g` + `l` = `<leader>gl`), so
  it cannot slice a single level. The `;` headings therefore come from replacing
  which-key's `View.sort` and inserting display-only rows: the popup body is a
  table whose rows *are* the items, and its render loop reads only `key`, `sep`,
  `icon`, `desc`, `group` and `icon_hl`. This, `local-plugin/git-review.nvim/lua/git_review/view.lua` and
  `local-plugin/agent-workbench.nvim/lua/agent_workbench/companion.lua` (next items) are the only places here that depend on
  plugin internals, apart from these narrower ones: `:checkhealth config`
  asks CodeDiff for its library and watcher versions (next item);
  `local-plugin/editor-core.nvim/lua/editor_core/window.lua` sizes edgy's panels through `edgy.editor`, the
  edgebars in `edgy.config.layout` and `edgy.layout.update` (window sizing,
  above); `local-plugin/editor-core.nvim/lua/editor_core/diffsplit.lua` tells gitsigns' revision windows by
  their `gitsigns://` buffer names, which `tests/gitsigns_spec.lua` pins;
  and `<leader>bP` calls `bufferline.groups.action` with a function -- the
  `group_action` bufferline documents but the pinned release does not
  export -- since `:BufferLineGroupClose` deletes with `force = true`
  (`tests/tabline_panel_spec.lua`). The `sort`
  replacement is guarded (a renamed `sort` drops headings and colours,
  ordering still works through the supported `sort` option, nothing errors)
  and covered by `tests/whichkey_popup_spec.lua`, with real contextual menus
  covered by `tests/context_actions_spec.lua`. It assumes the single-column `helix`
  preset: a multi-column preset would split a heading from its items.
- `local-plugin/git-review.nvim/lua/git_review/view.lua` is the one reader of CodeDiff's internals;
  everything else -- `local-plugin/git-review.nvim/lua/git_review/actions.lua`, `agent_workbench.review`, the
  `<leader>g` spec -- goes through it, and only the specs and
  `local-plugin/editor-core.nvim/lua/editor_core/health.lua` require `codediff.core.*` or `codediff.ui.*`
  themselves. The health check is the second, sanctioned reader, of two
  values and nothing else: the library's version through
  `core.diff.get_version`, called only from `:checkhealth`, only once the
  library file exists, and with `VSCODE_DIFF_NO_AUTO_INSTALL` held at 1 for
  the require (which loads the plugin); and the watcher release it wants,
  `core.installer.watcher.VERSION`, read only once CodeDiff is loaded. Both
  are pcall'd and type-checked. `local-plugin/git-review.nvim/lua/git_review/view.lua` also relies on the
  chunk names of CodeDiff's modules (its `lua/codediff/` directory, read from
  `require("codediff").setup` at setup), which tell its own pane swaps from
  others (`guard_panes`); without that prefix it lets every swap through, as
  plain CodeDiff does. `local-plugin/git-review.nvim/lua/git_review/view.lua` reads `ui.lifecycle`
  (`get_session`, `set_buf_keymap`, `begin`/`end_keymap_scope`, `close`, and
  wraps `update_buffers`), the session's fields and
  `stored_diff_result.changes`, the panel tree's `get_node`,
  `ui.explorer.actions`, `ui.view.actions.hunk.unstage_hunk`,
  `ui.refresh.request`, `core.diff.compute_diff`,
  `ui.view.render.diff_options` and `ui.layout.arrange`, and patches
  `core.git.runner.run_async` (`-c core.quotePath=false`),
  `core.git.get_commit_list` (`history_limit`) and
  `core.git.changes.get_diff_revision` (the listing). It also calls the
  public `codediff` module's `next_hunk`/`prev_hunk` for `]h`/`[h`, which is
  no internal. Its header is that list, plus that public call; keep it
  current. Every access is pcall'd and type-checked, and `setup()`
  compares `codediff.version` with `M.VERSION` (4.0.6, the lazy pin): a
  mismatch warns once and leaves the three patches off, which is safe
  because the upstream keys that would be dangerous are already off in
  `lua/plugin/git/codediff.lua`. CodeDiff's own setup runs inside
  `git_review.view.setup`, after the runner patch, since each
  `codediff.core.git.*` module copies `run_async` when it loads.
  `tests/codediff_spec.lua` pins the internals,
  `tests/codediff_listing_spec.lua` the listing and
  `tests/hunk_actions_spec.lua` `refresh.request`; moving the pin means
  re-running them first. Keys on a view go through its `set_keys`,
  CodeDiff's own keymap registry, from `User CodeDiffKeys`: the panes borrow
  the user's real file buffers, and the registry suspends its claims on them
  in other tabpages and hands every key back when the view closes. Never map
  a pane buffer with a bare `vim.keymap.set`.
- `local-plugin/agent-workbench.nvim/lua/agent_workbench/companion.lua` reads CodeCompanion's `chat.adapter`, `chat.ui`
  (`is_visible`, `is_visible_non_curtab`, `open`, `hide`, `hide({
  keep_window = true })`, `winnr`), `chat.title`, `chat.prompt:add`,
  `interactions.chat.open({ ui, winnr })`, the `hidden` argument of
  `codecompanion.chat()` and `buf_get_chat()`'s entries, because upstream's
  Toggle and Add cannot be aimed at one chat, and its window-less `Chat.open`
  closes `last_chat` wherever it is shown. A chat is created hidden and shown
  as exactly itself (`agent_workbench.slot.show_chat`, which opens it through
  `agent_workbench.companion.open`): gone to in another tabpage, handed a chat window here
  (`ui:hide({ keep_window = true })` then `Chat.open({ ui, winnr })`), or
  given a window by `ui:open()` once the slot has made room; it is not
  upstream's `last_chat` until first entered. Nothing here calls
  `Chat.open` without a window. Upstream's own paths still can (`<leader>ao`,
  a typed `:CodeCompanionChat`, the action palette), and may hide a
  chat in another tabpage on the way; the slot's guard keeps this tabpage to
  one AI window afterwards (`next_chat`/`previous_chat`, upstream's `}`/`{`,
  are off: switching chats is `<leader>al`). `,q` (upstream's `close`) shows
  its successor in the closed chat's window, which becomes the successor's
  own (`ui.winnr`), and leaves the successor's buffer in the window of the
  tabpage that showed it: there it is still the chat on the right, shown in
  a window that is not its own, which `show_chat` and `focus_prompt` use
  where it is and `<leader>ac` closes.
  `agent_workbench.slot` reaches chats only through `agent_workbench.companion` (`chats`, `chat_of`,
  `key`, `buf`, `label`, `name`, `win`, `win_here`, `where`, `busy`, `hide`,
  `open`, `create`, `focus_prompt`), which reads them in a pcall and checks
  what it gets; `agent_workbench.companion` never calls back into the slot. A
  failure is reported as an error by the facade's guards; nothing falls back
  to an upstream command, which would aim at `last_chat` instead.
  `tests/companion_spec.lua` pins the internals without creating an ACP chat
  (that spawns the bridge) or sending a request, and
  `tests/ai_slot_spec.lua` the slot. Review feedback goes to one exact chat
  through `add_text` and `busy`, which also read
  `chat.current_request` and the private
  `chat._turn_in_progress`: a tool loop clears `current_request` and makes the
  buffer editable between its steps, and only that flag stays set. It is read
  in a pcall, so a rename upstream loses that signal only; `add_text` answers
  `false, "gone"|"busy"|"failed"` rather than raising, and
  `tests/review_feedback_spec.lua` pins the mid-loop refusal. A chat's
  progress line (`local-plugin/agent-workbench.nvim/lua/agent_workbench/progress.lua`) hooks its `on_submitted` callback on
  `User CodeCompanionChatCreated`, as review rounds hook `on_before_submit`,
  and ends when `agent_workbench.companion.busy` turns false: upstream shows nothing
  until the first chunk, and its `RequestStarted` event fires only after an
  ACP chat's connection or an HTTP adapter's blocking setup, so a spinner on
  it starts too late (`tests/companion_spec.lua`). `<leader>ab`'s
  file goes to one exact chat through `add_buffer`, which calls the output
  of upstream's `/buffer` (`interactions.shared.slash_commands.buffer`,
  `new` and `output`) on it, refuses as `add_text` does, and reads
  `chat.messages` to tell whether it took (`output` reports a failure only
  to CodeCompanion's log).
- which-key keeps description-only entries in its trie, separate from actual
  maps. Actual bindings now belong to core/feature owners; no RHS belongs in
  config.whichkey_spec. Descriptions on remappable/filetype keys belong to
  their real maps, so global metadata cannot override a local action. LSP and
  filetype descriptions preserve builtin callbacks; tests read both live maps
  and display-only metadata. Core actions and guide must work without which-key.
- Window commands should normally affect the current tab only. Be deliberate
  before using global APIs such as `nvim_list_wins()`.
- Messages and the cmdline come from noice (`lua/plugin/ui/noice.lua`), which
  hands Vim's messages to the snacks notifier; vim.notify goes to that
  notifier directly (noice's own `notify` is off). noice's LSP progress, hover
  and signature help are off too: lualine, `K` and blink.cmp own those, and a
  second owner draws them twice. So is its `window/showMessage` handler, which
  is nil at the pinned commit and dropped every server message: Nvim's own
  goes to vim.notify. noice drops any message kind no route names, and Nvim
  0.11+ has kinds its defaults miss (`:!` output, `:w`'s `progress`, undo,
  quickfix); `routes` in `lua/plugin/ui/noice.lua` names them, and
  `tests/messages_spec.lua` pins those routes. It skips
  'showcmd' too, which therefore sits in the statusline (`showcmdloc`,
  lualine's `%S`). Never enable Nvim's ui2 beside it: both take over the
  message grid. Notifications, noice's popups and incline's label
  are floats in the tabpage, so a "last window here?" check must count
  non-floating windows only; counting `nvim_tabpage_list_wins()` made the
  transcript's `q` fail with E444. Neither runs without a UI: noice loads on
  VeryLazy, which lazy.nvim fires only on the first `UIEnter`, and the
  notifier is enabled only with a UI attached. So `--headless` keeps plain
  stderr messages and the specs never exercise them: check message, cmdline
  and float changes in a real UI as well. A UI that attaches after startup
  (`--remote-ui`) gets both on that first `UIEnter` -- the notifier from a
  once-`UIEnter` hook that also marks it enabled, which noice reads before
  routing to it; decide on that event, not only on `nvim_list_uis()` at
  spec-evaluation time.
- Neovim's built-in `gc`/`gcc` commenting is the default; do not reintroduce a
  comment plugin without a concrete missing capability.
- Add/remove dependencies through specs and lazy-lock.json together. This
  Codex release removes claudecode.nvim intentionally; do not reinstall it to
  satisfy old tests. A shared developer lazy directory may retain its checkout
  until Lazy clean; the original dirty worktree must remain usable.

## Documentation

- `README.md` / `README_CN.md` are the quick start: what this is, how to install
  it, what is in it, and a keymap summary. Keep the two behaviorally
  synchronized.
- `docs/MANUAL.md` / `docs/MANUAL_CN.md` is the long-form guide for someone new
  to Vim or to this config: the prefix model, then each workflow end to end.
  Detail belongs there rather than growing the README.
- Update `docs/DIAGNOSTICS.md` when dependency, health, AI backend,
  formatter, or troubleshooting behavior changes.
- Update `docs/UTILITIES.md` when a public utility contract changes.
- Document actual mappings and dependencies, not planned behavior.

## Validation

Run checks proportional to the change. At minimum, run the spec suite, one
startup and the working-tree whitespace check -- `make verify` runs all three
(`make test S="name ..."` runs some specs; the Makefile lists the rest):

```sh
./tests/run.sh
nvim --headless -u init.lua -i NONE +qa
git diff --check
```

The specs run one at a time: several share what one Nvim at a time expects
(the llama-server llama_service shares, git index and gitsigns watcher timing),
and failed when run side by side.

`tests/*_spec.lua` run against the real configuration (`-u init.lua`), so they
catch what a startup check cannot. Each spec exits through `cquit`: a plain
`-c qa` returns 0 even after an uncaught Lua error, which would make a broken
spec read as a passing one. `helper.done()` also keeps SIGPIPE caught through
Nvim's teardown, which resets it before the loop's last iteration: otherwise a
late write to a pipe whose reader is gone, such as an LSP server the spec has
just stopped, can kill a passing spec with status 141, and sh does not report
that (`tests/exit_status_spec.lua`).

Specs never download. CodeDiff fetches its native diff library on first setup
and its file watcher on first view when they are missing; `tests/run.sh`
exports `VSCODE_DIFF_NO_AUTO_INSTALL=1` and
`CODEDIFF_WATCHER_NO_AUTO_INSTALL=1`, so a missing library fails the specs
that need one and says so, and a missing watcher only makes views poll. Set
both when running one spec by hand. Install the library once from a normal
Nvim (load `codediff.nvim`; see `docs/DIAGNOSTICS.md`). CI loads the plugin
once after `Lazy! install` to fetch it, checks the library (and `libgomp`,
when that was fetched too) against the release's `SHA256SUMS`, and installs
no watcher.

For CodeCompanion changes, load it and confirm the resolved chat adapter (the
first `acp` in provider order) plus `:CodeCompanionHistory`. For formatting changes,
trigger `BufWritePre` before checking Conform. For keymap, terminal, window, or
deletion changes, reproduce the exact edge case rather than relying only on
startup.
For baseline, CodeDiff or review changes, use a temporary repository (a space
in its path, an empty global git config) and never start a real agent or
submit a chat: the specs hand hook payloads to `agent_workbench.review.hook.event` and
dispatch a chat's `on_before_submit` directly.

Use `:checkhealth config` as the config-specific dependency check and
`:ConformInfo`, `:checkhealth vim.lsp`, `:Mason`, and `:Lazy profile` as the
primary diagnostic sources. Do not reach for `:LspInfo` — nvim-lspconfig stops
defining the `Lsp*` commands once Nvim 0.12's builtin `:lsp` exists.

## Code Review Rules

- Flag terminal-provider behavior or advertised native capabilities that disagree with the supported contract.
- Flag force deletion, cross-tab window mutation, unescaped shell paths, and
  lazy specs that load a plugin earlier than their declared trigger.
- Flag README/README_CN claims that disagree with the active Lua configuration.
