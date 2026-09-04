# Utility Modules Documentation

This document provides detailed documentation for all utility modules in the Neovim configuration.

## Overview

The utility modules provide focused helpers for logging, debug inspection, LSP, table manipulation, macOS input sources, terminals, windows, and running the current file. For diagnostic and debugging workflows (health checks, profiling, LSP/treesitter inspection), see [DIAGNOSTICS.md](DIAGNOSTICS.md).

## Core Utilities

### 📝 Logger (`util.logger`)

Structured logging framework with level control and history.

#### Features
- **Leveled Logging**: DEBUG, INFO, WARN, ERROR
- **Message Formatting**: Printf-style string formatting
- **History Tracking**: Keeps recent log entries for debugging
- **Safe Execution**: `safe_call()` for error handling
- **Environment Integration**: Configurable via `NVIM_LOG_LEVEL`

#### API Reference

```lua
local logger = require("util.logger")

-- Set log level
logger.set_level("DEBUG")  -- DEBUG|INFO|WARN|ERROR
local level = logger.get_level()

-- Logging methods
logger.debug("Debug message: %s", variable)
logger.info("Operation completed successfully")
logger.warn("Warning: %s may cause issues", feature)
logger.error("Critical error: %s", error_message)

-- Safe function execution
local success, result = logger.safe_call(function()
  -- Potentially failing operation
  return risky_operation()
end, "operation description")

-- History management
local recent = logger.get_recent(10)    -- Get last 10 entries
logger.show_recent(20)                  -- Print last 20 entries
logger.clear_history()                  -- Clear all history
```

#### Configuration

```bash
# Environment variables
export NVIM_LOG_LEVEL=DEBUG    # Set logging level
export NVIM_DEV=1              # Enable development logging
```

## Debug Inspection (`util.debug`)

Throwaway helpers for working *on* this configuration. Distinct from
`util.logger`, which carries messages a user of the config should see.

`init.lua` wires the module into two globals, lazily, so a startup that never
debugs never loads it:

```lua
_G.dd = function(...) require("util.debug").dump(...) end
vim.print = _G.dd
```

`dd(value, ...)` pretty-prints through `vim.notify`, titled with the file and
line that called it, and syntax-highlighted as Lua. Taking over `vim.print`
means `:lua =expr` lands in the same view. A call in a fast event is deferred
rather than dropped (`vim.notify` and treesitter are both unavailable there).

Note that `dd` reports the *caller's* frame, so `return dd(x)` mis-attributes:
a Lua tail call replaces the calling frame outright. Use `dd(x)` as a statement.

The rest is for a slowdown, not a value:

```lua
local debug = require("util.debug")

debug.extmark_leaks()          -- extmark count per namespace/buffer, worst first
debug.module_leaks("^snacks")  -- estimated MB per loaded module, worst first
debug.get_upvalue(fn, "state") -- reach a plugin's local state when it exposes none
```

`module_leaks()` sizes are an estimate, not a measurement: the per-type constants
are nominal and shared references are counted once. Use it to rank modules
against each other, not to trust a total.

Because `dd` is a global, `.luarc.json` lists it in `diagnostics.globals`
alongside `vim` and `Snacks`.

## macOS Input Method (`util.input_method`)

Keeps Normal and Terminal-Normal modes on an English keyboard layout while
restoring the last captured input source in Insert and terminal-input modes.
The module serializes `macism` operations so a rapid `Esc`/`i` sequence cannot
leave a stale switch as the final system state. It does nothing for headless
Nvim or non-macOS processes.

`setup()` is called by `lua/autocmds.lua`. The public inspection API is:

```lua
local input_method = require("util.input_method")

local source, origin = input_method.default_source()
-- source: e.g. "com.apple.keylayout.ABC"
-- origin: "NVIM_ENGLISH_INPUT_SOURCE" or "macOS keyboard layout"
```

Resolution order:

1. `NVIM_ENGLISH_INPUT_SOURCE`, when non-empty.
2. An enabled keyboard layout from `AppleEnabledInputSources`, preferring a
   Latin one (`ABC`, `US`, `Colemak`, `British`, …). That list is in the user's
   own order, so its first layout may be non-Latin — and Normal mode on a
   non-Latin layout is worse than no switching at all, since `d`, `w` and `:`
   would stop reaching Nvim. A non-Latin layout is still used when it is the
   only one enabled.
