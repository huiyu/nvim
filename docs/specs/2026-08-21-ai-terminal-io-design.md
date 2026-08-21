# Design: AI terminal input and transcript viewing

## Requirements Reference

- Requirements evidence: `docs/scope/2026-08-21-ai-terminal-io.md`
- Covers: UC-1 … UC-8, UC-11 … UC-19, UC-R1 … UC-R8
- Deferred to issue #14: UC-9, UC-10, UC-20, UC-21, UC-R9
- NFRs: performance (measured), third-party format compatibility, error
  handling, privacy

## Process deviation

DevMuse's mu-arch normally records each trade-off as `docs/adr/NNNN-<slug>.md`.
This repository already has an established convention for the same purpose:
decision rationale lives in code comments next to the code it explains — see
`lua/util/terminal.lua:26-47` (why libvterm only invalidates on shrink) and
`lua/plugin/lsp/ai.lua:47-54` (why `TERM` is downgraded for the child). That also
matches the operator's stated documentation priority, which puts code comments
above standalone markdown. No `docs/adr/` tree is created. The Decisions section
below carries the rationale, and the implementation carries the same rationale as
comments.

## Measured constraints

All figures from this machine, Nvim 0.12.2, `vim.json.decode` over the real
on-disk transcripts.

| Input | Records | Time | Lua heap |
|---|---|---|---|
| This project's largest transcript (1.8 MB) | 527 | 3 ms | — |
| Codex typical (3.6 MB) | 355 | 4.8 ms | — |
| Codex pathological (270 MB) | 29 844 | 349 ms | 244 MB |
| Same, streamed into a 500-record ring buffer | 500 | 68 ms | 21 MB |
| Codex session discovery (line 1 of 194 files) | 194 | 19 ms | — |

Two conclusions follow, and both remove architecture rather than adding it:

1. **Everything is synchronous.** No async job, no `fs_event` watcher, no
   incremental render. The realistic case is 3 ms.
2. **A cap is a safety valve, not a feature.** Only a 270 MB transcript from an
   unrelated project comes close to mattering. Streaming into a fixed-size ring
   buffer bounds both time and memory at essentially no cost.

## Component map

Only the neighbourhood this change touches. `➕` new, `✏️` modified.

```
                    lua/ai/init.lua  ✏️
                    provider-neutral facade, keymaps
                            │
            ┌───────────────┼────────────────┐
            │               │                │
    composer.lua ➕   selection.lua ➕   transcript/ ➕
    scratch buffer    visual → draft    init.lua  open_current/pick/refresh
    + submit          text (shared)     render.lua  entries → lines + foldlevels
            │               │           claude.lua  ┐ Adapter
            │               │           codex.lua   ┘
            └───────┬───────┘
                    │ send_text(text, opts)
            ┌───────┴────────┐
    backend/claude.lua ✏️   backend/codex.lua ✏️
    claudecode.terminal      export existing
    .send_to_terminal        private send()
```

`lua/mappings.lua` is **not** touched: the chords that would have lived there are
deferred to issue #14.

`lua/ai/transcript/render.lua` and `init.lua` never learn which provider is
active. Provider knowledge is confined to the two adapters and the two backends.

## Interfaces

```lua
---@class ai.transcript.Session
---@field id string        -- short identifier shown in the picker
---@field path string      -- absolute path to the JSONL file
---@field mtime integer    -- sort key, newest first
---@field title string?    -- Claude exposes ai-title records; Codex has none

---@class ai.transcript.Entry
---@field role "user"|"assistant"
---@field kind "text"|"thinking"|"tool_call"|"tool_result"
---@field text string
---@field name string?     -- tool name, for tool_call / tool_result
---@field time string?     -- HH:MM, for the turn header

---@class ai.transcript.Adapter
---@field sessions fun(root: string): ai.transcript.Session[]
---@field parse fun(path: string, cap: integer): ai.transcript.Entry[], boolean
```

`parse` returns the entries plus a `truncated` flag. The adapter is selected the
same way backends already are:

```lua
local function adapter()
  return require("ai.transcript." .. require("ai.config").provider)
end
```

Backends gain one method, matching the facade's existing `invoke` dispatch:

