# AI Terminal Input and Transcript Viewing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use devmuse:mu-code to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the agent panel a real editor for composing prompts and a
searchable Vim buffer for reading past output, symmetrically for Claude and
Codex.

**Deferred:** Terminal-mode `<C-S-…>` chords (UC-9, UC-10, UC-20, UC-21) are
out of scope — see issue #14. `lua/mappings.lua` is not modified.

**Architecture:** A provider-neutral facade (`lua/ai/init.lua`) gains three
methods. Provider knowledge stays confined to two backends (which send text) and
two transcript adapters (which locate and parse JSONL). A shared renderer turns
the adapter's common `Entry` model into a folded Markdown buffer.

**Tech Stack:** Lua, Nvim 0.12 API, `vim.json`, `vim.treesitter`, Snacks
(terminal + picker), claudecode.nvim.

**Spec:** `docs/specs/2026-08-21-ai-terminal-io-design.md`
**Scope:** `docs/scope/2026-08-21-ai-terminal-io.md`

---

## Global Constraints

Every task must honour these; they come from AGENTS.md and the approved spec.

1. **Provider symmetry.** No feature may work for Claude but not Codex, or vice
   versa. If a capability cannot be made symmetric, stop and report rather than
   shipping one side.
2. **Comments carry rationale.** This repo records decisions in code comments,
   not an ADR tree. Every non-obvious constant, guard, or workaround gets a
   comment explaining *why*, in the style of `lua/util/terminal.lua:26-47`.
   All comments in English.
3. **No force deletion.** Never `bdelete!` a buffer the feature does not own.
4. **Current tab only.** Use `nvim_tabpage_list_wins`, not `nvim_list_wins`.
5. **Lazy triggers must match first use.** No plugin loads earlier than its
   declared trigger.
6. **Escape user paths** with `vim.fn.shellescape` in any shell fragment.
7. **Preserve unrelated working-tree changes.** The tree carries uncommitted
   Codex `--yolo` edits in `README.md`, `README_CN.md`, `docs/DIAGNOSTICS.md`,
   and `lua/ai/backend/codex.lua`. Stage only files this plan touches, and only
   the hunks it created.

## Interfaces

Produced by Task 4, consumed by Tasks 5 and 7:

```lua
---@class ai.transcript.Entry
---@field role "user"|"assistant"
---@field kind "text"|"thinking"|"tool_call"|"tool_result"
---@field text string
---@field name string|nil   -- tool name, for tool_call / tool_result
---@field time string|nil   -- "HH:MM"

---@class ai.transcript.Session
---@field id string
---@field path string
---@field mtime integer
---@field title string|nil

---@class ai.transcript.Adapter
---@field sessions fun(root: string): ai.transcript.Session[]  -- newest first
---@field parse fun(path: string, cap: integer): ai.transcript.Entry[], boolean
```

Produced by Task 2, consumed by Task 3:

```lua
-- lua/ai/backend/<provider>.lua
---@param text string  non-empty
---@param opts { submit?: boolean, focus?: boolean }
---@return boolean sent
function M.send_text(text, opts) end
```

Produced by Task 1, consumed by Task 3:

```lua
-- lua/ai/selection.lua
---@return string|nil draft, string|nil err
function M.draft() end   -- reads the current visual selection
```

## Test convention

This repo has no test framework and does not need one. Tests are plain Lua
assertion scripts under `tests/`, run headlessly against the real config:

```sh
nvim --headless -u init.lua -i NONE -c 'luafile tests/<name>.lua' -c qa
```

Each script prints `ok - <what>` per assertion and calls `error()` on failure, so
a non-zero exit or a missing `ok` line is the failure signal. Add
`tests/run.sh` in Task 0 to run them all.

Fixtures are hand-written miniatures, never real transcripts — real ones contain
private conversation content and must not enter the repo.

---

## Task 0: Test harness

**Covers:** infrastructure for every later task

**Files:**
- Create: `tests/run.sh`
- Create: `tests/helper.lua`