3. `defaults read com.apple.HIToolbox AppleCurrentKeyboardLayoutInputSourceID`.

Detection is deferred to the first UI event rather than run from `setup()`:
steps 2 and 3 shell out, and headless Nvim can never use the result.

The current text-entry source is not stored in an environment variable. It is
queried with `macism` whenever Insert or terminal-input mode is left and kept in
the Nvim process for the next restoration.

`ensure_normal_source()` backs the Normal-mode `<C-\>` and `<C-]>` mappings. It
queries the current source without changing modes, captures a non-default
source, and switches to the Normal layout. The state machine records restoration
ownership only after that switch succeeds, so the next Insert/terminal-input
entry leaves the current source alone when the mapping closed nothing. Repeated
requests are serialized and do not replace a pending CJK restoration with the
already-active Normal layout. (`help` and `man` keep their buffer-local builtin
`<C-]>`; `<C-\>` remains available there.)

`NVIM_MACISM_WAIT_TIME_MS` is passed as macism's optional third argument on
source switches. Leave it unset for macism's built-in wait (currently 150ms),
set it to a positive millisecond value to shorten that wait, or set it to `0`
to disable the temporary focus-stealing window. Disabling the workaround removes
the Ghostty focus flash but can make the first CJK characters race on macOS 26.

## LSP Utilities (`util.lsp`)

Enhanced LSP functionality with error handling.

#### Features
- **Safe Attachment**: Error-handled LSP client attachment
- **Action Management**: Dynamic LSP action execution
- **Client Management**: Query and manage LSP clients
- **Command Wrapper**: Safe LSP command execution

#### API Reference

```lua
local lsp = require("util.lsp")

-- Safe LSP attachment
local autocmd_id = lsp.on_attach(function(client, buffer)
  -- Setup LSP for buffer
  print("LSP attached:", client.name)
end, "lua_ls")  -- Optional: specific client name

-- LSP actions (dynamic)
lsp.action["source.organizeImports"]()  -- Organize imports
lsp.action["quickfix"]()                -- Apply quickfix

-- Client management
local available, clients = lsp.is_available()
local client = lsp.get_client("lua_ls")

-- Safe command execution
local success = lsp.buf_command("hover")
local success = lsp.buf_command("definition")
```

## Common Utilities (`util.common`)

Functional programming utilities for table manipulation.

#### API Reference

```lua
local common = require("util.common")

-- Create table wrapper
local tbl = common.table({a = 1, b = 2, c = 3})

-- Chainable operations
local keys = tbl:keys()                    -- Get all keys
local values = tbl:values()                -- Get all values
local doubled = tbl:map(function(k, v)     -- Transform values
  return k, v * 2
end)

-- Query operations
local has_key = tbl:containsKey("a")       -- true
local has_value = tbl:containsValue(2)     -- true
local result = tbl:get()                   -- Get underlying table
```

## Window Management (`util.window`)

Advanced window management utilities.

#### API Reference

```lua
local window = require("util.window")

-- Window operations (via autocmds)
-- :WindowCloseOthers  - Close eligible splits in the current tab only
-- :WindowCloseCurrent - Close current window
-- :WindowFocusEditor  - Jump to the editor window in the current tab; press
--                       again from the editor to return to the origin window.
--                       Bound to <C-,> in Normal and terminal-input mode, and
--                       to `se` where that chord cannot be sent.

-- Jump to the editor area, or back to where the jump started. An editor window
-- is a non-floating window in the current tab whose buffer has an empty
-- buftype, plus the dashboard. With several open, the one the cursor last left
-- wins, otherwise the widest. Notifies instead of moving when there is no
-- target. Backs :WindowFocusEditor.
window.focus_editor()

-- Record the current window as the last editor window when it qualifies.
-- Driven by a WinLeave autocmd (not WinEnter: a fresh `split` still shows a
-- file buffer when WinEnter fires and only becomes a terminal afterwards).
window.track_editor_win()

-- Quit Nvim, including from inside a Snacks terminal window. Backs <leader>qq
-- and, with force, <leader>qQ.
window.quit_all(force)
```