```lua
---@param text string
---@param opts { submit?: boolean, focus?: boolean }
---@return boolean sent
function M.send_text(text, opts) end
```

- Codex: the existing private `send()` (`lua/ai/backend/codex.lua:172`) becomes
  this, unchanged in behaviour.
- Claude: delegates to `require("claudecode.terminal").send_to_terminal`, which
  already applies the same bracketed-paste and trailing-CR contract.

**The two are not equivalent at the edges, and `send_text` is where that is
levelled.** Codex's `send()` calls `ensure()` and starts the agent when none is
running, deferring 350 ms for the channel to come up. `send_to_terminal` is
documented as the opposite: it "does NOT open the terminal: it requires one to
already be running, otherwise it warns and returns false". UC-3 requires the
start-then-send behaviour from both, so the Claude implementation is:

```
send_text(text, opts):
  if no active terminal bufnr:
      terminal.ensure_visible()
      defer 350ms          -- same readiness delay Codex already proved
  send_to_terminal(text, opts)
```

The 350 ms is not a new guess; it is the constant `codex.lua` already uses for
the same race. Both backends therefore satisfy UC-3 with one contract:
`send_text` starts the agent if needed and returns whether the text was written.

## Composer

**Submit semantics are `git commit`'s, implemented with `buftype=acwrite`.**
That is what makes `:wq` mean submit and `:q!` mean abort without inventing a
mapping:

| Action | Mechanism | Result |
|---|---|---|
| `:w`, `:wq`, `ZZ` | `BufWriteCmd` fires, sets `submitted=true`, clears `modified` | text sent on wipeout |
| `:q!` | force-quit, `BufWriteCmd` never fires | nothing sent (UC-5) |
| `:q` with content | refused with `E37` because `modified` is set | nothing lost |
| empty / whitespace only | blank test runs before send | nothing sent, notice shown (UC-4) |

The send itself happens on `BufWipeout`, reading the buffer before it is
destroyed, then calling `send_text(text, { submit = true, focus = true })`.

**No instructional text goes into the buffer.** `git commit` puts `# Please
enter…` in the file and strips comment lines afterwards; a stripping rule is a
liability here because prompts legitimately contain `#`. The hint lives in the
composer window's `winbar` instead, so buffer content is exactly what gets sent.

**Placement is a float.** The agent panel is a fixed-width right-hand split
(`ai.config.panel.width = 90`), and AGENTS.md warns against layout-fragile
multi-window views. A centred float disturbs no window geometry and needs no
`winfix*` bookkeeping.

**Seeding from a visual selection (UC-6) uses a shared helper.** The draft-
building logic currently lives inline in `codex.lua:258-294`. It moves to
`lua/ai/selection.lua` with identical behaviour; `codex.lua` calls it, so
`<leader>as` is unchanged (UC-R2), and the composer calls it for seeding. Claude's
`<leader>as` continues to use `:ClaudeCodeSend` over the IDE WebSocket — that
path is untouched. Only composer *seeding* is unified, because seeding needs
text and the WebSocket route does not produce any.

## Terminal-mode chords — deferred to issue #14

UC-9, UC-10, UC-20 and UC-21 are not implemented in this round. `man tmux` on
`extended-keys off`: "this feature is disabled and only standard keys are
reported." Every `<C-S-x>` collapses to `<C-x>` before Nvim receives it, so the
mappings could not fire. The same finding indicates `lua/mappings.lua:87`'s
`<C-S-l>` is already dead code.

Issue #14 holds the evidence, the two-line tmux fix, and the verification probe.
`lua/mappings.lua` is untouched by this change.

## Transcript viewer

### Discovery

| Provider | Method |
|---|---|
| Claude | cwd → slug (`/` and `.` both become `-`), then `~/.claude/projects/<slug>/*.jsonl` sorted by mtime |
| Codex | glob `~/.codex/sessions/**/*.jsonl`, sort by mtime, read line 1 of each, keep those whose `session_meta.payload.cwd` equals the project root |

`/Users/jeff/.config/nvim` → `-Users-jeff--config-nvim`, confirmed against disk.
The Codex scan costs 19 ms for 194 files and needs no cache.