- [ ] **Step 1: Write the helper**

```lua
-- tests/helper.lua
local M = {}
local failures = 0

function M.ok(cond, what)
  if cond then
    print("ok - " .. what)
  else
    failures = failures + 1
    print("FAIL - " .. what)
  end
end

function M.eq(got, want, what)
  M.ok(vim.deep_equal(got, want), ("%s (got %s, want %s)")
    :format(what, vim.inspect(got), vim.inspect(want)))
end

function M.done()
  if failures > 0 then
    error(("%d assertion(s) failed"):format(failures), 0)
  end
end

return M
```

- [ ] **Step 2: Write the runner**

```sh
#!/bin/sh
# tests/run.sh — run every tests/*_spec.lua against the real config.
set -e
cd "$(dirname "$0")/.."
status=0
for f in tests/*_spec.lua; do
  [ -e "$f" ] || continue
  echo "== $f"
  nvim --headless -u init.lua -i NONE -c "luafile $f" -c qa || status=1
done
exit $status
```

- [ ] **Step 3: Verify it runs with no specs present**

Run: `chmod +x tests/run.sh && ./tests/run.sh`
Expected: exits 0, prints nothing but the shell trace

- [ ] **Step 4: Commit**

```bash
git add tests/run.sh tests/helper.lua
git commit -m "test: add headless assertion harness"
```

---

## Task 1: Extract the selection draft helper

**Covers:** UC-6, UC-R2

`lua/ai/backend/codex.lua:258-294` builds a draft string from the visual
selection. The composer needs the same string, and Claude's `<leader>as` cannot
supply one because it routes over the IDE WebSocket. Move the logic to a neutral
module with **identical behaviour**, then have Codex call it.

**Files:**
- Create: `lua/ai/selection.lua`
- Modify: `lua/ai/backend/codex.lua:258-294`
- Test: `tests/selection_spec.lua`

- [ ] **Step 1: Write the failing test**

```lua
-- tests/selection_spec.lua
local t = require("tests.helper")
local sel = require("ai.selection")

-- Unsaved buffer: must fence the literal text, never emit an @-mention.
local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "alpha", "beta" })
vim.bo[buf].filetype = "lua"
vim.api.nvim_set_current_buf(buf)
vim.cmd("normal! ggVG")
local draft = sel.draft()
t.ok(draft ~= nil, "draft() returns a string for an unsaved buffer")
t.ok(draft:find("alpha", 1, true) ~= nil, "draft contains the selected text")
t.ok(draft:find("@", 1, true) == nil, "unsaved buffer produces no @-mention")
t.ok(draft:find("```", 1, true) ~= nil, "unsaved buffer text is fenced")

-- No selection at all: must fail softly, not raise.
vim.cmd("normal! \\<Esc>")
local none, err = sel.draft()
t.ok(none == nil and type(err) == "string", "no selection returns nil plus a reason")