`quit_all` exists because `:qall` does not work from inside a Snacks terminal.
Snacks closes each of its terminal windows from its own `ExitPre`, and Nvim
refuses to finish a quit whose autocommands made a window disappear -- so
`:qall` typed in the agent panel or a `<C-/>` terminal closed that terminal and
then silently dropped the quit, which reads as "the agent exited but Nvim
stayed". Closing those windows up front, while it is still an ordinary window
operation, leaves `ExitPre` with nothing to close.

Only the windows are closed; the buffers are left to `ExitPre` as usual. A
Snacks terminal that is merely hidden never blocked the quit, and not deleting
buffers keeps this clear of the textlock `nvim_buf_delete` can hit in a nested
command context.

The unsaved check runs first, because closing the panel is not free. Nvim fires
`ExitPre` before it looks at modified buffers, so a refused `:qall` tears the
agent panel down *and* fails to quit -- and issued from inside the panel it then
drops the quit without a word, since the autocommand closed the current window.
So when a modified buffer would make Nvim refuse, `quit_all` issues no `:qall`
at all: it refuses on its own, with a `vim.notify` warning that names the
unsaved buffers and points at `<leader>qQ`. Going through `vim.cmd` would also
have turned Nvim's refusal into an `E5108` Lua traceback rather than the
one-line `E37` that `:qa` shows. Which buffers count is Nvim's own rule, read
through the `'modified'` option: `nofile`, `nowrite`, `terminal` and `prompt`
buffers never count, while an `acwrite` buffer (oil) blocks the quit like a
file. `<leader>qQ` passes `force`, which is the user saying they mean it.

Typing `:qa` by hand still takes the upstream path; only these entry points are
covered.

## Terminal (`util.terminal`)

Helpers for `:terminal` windows, including the selected native AI agent.

#### API Reference

```lua
local terminal = require("util.terminal")

-- Fix stale renders ("drift") in a TUI terminal by shrinking the window by one
-- row and restoring it ~25ms later, which resizes the pty and makes the child
-- TUI repaint. The delay is required: nvim pushes a terminal window's new size
-- to the pty on an internal ~10ms refresh timer, so a same-tick restore is
-- never observed and propagates nothing. Uses window APIs so non-modifiable
-- terminal buffers are safe. Bound to <leader>md.
terminal.fix_drift(win)   -- win defaults to the current window

-- True when buf belongs to the selected native coding agent.
terminal.is_agent_buf(buf)

-- Open or close a terminal -- the only thing that closes one. Without a count
-- it resolves to the terminal you are in, an explicit v:count, or the one you
-- were last in. Bound to <C-/>.
terminal.toggle(count)

-- Show a terminal and put the cursor in it; never closes. Bound to <C-1>-<C-9>,
-- which are for choosing which terminal you look at, not for dismissing one.
terminal.focus(count)
```

Native coding-agent terminals do not run `fix_drift()` on `TermEnter`, avoiding
a one-row flash whenever focus moves into the terminal. Opening a numbered
bottom terminal still repairs the visible agent after the resulting layout
change. Use `<leader>md` for a manual repair.

## Move (`util.move`)

Moves the current line, or the selection, with `hjkl` — vertically by moving the
line, horizontally by indenting it.

#### API Reference

```lua
local move = require("util.move")

move.run("down")   -- also "up", "left", "right"; bound to ,{h,j,k,l}
```

The first press comes from `<leader>m`, then bare `h`/`j`/`k`/`l` keep going
until some other key ends the run — and that key is fed back rather than
swallowed. Directions mix freely within a run.

Alt would be the conventional home for this (`<A-j>`/`<A-k>` in LazyVim), but
tmux claims `M-h/j/k/l` for pane navigation here, so those never reach Nvim at
all — see huiyu/nvim#12. Putting it on `<leader>` alone would cost a keystroke
per line, which the repeat loop is there to avoid.

## Running Files (`util.run`)

Run the current file with a per-filetype command. See [DIAGNOSTICS.md](DIAGNOSTICS.md)
for the broader diagnostic workflow.

#### API Reference

```lua
local run = require("util.run")

-- Register a runner (in a lang/*.lua module). builder(path) -> shell command.
run.register("python", function(path)
  return "python3 " .. vim.fn.shellescape(path)
end)
run.register({ "sh", "bash" }, function(path)  -- multiple filetypes at once
  return "bash " .. vim.fn.shellescape(path)
end)

-- Write and run the current buffer's file in a split terminal (bound to ,x).
run.run_current()
```

## AI Panel Input (`ai.terminal`)