### Record mapping

| Entry | Claude | Codex |
|---|---|---|
| user text | `type=user` → `message.content[] type=text` | `response_item`/`message`/`role=user` → `input_text` |
| assistant text | `type=assistant` → `text` | same path with `output_text`; also `agent_message` |
| thinking | `thinking` block | `response_item`/`reasoning` |
| tool call | `tool_use` | `custom_tool_call` |
| tool result | `tool_result` | `custom_tool_call_output` |
| skipped | `attachment`, `system`, `mode`, `last-prompt`, `ai-title`, `file-history-*`, `queue-operation` | `role=developer`, `turn_context`, `world_state`, `session_meta`, `event_msg` |

Claude's `message.content` is sometimes a bare string instead of a block array;
both forms occur in the same file and the adapter handles both.

### Render

Markdown sections, one heading per turn:

```markdown
# claude · 4ccc2adc · 2026-08-21 00:02
> /Users/jeff/.config/nvim · 84 turns

## ▌ You · 00:02
有哪些Open issue

## ▌ Claude · 00:02
当前仓库共 8 个 Open issue：

| # | 标题 |
|---|---|
| 13 | LSP staleness... |

+--  4 lines: ▸ thinking ---------------
+--  8 lines: ▸ Bash  gh issue list ----
```

`render.lua` returns `lines` and a parallel `foldlevels` array. Text entries are
level 0; thinking and tool entries are level 1, so `foldlevel=0` opens on a
buffer where prose is visible and machinery is folded (UC-14).

**Thinking will almost never appear, and that is a property of the data, not of
this design.** Neither CLI persists reasoning text. Claude writes `thinking`
blocks whose `thinking` field is an empty string -- measured 123/123, 4/4 and
50/50 empty across three real sessions, with only the signature retained. Codex
writes `reasoning` records whose `summary` is empty and whose real content sits
in `encrypted_content` -- measured 58/58. Both adapters therefore skip empty
thinking rather than emitting blank entries, and render it only if a future CLI
version starts persisting it. Folding remains essential regardless: tool calls
and their results were 402 of 529 entries in a real session.

### Buffer configuration

```lua
buftype    = "nofile"     -- UC-R5, cannot reach disk
bufhidden  = "wipe"
modifiable = false
swapfile   = false
filetype   = "ai-transcript"
foldmethod = "expr"
foldexpr   = "v:lua.require'ai.transcript.render'.foldexpr()"
foldlevel  = 0
```

Buffer-local `R` refreshes (UC-13) and `q` closes. AGENTS.md assigns single
letters to standalone panels, which this is; it owns one window and no file.
The cursor lands on the last line after render (UC-11): the newest turn is the
entry point, and searching backward with `?` is the intended motion.

## Traceability

| UC | Where it is satisfied |
|---|---|
| UC-1 | `composer.open()` — float, empty buffer, `startinsert` |
| UC-2 | `BufWriteCmd` marks submitted, `BufWipeout` sends |
| UC-3 | `send_text` start-then-send contract, both backends |
| UC-4 | blank test precedes send, notice on discard |
| UC-5 | `:q!` never fires `BufWriteCmd` |
| UC-6 | `lua/ai/selection.lua` seeds the composer |
| UC-7 | bracketed paste in both send primitives |
| UC-8 | `send_text` returns false, draft left intact |
| UC-11 | cursor to last line after render |
| UC-12 | `transcript.pick()` over `adapter.sessions(root)` |
| UC-13 | buffer-local `R` → `transcript.refresh(buf)` |
| UC-14 | `foldlevels` — text 0, thinking/tool 1, `foldlevel=0` |
| UC-15 | Codex adapter filters on `session_meta.payload.cwd` |
| UC-16 | Claude adapter resolves the cwd slug |
| UC-17 | empty `sessions()` → notify, open nothing |
| UC-18 | ring-buffer cap at 5000, truncation stated in header |
| UC-19 | per-line `pcall(vim.json.decode, …)`, skip on failure |
| UC-R1 | new keys are `ai`/`at`/`aT`, all previously unbound |
| UC-R2 | `codex.send_selection` keeps calling the extracted helper; Claude's `<leader>as` still routes to `:ClaudeCodeSend` |
| UC-R3 | `lua/mappings.lua` is not modified at all this round |
| UC-R4 | `setup_scrollback_maps` is not touched; the viewer is additive |
| UC-R5 | `buftype=nofile`, `modifiable=false` |
| UC-R6 | adapters open transcripts read-only and never write |
| UC-R7 | the composer wipes only its own scratch buffer; `q` closes only the transcript's own window |
| UC-R8 | no change to `lua/plugin/lsp/ai.lua` or the watchdog |