t.done()
```

- [ ] **Step 2: Run it to verify it fails**

Run: `nvim --headless -u init.lua -i NONE -c 'luafile tests/selection_spec.lua' -c qa`
Expected: FAIL — `module 'ai.selection' not found`

- [ ] **Step 3: Implement `lua/ai/selection.lua`**

Signature: `function M.draft() -> string|nil, string|nil`

Constraints:
- Lift the logic from `codex.lua:258-294` verbatim in behaviour. Do not
  redesign it while moving it.
- Saved and unmodified file → `("@%s lines %d-%d "):format(rel, first, last)`,
  **with the trailing space** — the composer and the TUI both rely on it.
- Otherwise → a fenced block labelled with the buffer's filetype, falling back
  to `text`; the fence is four backticks, matching the current code.
- `first`/`last` come from `math.min`/`math.max` over `getpos("v")` and
  `getpos(".")`, because the selection can be made in either direction.
- Return `nil, "<reason>"` when `vim.fn.getregion` fails or yields no lines. Do
  not call `vim.notify` here; the caller decides how to surface it.
- Comment why this module exists at all: Claude's `<leader>as` uses the IDE
  WebSocket and produces no text, so composer seeding needs a neutral producer.

- [ ] **Step 4: Run the test to verify it passes**

Expected: 5 `ok -` lines, exit 0

- [ ] **Step 5: Rewire Codex and prove no behaviour change**

Replace the body of `codex.lua`'s `M.send_selection` with a call to
`require("ai.selection").draft()`, keeping its existing `vim.notify` calls for
the unsaved-buffer warning. The observable behaviour of `<leader>as` under Codex
must be identical.

Run: `NVIM_AI_PROVIDER=codex CODEX_HOME="$HOME/.codex-oauth" nvim --headless -u init.lua -i NONE +qa`
Expected: exit 0

- [ ] **Step 6: Commit**

```bash
git add lua/ai/selection.lua tests/selection_spec.lua
git add -p lua/ai/backend/codex.lua   # only this task's hunks
git commit -m "refactor(ai): extract visual-selection draft into ai.selection"
```

---

## Task 2: `send_text` on both backends

**Covers:** UC-3, UC-7, UC-8

**Files:**
- Modify: `lua/ai/backend/codex.lua:172-196`
- Modify: `lua/ai/backend/claude.lua`
- Test: none — this needs a live agent; covered by Task 9's manual checks

- [ ] **Step 1: Export Codex's existing send**

Signature: `function M.send_text(text, opts) -> boolean`

Constraints:
- The existing private `send()` already implements the contract. Rename it and
  make it return `true` when `nvim_chan_send` ran, `false` when the channel was
  missing. Keep every existing caller (`select_model`, `add_buffer`,
  `send_selection`) working through the renamed function.
- Do not change the bracketed-paste wrapping or the `\r` submit byte.
- Do not change the 350 ms `created` delay.

- [ ] **Step 2: Implement Claude's `send_text`**

Signature: `function M.send_text(text, opts) -> boolean`

Constraints:
- `claudecode.nvim`'s `terminal.send_to_terminal` **does not start the
  terminal** — it warns and returns false when none is running. UC-3 requires
  start-then-send, so check `terminal.get_active_terminal_bufnr()` first and
  call `terminal.ensure_visible()` when it is nil.
- After starting, defer 350 ms before sending. Use the same constant Codex uses
  and comment that it is the same channel-readiness race, not a new guess.
- Pass `opts` straight through: `send_to_terminal` already applies bracketed
  paste and the trailing CR, so do not wrap the text a second time.
- Return whether the text was written.

- [ ] **Step 3: Verify both providers still start**

Run both AGENTS.md provider commands.
Expected: exit 0 for each

- [ ] **Step 4: Commit**

```bash
git add lua/ai/backend/claude.lua
git add -p lua/ai/backend/codex.lua
git commit -m "feat(ai): add provider-neutral send_text to both backends"
```

---

## Task 3: Composer buffer

**Covers:** UC-1, UC-2, UC-4, UC-5, UC-6, UC-8

**Files:**
- Create: `lua/ai/composer.lua`
- Test: `tests/composer_spec.lua`

- [ ] **Step 1: Write the failing test**

```lua
-- tests/composer_spec.lua
local t = require("tests.helper")
local composer = require("ai.composer")

-- Capture sends instead of touching a real agent.
local sent = {}
composer._send = function(text, opts) sent[#sent + 1] = { text = text, opts = opts } end

-- Empty composer must abort (UC-4).
composer.open()
local buf = vim.api.nvim_get_current_buf()
t.ok(vim.bo[buf].buftype == "acwrite", "composer buffer is acwrite")
vim.cmd("write")
vim.cmd("bwipeout")
t.eq(#sent, 0, "empty composer sends nothing")

-- Whitespace-only must also abort (UC-4).
composer.open()
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "   ", "", "\t" })
vim.cmd("write")
vim.cmd("bwipeout")
t.eq(#sent, 0, "whitespace-only composer sends nothing")

-- Written then closed must send, submitting (UC-2).
composer.open()
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "line one", "line two" })
vim.cmd("write")
vim.cmd("bwipeout")
t.eq(#sent, 1, "written composer sends once")
t.eq(sent[1].text, "line one\nline two", "multi-line text is sent intact")
t.ok(sent[1].opts.submit == true, "send requests submission")

-- Never written must abort, mirroring :q! (UC-5).
composer.open()
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "discard me" })
vim.cmd("bwipeout!")
t.eq(#sent, 1, "unwritten composer sends nothing")

-- Seeding (UC-6).
composer.open("seeded text")
t.eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "seeded text" }, "seed lands in the buffer")
vim.cmd("bwipeout!")

