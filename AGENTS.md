# Repository Instructions

## Purpose

This is a personal Neovim configuration for Neovim 0.12.5+ written in Lua and
managed by lazy.nvim. Keep changes small, reversible, lazy-loaded where
practical, and consistent with the existing LazyVim-style key namespaces.

## Architecture

- The layout follows lazy.nvim's and LazyVim's: `init.lua` turns on
  `vim.loader` and requires `config`; `lua/config/init.lua` is the startup
  sequence, one plain `require` per step, in order: `config.cwd` (recover a
  deleted cwd, pick the startup cwd at `VimEnter`), `config.options`,
  `config.keymaps`, `config.autocmds`, the AI facade (`ai`) and `config.lazy`
  (lazy.nvim, last). Each step does its work when required -- the AI facade
  too: `lua/ai/init.lua` installs itself at the end of the file -- so there
  is no `require(...).setup()` in the sequence. `lua/config/` also holds the
  data and checks of this configuration itself: `whichkey_spec.lua` (which-key
  sections and descs) and `health.lua` (`:checkhealth config`).
- `lua/plugins/` holds every lazy.nvim spec, imported by
  `config.lazy` in this order (it is merge order): `editor/` (editing,
  navigation, pickers, panels), `coding/` (LSP, completion, formatting,
  linting, DAP, tests), `ai/` (Claude Code, CodeCompanion, ghost text), `ui/`,
  `git/` and `lang/` last.
- `lua/plugins/lang/*.lua` owns language contributions: LSP servers, Mason
  tools, formatters, linters, Treesitter parsers, DAP adapters, tests, and
  runners. Add language-specific behavior there instead of expanding a core
  plugin spec.
- `lua/util/` contains small reusable helpers, and requiring one changes
  nothing: startup wiring that uses a helper lives in `lua/config/` (as
  `config.cwd` uses `util.cwd`). A helper requires no `ai.*`: what the AI
  layer owns is handed in -- `util.baseline`'s `max_file_size`/`keep` by each
  caller, util.codediff's through `setup`'s hooks, which terminals are agent
  panels through `util.terminal.set_agent_test`. Avoid introducing frameworks
  for behavior already covered by Neovim or a maintained plugin.
- `lua/ai/config.lua` holds the AI state -- the ordered `providers` list,
  validated at load (`M.build`), and the HTTP key profile, which
  `lua/ai/switch.lua` (`:AI key`) switches in-process -- and the list of
  backends a chat can be started on (`backends()`: the terminals, then the
  ACP chats, then the API chats, each in provider order).
  `lua/ai/init.lua` exposes agent-neutral mappings;
  `lua/ai/slot.lua` keeps one AI window per tabpage and resolves "the chat on
  the right"; `lua/ai/backend/` owns native-agent details.
