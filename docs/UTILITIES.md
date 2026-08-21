# Utility Modules Documentation

This document provides detailed documentation for all utility modules in the Neovim configuration.

## Overview

The utility modules provide focused helpers for logging, LSP, table manipulation, terminals, windows, and running the current file. For diagnostic and debugging workflows (health checks, profiling, LSP/treesitter inspection), see [DIAGNOSTICS.md](DIAGNOSTICS.md).

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
--                       Bound to <C-\> in Normal and terminal-input mode.

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
```

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
-- terminal buffers are safe. Bound to <leader>td.
terminal.fix_drift(win)   -- win defaults to the current window

-- True when buf belongs to the selected native coding agent.
terminal.is_agent_buf(buf)

-- Open or close a terminal -- the only thing that closes one. Without a count
-- it resolves to the terminal you are in, an explicit v:count, or the one you
-- were last in. Bound to <C-/>.
terminal.toggle(count)

-- Show a terminal and put the cursor in it; never closes. Bound to <leader>t1-9,
-- which are for choosing which terminal you look at, not for dismissing one.
terminal.focus(count)
```

Native coding-agent terminals do not run `fix_drift()` on `TermEnter`, avoiding
a one-row flash whenever focus moves into the terminal. Opening a numbered
bottom terminal still repairs the visible agent after the resulting layout
change. Use `<leader>td` for a manual repair.

## Move (`util.move`)

Moves the current line, or the selection, with `hjkl` — vertically by moving the
line, horizontally by indenting it.

#### API Reference

```lua
local move = require("util.move")

move.run("down")   -- also "up", "left", "right"; bound to <leader>m{h,j,k,l}
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

-- Write and run the current buffer's file in a split terminal (bound to <leader>cx).
run.run_current()
```

## AI Selection (`ai.selection`)

Builds agent-ready text from the live visual selection. It sits outside the
backends because the two providers attach selections through different channels:
Codex pastes text, while Claude's `<leader>as` goes over the IDE WebSocket and
produces no text at all. The composer needs text under both, so the text form has
exactly one producer.

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
notified from inside the module — `<leader>as` and the composer surface failures
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

`attach` is sequential and deferred rather than a loop: each keystroke it sends
makes the TUI spawn its own clipboard reader, and the next image cannot be placed
on the clipboard until that read finishes.

Every entry point returns `false, reason` off macOS rather than raising, and any
path containing a quote, backslash or newline is refused — paths are interpolated
into AppleScript source, which has no equivalent of `shellescape`.

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