t.done()
```

- [ ] **Step 2: Run it to verify it fails**

Expected: FAIL — `module 'ai.composer' not found`

- [ ] **Step 3: Implement `lua/ai/composer.lua`**

Signature: `function M.open(seed) end`

Constraints:
- `buftype = "acwrite"` is what makes `:wq` mean submit and `:q!` mean abort
  without inventing a mapping. Comment that this is deliberate `git commit`
  semantics, and that `:q` refusing with `E37` on a modified buffer is the
  feature protecting a half-written prompt.
- `BufWriteCmd` sets a `submitted` flag and clears `modified`. It must not write
  anything to disk.
- `BufWipeout` reads the buffer, and sends only when `submitted` is true **and**
  the text is not blank after `vim.trim`. On abort, `vim.notify` at INFO that
  the draft was discarded.
- Send through `M._send`, a module field defaulting to
  `require("ai").send_text`, so tests can substitute it. Comment that the
  indirection exists for testability.
- Window is a centred float. Do not create splits: the agent panel is a
  fixed-width side split and AGENTS.md warns against layout-fragile
  multi-window views.
- The usage hint goes in the window's `winbar`, never into the buffer. Comment
  why: `git commit` strips `#` lines, and prompts legitimately contain `#`, so a
  stripping rule would eat real content.
- Open in Insert mode (`startinsert`) with the cursor after any seed text.
- Guard against a second composer: if one is already open, focus it instead of
  stacking a new float.

- [ ] **Step 4: Run the test to verify it passes**

Expected: 9 `ok -` lines, exit 0

- [ ] **Step 5: Commit**

```bash
git add lua/ai/composer.lua tests/composer_spec.lua
git commit -m "feat(ai): add composer buffer with git-commit submit semantics"
```

---

## Task 4: Transcript adapters

**Covers:** UC-15, UC-16, UC-19

**Files:**
- Create: `lua/ai/transcript/claude.lua`
- Create: `lua/ai/transcript/codex.lua`
- Create: `tests/fixtures/claude-sample.jsonl`
- Create: `tests/fixtures/codex-sample.jsonl`
- Test: `tests/transcript_adapter_spec.lua`

- [ ] **Step 1: Write the fixtures**

Hand-write one record per shape. Real transcripts must never be committed.

`tests/fixtures/claude-sample.jsonl` — one line each:
`{"type":"user","message":{"role":"user","content":"bare string form"}}`,
a `user` record whose `content` is a `text` block array,
an `assistant` record with `text` plus `thinking` plus `tool_use` blocks,
a `user` record carrying a `tool_result` block,
an `attachment` record and an `ai-title` record (both must be skipped),
and a deliberately malformed line: `{"type":"assistant"` (UC-19).

`tests/fixtures/codex-sample.jsonl` — one line each:
a `session_meta` with `payload.cwd` set to `/tmp/fixture-project`,
a `response_item` `message` with `role=user` and an `input_text` block,
a `response_item` `message` with `role=assistant` and an `output_text` block,
a `response_item` `reasoning`, a `custom_tool_call`, a `custom_tool_call_output`,
a `response_item` `message` with `role=developer` (must be skipped),
an `event_msg` (must be skipped),
and a malformed trailing line.

- [ ] **Step 2: Write the failing test**