- `lua/ai/review/` is the review loop: `config.lua` (every setting's default,
  `vim.g.ai_review` merged over them), `hook.lua` (the native agents' prompt
  hooks), `rounds.lua` (rounds and delivery checks), `init.lua` (`<leader>av`
  and `,C`), `feedback.lua` (drafts and delivery) and `labels.lua` (baseline
  labels for the `<leader>gM`/`<leader>gk` pickers and `<leader>gK`'s offered
  name). Its storage and its
  views are utilities: `lua/util/baseline.lua` (snapshots under
  `refs/nvim-review/`), `lua/util/codediff.lua` and
  `lua/util/codediff_actions.lua` (the CodeDiff views behind `<leader>g` and
  their hunk keys). The vcs layer reads a baseline's subject, sha, kind and time only;
  its trailers mean something to `ai.review` alone (`rounds.review_vars`,
  and `labels.describe` for the pickers' labels, which read session names and
  turn ends from the agents' own records through `ai.transcript.marks`).

## AI Provider Invariants

- There is no default backend. `lua/ai/config.lua` holds an ordered
  `providers` list, configured the way CodeCompanion's adapters are: each
  entry has a unique `name`, a `label`, optionally a `cli_api_key` (the
  variable its CLIs bill against instead of the subscription login, which the
  picker and `:checkhealth config` warn of while it is set) and at least one
  of three parts. A part left out is not offered:
  - `tui = { kind }`, its native terminal agent. `kind` must be one this
    config implements (`claude` or `codex`, `TUI_KINDS`), each at most once:
    a new kind needs code -- a `lua/ai/backend/` module, a tmux wrapper, the
    prompt hooks and a transcript reader -- not just an entry.
  - `acp = { adapter, command, auth_method? }`, its CLI driven by
    CodeCompanion over ACP, on the subscription.
  - `api = { adapter, label?, api_key, model?, name? }`, a CodeCompanion
    HTTP chat on API credits, and a key profile named `api.name` (default
    `api.adapter`): that name is unique, and is also the CodeCompanion adapter
    it registers. `api_key` names an `NVIM_*` variable.

  The list as shipped is `claude` (terminal; `claude_code` through
  `claude-agent-acp`; `anthropic` on `NVIM_ANTHROPIC_API_KEY`) then `codex`
  (terminal; `codex` through `codex-acp`, `auth_method = "chat-gpt"`;
  `openai` on `NVIM_OPENAI_API_KEY`). A second key on one API is one more
  provider with only an `api` part (the file has an example). `M.build`
  validates the list at load, and a bad entry stops startup, naming the
  provider.
- The order is the only preference. `<leader>an`/`:AI new` lists every
  available terminal, then every ACP chat, then every API chat, each group in
  provider order. A key only a native agent answers asks among the installed
  terminals in that order (below). CodeCompanion's own paths that name no
  adapter (a typed `:CodeCompanionChat`, the action palette) use the first
  `acp` in provider order, else the first `api`, and `auto` is the first
  `api` whose key is set (below). The order never decides what a key is called or where
  it acts. `vi` is plain `nvim`: no launcher flag picks an agent, and
  `NVIM_AI_PROVIDER`/`vim.g.ai_provider` are not read -- a leftover value
  earns one warning that it is no longer read, not a failed start.
  `:AI provider` is gone and says so, pointing at `:AI new` and the order of
  `lua/ai/config.lua`. `:AI info` lists the providers in order with their
  parts (terminal · ACP · API, ✗ where unavailable here), the adapter
  CodeCompanion's own chats use, the key, the profiles, the CLI keys and the
  open chats. `:checkhealth config` ("config: AI backends") warns of a
  missing CLI or ACP bridge, which the picker leaves out, and errors only
  when nothing at all is available.
  `NVIM_AI_KEY_PROFILE` (optional) is the startup HTTP key profile, which
  `:AI key` (`<leader>ax`, `lua/ai/switch.lua`) switches; nothing is
  persisted. A key switch changes state, `<leader>ae`'s description and
  CodeCompanion's inline/cmd adapters only -- it never starts, stops, shows or
  hides a native terminal, ACP connection or chat.
- One AI window per tabpage (`lua/ai/slot.lua`): the right shows at most one
  of native Claude, native Codex or a CodeCompanion chat. Showing one hides
  the others in this tabpage through their owner's hide (claudecode's
  `cc_hide`, Snacks' hide, CodeCompanion's `ui:hide`) -- never a stop, close
  or wipe, never edgy's hide/close, never another tabpage; a window its owner
  cannot hide (claudecode's terminal copy in a diff tabpage) is left alone,
  and still counts as shown here: a key delivers to that copy where it is,
  and nothing opens a second window beside it or jumps away from it. The one
  copy `<leader>ac` closes is a chat's whose own window is in another
  tabpage (the successor `,q` leaves there, below): the chat stays on screen
  there.
  `<leader>ac` never hides a tabpage's only window. Hide comes first, show
  second, except when the windows to hide are all the tabpage has (E444). A
  `BufWinEnter` guard holds the rule for upstream's own paths (`<leader>ao`,
  a typed `:CodeCompanionChat`/`:ClaudeCode`, the action palette, the
  successor CodeCompanion shows after `,q`, claudecode's re-show after a
  diff); it records the tabpage when the event fires, ignores floats, and
  the latest AI window entered in a tick wins.
  Between two chats the window is handed over in place; a terminal window
  cannot take another buffer (Snacks' fixbuf), so between a terminal and
  anything else one window closes and another opens.
- The chat keys (`ac`, `af`, `ab`, `as`, `ai`) act on the chat on the right,
  read off the windows: the one shown in this tabpage; from a
  prefix-blocking view (CodeDiff), the one shown in the page the view came
  from (`util.window.origin_tab`, which `ai.review.feedback` uses too), which
  becomes current; otherwise they ask, listing the open chats (● here / tab
  N / hidden, with billing) and "New chat…", or the new-chat picker when none
  is open (`ac`/`af` first bring back `vim.t.ai_slot_last`, below). `an` and
  `al` always ask -- the new-chat picker and that switcher -- from the same
  page. A chat shown in another tabpage is gone to, never moved. A
  question cancelled from a view goes back to the view. `<leader>ac` from a
  view goes into the origin's chat as `<leader>af` would: the user never saw
  it, so hiding it would only strand them outside the view. A delivery that
  changes tabpage says so once ("Sent to X (tab N)"), not also as a jump. Nothing is
  delivered silently to a hidden chat, another tabpage's or a provider picked
  for the user; `vim.t.ai_slot_last` only lets `ac`/`af` bring the last one
  back.
  `ab` asks among the native agents alone, since a chat takes no file. A
  selection is captured with plain Neovim API before any question
  (`ai.selection.capture`): vim.ui.select is asynchronous, and Visual mode is
  gone by its answer. `ar`/`aR`/`am` and `at`/`aT` act on the native agent
  on the right, else ask which (the installed terminals in provider order;
  with one installed, that one). Each native agent keeps one session per Nvim: `ar`/`aR`/`am` show a
  running one and leave it as it is, saying so, instead of toggling it away
  with their arguments dropped, and the new-chat picker's native entry is
  that session ("running", "● here"), never a second; `at`/`aT` only read
  its records. oil's `<leader>aS` is in every oil buffer and refuses
  unless Claude Code is on the right: it reads the listing's cursor where it
  is, so it asks nothing, as a listing's Visual `as` does not.
  Nothing is typed into a running agent's box for `am`: it may hold a draft
  an Enter would submit, or an approval an Enter would answer. A cold start
  that asks first (a backend's `asks_first`: claudecode's model question for
  Claude's `am`) hides nothing, since it can be cancelled; the guard hides
  the rest once its terminal shows. A session these keys start is announced,
  as one `<leader>an` starts is. Both agents read a mention from disk, so a
  buffer with unsaved changes is said: Codex gets the exact text instead,
  Claude a warning with its mention.
  A native agent cold-starts from the editor window
  (`util.window.editor_win`, which does not toggle like `focus_editor`), so
  its root is the edited file's. Delivering review feedback (`ai.feed`) makes
  room for the round's agent, whichever it is; a panel already on screen in
  any tabpage makes nothing yield there. Per-buffer behaviour (terminal input
  rules, edgy slot, statusline label, image hand-back, the feedback a review
  round delivers) follows the buffer's own agent. A prompt float whose path
  names no agent (`ai.config.agent_of_prompt` answers nil: a `git commit`
  run in an agent's pane) has no owner: it takes no seed, `<C-v>` refuses,
  and its title is " Prompt "; nothing falls back to the first provider's
  agent or any other.
- The key profile is `auto` unless pinned: `auto` is the first provider
  `api` whose `NVIM_*` key is set, else the first `api`, resolved when `auto`
  is selected (at startup, and at every `:AI key auto`, which picks again
  when a key was exported since); `:AI key <name>` and `NVIM_AI_KEY_PROFILE`
  pin one. With no `api` in the list there is no key, and inline edits and
  command prompts refuse with a notice (`ai.companion.preflight`), never a
  Lua error.
  It is the key of inline edits and command prompts alone: an API chat's
  profile is the one its new-chat entry names. The statusline names the key
  only while one is pinned.
- Native Claude and Codex share the same `<leader>a` keys and open or refocus
  in terminal input mode. The facade owns every `<leader>a` key
  (`lua/ai/init.lua`, `apply_keymaps`). Their descriptions are fixed and name
  no agent -- what a key reaches is the chat on the right, which a description
  cannot follow -- except `<leader>ae`, which names the key profile it bills
  and is relabelled by `:AI key`, and the Claude-only `<leader>aa`/`<leader>ad`
  and oil's `<leader>aS`, which say "Claude". `<leader>an`/`<leader>al` are
  leaves. `<leader>aa`/`<leader>ad` answer Claude's diffs and exist once
  claudecode.nvim has loaded, whatever is on the right. The CodeCompanion keys
  are facade-owned too, not in its lazy spec; they load the plugin on first
  `require`. So are `<leader>av`/`aV` (review): a round belongs to a
  conversation, and they load the review modules on first press. `<leader>ap`
  is a leaf: no `<leader>ap*` mapping may return. `<leader>ag`/`aG`/`ah`/`aH`
  are gone: a chat of either kind starts from `<leader>an`.
- Claude proposes its diffs in a tabpage of its own
  (`diff_opts.open_in_new_tab`, asserted by `tests/ai_terminal_spec.lua`):
  claudecode picks its target window by skipping `'diff'` windows, CodeDiff's
  panes never set `'diff'`, and its working-tree pane is an ordinary file
  window a proposal could land in.
- Two chat kinds, one picker: an ACP chat is an agent CLI over ACP, on the
  subscription; an API chat is a key profile over HTTP, on API credits. Both
  start from `<leader>an`, beside the native terminals: `ai.config.backends()`
  lists every backend the providers offer (the native terminals, the ACP
  chats, one API chat per key profile, never another upstream adapter), each
  entry naming its transport and billing and whether it can start here, the
  picker offers the ones that can, and `lua/ai/companion.lua` refuses before
  anything starts when the profile's `NVIM_*` key is unset or the ACP bridge
  is missing -- upstream's Toggle/Add only know `last_chat`, so it creates and
  shows exactly the chat asked for. A native entry stands for that agent's
  one session and never starts a second. A chat or session it starts is
  announced with its billing. Inline edits (`<leader>ae`) and command prompts
  use the key profile. Keep the billing visible: the picker's entries, the
  switcher's labels, the chat header (`roles.llm`, "CodeCompanion (Claude Code
  · ACP)") and the which-key heading over the keys that spend API credits
  (`HTTP · API credits`: `ae`, `ax`) name it. A chat's adapter is fixed at
  creation and `change_adapter` stays disabled. CodeCompanion's
  `interactions.chat.adapter` is the first `acp` adapter in provider order
  (else the first `api` profile's, else CodeCompanion's own), set at load and
  never changed; `:AI key` writes `interactions.inline.adapter` and
  `interactions.cmd.adapter` in the live config (`companion.sync`), never
  `vim.g.codecompanion_adapter` (v20 `cmd.lua` resolves it through
  `config.adapters[name]`, which is nil, and falls back to the chat adapter).
- codecompanion-history stores the local transcript; continuing the agent's
  stateful ACP session is a separate `/resume` workflow. Preserve that
  distinction in implementation and documentation.
- CodeCompanion's HTTP adapters read `NVIM_*` variables (as shipped
  `NVIM_ANTHROPIC_API_KEY` / `NVIM_OPENAI_API_KEY`), never
  `ANTHROPIC_API_KEY` / `OPENAI_API_KEY`: those
  are the CLIs' own and can take precedence over the subscription login, so a
  config that asks for them moves the native agent and agent chat onto API
  billing. Every key profile in `lua/ai/config.lua` names an `NVIM_*`
  variable, and config.lua refuses a profile naming a CLI variable.
  CodeCompanion's built-in `anthropic` and `openai` adapters are always
  extended (through `adapters.http.extend`) with `NVIM_ANTHROPIC_API_KEY` and
  `NVIM_OPENAI_API_KEY`, whatever the providers list holds -- a provider
  `api` registered under the built-in's own name sets its own `NVIM_*` key
  over that -- so a chat restored from history or an upstream path naming
  one never reads a CLI variable. Likewise the built-in `codex` ACP adapter
  always gets `auth_method = "chat-gpt"` (`builtin_acp_auth`), whatever the
  list holds, since codex-acp's own default (`api-key`) bills
  `OPENAI_API_KEY`; a provider's `acp.auth_method` sets its adapter's over
  that. Nothing
  writes `vim.env` for billing variables. Exercised by
  `tests/ai_api_key_spec.lua`.
- CodeCompanion is an additional chat/inline workflow, not a second native
  terminal facade. Do not stack overlapping native integrations. Its own code
  review stays off (`interactions.code_review.enabled = false`, and
  `#{code_review}` offered to no interaction), `:CodeCompanionCodeReview` is
  deleted after setup and is not a lazy `cmd` trigger: that review keeps a
  second set of baselines under `refs/worktree/codecompanion/*`, and there is
  one baseline system here, `refs/nvim-review/`. `tests/companion_spec.lua`
  asserts the command stays gone.
- Preserve the Claude tmux wrapper and watchdog unless a replacement is tested
  against terminal flicker, CJK rendering, cleanup, resume, and appended CLI
  arguments. Claude's watchdog, and its sweep of stale servers, starts when
  claudecode.nvim first loads -- with the first Claude this Nvim starts --
  as Codex's does on its first spawn.
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
- Inline ghost text (`lua/plugins/ai/minuet.lua`) is not part of the AI
  facade: it always comes from the local `llama-server` that `util.llama`
  shares between Nvims, whatever the providers list or the chat on the right.
  Do not route it through `ai.config`. The server only starts when a UI is
  attached, so the headless spec suite never loads the model; keep that guard.

## Review Baselines

- A baseline is an immutable snapshot of a worktree (`lua/util/baseline.lua`):
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
- Every git command `util.baseline` runs, and those of util.codediff's
  listing, `util.codediff_actions` and `ai.review`, goes through
  `util.baseline.git_cmd`: `--no-optional-locks` (no opportunistic index
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
  revision-vs-working-tree listing goes through util.codediff's listing patch
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
  `util.baseline.set_exempt`). Objects are left to git's own gc. Exercised by
  `tests/baseline_spec.lua`.

## Agent Hooks

- Local native plugins share `NVIM_AI_PLUGIN_DIR` (`lua/ai/plugins.lua`): an
  entry is a plugin directory or a distribution root with `claude/<plugin>`
  and `codex/<plugin>` packages. Claude receives `--plugin-dir`; Codex gets
  invocation-local marketplace/enabled overrides (reusing an enclosing native
  catalog's identity when available) after refreshing local
  snapshots through `plugin add`. Installation uses a disposable CODEX_HOME
  sharing only the real plugin cache; never write the user's config or change
  global enablement. Preserve native hook trust. Nothing installs at Nvim
  startup or for CodeCompanion. `tests/native_plugins_spec.lua` exercises
  offline discovery and both Codex terminal launch paths without a thread.
- The native agents' prompt hooks are injected per process, never through
  the user's configuration. Claude gets `--settings <json>`
  (`build_terminal_cmd` in `lua/plugins/ai/claudecode.lua`): UserPromptSubmit, plus
  SessionStart run async. Codex gets one `-c hooks={...}` (`codex_command` in
  `lua/ai/backend/codex.lua`): UserPromptSubmit only, with its
  `trusted_hash` under `state` in the same `-c`, so it runs without a review
  prompt. Both CLIs merge these with the user's own hooks. Nothing writes
  `~/.claude/settings.json`, `~/.codex/config.toml` or `vim.env` for them; no
  `--dangerously-bypass-hook-trust` (it trusts every project's hooks) and no
  `notify` override (it replaces the user's). Codex gets no SessionStart: it
  runs only at a thread's first turn, never before its first
  UserPromptSubmit.
- `lua/ai/review/hook.lua` builds both strings with a hand-written JSON
  encoder (sorted keys, serde_json's escapes: Codex hashes the handler that
  way) and computes the trust hash from the same data as the command it
  injects. It is pure string work, because the plugin spec calls it at
  startup: no plugin, no git. A Codex upgrade that changes the hash or the
  key format turns the hook untrusted without a word;
  `tests/agent_hook_spec.lua` pins the hash against fixed vectors.
- `scripts/agent-hook <agent> <event> [<wait-ms>]` never prints and always
  exits 0: both CLIs feed a hook's stdout to the model, report any other
  status as a hook error, and exit 2 blocks the prompt. Its wait is bounded:
  a submit waits for the baseline up to `hook_wait_ms` (in argv, since the
  script cannot read Lua), the RPC's delivery as long but never under
  0.5 s, and a client that failed -- no socket, a receiver that raised --
  ends the wait at once. It deletes the payload when it stops waiting; that
  is how Nvim tells a baseline that landed too late (Late), and a request
  that arrives after it (a missed submit: no baseline, possibly a notice).
- `hook.event` answers the RPC at once and schedules the work. Events that
  carry `agent_id` (a Claude subagent or teammate, a Codex spawned thread)
  are dropped there, and again in `rounds.native_event`: they belong to the
  parent's turn. `sources.claude` / `sources.codex` gate the injection, and
  the receiver reads them again on every event.
- The hook finds its Nvim through the `NVIM` both wrappers already forward;
  the agent kind travels in argv. Add no environment variable for it: a new
  one has to join both wrappers' `new-session -e` whitelist, or it silently
  never reaches the pane.
- The injected words follow the CLI's name, so `agent_of_command` still
  finds the agent (`tests/agent_hook_spec.lua` and
  `tests/ai_terminal_spec.lua`, both wrapper paths), and claudecode's appended
  `--resume`/`--continue` still land after them through `"$@"`. Claude's
  command is built again in claudecode's `config`, so a `vim.g.ai_review` set
  later in `init.lua` reaches the first launch; Codex's on every spawn.

## One Round Model

- Every source opens rounds through `rounds.submit`
  (`lua/ai/review/rounds.lua`), where the round rules live once: the native
  UserPromptSubmit hooks (`rounds.native_event`), CodeCompanion's
  `on_before_submit` for agent and API chats (attached on
  `User CodeCompanionChatCreated`), and `<leader>aV` (`rounds.start`).
  `<leader>gK`'s saved baselines are no round and belong to no conversation.
  Outside an agent's or a chat's own buffer, `<leader>aV`'s owner and the
  round `<leader>av` prefers are the chat on the right's
  (`ai.slot.shown_here`: this tabpage's, or from a CodeDiff view the page it
  came from; of several, the current window's, else none -- it never asks
  and never moves), and `rounds.live_conversations` lists that one first.
  No provider stands in when nothing is on the right, the first one
  included.
  Claude waking itself to go on with the work opens no round
  (`continues_turn` in `rounds.lua`): a `<task-notification>` when a
  background task it started finishes, and a background agent's
  `[Subagent hand-back]` message. Their changes and their turn end belong to
  the session's newest round -- the prompt that started the task, unless the
  user prompted again in between. They still report the session and count as
  a prompt for `rounds.prompted_at`. A scheduled wake-up (ScheduleWakeup,
  `/loop`, cron) is a prompt like any other.
- Conversation ids are `claude:<session_id>`, `codex:<session_id>` and
  `cc:<nonce>:<chat.id>`, with a nonce made once per process: CodeCompanion's
  `chat.id` comes from an unseeded `math.random`, so two Nvims, or one before
  and after a restart, hand out the same ids. The chat callback waits for the
  baseline with a bounded `vim.wait(hook_wait_ms)` and never returns false,
  which would cancel the user's submit. A baseline that lands after its
  source stopped waiting is recorded `Late`.
- A conversation's root is the Git toplevel of the agent's working
  directory, fixed when it starts: a native terminal's cwd at TermOpen, a
  chat's `getcwd()` at ChatCreated (CodeCompanion's ACP session and tools work
  there). Claude starts in the current file's Git root, as Codex does
  (claudecode's `cwd_provider`, `claude_cwd = "git_root"`); an agent that
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
- Seeds are per agent (`ai.editor.stage_seed`, whose agent is
  required): feedback staged for
  Claude is never taken by a Codex prompt, or the other way round, and
  exactly one of `on_consumed` / `on_expired` fires. A draft is copied to
  `<id>.last-sent.md` and emptied only once its text arrived -- that agent's
  prompt editor took the seed, or `ai.companion.add_text` succeeded. A seed
  not taken within `seed_ttl_ms`, or replaced by a plain `<leader>ai`, leaves
  the draft as it was.
- A round proves only that a change came after its baseline: the user or
  another agent in the same worktree is listed too. Messages say "changes
  since round HH:MM:SS", never "the agent's changes".
- There is one review tab per root. `<leader>av` reads every tabpage's
  `vim.t.ai_review` and closes only an older review of the same root, through
  CodeDiff's own close; it never changes another tabpage's windows.
- Exercised by `tests/review_round_spec.lua` (round rules, the
  `resolve_sink` matrix), `tests/review_view_spec.lua`,
  `tests/review_feedback_spec.lua` (drafts, sinks, seed slots),
  `tests/compose_spec.lua` (`<leader>ai`'s seeds) and
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
  (`lua/util/codediff_actions.lua`). `]h`/`[h` in every view's panes are
  CodeDiff's own next/prev hunk (as its `]c`/`[c`, which stay), installed by
  util.codediff through `set_keys`. Terminal digits only map Normal mode.
  grug-far's editable search panel uses `,S...`, in its own panel only (its
  own which-key section, filetype `grug-far`); in a CodeDiff pane `,S` is the
  stage key. Its plugin defaults also use localleader and must not overwrite
  general comma actions.
  A CodeCompanion chat (`interactions.chat.keymaps` in
  `lua/plugins/ai/codecompanion.lua`) puts upstream's acts that took keys
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
  `on_attach` in `lua/plugins/lang/typescript.lua`. The dividing line is whether the key
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
  `lua/plugins/ai/codecompanion.lua`: "Save chat", "Clear chat messages",
  "Close chat (ends it)", "Fold code blocks"), and the chat's `gh` reads
  "Browse saved Companion chats", as `<leader>ao` does.
- Under a which-key popup the letter may be a mnemonic or an accident, but the
  `desc` is the interface: it is exact, and one act is worded one way
  everywhere (`tests/key_descriptions_spec.lua`; `tests/ai_keymap_spec.lua`
  for `<leader>a`, and the view and LSP specs for theirs). Sentence case: the
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
  confirmation -- before it acts: `<leader>an`/`al`/`ar`/`am`/`ae`/`ax`/`ap`,
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
  Same `nowait` and hint, through util.codediff's `set_keys`, handed back on
  close; only `;` and `s` swallow the next key, these are whole keys. Picking
  a buffer by its tab letter is `;B` (bufferline), so the `;` block covers it.
  Behind the keys, util.codediff's `guard_panes` puts back any swap of a
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
  `lua/config/options.lua` so the first frame, drawn before bufferline loads on
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
  `fill` in the bufferline spec, `TabLineFill` in `lua/plugins/ui/solarized.lua`
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
  No keystroke reaches them either: edgy's panel keys `<c-q>` (hide) and `Q`
  (close the edgebar) are off in `opts.keys` (`lua/plugins/editor/edgy.lua`),
  with its `]w`/`[w`/`]W`/`[W` window cycling, which took the global warning
  jumps; `q` and the `<c-w>` resizers stay.
- The first tabpage stays a page the global prefixes work in
  (`util.window.protect_first_tab`, driven by `TabClosed` and
  `SessionLoadPost`). Views open after it on their own -- `tab split`
  inserts after the current tabpage -- so the guard only repairs the state
  where the pages in front of a view are gone. It keys on the view, not on
  window contents: CodeDiff's working-tree pane holds an ordinary file
  buffer, so every window-level check calls its tabpage editable while `;f`
  is mapped to a disabled hint throughout it. The view says so itself:
  util.codediff sets `vim.t.blocks_global_prefixes` on `CodeDiffOpen` and
  clears it on `CodeDiffClose`, which `util.window.blocks_global_prefixes`
  reads first; `PREFIX_BLOCKING_FILETYPES` (`codediff-explorer`,
  `codediff-history`) is the second test, for a tabpage CodeDiff let go of
  with its panel still on screen. A single-file `:CodeDiff file` has no
  panel, so a new prefix-blocking view sets that tab variable (and adds its
  panel filetypes). `tests/first_tab_spec.lua` stands a view in with the
  variable alone.
- Both paths that place a stopped frame -- nvim-dap's `switchbuf`
  (`util.dap.jump`) and nvim-dap-ui's `select_window` -- must stay scoped to the
  current tabpage. `usetab`, or anything else that hunts across tabpages, turns
  the debug view into something that steals focus from an editor tabpage on
  every step, which is more intrusive than the split layout it replaced.
- Do not force-delete ordinary buffers from terminal-specific mappings.
- Popup sections are declared as data in `lua/config/whichkey_spec.lua` (`sections`,
  keyed by prefix then suffix) and only read by `lua/plugins/editor/whichkey.lua`.
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
  determine which rows exist; headings never create keys or load plugins.
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
  `icon`, `desc`, `group` and `icon_hl`. This, `lua/util/codediff.lua` and
  `lua/ai/companion.lua` (next items) are the only places here that depend on
  plugin internals, apart from these narrower ones: `lua/ai/backend/claude.lua`
  drives claudecode through `claudecode.terminal` (`open`, which reuses its one
  terminal and never hides it, `ensure_visible`, `get_active_terminal_bufnr`)
  and `claudecode.send_at_mention` (a selection's lines, and `<leader>ab`'s
  file: `:ClaudeCodeAdd` splits its argument on whitespace), and finds its
  Snacks terminal by buffer -- `tests/ai_terminal_spec.lua` pins those
  signatures against the pinned plugin's source; `:checkhealth config`
  asks CodeDiff for its library and watcher versions (next item);
  `lua/util/window.lua` sizes edgy's panels through `edgy.editor`, the
  edgebars in `edgy.config.layout` and `edgy.layout.update` (window sizing,
  above); and `lua/util/diffsplit.lua` tells gitsigns' revision windows by
  their `gitsigns://` buffer names, which `tests/gitsigns_spec.lua` pins. The `sort`
  replacement is guarded (a renamed `sort` drops headings and colours,
  ordering still works through the supported `sort` option, nothing errors)
  and covered by `tests/whichkey_popup_spec.lua`, with real contextual menus
  covered by `tests/context_actions_spec.lua`. It assumes the single-column `helix`
  preset: a multi-column preset would split a heading from its items.
- `lua/util/codediff.lua` is the one reader of CodeDiff's internals;
  everything else -- `lua/util/codediff_actions.lua`, `ai.review`, the
  `<leader>g` spec -- goes through it, and only the specs and
  `lua/config/health.lua` require `codediff.core.*` or `codediff.ui.*`
  themselves. The health check is the second, sanctioned reader, of two
  values and nothing else: the library's version through
  `core.diff.get_version`, called only from `:checkhealth`, only once the
  library file exists, and with `VSCODE_DIFF_NO_AUTO_INSTALL` held at 1 for
  the require (which loads the plugin); and the watcher release it wants,
  `core.installer.watcher.VERSION`, read only once CodeDiff is loaded. Both
  are pcall'd and type-checked. `lua/util/codediff.lua` also relies on the
  chunk names of CodeDiff's modules (its `lua/codediff/` directory, read from
  `require("codediff").setup` at setup), which tell its own pane swaps from
  others (`guard_panes`); without that prefix it lets every swap through, as
  plain CodeDiff does. `lua/util/codediff.lua` reads `ui.lifecycle`
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
  `lua/plugins/git/codediff.lua`. CodeDiff's own setup runs inside
  `util.codediff.setup`, after the runner patch, since each
  `codediff.core.git.*` module copies `run_async` when it loads.
  `tests/codediff_spec.lua` pins the internals,
  `tests/codediff_listing_spec.lua` the listing and
  `tests/hunk_actions_spec.lua` `refresh.request`; moving the pin means
  re-running them first. Keys on a view go through its `set_keys`,
  CodeDiff's own keymap registry, from `User CodeDiffKeys`: the panes borrow
  the user's real file buffers, and the registry suspends its claims on them
  in other tabpages and hands every key back when the view closes. Never map
  a pane buffer with a bare `vim.keymap.set`.
- `lua/ai/companion.lua` reads CodeCompanion's `chat.adapter`, `chat.ui`
  (`is_visible`, `is_visible_non_curtab`, `open`, `hide`, `hide({
  keep_window = true })`, `winnr`), `chat.title`, `chat.prompt:add`,
  `interactions.chat.open({ ui, winnr })`, the `hidden` argument of
  `codecompanion.chat()` and `buf_get_chat()`'s entries, because upstream's
  Toggle and Add cannot be aimed at one chat, and its window-less `Chat.open`
  closes `last_chat` wherever it is shown. A chat is created hidden and shown
  as exactly itself: gone to in another tabpage, handed a chat window here
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
  a window that is not its own, which `show` and `focus_prompt` use where it
  is and `<leader>ac` closes.
  `ai.slot` reaches chats only through `ai.companion` (`chats`, `chat_of`,
  `key`, `buf`, `label`, `name`, `win`, `where`, `busy`, `hide`, `create`,
  `focus_prompt`), which reads them in a pcall and checks what it gets. A
  failure is reported as an error by the facade's guards; nothing falls back
  to an upstream command, which would aim at `last_chat` instead.
  `tests/companion_spec.lua` pins the internals without creating an ACP chat
  (that spawns the bridge) or sending a request, and
  `tests/ai_slot_spec.lua` the slot. Review feedback goes to one exact chat
  through `add_text`, `busy` and `show_input`, which also read
  `chat.current_request` and the private
  `chat._turn_in_progress`: a tool loop clears `current_request` and makes the
  buffer editable between its steps, and only that flag stays set. It is read
  in a pcall, so a rename upstream loses that signal only; `add_text` answers
  `false, "gone"|"busy"|"failed"` rather than raising, and
  `tests/review_feedback_spec.lua` pins the mid-loop refusal.
- which-key keeps description-only spec entries in its own trie, so `maparg()`
  cannot see those. Entries with an RHS are created through `vim.keymap.set`
  after which-key's scheduled loader runs; assert those with `maparg()` after
  `VimEnter`, and assert description-only entries against `whichkey_spec`.
  A description-only entry outranks every desc, buffer-local ones included,
  so it is only for a key that no buffer remaps. A key with a buffer-local
  twin carries a real desc on its global mapping instead: the treesitter
  moves `]m`/`]c` (and `]M`/`]C`, `[`-side alike) and the `af`/`ac` objects
  (`lua/plugins/ui/treesitter.lua`), whose twins are CodeDiff's `]c`, Python's
  and VimTeX's `]m` and VimTeX's `ac`; and Nvim's `gO`, whose twins are the
  markdown, help, checkhealth and man outline. Nvim's LSP defaults (`gO`,
  `grr`/`gri`/`grt`/`grn`/`gra`/`grx`) keep their callbacks:
  `lua/config/keymaps.lua` rewrites only their desc, in place, with `mapset()`, and
  leaves alone one that something already replaced. Filetype plugins' own
  desc-less motions (Python's `]]`, VimTeX's `]n`, man's `gO`) get descs from
  `whichkey_spec`'s `filetype_descs`, which `lua/plugins/editor/whichkey.lua`
  writes onto the buffer's own mapping on `FileType` -- never as a which-key
  entry, which would outlive the filetype.
- Window commands should normally affect the current tab only. Be deliberate
  before using global APIs such as `nvim_list_wins()`.
- Messages and the cmdline come from noice (`lua/plugins/ui/noice.lua`), which
  hands Vim's messages to the snacks notifier; vim.notify goes to that
  notifier directly (noice's own `notify` is off). noice's LSP progress, hover
  and signature help are off too: lualine, `K` and blink.cmp own those, and a
  second owner draws them twice. So is its `window/showMessage` handler, which
  is nil at the pinned commit and dropped every server message: Nvim's own
  goes to vim.notify. noice drops any message kind no route names, and Nvim
  0.11+ has kinds its defaults miss (`:!` output, `:w`'s `progress`, undo,
  quickfix); `routes` in `lua/plugins/ui/noice.lua` names them, and
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
- Add or remove plugins through lazy.nvim specs and include the resulting
  `lazy-lock.json` change. claudecode.nvim is declared always (lazy,
  cmd-triggered). Never make a spec conditional on the providers in
  `lua/ai/config.lua`: lazy then prunes its lock line and lists the plugin in
  `to_clean`, so `:Lazy clean`/`sync` deletes it.

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
(the llama-server util.llama shares, git index and gitsigns watcher timing),
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
submit a chat: the specs hand hook payloads to `ai.review.hook.event` and
dispatch a chat's `on_before_submit` directly.

Use `:checkhealth config` as the config-specific dependency check and
`:ConformInfo`, `:checkhealth vim.lsp`, `:Mason`, and `:Lazy profile` as the
primary diagnostic sources. Do not reach for `:LspInfo` — nvim-lspconfig stops
defining the `Lsp*` commands once Nvim 0.12's builtin `:lsp` exists.

## Code Review Rules

- Flag provider behavior that works for Claude but not Codex, or vice versa.
- Flag force deletion, cross-tab window mutation, unescaped shell paths, and
  lazy specs that load a plugin earlier than their declared trigger.
- Flag README/README_CN claims that disagree with the active Lua configuration.