Buffer-local input rules for the native agent panel, applied through one
`TermOpen` hook because both providers open through Snacks — the per-backend
alternative would need a callback threaded through claudecode.nvim's own
terminal provider. Ordinary `:terminal` buffers are untouched.

#### API Reference

```lua
local panel = require("ai.terminal")

panel.setup()      -- install the TermOpen hook; called from ai.setup()
panel.attach(buf)  -- apply the rules to one agent terminal buffer
```

Three rules, the first two undoing something Nvim or Snacks does that is right
for a shell and wrong for an agent TUI:

`<Esc>` is mapped buffer-locally so it goes straight to the agent. Snacks maps
`<esc>` on its terminal buffers as a 200ms double-tap to Normal mode, and
`lua/mappings.lua` maps `<Esc><Esc>` globally; between them, neither CLI ever
received the quick double Esc that both read as "go back a message". The
buffer-local single `<Esc>` is a complete match, so it wins over the longer
global sequence without waiting out `timeoutlen`. Snacks' own entry is dropped
where each terminal is created, via `keys.term_normal = false`. `jk` and `<C-\>`
still leave Terminal-mode.

Mouse clicks that land inside the panel are swallowed so Terminal-mode survives
them. Nvim only forwards a mouse event to a terminal job that asked for mouse
reporting, and neither TUI asks, so Nvim handled the click itself — which means
leaving Terminal-mode, and made a click that merely returned focus to the
terminal window look like a random drop into Normal mode. Clicks on another
window still move there. This applies to the unwrapped path only: under the tmux
wrapper tmux enables mouse reporting, so Nvim forwards and Terminal-mode
survives on its own, and mapping there would take the click away from tmux's
copy-mode. The wrapper is detected from the command recorded on the buffer,
since who enables the mouse is the only reason that distinction matters.

Scrolling from terminal-Normal mode is forwarded into the pane, and terminal
input is restored afterwards. This is the wrapped path's counterpart to the
mouse guard: tmux owns the real transcript, so Nvim's terminal buffer holds
only the screenful tmux last composed and scrolling it shows nothing useful.
`<PageUp>`/`<PageDown>`, `<C-u>`/`<C-d>` and the wheel are sent to the pane as
`<PageUp>`/`<PageDown>`, which the wrapper binds to `copy-mode -eu`; returning
to terminal input means the next wheel event reaches copy-mode directly instead
of scrolling the near-empty buffer again. That automatic transition is marked
for one event so it preserves copy-mode; any later `TermEnter` -- whether from
`i`, `a`, another terminal-input entry key, or automatic focus -- runs
`tmux copy-mode -q` and returns the panel to its live bottom. This used to live
in `ai.backend.codex`, so Claude never had it.

## AI Selection (`ai.selection`)

Builds agent-ready text from the live visual selection. It sits outside the
backends because the two providers attach selections through different channels:
Codex pastes text, while Claude's `<leader>as` goes over the IDE WebSocket and
produces no text at all. `<leader>ai` needs text under both providers to seed the
agent's input box, so the text form has exactly one producer.

#### API Reference

```lua
local selection = require("ai.selection")

---@return string|nil draft   nil when the selection could not be read
---@return string|nil err     reason, set only when draft is nil
---@return string|nil notice  informational message the caller may surface
local draft, err, notice = selection.draft()
```

Must be called while Visual mode is active — it reads `mode()` and the `v` mark,
not the `'<`/`'>` marks left behind afterwards. Outside Visual mode it returns
`nil` plus a reason rather than guessing, because `getregion()` does not object
there: the stale `v` mark makes it return the current line, which would seed a
draft the user never selected.

A saved, unmodified file yields an `@path lines N-M ` mention, trailing space
included. Anything unsaved or modified yields the literal selection in a fenced
block, since a path reference would point the agent at stale bytes; that case
also returns `notice` so the caller can explain the fallback. Nothing is
notified from inside the module — `<leader>as` and `<leader>ai` surface failures
differently.

## AI Clipboard (`ai.clipboard`)

Moves clipboard images between the system, a staging file, and the agent TUI.
macOS only — it shells out to `osascript`, the same way both agent CLIs do.

#### API Reference

