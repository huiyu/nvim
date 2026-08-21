# Scope: AI terminal input and transcript viewing

## Problem

Two things are painful in the agent terminal panel.

**Input editing.** `lua/mappings.lua:102-116` binds `<C-h/j/k/l>` in Terminal-mode
for window navigation, so those bytes never reach the agent TUI. In Claude Code
and Codex those are the prompt-editing keys — `<C-h>` backspace, `<C-j>` insert
newline, `<C-k>` kill-to-end. Losing `<C-j>` is the sharpest edge: it is how you
write a multi-line prompt. `lua/mappings.lua:84-89` already recognised this
problem and recovered exactly one key, `<C-l>`, by forwarding `\x0c` on the
shifted chord `<C-S-l>`.

**Output review.** Scrolling back to find something is awkward. The current
answer for Codex is `setup_scrollback_maps` (`lua/ai/backend/codex.lua:123-147`),
which forwards scroll keys into tmux copy-mode. Copy-mode is not Vim: no `/`
search history, no text objects, no yank into the editor's registers.

## Evidence

Measured against the live tmux servers on this machine:

```
Claude  claude-nvim-40671   alt=1  hist=0/2000
Claude  claude-nvim-78941   alt=1  hist=0/2000
Codex   codex-nvim-91934    alt=0  hist=2711/50000   capture-pane -> 2773 lines
Codex   codex-nvim-12540    alt=0  hist=1331/50000   capture-pane -> 1394 lines
```

Codex runs `--no-alt-screen` (`lua/ai/backend/codex.lua:101`) with
`history-limit 50000` (line 53), so its transcript lives in tmux history. Claude
runs with `CLAUDE_CODE_NO_FLICKER=1` (`lua/plugin/lsp/ai.lua:96`), which puts it
on the alternate screen: **its tmux scrollback is permanently empty**. Reading
the terminal is therefore not a viable common source, and Claude is the daily
driver.

Both CLIs do persist structured transcripts:

| Provider | Location | Project resolution |
|---|---|---|
| Claude | `~/.claude/projects/<cwd-slug>/<uuid>.jsonl` | directory slug derived from cwd |
| Codex | `~/.codex/sessions/YYYY/MM/DD/rollout-<ts>-<id>.jsonl` | `session_meta.payload.cwd` inside the file |

Both providers already expose a text-send primitive that wraps content in
bracketed paste (`\27[200~` … `\27[201~`) so embedded newlines do not fire
premature submits:

- Codex — private `send(text, opts)`, `lua/ai/backend/codex.lua:172`
- Claude — `require("claudecode.terminal").send_to_terminal(text, opts)`

## Record shapes

Both files map onto one internal model.

| Model | Claude | Codex |
|---|---|---|
| user turn | `type=user`, `message.content[] type=text` | `response_item` / `payload.type=message` / `role=user` → `input_text` |
| assistant turn | `type=assistant` → `text` | same path, `role=assistant` → `output_text`; also `agent_message` |
| thinking | `thinking` block | `response_item` / `reasoning` |
| tool call | `tool_use` / `tool_result` | `custom_tool_call` / `custom_tool_call_output` |
| skip | `attachment`, `system`, `mode`, `last-prompt`, `ai-title`, `file-history-*` | `role=developer`, `turn_context`, `world_state`, `session_meta` |

`message.content` on the Claude side is occasionally a bare string rather than a
block array; both forms occur in the same file.

## Use cases

### Composer buffer

- UC-1: When `<leader>ai` is pressed, Then a scratch composer buffer opens for
  the active provider, in Insert mode, empty.
- UC-2: Given the composer holds text, When it is written and closed (`:wq`,
  `ZZ`), Then the text is sent to the agent with bracketed paste and a trailing
  carriage return, and the agent panel takes focus.
- UC-3: Given no agent terminal is running, When the composer is submitted, Then
  the agent starts first and receives the text once its channel is live.
- UC-4: Given the composer is empty or holds only whitespace, When it is closed,
  Then nothing is sent and a notice states the draft was discarded — `git commit`
  abort semantics.
- UC-5: When the composer is closed with `:q!`, Then nothing is sent regardless
  of content.
- UC-6: Given a visual selection, When the composer is opened from Visual mode,
  Then it is seeded with the same payload `send_selection` produces today.
- UC-7: Given multi-line content, When it is submitted, Then the agent receives
  one message, not one submit per line.
- UC-8: Given the agent's channel is unavailable at submit time, Then warn and
  leave the draft intact rather than dropping the text.