```lua
-- tests/transcript_adapter_spec.lua
local t = require("tests.helper")
local root = vim.fn.fnamemodify("tests/fixtures", ":p")

for _, name in ipairs({ "claude", "codex" }) do
  local adapter = require("ai.transcript." .. name)
  local entries, truncated = adapter.parse(root .. name .. "-sample.jsonl", 1000)

  t.ok(#entries > 0, name .. ": parses at least one entry")
  t.ok(truncated == false, name .. ": small fixture is not truncated")

  local kinds, roles = {}, {}
  for _, e in ipairs(entries) do
    kinds[e.kind] = true
    roles[e.role] = true
    t.ok(type(e.text) == "string", name .. ": every entry carries text")
  end
  t.ok(kinds.text, name .. ": recognises text")
  t.ok(kinds.thinking, name .. ": recognises thinking")
  t.ok(kinds.tool_call, name .. ": recognises tool calls")
  t.ok(kinds.tool_result, name .. ": recognises tool results")
  t.ok(roles.user and roles.assistant, name .. ": recognises both roles")

  -- The malformed final line must be skipped, not raised (UC-19).
  t.ok(true, name .. ": malformed line did not raise")
end

-- The cap streams rather than retaining everything (UC-18).
local capped, was_truncated = require("ai.transcript.claude")
  .parse(root .. "claude-sample.jsonl", 1)
t.ok(#capped <= 1, "cap limits retained entries")
t.ok(was_truncated == true, "cap reports truncation")

t.done()
```

- [ ] **Step 3: Run it to verify it fails**

Expected: FAIL — `module 'ai.transcript.claude' not found`

- [ ] **Step 4: Implement both adapters**

Signatures:
`function M.sessions(root) -> Session[]` and
`function M.parse(path, cap) -> Entry[], boolean`

Shared constraints:
- Read with `io.lines`, decoding one line at a time under
  `pcall(vim.json.decode, line)`. A failed decode is skipped silently — a
  partial trailing line is normal while the agent is mid-write.
- Retain entries in a fixed-size ring buffer of `cap` elements. Never build a
  list of every record first: measured, full retention of a 270 MB transcript
  costs 349 ms and a 244 MB Lua heap versus 68 ms and 21 MB streamed. Comment
  those numbers.
- Return `truncated = true` when more entries were produced than `cap`.
- An unrecognised record type is skipped, never an error. Comment that both
  formats are undocumented third-party details that will change, so degrading
  to missing entries beats a broken viewer.

Claude constraints:
- `sessions(root)`: slug is `root` with **both** `/` and `.` replaced by `-`,
  giving `/Users/jeff/.config/nvim` → `-Users-jeff--config-nvim`. Glob
  `~/.claude/projects/<slug>/*.jsonl`, sort by mtime descending.
- `title` comes from records with `type == "ai-title"` (field `aiTitle`).
- `parse`: handle `message.content` being **either** a bare string or a block
  array — both occur in the same real file.
- Map `text`→text, `thinking`→thinking, `tool_use`→tool_call (name from
  `.name`), `tool_result`→tool_result. Skip every other `type`.

Codex constraints:
- `sessions(root)`: glob `~/.codex/sessions/**/*.jsonl`, sort by mtime
  descending, then read **only line 1** of each and keep those whose
  `payload.cwd` equals `root`. Measured at 19 ms for 194 files, so no cache.
- `parse`: only `type == "response_item"` yields entries. Within it,
  `payload.type == "message"` maps `input_text`/`output_text` by
  `payload.role`; `reasoning`→thinking; `custom_tool_call`→tool_call;
  `custom_tool_call_output`→tool_result; `agent_message`→assistant text.
- Skip `role == "developer"`, `event_msg`, `turn_context`, `world_state`,
  `session_meta`.

- [ ] **Step 5: Run the test to verify it passes**

Expected: all `ok -`, exit 0

- [ ] **Step 6: Commit**

```bash
git add lua/ai/transcript/ tests/fixtures/ tests/transcript_adapter_spec.lua
git commit -m "feat(ai): add Claude and Codex transcript adapters"
```