```lua
local clipboard = require("ai.clipboard")

clipboard.has_image()            --> boolean
clipboard.save_image(path)       --> ok, err   write the clipboard image as PNG
clipboard.restore_image(path)    --> ok, err   put a PNG file back on the clipboard
clipboard.attach(chan, paths, done)            -- feed each image to a terminal job
clipboard.staging_dir()          --> string    per-process temp directory
```

This exists because an image cannot reach the agent any other way: only the CLI
can put image bytes into its request, and the one channel to it is the pty. So
`attach` replays the keystroke the TUIs already bind to "read the clipboard"
(`0x16`, ctrl+v) once per image, and the CLI writes its own `[Image #N]` marker.

`attach` is sequential and deferred rather than a loop: each keystroke makes the
TUI spawn its own clipboard reader, and the next image cannot be placed on the
clipboard until that read finishes.

Staging to a file at attach time is required rather than tidy: `clipboard =
"unnamedplus"` means the next yank or delete in the prompt buffer would
otherwise overwrite the screenshot. Sending therefore also replaces whatever is
on the clipboard at that moment.

Every entry point returns `false, reason` off macOS rather than raising, and any
path containing a quote, backslash or newline is refused — paths are
interpolated into AppleScript source, which has no equivalent of `shellescape`.

## AI Editor (`ai.editor`)

Host side of the agent TUI's `ctrl+g` handoff. Both native agents bind that key
to "edit the input box in `$EDITOR`"; `scripts/agent-editor` is that `$EDITOR`,
and it forwards the file here over RPC rather than starting a nested Nvim inside
the `:terminal`.

#### API Reference

```lua
local editor = require("ai.editor")

---@return string status  "opened", "focused", or "error: <reason>"
editor.open(path, sentinel)  -- open the agent's temp prompt file in a float
editor.wrapper()             -- absolute path to scripts/agent-editor
editor.EDIT_KEY              -- the byte both TUIs bind to "edit in $EDITOR" (0x07)
editor.stage_seed(text)      -- text to add to the next prompt this Nvim is handed
editor.tui_ready(buf)        -- has the agent TUI in buf drawn its input prompt?
editor.when_ready(get_buf, action, on_timeout)

-- Absolute paths to the shell helpers the agent terminals need.
editor.wrapper()  -- scripts/agent-editor, the agents' $EDITOR for ctrl+g
editor.runner()   -- scripts/agent-run, the pane command inside both wrappers
editor.teardown() -- scripts/agent-teardown, run by the hook and the watchdog
editor.teardown_hook(socket)  -- the client-detached hook command for a wrapper server
```

`open` is called over RPC by the wrapper, which is blocked in a poll loop while
the agent TUI is in turn blocked on the wrapper. So every exit path releases the
sentinel — success, refusal, discard, and `VimLeavePre`. A missed release does
not merely lose an edit, it hangs the agent.

`<C-d>` / `:wq` writes the buffer back to the file the agent re-reads; `<C-c>` /
`:q!` leaves the file untouched so the input box keeps what it had. The buffer
opts out of format-on-save because the file is real markdown: reformatting it
on the write that hands it back would reflow a prompt the user wrote
deliberately.

A second request for a prompt already on screen focuses the existing float and
releases the duplicate's sentinel instead of stacking two windows on one buffer.
Each open also gets its own augroup: naming it after the buffer meant a second
open of the same file silently deleted the first one's `BufWipeout`, which is
the only thing that releases the first wrapper.

A Visual selection reaches the prompt through `stage_seed`, not through the
pty. Seeding used to be a bracketed paste sent just ahead of the edit key, on
the reasoning that a single channel write fixes their order. The bytes do arrive
in order, but the TUI applies a paste asynchronously and acts on the key first —
measured: the float came up empty with a selection staged. Handing the text to
the buffer instead has no ordering to lose, and needs no paste sanitising. The
stage is consumed by the first `open` that follows, so an unanswered request
cannot leak its seed into a later `ctrl+g`.

### Images

`<C-v>` stages the clipboard image through `ai.clipboard` and nothing is written
into the buffer — the prompt file is plain markdown, and only the CLI can put
image bytes into its request. On return, the staged files are replayed through
the TUI's own `ctrl+v` (`ai.attach_images`), and the CLI writes its own
`[Image #N]` marker.

The replay is deferred until after the buffer closes. Measured: while the prompt
is open the agent is blocked on the editor and discards pty input, so a `ctrl+v`
sent during the edit never arrives and the same one sent afterwards does. 100ms
after close was still too early; 300ms landed.