## Decisions

**Fold with `foldexpr`, not `foldmarker`.** Markers would have to be written into
the rendered text, so every yank out of the transcript would carry `{{{`/`}}}`
into the destination. `foldexpr` reads a buffer-local level table produced by the
renderer: the text stays exactly what the agent said, and fold structure is
deterministic rather than inferred.

**A dedicated `ai-transcript` filetype with `vim.treesitter.start(buf,
"markdown")`, not `filetype=markdown`.** Setting the filetype to markdown inherits
markdown's ftplugin, any markdown LSP, conform configuration, and treesitter's own
folding — the last of which would fight the `foldexpr` above. Starting the
markdown parser explicitly borrows the highlighting without the rest.

**Stream into a ring buffer; cap at 5000 records and say so.** Measured: full
retention of the pathological 270 MB transcript costs 349 ms and a 244 MB Lua
heap, versus 68 ms and 21 MB streamed. This project's largest transcript is 527
records, so the cap will not fire here — it exists so a transcript from another
project cannot hang the editor. When it does fire, the buffer header states how
many records were dropped. No silent truncation.

**Read JSONL rather than the terminal.** Claude runs on the alternate screen
(`CLAUDE_CODE_NO_FLICKER=1`), so its tmux scrollback is permanently empty —
measured `alt=1 hist=0/2000` against the live wrapper. Reading the persisted
transcript is the only source that works for both providers, and it keeps the
Claude tmux wrapper untouched (UC-R8). Full rationale is in the scope document.

## NFR scan

**Performance** — triggered, and resolved by measurement above rather than by
design. Worst realistic case is 3 ms.

**Third-party format compatibility** — the largest standing risk. Both JSONL
formats are undocumented implementation details of tools that update frequently,
so a schema change will eventually break parsing. Mitigation is structural: the
adapters skip any record they do not recognise instead of raising, so a partial
schema change degrades to missing entries rather than a broken viewer. If a parse
yields zero entries the viewer reports the path it tried, making the failure
diagnosable rather than silent.

**Error handling** — a partial trailing line is expected whenever the agent is
mid-write, so decode failures are skipped per line (UC-19). A missing transcript
notifies instead of opening an empty buffer (UC-17). An unavailable terminal
channel at submit time warns and leaves the draft intact (UC-8).

**Privacy** — transcripts contain the entire conversation, including anything
pasted into it. The viewer reads local files, renders into a `nofile` buffer, and
transmits nothing. It never writes, locks, or truncates the source.

## Validation

The repository has no test framework; validation is headless assertions plus
targeted manual reproduction, proportional to the change.

Automatable headless:

- both providers start clean — the two `NVIM_AI_PROVIDER` commands from AGENTS.md
- each adapter parses the real on-disk transcripts for this project and yields a
  non-zero entry count with no decode errors
- the renderer produces `#lines == #foldlevels`
- `<leader>ai`, `<leader>at`, `<leader>aT` resolve to the intended callbacks and
  no existing `<leader>a` mapping changed (UC-R1)

Manual, because they need a live agent or a real terminal:

- composer round trip under both providers: `:wq` sends, `:q!` aborts, empty
  aborts, multi-line arrives as one message (UC-2, UC-4, UC-5, UC-7)
- transcript folding, `R` refresh, and picker selection under both providers

## Documentation impact

- `README.md` and `README_CN.md` — the `<leader>a` key table gains `ai`, `at`,
  `aT`
- `docs/UTILITIES.md` — `lua/ai/selection.lua` is a new public helper contract
- `docs/DIAGNOSTICS.md` — how to diagnose an empty or partial transcript, since
  that is the failure the third-party format risk will produce