---

## Task 5: Transcript renderer

**Covers:** UC-14

**Files:**
- Create: `lua/ai/transcript/render.lua`
- Test: `tests/transcript_render_spec.lua`

- [ ] **Step 1: Write the failing test**

```lua
-- tests/transcript_render_spec.lua
local t = require("tests.helper")
local render = require("ai.transcript.render")

local entries = {
  { role = "user",      kind = "text",        text = "hello",        time = "00:02" },
  { role = "assistant", kind = "thinking",    text = "pondering",    time = "00:02" },
  { role = "assistant", kind = "tool_call",   text = "gh issue list", name = "Bash", time = "00:02" },
  { role = "assistant", kind = "tool_result", text = "13 OPEN",      name = "Bash", time = "00:02" },
  { role = "assistant", kind = "text",        text = "8 open issues", time = "00:03" },
}

local lines, folds = render.build(entries, {
  provider = "claude", id = "abcd1234", root = "/tmp/p", truncated = false,
})

t.eq(#lines, #folds, "every line has a fold level")
t.ok(lines[1]:match("^# "), "starts with a level-1 markdown heading")

local joined = table.concat(lines, "\n")
t.ok(joined:find("hello", 1, true) ~= nil, "user text is rendered")
t.ok(joined:find("8 open issues", 1, true) ~= nil, "assistant text is rendered")
t.ok(joined:find("pondering", 1, true) ~= nil, "thinking is present, not dropped")

-- Prose must be visible at foldlevel 0; machinery must be foldable.
local text_line, think_line
for i, l in ipairs(lines) do
  if l:find("hello", 1, true) then text_line = i end
  if l:find("pondering", 1, true) then think_line = i end
end
t.eq(folds[text_line], 0, "text sits at fold level 0")
t.ok(folds[think_line] >= 1, "thinking sits at fold level 1 or deeper")

-- Truncation must be stated, never silent (UC-18).
local tl = render.build(entries, {
  provider = "claude", id = "x", root = "/tmp/p", truncated = true, dropped = 42,
})
t.ok(table.concat(tl, "\n"):find("42", 1, true) ~= nil, "truncation states how many were dropped")

t.done()
```

- [ ] **Step 2: Run it to verify it fails**

Expected: FAIL — `module 'ai.transcript.render' not found`

- [ ] **Step 3: Implement `render.build` and `render.foldexpr`**

Signatures:
`function M.build(entries, meta) -> string[], integer[]`
`function M.foldexpr() -> integer`

Constraints:
- Header is `# <provider> · <id> · <time>` then a `> <root> · N turns` line.
  When `meta.truncated`, add a line stating how many records were dropped.
- Each turn opens `## ▌ You · HH:MM` or `## ▌ <Provider> · HH:MM`.
- `text` entries get fold level 0. `thinking`, `tool_call`, `tool_result` get
  level 1, so `foldlevel=0` shows prose and hides machinery.
- Return the fold levels as a **parallel array**, never as `{{{` markers in the
  text. Comment why: markers would travel with any yank out of the buffer.
- `foldexpr()` reads `vim.b.ai_transcript_folds[vim.v.lnum]`, defaulting to 0
  when absent so a stale call cannot error.

- [ ] **Step 4: Run the test to verify it passes**

Expected: all `ok -`, exit 0

- [ ] **Step 5: Commit**

```bash
git add lua/ai/transcript/render.lua tests/transcript_render_spec.lua
git commit -m "feat(ai): render transcripts as folded markdown"
```

---

## Task 6: Transcript viewer

**Covers:** UC-11, UC-12, UC-13, UC-17, UC-R5, UC-R6

**Files:**
- Create: `lua/ai/transcript/init.lua`
- Test: `tests/transcript_view_spec.lua`

- [ ] **Step 1: Write the failing test**