### Reading the screen

Prompt *content* is never scraped: a real newline and a soft wrap render
identically in both TUIs — a two-space-indented continuation line either way —
so screen text cannot be reassembled into the original prompt.

`tui_ready` does read the screen, for the single question "has the input box
appeared yet", and `when_ready` polls it so a freshly started agent gets its
keystroke at the right moment instead of swallowing it. That use is safe for the
same reason content extraction is not: a wrong answer costs one keystroke the
user can repeat. A numbered line (`❯ 1. Yes, I trust this folder`) is one of the
CLI's own choice lists, not an input box, and does not count as ready.

### Why `agent-run` exists

An agent that fails on startup used to make the panel vanish with no trace.
Both tmux wrappers end with `exit-empty on` and a `client-detached` teardown
hook, and that teardown makes the tmux client exit 0 however the pane's command
ended -- measured: `sh -c 'exit 1'` through the real wrapper reaches nvim as
status 0. Nvim's `:terminal` job therefore reports success,
Snacks' `auto_close` closes the window, and the agent's error text dies with the
tmux server, leaving nothing in `:messages` either.

The status cannot be recovered on nvim's side, so `scripts/agent-run` keeps the
message where it was printed: on a non-zero exit it holds the pane, with the
agent's own diagnostics still on screen, until the panel is dismissed. A clean
exit passes straight through, so quitting an agent normally still closes the
panel with no extra keystroke.

### Why `agent-teardown` exists

Quitting Nvim used to leave the agent's background work running. tmux signals
only each pane's own process when a server dies, and the kernel's hangup reaches
only the pane's session leader, so anything the agent had spawned into a process
group of its own -- a Codex `exec_command` background session, a Bash-tool job
-- kept running with ppid 1 and no terminal (measured: a `pnpm dev:server` tree
outlived its Nvim by three days). Both wrappers now end their server through
`scripts/agent-teardown`: from the `client-detached` hook (`editor.teardown_hook`)
and from the watchdog. It records the process tree under every pane, kills the
server, then SIGTERMs and after two seconds SIGKILLs whatever of that tree is
still alive. Shared daemons -- emulator, Gradle daemon, container runtime -- are
spared together with their children, but only from the agent's children down:
the launcher and the agent itself are never exempt, or a plugin path with the
wrong word in it would silently spare the whole tree.
`NVIM_AGENT_TEARDOWN_IGNORE` replaces the pattern (an awk ERE). Each run is
logged to `~/.local/state/nvim/agent-teardown.log`.

`destroy-unattached` is off in both wrappers on purpose. With it on, the session
-- and the process tree the hook has to record -- was gone before the hook ran
(measured), which is how a `kill-server` hook that never executed hid the leak.
`exit-empty` still ends the server when the agent itself exits; the hook then
finds no panes and does nothing. The hook's `run-shell` job would die with the
server it kills, so the script hands the work to a detached copy of itself; the
watchdog uses the synchronous `--wait` form and only removes the socket file
afterwards.

## AI Transcript (`ai.transcript`)

Renders the active provider's recorded sessions into a read-only buffer.

#### API Reference

```lua
local transcript = require("ai.transcript")

transcript.open_current()  -- newest session for the project (<leader>at)
transcript.pick()          -- Snacks picker over this project's sessions (<leader>aT)
transcript.refresh(buf)    -- re-read and re-render in place (`R` in the buffer)
```

Provider knowledge lives in `ai.transcript.claude` and `ai.transcript.codex`,
which share one `Adapter` contract: `sessions(root)` and `parse(path, cap)`.
`ai.transcript.render` turns their common `Entry` list into lines plus a parallel
fold-level array, and never learns which provider produced them.

## Best Practices

### Error Handling

Always use safe operations for potentially failing code:

```lua
local logger = require("util.logger")

local success, result = logger.safe_call(function()
  -- Potentially failing operation
  return risky_function()
end, "operation description")

if not success then
  logger.error("Operation failed: %s", result)
  return nil
end
```

### Logging

Use structured logging for debugging:

```lua
local logger = require("util.logger")

function M.complex_operation(params)
  logger.debug("Starting complex operation with: %s", vim.inspect(params))
  
  local result = do_work(params)
  
  logger.info("Complex operation completed successfully")
  return result
end
```