### Terminal-mode chords — deferred to issue #14

Four use cases originally lived here: `<C-S-h/j/k>` forwarding the editing bytes
the window-navigation maps consume (UC-9, UC-10), and `<C-S-e>` / `<C-S-t>`
opening the composer and viewer from Terminal-mode (UC-20, UC-21).

They are **out of scope for this round** because the keys provably cannot arrive.
The outer tmux runs `extended-keys off`, and `man tmux` is explicit: "When set to
off, this feature is disabled and only standard keys are reported." Every
`<C-S-x>` therefore collapses to `<C-x>` before Nvim sees it. The same finding
means `lua/mappings.lua:87`'s existing `<C-S-l>` mapping has almost certainly
never fired.

The fix is a two-line change in the dotfiles tmux config, which is a separate
repository and a deliberate decision. Issue #14 carries the evidence, the
deferred use cases, and the verification procedure.

**Consequence accepted for this round:** the composer has no one-key entry from
the agent's input box. Reaching it costs `<C-\>` or `jk` first, then
`<leader>ai`.

### Transcript viewer

- UC-11: When `<leader>at` is pressed, Then the active session's transcript
  renders into a read-only buffer with the cursor at the end.
- UC-12: When `<leader>aT` is pressed, Then a Snacks picker lists this project's
  sessions newest-first, and selecting one renders it the same way.
- UC-13: In a transcript buffer, `R` re-reads the file and re-renders.
- UC-14: Both providers render through one internal model: user and assistant
  text always visible, thinking and tool calls present but folded closed.
- UC-15: Given the provider is Codex, When resolving this project's sessions,
  Then filter candidates by `session_meta.payload.cwd` against the project root.
- UC-16: Given the provider is Claude, Then resolve
  `~/.claude/projects/<slug>/` from the project root.
- UC-17: Given no transcript exists for the project, Then notify and open
  nothing.
- UC-18: Given a large transcript (the Codex sample is 3.6 MB / 355 records),
  Then rendering stays responsive — parsing is capped or incremental rather than
  loading every record into one synchronous pass.
- UC-19: Given the last line is a partial write because the agent is appending,
  Then that line is skipped rather than raising a decode error.

### Must not change

- UC-R1: Every existing `<leader>a` mapping keeps its current behaviour and key.
- UC-R2: `add_buffer` and `send_selection` behave exactly as they do today,
  including the unsaved-buffer warnings.
- UC-R3: `<C-h/j/k/l>` window navigation and `<C-S-l>` redraw are unchanged.
- UC-R4: Codex's tmux scrollback maps (`setup_scrollback_maps`) keep working;
  the viewer is an addition, not a replacement.
- UC-R5: Transcript buffers are `buftype=nofile`, `modifiable=false`, so an
  accidental edit cannot reach disk.
- UC-R6: The viewer only reads transcript files. It never writes, locks, or
  truncates them, and never disturbs the running agent.
- UC-R7: No ordinary buffer is force-deleted by any new mapping.
- UC-R8: The Claude tmux wrapper, its watchdog, and `CLAUDE_CODE_NO_FLICKER=1`
  are untouched — the viewer exists precisely so that wrapper does not have to
  change.

## Conflicts

- UC-2 (close sends) vs UC-4 (empty aborts) — resolved: the whitespace-only test
  runs first, so an emptied composer always aborts.
- UC-6 (seeded from selection) vs UC-4 — resolved and intentional: clearing the
  seeded text is the way to cancel a selection send.
- UC-11 (cursor at end) vs the stated goal of scrolling back — resolved: the end
  is the correct entry point; searching backward with `?` is the intended motion.
- UC-13 (`R` refreshes) vs Normal-mode `R` (replace) — resolved: the buffer is
  unmodifiable, so `R` has no native meaning to preserve there.

## Out of scope

- Changing Claude to `--no-alt-screen`, or otherwise touching the tmux wrapper.
- Live tailing of transcripts. UC-13's manual refresh covers the need.
- Rendering images or file-history records from either transcript format.
- Editing or replaying past turns from the viewer.

## Provider symmetry

Every use case above resolves for both Claude and Codex. The two provider
differences are contained: transcript discovery (UC-15 vs UC-16) and the
send primitive behind the composer. Neither leaks into the facade contract in
`lua/ai/init.lua`, which gains `compose`, `transcript`, and `transcript_pick`
as ordinary provider-neutral methods.