```lua
-- tests/transcript_view_spec.lua
local t = require("tests.helper")
local view = require("ai.transcript")

-- Substitute a stub adapter so the test does not depend on real sessions.
view._adapter = function()
  return {
    sessions = function() return {
      { id = "s1", path = "/tmp/does-not-matter", mtime = 2 },
    } end,
    parse = function()
      return { { role = "user", kind = "text", text = "hi", time = "00:01" } }, false
    end,
  }
end

view.open_current()
local buf = vim.api.nvim_get_current_buf()

t.eq(vim.bo[buf].buftype, "nofile", "transcript buffer is nofile")
t.eq(vim.bo[buf].modifiable, false, "transcript buffer is read-only")
t.eq(vim.bo[buf].filetype, "ai-transcript", "transcript uses its own filetype")
t.eq(vim.wo.foldmethod, "expr", "folding is expression-driven")
t.ok(vim.b[buf].ai_transcript_folds ~= nil, "fold levels are attached to the buffer")
t.ok(vim.fn.line(".") == vim.fn.line("$"), "cursor starts at the end")
t.ok(vim.fn.maparg("R", "n") ~= "", "R is mapped for refresh")
t.ok(vim.fn.maparg("q", "n") ~= "", "q is mapped to close")
vim.cmd("bwipeout!")

-- No sessions must notify, not open an empty buffer (UC-17).
view._adapter = function()
  return { sessions = function() return {} end, parse = function() return {}, false end }
end
local before = vim.api.nvim_get_current_buf()
view.open_current()
t.eq(vim.api.nvim_get_current_buf(), before, "no sessions opens nothing")

t.done()
```

- [ ] **Step 2: Run it to verify it fails**

Expected: FAIL — `module 'ai.transcript' not found`

- [ ] **Step 3: Implement `lua/ai/transcript/init.lua`**

Signatures:
`function M.open_current() end`
`function M.pick() end`
`function M.refresh(buf) end`

Constraints:
- Adapter lookup goes through `M._adapter()`, defaulting to
  `require("ai.transcript." .. require("ai.config").provider)`, mirroring how
  `lua/ai/init.lua:6-8` resolves backends. The indirection exists for tests.
- Project root is `vim.fs.root(cwd, ".git")` falling back to cwd, matching
  `codex.lua`'s `project_root`.
- Buffer options exactly: `buftype=nofile`, `bufhidden=wipe`,
  `modifiable=false`, `swapfile=false`, `filetype=ai-transcript`.
- Highlight via `vim.treesitter.start(buf, "markdown")`, **not**
  `filetype=markdown`. Comment why: the markdown filetype drags in its ftplugin,
  LSP, conform config, and treesitter's own folding, and the last would fight
  our `foldexpr`.
- Window-local `foldmethod=expr`,
  `foldexpr=v:lua.require'ai.transcript.render'.foldexpr()`, `foldlevel=0`.
- Store the fold array in `vim.b[buf].ai_transcript_folds` before setting
  `foldmethod`, or the first fold evaluation sees nothing.
- Cursor to the last line after render (UC-11).
- Buffer-local `R` → `M.refresh(buf)`, `q` → close this window only. Never
  `bdelete!` anything else.
- Empty `sessions()` → `vim.notify` naming the directory that was searched, and
  open nothing (UC-17).
- `pick()` uses `Snacks.picker` over `sessions(root)`, showing title when the
  adapter provides one and the id otherwise.

- [ ] **Step 4: Run the test to verify it passes**

Expected: all `ok -`, exit 0

- [ ] **Step 5: Commit**

```bash
git add lua/ai/transcript/init.lua tests/transcript_view_spec.lua
git commit -m "feat(ai): add read-only transcript viewer"
```

---

## Task 7: Facade methods and leader mappings

**Covers:** UC-1, UC-11, UC-12, UC-R1

**Files:**
- Modify: `lua/ai/init.lua:26-36` (methods), `lua/ai/init.lua:57-63` (mappings)
- Test: `tests/ai_keymap_spec.lua`

- [ ] **Step 1: Write the failing test**

```lua
-- tests/ai_keymap_spec.lua
local t = require("tests.helper")

for _, lhs in ipairs({ " ai", " at", " aT" }) do
  t.ok(next(vim.fn.maparg(lhs, "n", false, true)) ~= nil, lhs .. " is mapped")
end

-- Nothing that already existed may have moved (UC-R1).
for _, lhs in ipairs({ " ac", " af", " ar", " aR", " am", " ab" }) do
  t.ok(next(vim.fn.maparg(lhs, "n", false, true)) ~= nil, lhs .. " still mapped")
end
t.ok(next(vim.fn.maparg(" as", "x", false, true)) ~= nil, "<leader>as still mapped in visual mode")

t.done()
```

- [ ] **Step 2: Run it to verify it fails**

Expected: FAIL — `<leader>ai is mapped` fails

- [ ] **Step 3: Add the facade methods and mappings**

Constraints:
- Add `M.compose()`, `M.transcript()`, `M.transcript_pick()`, and
  `M.send_text(text, opts)` following the existing `invoke` pattern so an
  unsupported backend degrades to the existing warning.
- `M.compose()` seeds from `require("ai.selection").draft()` when called from
  Visual mode, and opens empty otherwise.
- Map `<leader>ai`, `<leader>at`, `<leader>aT` with `desc` strings that name the
  provider, matching the existing `"Toggle " .. config.label` style.
- Do not touch any existing mapping.

- [ ] **Step 4: Run the test to verify it passes**

Expected: 10 `ok -` lines, exit 0

- [ ] **Step 5: Commit**

```bash
git add lua/ai/init.lua tests/ai_keymap_spec.lua
git commit -m "feat(ai): expose compose and transcript through the facade"
```

---

## Task 8: Documentation

**Covers:** documentation obligations from AGENTS.md

**Files:**
- Modify: `README.md`, `README_CN.md`, `docs/UTILITIES.md`, `docs/DIAGNOSTICS.md`

- [ ] **Step 1: Sync both READMEs**

`<leader>a` table gains `ai` composer, `at` transcript, `aT` session picker. The
terminal chords are deferred to issue #14 and must not be documented as
working. Keep `README.md` and `README_CN.md` behaviourally identical.

- [ ] **Step 2: Document the new utility contract**

`docs/UTILITIES.md` gains `lua/ai/selection.lua`: what `draft()` returns and
when it returns `nil`.

- [ ] **Step 3: Document the failure this will actually produce**

`docs/DIAGNOSTICS.md` gains a transcript section: both JSONL formats are
undocumented third-party details, so the expected failure mode is an empty or
partial transcript after a CLI update. Give the paths to check and note that
adapters skip unrecognised records by design.

- [ ] **Step 4: Verify and commit**

```bash
git diff --check
NVIM_AI_PROVIDER=claude nvim --headless -u init.lua -i NONE +qa
NVIM_AI_PROVIDER=codex CODEX_HOME="$HOME/.codex-oauth" nvim --headless -u init.lua -i NONE +qa
./tests/run.sh
git add -p README.md README_CN.md docs/UTILITIES.md docs/DIAGNOSTICS.md
git commit -m "docs: document composer, transcript viewer, and terminal chords"
```

---

## Manual verification

These need a live agent or real keypresses and cannot be automated here.

- [ ] Composer round trip under **Claude**: `<leader>ai`, type multi-line text,
      `:wq` → arrives as one message, agent takes focus
- [ ] Composer round trip under **Codex**: same
- [ ] Composer with no agent running → agent starts, then receives the text (UC-3)
- [ ] `:q!` in the composer sends nothing (UC-5)
- [ ] Empty composer closed with `:wq` sends nothing and says so (UC-4)
- [ ] Visual selection → `<leader>ai` seeds the composer (UC-6)
- [ ] `<leader>at` under both providers renders the current session, folded
- [ ] `R` refreshes after the agent writes more (UC-13)
- [ ] `<leader>aT` lists this project's sessions under both providers
- [ ] Codex tmux scrollback keys still work (UC-R4)
