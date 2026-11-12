# Utility Modules Documentation

This document provides detailed documentation for all utility modules in the Neovim configuration.

## Overview

The utility modules provide focused helpers for logging, debug inspection, LSP, table manipulation, macOS input sources, terminals, windows, gitsigns' diff split, review baselines, the CodeDiff views, and running the current file. The AI modules follow, with the review loop's under [AI Review](#ai-review-aireview). For diagnostic and debugging workflows (health checks, profiling, LSP/treesitter inspection), see [DIAGNOSTICS.md](DIAGNOSTICS.md).

## Core Utilities

### Keymap section data (`whichkey_spec`)

`lua/whichkey_spec.lua` exports `spec`, `sections`, `fallback_section` and
`filetype_descs`. `spec` contains which-key mapping/group metadata.
`sections[prefix]` is an ordered list of display sections, read by
`lua/plugin/editor/whichkey.lua`. Filetype mappings remain in `lua/lang/`; view
mappings remain with their plugins.

`filetype_descs[ft][lhs]` is the desc for a key that `ft`'s own plugin (a
runtime ftplugin or VimTeX) maps in its buffers without one, or in words of
its own: Python's `]]`/`]m`, Go's, Rust's and Vim's section motions, VimTeX's
`]n`/`]r`/`]/` motions and `ac`/`id`/`a$` objects, and the heading outline
`gO` of markdown, help, checkhealth and man buffers ("Show outline").
`lua/plugin/editor/whichkey.lua` writes it onto the buffer's own mapping with
`mapset()` on `FileType`, mode by mode, and only where the buffer maps the key
itself: VimTeX maps nothing where a global map already holds the key
(Nvim's Visual `]n`), and that one keeps its own desc; VimTeX's Normal
`]r`/`[r`, which the global references hold, are mapped back by
`lua/lang/tex.lua` on `VimtexEventInitPost`. It never adds a
which-key entry, so the desc goes away when the filetype unmaps the key.

| Section field | Meaning |
|---|---|
| `[1]` | Heading text |
| `keys` | Suffixes after the prefix; exact keys, never description patterns |
| `icon`, `color` | Heading and row styling; `color` is a which-key color name |
| `filetype` | Optional list of source-buffer filetypes where the section applies |
| `buftype` | Optional source-buffer type, such as `"terminal"` |
| `labels` | Optional suffix-to-label table for existing implicit subgroups |

For example, the comma menu declares Python's `o`/`v` under imports/environment,
and LaTeX's `v`/`t`/`L` under preview/tools. The first matching section owns the
row, so a filetype section must come before any unfiltered section that
declares the same suffix: `g`'s `oil · listing`, `CodeDiff · panel`,
`Chat · conversation/context`, `Lazy · plugin` and `outline` come before
`LSP`, and `,`'s `Lazy · plugin` comes before `refactor` and `lines`;
`tests/whichkey_popup_spec.lua` asserts this order. Filetype and buftype
filters both apply when both are present. A heading joins single words with
"/" and no spaces, as descs do (`AGENTS.md`): imports/environment,
preview/tools, replace/sync, search/panel, format/replace. `labels.L`
names the existing VimTeX group without registering an empty placeholder key.
Headings add no keystrokes, register no mappings, and load no plugins. Only keys
already present in the source buffer appear. Unclassified rows use
`fallback_section` in a sectioned popup.

View sections can appear alongside language sections. CodeDiff's
`P`/`B`/`g`/`z`/`I` and the review keys `C`/`u`/`U`/`X` are distinct from
Markdown's `p`/`m` and LaTeX's `b`/`v`, so the same source buffer can show
both. Terminal `1`–`9` mappings are installed by `TermOpen`
in Normal mode; they never intercept terminal input. `<localleader>` is `,`
and uses this same action menu.
grug-far overrides its localleader defaults with `,S…` to preserve general
editing keys; `sections[",S"]` groups replace/sync, results, history and
search/panel controls. Its implicit `S` group is labeled "Search panel" beside
`,f`/`,F`/`,w` under the comma menu's format/replace heading.

`tests/whichkey_popup_spec.lua` checks section ordering and rendering;
`tests/context_actions_spec.lua` checks real contextual menus and unchanged
general keys; `tests/codediff_spec.lua` checks combined language/view actions
and cleanup. Keep labels and categories in the data file when extending the menu.

### Debugger actions (`util.dap`)

`attach()` powers `<leader>dA` and `:DapAttach`. It reads the current filetype's
static DAP configurations and the working directory's `.vscode/launch.json`
through `dap.ext.vscode.getconfigs`, then offers only `request = "attach"`
entries. JSONC is supported; a read/parse error is reported while built-in
entries remain usable. Cancelling or changing the source buffer/working
directory before selection makes no connection. A selection calls
`dap.run(config, { new = true, filetype = ft })`, leaving existing sessions
available and avoiding save/build side effects.

`input(prompt, default)` returns trimmed nonempty text or `dap.ABORT` on empty
input/cancellation. `port(default)` additionally validates an integer in
1–65535 and returns a number. Language modules own prompt defaults and transport
fields; Dart/Flutter separately handle required/optional VM service URIs.

Language specs contribute `opts.targets[filetype]` to nvim-dap, with optional
`file`, `test`, and `test_file` callbacks. DAP setup assigns that table to
`util.dap.targets`; `run_target(kind)` dispatches the matching callback after
`:update`. Unsupported, unnamed or special buffers and failed saves abort.
Callbacks receive `{ bufnr, path, filetype, line, col }`: the absolute buffer
path, a one-based line and zero-based column captured after save hooks. Resolve
project roots from this context before asynchronous work, rather than reading
the subsequently focused buffer. Language behavior stays in `lua/lang/*.lua`.

`syntax(ctx)` returns the parsed Treesitter root and language, or reports a
missing parser. The language module supplies the query and target semantics.
Go/Python call the neotest `debug_target(ctx, file)` consumer, which uses an
explicit path/row and refuses to widen a missing nearest test to a whole file.

`expression()` reads the live character, line or block Visual selection using
`getregion()`, respects exclusive selection, leaves Visual mode, and preserves
registers. In Normal mode it returns `<cexpr>`. `evaluate()` sends that expression
to the DAP hover; `watch()` opens an editable prompt and adds a nonempty result
to dapui watches. `logpoint()` prompts at the current source location; cancelling
or entering an empty message preserves the existing breakpoint.

`exceptions()` offers None, All, or an individual exception filter advertised by
the current adapter. It does not assume language-specific names. Cancellation
and a session change while the picker is open leave breakpoints unchanged.
The module loads with DAP on first use, not during startup.

`disconnect()` requests `terminateDebuggee=false`. A language module may supply
the config-owned `adapter.options.before_disconnect(session, done)` hook to
prepare that session before disconnecting. Call `done()` only on success; the
helper keeps the original session even if the user selects a different one.
Go remote uses this to clear server-side source breakpoints and resume, while
preserving local breakpoints for the next attachment.

`disconnect()` and `restart()` (`<leader>dR`) act on the root of the session
tree, not on whichever child session last stopped. An adapter that drives
several targets (js-debug) answers with child sessions. `disconnect()` lets go
of every session in the tree, deepest first. `restart()` selects the root
before `dap.restart()`.

The debug view owns a tabpage of its own. `open_panels()` creates it with
`tab split` (or focuses it) and opens dap-ui. `close_panels()` closes dap-ui
and that tabpage, unless it is the last tabpage left. `toggle_panels()` is
`<leader>du`. A root session's `event_initialized` opens the view, and the end
of the last root session closes it. `jump(bufnr, line, column)` is nvim-dap's
`switchbuf`: it places a stopped frame in `util.window.ensure_editor_win()` of
the current tabpage, never another one.

### URLs and local files (`util.url`)

`open()` implements Normal-mode `gx`: open the nearest HTTP(S) URL or existing
local file on the current row. URLs use `vim.ui.open`; file references use
`:edit`, focusing `util.window.ensure_editor_win()` first in special buffers so
terminal panels remain intact. File candidates must exist and be regular files.
Absolute and `~/` paths work; relative paths resolve beside an ordinary source
file, against a Snacks terminal's recorded `cwd`, or via `util.cwd.buffer_dir()`
otherwise. Quotes and backticks support paths containing spaces, including
consecutive spaces on one row. Filenames are passed literally to `:edit`, with
filename expansion and command separators disabled. If no target is found,
ordinary file buffers fall back to opening themselves through `vim.ui.open`;
special buffers do nothing. It handles Markdown wrappers without discarding
balanced parentheses in URL paths, and preserves Unicode hostnames, paths and
query values. CJK and fullwidth
punctuation (`，。、（）「」“”…`) ends the URL text, so prose that runs straight
into a link without a space never leaks into it.

In terminal buffers, targets enclosed in parentheses or angle brackets can span
up to 16 consecutive rows in the same table column. Alignment uses display
width, including CJK text; padding and vertical rules separate columns. The
full target must reach its closing delimiter before continuation is accepted.
Quoted local paths can also span rows. Any target, bare or enclosed, that runs
into the right edge of a row the terminal wrapped (`util.terminal.soft_wraps`)
continues from column 0 of the next row, whatever column it started in; that
join needs no closing delimiter, and a file path whose joined form does not
exist falls back to its first row.

Wrapped rows do not count against the 16-row window. The window grows over
the wrapped run through the cursor row, up to 256 rows each way, so a long
signed URL opens whole. A link wrapped past that cap opens nothing rather than
a truncated URL. Only that run can put a target on the cursor row, since
nothing continues down a column after a wrap, and each row's wrap is judged
once. A token that only continues the row above is not walked again. Together
these keep gx in milliseconds next to a long minified or base64 line.

A wrap that cuts the scheme (`htt` | `ps://`) is found from the prefix at the
row's edge, unless a word or link character comes right before it. Once a
target has wrapped, it never continues down a table column.

Either part of a wrapped target resolves to the same destination. Blank rows,
table separators and new URLs stop the lookup. Ordinary source lines are
never joined.
The module loads on the first `gx`; URL opening does not modify the buffer or cursor.

### Working directories (`util.cwd`)

`buffer_dir()` returns an existing local directory for the current buffer:
the parent of an ordinary file, the displayed local Oil directory, or the
current window/tab working directory for terminals, unnamed buffers and other
virtual buffers. Missing directories fall back to their nearest existing
ancestor, then the cwd, home or `/`. It neither changes the cwd nor loads Oil.
The directory-scoped `;F` and `;D` mappings share this resolver, as does Oil
when it is opened from a terminal.

`recover()` repairs a deleted process cwd and returns a one-line report, or
nil when no repair was needed. `setup()` runs it immediately, schedules any
report after the UI has loaded, and sets the initial cwd from the first file
or directory argument at `VimEnter`. See [Working Directory](#working-directory-utilcwd).

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
_G.dd = function(...) return require("util.debug").dump(...) end
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

LSP code actions with a client check and logging.

#### API Reference

```lua
local lsp = require("util.lsp")

-- LSP actions (dynamic): one function per code action kind
lsp.action["source.organizeImports"]()  -- Organize imports
lsp.action["quickfix"]()                -- Apply quickfix
```

## Vim Errors (`util.vim_error`)

Nvim's own line for a refused Ex command or API call. `vim.cmd` and the
`nvim_*` API turn a refusal -- last window, read-only file, no client attached
-- into a Lua error, and a mapping or command callback that lets it escape
prints an `E5108` block with a stack traceback for what `:q` typed by hand
shows as one line.

#### API Reference

```lua
local vim_error = require("util.vim_error")

-- The message Nvim would have printed, without Lua's wrapping:
-- "vim/_core/editor.lua:0: nvim_exec2(), line 1: Vim(write):E45: ..." and
-- "Vim:E444: ..." both come back as "E45: ..." and "E444: ...". Anything else
-- is returned as it is.
vim_error.message(err)

-- vim.notify that line at WARN, optionally prefixed with the action.
local ok, err = pcall(vim.cmd, "update")
if not ok then vim_error.notify(err, "Run file") end
```

`:WindowCloseCurrent`, `:WindowCloseOthers` and `,x` report through it. Where
the refusal is known before the call -- `:GoplsRebuildIndex` with no client,
`;P` on a file mkdp does not claim, `<leader>gm`/`<leader>gM` outside a
repository, `<leader>at` when the view fails -- the entry point checks first
and notifies, so none of them ends in a traceback.

## Working Directory (`util.cwd`)

At `VimEnter`, `setup()` sets cwd from the first command-line argument: a file
uses its nearest `.git` ancestor, falling back to its parent outside Git; a
directory argument uses that exact directory. `.git` may be a directory or a
file (worktrees/submodules), and symlinks resolve to their target first. Missing
parents fall back to their nearest existing ancestor. The argument is captured
as an absolute path before plugins load, and cwd changes only after startup
has resolved all relative arguments. No argument, stdin and URI arguments leave
cwd alone, as does a startup command or restored session that already changed
cwd or set a window/tab-local directory. The hook runs once; buffer switches
never move cwd. It uses Neovim's filesystem APIs without loading a plugin.

A shell whose directory was deleted under it still starts Nvim, but the process
then has no working directory: `vim.uv.cwd()` is nil, and the first thing to
hash it -- Snacks' dashboard terminal sections, at `UIEnter` -- dies with a
traceback for what is really "your directory is gone". `init.lua` runs the
recovery before options and plugins load.

#### API Reference

```lua
local cwd = require("util.cwd")

-- Move to the nearest surviving ancestor of the shell's $PWD (a pruned
-- worktree lands in its repository, a removed temp dir in its parent), or to
-- ~ when even that is unknown. Returns the one-line report, nil when the cwd
-- was fine.
cwd.recover()

-- Startup entry: recover immediately, register the once-only VimEnter cwd
-- selection, and notify any recovery report after VeryLazy, once the snacks
-- notifier is in place. At init time vim.notify is the builtin echo, which
-- the dashboard's first draw wipes.
cwd.setup()
```

## Window Management (`util.window`)

Advanced window management utilities.

#### API Reference

```lua
local window = require("util.window")

-- Window operations (via autocmds)
-- :WindowCloseOthers  - Close eligible splits in the current tab only. A close
--                       Nvim refuses (the last split, from a float) is a warning.
-- :WindowCloseCurrent - Close window (the desc `sd` shows too); the last window
--                       (E444) or a modified buffer that cannot be hidden (E37)
--                       is a warning.
-- :WindowFocusEditor  - Editor window (toggle back), as `se` and <C-,> say:
--                       jump to the editor window in the current tab; press
--                       again from the editor to return to the origin window.
--                       Bound to <C-,> in Normal and terminal-input mode, and
--                       to `se` where that chord cannot be sent.

-- Jump to the editor area, or back to where the jump started. An editor window
-- is a non-floating window in the current tab whose buffer has an empty
-- buftype, plus the dashboard, Oil listings and GitHub issue/PR reading views.
-- With several open, the one the cursor last left wins, otherwise the widest.
-- Notifies instead of moving when there is no target. Backs :WindowFocusEditor.
window.focus_editor()

-- The editor window of the current tabpage, without moving to it: the current
-- window when it is one, else the one the cursor last left, else the widest;
-- nil when there is none. focus_editor toggles (pressed in the editor it jumps
-- back out), so code that needs "the edited file's window" -- a native agent's
-- cold start, a new chat -- asks here instead.
window.editor_win()  --> win | nil

-- The tabpage a prefix-blocking view (CodeDiff) was opened from: the nearest
-- one before it that is no such view itself, so a second view opened from the
-- first still finds the page both came from. nil when `tabpage` is no view.
-- The AI keys and review feedback both go there from a view.
window.origin_tab(tabpage)  --> tabpage | nil

-- Record the current window as the last editor window when it qualifies.
-- Driven by a WinLeave autocmd (not WinEnter: a fresh `split` still shows a
-- file buffer when WinEnter fires and only becomes a terminal afterwards).
window.track_editor_win()

-- Return a window a file can be opened into, creating an empty horizontal
-- split when only panels or modified Oil/GitHub views remain. An unmodified
-- listing or issue/PR reading view can receive the file in place; pending edits
-- stay visible and untouched. Does not move focus; the caller decides when to
-- enter it.
-- Used by file-tab clicks, location pickers, Oil's terminal entry points, and
-- both debug frame paths: nvim-dap's `switchbuf` (via `util.dap.jump`) and
-- nvim-dap-ui's `select_window`. Being scoped to the current tabpage is what
-- keeps a stopped frame in the tabpage the user is actually in.
window.ensure_editor_win()

-- Resize the current window through whichever system owns it: edgy's own
-- per-window override or bar size when edgy manages the window, `:resize`
-- otherwise. A bare `:resize` stops working once edgy has a panel in the
-- tabpage -- every panel is winfix, so there is nothing to take space from.
window.resize(dim, delta)

-- Give the current window the whole tabpage, and put the layout back.
-- Collapses edgy's bars first (their size and their views' thickness, both
-- remembered) because `wincmd _` alone is reverted when edgy re-applies its
-- geometry. Shrinks rather than hides: edgy's `hide` drops a non-pinned
-- window from its edgebar outright and only pinned views can be reopened.
window.toggle_zoom()

-- `wincmd =`, then put every winfixwidth/winfixheight panel back to the size
-- it was first seen at. Run in every tabpage on VimResized, by toggle_zoom
-- when it restores the layout, and bound to `s=`.
window.equalize_respecting_fixed()

-- Whether `tabpage` holds a view that disables the global prefixes: its
-- vim.t.blocks_global_prefixes is set (util.codediff sets it while CodeDiff
-- has a session there; a new prefix-blocking view sets it too), or one of its
-- windows shows a CodeDiff panel (codediff-explorer, codediff-history), for a
-- tabpage CodeDiff let go of with its panel still on screen. It names the
-- view rather than inspecting windows: the working-tree pane is an ordinary
-- file window, and a single-file `:CodeDiff file` has no panel at all.
window.blocks_global_prefixes(tabpage)

-- Keep the first tabpage one the global prefixes still work in. CodeDiff
-- disables `;` and `s` inside its own tabpage, so a layout where its page is
-- the first one leaves `;f` with nowhere to run. Inserts a fresh page in
-- front (`noautocmd 0tabnew`) when blocks_global_prefixes() says so of the
-- first page, without moving the cursor. Driven by TabClosed and
-- SessionLoadPost; views never open as the first tabpage on their own, since
-- `tab split` inserts after the current one.
window.protect_first_tab()

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

Helpers for `:terminal` windows, including the native AI agents' panels.

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

-- Which native coding agent buf runs ("claude" / "codex"), or nil for any
-- other buffer. Every agent a provider offers counts: several can be
-- running, and each panel keeps its own rules.
terminal.agent_of(buf)

-- True when buf belongs to any configured native coding agent.
terminal.is_agent_buf(buf)

-- Open or close a terminal -- the only thing that closes one. Without a count
-- it resolves to the terminal you are in, an explicit v:count, or the one you
-- were last in. Bound to <C-/>.
terminal.toggle(count)

-- Show a terminal and put the cursor in it; never closes. Bound to `,1`-`,9`
-- only in terminal buffers' Normal mode (installed on TermOpen).
terminal.focus(count)

-- Whether terminals float (the default) rather than dock at the bottom
-- (vim.g.terminal_position = "bottom"). edgy asks it, so its bottom slot
-- claims no terminal that is meant to float.
terminal.floats()

-- Width in cells of the grid behind terminal buf: Nvim sizes the pty to the
-- widest window showing it, less that window's textoff. nil when no window
-- shows the buffer.
terminal.grid_width(buf)

-- Whether terminal row `line` runs on into `next_line` because the terminal
-- wrapped it at `width` cells. A terminal buffer has one line per row and Nvim
-- exposes no wrap flag, so this reads the shape: the row is full (the next
-- row's first character did not fit after it, so a wide one may wrap a cell
-- early) and that character is a non-blank in column 0. Layout that fills a
-- row on purpose never wraps:
--   * rows ending in two or more blanks;
--   * box-drawing/block characters on either side of the break;
--   * a progress bar: three or more of one box/block character anywhere in
--     the row (tqdm's █, rich's ━, but not a tree's `└──`), or tqdm's
--     `N%|…| a/b […]` shape;
--   * a run of four identical ASCII rule characters (`-=_*#~+`) ending the
--     row or leading the next (pytest's separators);
--   * a counter at the edge: tmux copy-mode's `[n/m]`, pytest -v's `[ 37%]`;
--   * a next row led by an emoji.
-- Rows wider than `width` (from before a resize) never wrap either. A newline
-- written at exactly the full width is indistinguishable and counts as a wrap,
-- and so does a program's own unindented word wrap at exactly the width.
terminal.soft_wraps(line, next_line, width)

-- TextYankPost handler (lua/autocmds.lua, terminal buffers only): rewrite the
-- yanked register with the rows soft_wraps joins, before yanky's handler reads
-- it. Characterwise (including one through the end of its last row, `v$y`)
-- and linewise `y` only; blockwise, black-hole and appending (uppercase) yanks
-- are left alone. An unnamed yank also rewrites "+ / "* per 'clipboard':
-- setreg("") never reaches the clipboard provider, which already received the
-- split text before the event.
terminal.unwrap_yank(buf)
```

Native coding-agent terminals do not run `fix_drift()` on `TermEnter`, avoiding
a one-row flash whenever focus moves into the terminal. Opening a numbered
bottom terminal still repairs the visible agent after the resulting layout
change. Use `<leader>md` for a manual repair.

## Buffers (`util.buffer`)

Housekeeping for listed buffers that bufferline and Snacks do not cover.

#### API Reference

```lua
local buffer = require("util.buffer")

-- True for a listed, plain file buffer whose file no longer exists on disk.
-- Terminals, URI-scheme buffers (oil://, codediff://) and unnamed scratch
-- buffers have no file to be missing and always return false.
buffer.is_missing_file(buf)

-- Delete every such buffer through Snacks.bufdelete, so the window layout
-- survives and a modified buffer still gets the save/discard/cancel prompt
-- (saving recreates the file, which is sometimes what you want after an
-- agent deleted it). Notifies how many were removed. Bound to <leader>bx.
buffer.delete_missing()

-- True for a listed buffer with an empty buftype that no window shows, in any
-- tabpage (floats included). Unlike Snacks.bufdelete.invisible(), which only
-- checks the current tabpage, a file shown in a CodeDiff or debug tabpage is
-- still in use.
buffer.is_hidden(buf)

-- Delete every such buffer through Snacks.bufdelete. No window changes, a
-- modified buffer gets the save/discard/cancel prompt, and the empty
-- placeholder Snacks creates when no listed buffer remains is wiped again.
-- Notifies how many were removed. Bound to <leader>bh.
buffer.delete_hidden()
```

## Diff Split (`util.diffsplit`)

The split `:Gitsigns diffthis` opens (`<leader>gd`, and `<leader>gD` for a
file with conflicts): a window per revision of the file -- the index, or ours
and theirs -- in diff mode beside the file's own window. gitsigns has no
command that closes it. `<leader>gq` calls `close()` when the tabpage has no
CodeDiff view; `<leader>gd` and `<leader>gD` are `toggle()`. A revision
window is a window in diff mode whose buffer name starts with `gitsigns://`,
the prefix gitsigns gives every buffer it reads from git
(`tests/gitsigns_spec.lua` fails if `<leader>gd` stops opening one).

Vim compares every diff window of a tabpage with every other, as one view.
So `close()` ends diff mode in all of the tabpage's windows, not only the
file's -- a `:split` of the file's window inherits diff mode, and 'diffopt'
`closeoff` ends it only in the last window left -- and `toggle()` from
outside the split moves it rather than add a second file to the comparison.

#### API Reference

```lua
local diffsplit = require("util.diffsplit")

-- The tabpage's split windows that show a gitsigns revision in diff mode.
-- tab: a tabpage handle, 0 or nil for the current one.
diffsplit.revision_wins(tab)   --> integer[]

-- Close them, then :diffoff every window of `tab`. Only `tab` is touched.
-- false when it has none. true otherwise, including when it refuses: an index
-- side with unsaved edits (gitsigns wipes the buffer with its window, and :w
-- there stages) closes nothing and says so. A revision that is the
-- tabpage's last split stays, out of diff mode, rather than close the tabpage.
diffsplit.close(tab)           --> boolean

-- <leader>gd (opts nil) / <leader>gD ({ unified = true }). From a diff window
-- of the current tabpage's split: close(), and the cursor goes back to the
-- file's window. In a buffer gitsigns has not attached to (untracked, outside
-- Git, not a file; get_hunks(0) is nil): an INFO notice, nothing else, since
-- diffthis would silently do nothing. Otherwise gitsigns' diffthis(nil, opts)
-- for the current window, after closing a split elsewhere in the tabpage
-- (not for the inline view, which sets no diff mode -- unless `git ls-files
-- --unmerged` lists the file, where gD opens ours and theirs) and after
-- :diffoff of the current window if it is the tabpage's only diff window --
-- diffthis ignores a window in diff mode, and a buffer last shown in one
-- carries it into the next window that opens it.
diffsplit.toggle(opts)
```

## Baselines (`util.baseline`)

Immutable snapshots of a worktree, kept as commits with no parent under
`refs/nvim-review/<wtid>/{round,saved}/<id>`: the review loop's rounds and
`<leader>gK`'s saved baselines, which `<leader>gk`/`<leader>gM` compare
against. A snapshot never writes the user's state: it copies the real index
to a temporary file of its own (`<gitdir>/nvim-review-index.XXXXXX`, mtime
kept), adds the worktree to that copy and writes its tree, so HEAD, the real
index, branches and stash stay as they were. AGENTS.md ("Review Baselines")
gives the reason for each step. Trailers are opaque key/value pairs here;
what `Source` or `Conversation` mean belongs to `ai.review.rounds`.
Retention counts and the size cut-off come from `ai.review.config`, read on
each use.

#### API Reference

```lua
local baseline = require("util.baseline")

baseline.NAMESPACE  -- "refs/nvim-review"
baseline.KINDS      -- { round = "rounds", saved = "saved" }: kind -> its retention key

-- A git argv with the prefix every call here carries: --no-optional-locks
-- -c core.hooksPath=/dev/null -c core.splitIndex=false. util.codediff's
-- listing, util.codediff_actions and ai.review run theirs through it too.
baseline.git_cmd(args)            --> string[]

-- The worktree that contains `path` (default: the cwd): { toplevel, gitdir,
-- wtid }, realpaths, wtid the first 12 hex digits of sha256(gitdir). Synchronous,
-- cached per directory, main loop only. nil and a reason outside Git, for a
-- bare repository, and while GIT_DIR or GIT_WORK_TREE is set.
baseline.locate(path)             --> loc | nil, err

-- Snapshot the worktree: cb(tree, info), or cb(nil, err). One snapshot at a
-- time per gitdir, and all requests waiting share the next one;
-- opts.priority puts a request ahead of the rest (a prompt's baseline before
-- a listing refresh). (root, opts, cb) works too.
baseline.snapshot(root, cb, opts)

-- Snapshot (or take meta.tree), commit it without a parent under the fixed
-- identity, create refs/nvim-review/<wtid>/<kind>/<id>, then prune that kind.
-- cb(entry, info), or cb(nil, err).
baseline.save(root, kind, meta, cb)

-- This worktree's baselines of `kind` (nil: both), newest first: cb(entries),
-- or cb({}, err). A ref whose commit is gone is deleted, with one warning.
-- (root, cb) lists both kinds.
baseline.list(root, kind, cb)

-- When an entry was taken, to the millisecond its id holds: entry.time plus
-- that fraction, or entry.time for an id that is not one of ours.
baseline.time_of(entry)

-- Delete refs compare-and-swap, each only if it still points at its `sha`:
-- cb(deleted, skipped). A ref that moved, is gone or lies outside
-- refs/nvim-review/ is skipped, never an error.
baseline.delete(root, entries, cb)

-- Keep the newest retention.rounds / retention.saved of `kind`, delete the
-- rest unless exempt (set_exempt, or opts.exempt): cb(deleted), or
-- cb({}, err). Deleted saved baselines are named in a notice unless
-- opts.quiet. Objects are left to git's own gc.
baseline.prune(root, kind, opts, cb)

-- The retention exemption, fn(entry) -> boolean; nil clears it.
-- ai.review.rounds installs "this round's draft is a non-empty file". A
-- predicate that raises keeps the entry and warns once.
baseline.set_exempt(fn)
```

`kind` is `"round"` or `"saved"`. `meta` (save): `subject` is the message's
first line, the display text (default `nvim review <kind> HH:MM:SS`); every key
that starts with an uppercase letter becomes a trailer after `Nvim-Review: 1`,
sorted (`true` is written `1`; `false` and nil are left out); `tree` skips the
snapshot; `prune = false` skips retention; `exempt` goes to prune.

`info` (snapshot, save): `skipped` (untracked paths over `max_file_size`, left
out of the tree and never hashed), `untracked` (how many untracked, non-ignored
files there were), `unreadable` (git's complaint, when `add --ignore-errors`
passed over a file or a nested repository), `toplevel`, `gitdir`, `wtid`.

An entry (save, list): `{ kind, id, ref, sha, oid, tree, time, subject,
trailers, root, wtid }`. `id` is `YYYYMMDDTHHMMSS-xxxx` in UTC and sorts by
creation time to the millisecond; `oid` equals `sha`; `time` is the committer
time; `root` the worktree's toplevel.

Every callback runs on the main loop, scheduled, and a call from a fast event
reschedules itself. More than 5000 untracked files warn once per gitdir: every
snapshot hashes them again. `tests/baseline_spec.lua` covers the user's state,
ignored and large files, racy git, gc, linked worktrees, signing and hooks.

## CodeDiff Views (`util.codediff`, `util.codediff_actions`)

`util.codediff` is the one module that reads CodeDiff's internals:
codediff.nvim has no API for its session, its hunks or its keymaps (upstream
#577). Its header lists each internal, and AGENTS.md says how they are
guarded. Everything else -- `util.codediff_actions`, `ai.review`, the
`<leader>g` spec -- goes through the functions below. The one exception is
`:checkhealth config` (`lua/config/health.lua`), which asks two things only
CodeDiff knows: the native library's version, through `codediff.core.diff`'s
`get_version`, once the library file is there and with
`VSCODE_DIFF_NO_AUTO_INSTALL` held at 1 for the require; and the watcher
release it wants, `codediff.core.installer.watcher`'s `VERSION`, once CodeDiff
is loaded. Both are pcall'd, and nothing else reads them.

`setup(opts, hooks)` runs from the lazy spec's `config`, at first use: it
compares `codediff.version` with `VERSION`, patches CodeDiff's git runner
(`-c core.quotePath=false`, so non-ASCII paths survive revision and history
views), its revision listing (`listing` below, for every
revision-vs-working-tree view) and its history limit (`hooks.history_limit()`,
the `history_limit` setting), and then runs CodeDiff's own setup, which loads
its native library. A version mismatch warns once and leaves those three patches off.

#### API Reference

```lua
local cd = require("util.codediff")

cd.VERSION            -- "4.0.6", the release the hooks were written against
cd.PANEL_FILETYPES    -- { "codediff-explorer", "codediff-history" }
cd.setup(opts, hooks) -- hooks: { history_limit?: fun(): integer|false }
cd.degraded()         --> true when the installed CodeDiff is not cd.VERSION

-- Open a view: :CodeDiff with `args` as a list, so a path with spaces stays
-- one argument. `root` adds `-C <root>`, escaped for the expand() CodeDiff
-- runs on it; a `-C` already in `args` goes as given, so escape that one
-- yourself. Pass revisions as shas: CodeDiff reads a name like `history` or
-- `file` as its subcommand.
cd.open({ args = {...}, root = ..., label = ..., tab_vars = {...}, quiet = bool, done = fn })
--> true once issued; false (with a WARN) for empty args in a tabpage that
--  already has a view, where a bare :CodeDiff would close it. Raises what
--  :CodeDiff raised.

cd.close(tab)          --> true when it closed a view, or an orphaned tabpage
cd.session(tab)        --> a plain copy of the view's session, or nil
cd.hunk_at_cursor(tab, win)  --> { index, side, original, modified } | nil
cd.fresh_hunk(tab, win)      --> that hunk | nil, reason
cd.panel_item(tab, win)      --> the explorer or history entry on the cursor line | nil
cd.unstage_hunk(tab)         --> ran: CodeDiff's own unstage (the Staged group only)
cd.refresh(tab)              --> requested: list, read and diff again
cd.set_keys(tab, specs, scope)  --> false when `tab` has no view
cd.listing(root, revision, tree, info, pathspec, done)
cd.left_out_lines(left_out, limit)  --> string[]
```

`tab` is a tabpage handle, 0 or nil for the current one; `win` defaults to the
current window (`panel_item`: the panel's own).

`open`: `label` (`vim.t.codediff_label`, shown in the statusline) and
`tab_vars` land on the view's tabpage when it opens -- CodeDiff opens
asynchronously, after its git commands -- and only on a view that fits the
spec: the `root` it names, a status, staged or history mode where `args` name
one, the revisions `args` give as full shas. Another view opening meanwhile,
from another `open()` or a typed `:CodeDiff`, never takes them, and several
opens can be in flight at once. `quiet` leaves out the `Comparing <label>`
notice, for a caller that says what the view compares itself. `done(tab)`
runs once the view has opened; `done(nil, why)` when CodeDiff refused it for
an empty listing or it did not open within 10 s; exactly once for an `open()`
that returned true.

`session`: `mode` (`"status"` for `:CodeDiff` with its Staged / Changes /
Conflicts groups, `"revision"` rev vs working tree, `"revisions"` rev vs rev,
`"staged"` rev vs index, `"history"`, `"dir"`, `"file"`), `git_root`,
`original`/`modified` as `{ relative, absolute }` real paths -- `""` on the
missing side of an added or deleted file, never a `codediff://` name --,
`original_revision`/`modified_revision` (nil is the working tree, `":0"` the
index), `base_revision`/`target_revision`, `source_revisions`, `selection`,
the `*_bufnr`/`*_win` of both panes and a conflict's `result`, `layout`,
`single_side`, `conflict`, `panel` (`"explorer"`, `"history"` or nil) with
`panel_bufnr`/`panel_win`, and `tabpage`.

`hunk_at_cursor`: the displayed hunk under the cursor of a pane, by CodeDiff's
own rule -- `original`/`modified` are `{ start_line, end_line }`, 1-based with
`end_line` exclusive, and an empty range matches at its start line; `side` is
the pane the cursor is in. `fresh_hunk` recomputes the diff from both
buffers' current text with CodeDiff's own engine and options and returns the
hunk only when the fresh result has the same ranges: a view behind an edit or
a write answers nil and why, so nothing acts on stale ranges.

`panel_item`: `{ panel, type, path?, old_path?, status?, group?, commit?,
short_hash?, subject? }`, `type` one of `"file"`, `"directory"`, `"group"`,
`"commit"`, `"title"`. A file has `path` (relative to the repository),
`status` (`M`, `A`, `D`, `R`, `??` ...), `old_path` for a rename and, in the
status view, `group` (`"staged"`, `"unstaged"`, `"conflicts"`); in a history,
the `commit` it belongs to. A history commit row has `commit`, `short_hash`
and `subject`, and no `status` or `old_path`: it claims no rename. In a single
file's history its `path` is that file as the working tree names it; in any
other history, the file CodeDiff lists for the commit, if any, with a verbatim
`old => new` reduced to the new name.

`set_keys`: each spec is `{ mode(s), lhs, rhs, desc = ..., on = ..., opts = {...} }`,
where `on` is `"all"` (the default), `"panes"`, `"panel"`, `"original"`,
`"modified"` or `"result"` and `opts` adds `vim.keymap.set` options. The keys
go through CodeDiff's own keymap registry, which snapshots what a buffer had,
suspends the claims on the real file buffers a view borrows while another
tabpage is current, and hands every key back when the file leaves the view or
the view closes; panel keys stay installed throughout. Call it again on every
`User CodeDiffKeys`: a file switch or a refresh swaps the pane buffers, and
the new ones start without these keys. With a `scope`, a claim the previous
pass of that scope made and this one does not repeat is released.

`listing`: what a view of `revision` against the working tree lists, by the
same rule the listing patch applies to every such view, for a caller that has
to know before it opens one whether CodeDiff will show anything (an empty
listing gets a bare "No changes to show" and no view, #582). `tree` and
`info` are a `util.baseline.snapshot()` of the worktree, and
`diff-tree -r -M -z <revision> <tree>` compares them. `done({ listed,
left_out })`, or `done(nil, err)` when git failed. `listed` holds CodeDiff's
status entries, `{ status, path, old_path? }`, a type change reading `M`;
`left_out` the paths not compared, by reason: `size` (untracked, over
`max_file_size`), `ignored` (ignored now, still on disk) and `other` (still on
disk, so not listed as deleted). It says nothing itself: `left_out_lines`
words `left_out` the way a view's own notice does, one
`Not compared (<why>): a, b` line per reason, with `limit` paths each and a
count of the rest.

What every view gets on its own, from each key pass: `;` and `s` blocked on
every buffer (`nowait`, a notice, and the next key swallowed when it comes
within 'timeoutlen'); `H`/`L`/`[b`/`]b`/`[B`/`]B`/`<C-^>`, the keys that put
another buffer in the window, blocked on every buffer too (`nowait` and a notice, the
next key left alone); `-` (oil's parent directory) blocked the same way on
the panes, and on the panel too unless the status explorer's stage key is
installed there; wheel scrolling that moves both panes, hovered or
focused; `]h`/`[h` on the panes, CodeDiff's own next / previous hunk (as its
`]c`/`[c`) through the public `codediff.next_hunk`/`prev_hunk`; `q` closing the view from the explorer and history panels; in the
status view, the explorer's `-`/`S`/`U`/`X`; and a buffer-local which-key
group `Conflict` where `,go` exists. Each pass then fires
`User CodeDiffKeys` with `data.tabpage`, on which
`util.codediff_actions.attach` (from the plugin spec) and `ai.review.attach`
(from `ai.setup()`) install theirs. A pass runs after `CodeDiffOpen`,
`CodeDiffFileSelect` and every pane buffer swap (a file picked, a refresh, a
layout toggle).

Tab variables, set when a view opens and cleared when it closes:

| Variable | Set by | Read by |
|---|---|---|
| `blocks_global_prefixes` | util.codediff, on every view | `util.window.blocks_global_prefixes` |
| `codediff_label` | `open()`'s label, else a default (`index/HEAD ↔ working tree`, `<rev> → working tree`, ...) | the statusline |
| `codediff_baseline` = `{ sha, kind }` | `<leader>av`, and `<leader>gk`/`<leader>gM` comparing a baseline with the working tree (`tab_vars`) | `util.codediff_actions` (`,X`), `ai.review.feedback` |
| `ai_review` = `{ id, sha, conversation?, source?, root, late }` | the same, when that baseline is a round's (`rounds.review_vars`) | `ai.review` (one review tab per root), `ai.review.feedback` (which draft) |

It also closes an orphaned tabpage -- one CodeDiff let go of with its panel
still on screen, after `:e` in a revision pane, a closed pane, or a pane's
buffer wiped while the tabpage was hidden -- after `CodeDiffClose`, `TabEnter`
and the wipeout of a `codediff://` buffer; unlists `codediff://` buffers;
evens out the two panes when the tabpage gains or loses a window; and, from
the listing, names the files left out (once per view) and a listed file with
unsaved edits whose disk copy changed since (once per change on disk).

`util.codediff_actions.attach(tab)` installs the hunk keys for the view's
kind, under its own `"actions"` scope, on every `User CodeDiffKeys`. It
reaches CodeDiff only through `util.codediff` and gitsigns only through its
public API. The letters are the status explorer's `S`/`U`/`X` (stage,
unstage, discard), for one hunk.

| View | Keys |
|---|---|
| status, Changes group (index → working tree) | `,S`; no `,U`, every hunk there is unstaged |
| status, Staged group (HEAD → index) | `,U`, CodeDiff's own |
| baseline → working tree | `,S` `,U` `,X` |
| the same, a file on one side only | `,X`, which only says what would do it |
| any other revision → working tree | `,S` `,U` |

Revision-vs-revision, `--staged`, history, conflict and single-file views get
none. Before any of them acts it checks that it acts on what is on screen (no
unsaved edits, the disk still holding the buffer's bytes, `fresh_hunk`, a
regular file on both ends with no filter attribute); its header has the
details. `,S`/`,U` change only the real index, `,X` only that one buffer,
written once.

## Move (`util.move`)

Moves the current line, or the selection, with `hjkl` — vertically by moving the
line, horizontally by indenting it.

#### API Reference

```lua
local move = require("util.move")

move.run("down")   -- also "up", "left", "right"; bound to ,{h,j,k,l}
```

The first press comes from `,h`/`,j`/`,k`/`,l`, then bare `h`/`j`/`k`/`l` keep going
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

-- Flush unsaved edits (:update) and run the current buffer's file in a
-- terminal split below it (bound to ,x; a plain :split under 'splitbelow').
-- A refused flush -- read-only file, unwritable directory -- is a warning,
-- and nothing runs.
run.run_current()
```

## Inline Completion Server (`util.llama`)

The local `llama-server` behind minuet's ghost text, started on demand and
shared by every Nvim. Each Nvim registers as `<dir>/clients/<pid>`;
`scripts/llama-supervise` owns the one server (`<dir>/lock`) and stops it once
no registered Nvim is alive; its header lists the exit codes `ensure()` acts
on. A server that never answered and then exited is reported once and not
started again in that session; one that crashes after serving is restarted.
Nothing here checks for a UI or a buffer: the minuet spec only calls
`ensure()` where suggestions can show, so headless runs never load the model.
Nor does anything here retry a request that `ready()` turned away; it fires
`User LlamaReady` instead, and the minuet spec asks again for the position the
cursor waits at.

#### API Reference

```lua
local llama = require("util.llama")

-- port (8012), dir (stdpath("state") .. "/llama"), server ("llama-server"),
-- args (the --fim-qwen-7b-default preset and its tuning), model (the Hugging
-- Face repo the preset loads, for :checkhealth config) and recheck (5000 ms).
llama.config

-- Register this Nvim and start the server unless /health already answers;
-- then poll until it does, asking the supervisor again every two seconds in
-- case the owner it handed over to was stopping. Returns at once while a
-- check is in flight, and while the server answers (or after a failed start)
-- checks at most every `recheck` ms, so it can run on every InsertEnter and
-- every request.
llama.ensure()

llama.ready()          -- true while /health answers; gates minuet's requests
llama.failed()         -- true after a failed start, which is not retried

-- `User LlamaReady` fires each time ready() turns true: the first answer after
-- a start (or from a server another Nvim started), and again once a server
-- that stopped is replaced. A recheck that finds it still answering is silent.
llama.release()        -- unregister (runs on VimLeavePre)
llama.url("/infill")   -- "http://127.0.0.1:8012/infill"
llama.log()            -- <dir>/server.log, rewritten at each server start
```

## AI State (`ai.config`, `ai.switch`)

The ways to chat are an ordered `providers` list in `lua/ai/config.lua`,
written like CodeCompanion's adapters; the HTTP **key profile** is the one
setting `:AI key` switches in-process. Nothing is persisted. A provider has a
`name`, a `label`, an optional `cli_api_key` (the variable its CLIs bill
against instead of the subscription login: the picker and `:checkhealth
config` warn while it is set) and the parts it offers; a part left out is not
offered:

- `tui = { kind }` -- its native terminal agent. `kind` is one this config
  implements, `claude` or `codex`, each offered at most once: a new kind needs
  code (a backend module, a tmux wrapper, the prompt hooks, a transcript
  reader), not just an entry.
- `acp = { adapter, command, auth_method? }` -- its CLI driven by
  CodeCompanion over ACP, on the subscription. `auth_method` becomes the
  adapter's default; Codex's is `"chat-gpt"`, since codex-acp's own default
  bills `OPENAI_API_KEY`.
- `api = { adapter, label?, api_key, model?, name? }` -- a CodeCompanion HTTP
  chat on API credits, and a key profile. `api_key` names an `NVIM_*`
  variable, never a CLI's own. The profile's name, `api.name` (default
  `api.adapter`), must be unique: it is also the CodeCompanion adapter it
  registers, so a chat restored from history finds its key again.

The defaults are `claude` (terminal `claude`, ACP `claude_code` through
`claude-agent-acp`, API `anthropic` on `NVIM_ANTHROPIC_API_KEY`), then `codex`
(terminal `codex`, ACP `codex` through `codex-acp` on the ChatGPT login, API
`openai` on `NVIM_OPENAI_API_KEY`). A second key on one API is one more
provider with only an `api` part; the file has a commented example. `build`
checks the list at load, and a bad entry stops startup naming the provider.

The order is the only preference; no backend is the default. The new-chat
picker lists every available terminal, then every ACP chat, then every API
chat, each group in provider order. A key only a native agent answers acts on
the native agent on the right, else asks among the installed terminals in
that order (with one installed, that one). CodeCompanion's own paths that
name no adapter (a typed `:CodeCompanionChat`, the action palette) use the
first `acp` in provider order, else the first `api`. The key profile is
`auto` -- the first profile whose `NVIM_*` key is set, else the first --
until `:AI key` pins one (`NVIM_AI_KEY_PROFILE` > `vim.g.ai_key_profile` at
startup).

Some of CodeCompanion's built-in adapters are set up whatever the list holds,
since a chat restored from history or an upstream path can name one that no
provider offers: `anthropic` and `openai` read `NVIM_ANTHROPIC_API_KEY` /
`NVIM_OPENAI_API_KEY` (`builtin_http_keys`), never a CLI's own variable, and
the `codex` ACP adapter uses the ChatGPT login (`builtin_acp_auth`). A
provider's `api` that keeps a built-in's name (no `api.name` of its own) sets
its own `NVIM_*` key there, and an `acp.auth_method` overrides the login.

`NVIM_AI_PROVIDER` and `vim.g.ai_provider` are no longer read: a leftover
value earns one warning, not a failed start. Every consumer holds the one
`ai.config` table and reads it per call, so a key switch mutates it in place.

#### API Reference

```lua
local config = require("ai.config")

config.providers       -- the list, in order, as written
config.agents          -- the native terminals offered, by kind: { name (the
                       -- kind), provider, label, command, prompt_pattern,
                       -- capabilities, cli_api_key? }
config.agent_names()   -- their kinds, in provider order
config.acp             -- the ACP chats offered, in order: { provider, label,
                       -- adapter, command, auth_method?, cli_api_key? }
config.key_profiles    -- the key profiles, by name: { name, provider, adapter
                       -- (the built-in it extends), label, api_key, model? }
config.key_names()     -- their names, in provider order
config.auto_key()      -- what `auto` stands for now: the first profile whose
                       -- key is set, else the first; nil when no provider offers `api`
config.builtin_http_keys -- { anthropic = "NVIM_ANTHROPIC_API_KEY", openai = "NVIM_OPENAI_API_KEY" }
config.builtin_acp_auth  -- { codex = "chat-gpt" }
config.codecompanion   -- { acp_adapter, chat_adapter, http_adapter, api_key, model }
config.key             -- { name, label, auto }; name nil (label "none") when
                       -- no provider offers `api`
config.panel.width     -- 90 columns, shared by both agent panels and the chat window

-- codecompanion.acp_adapter is the adapter of the first `acp` in provider
-- order (nil when no provider offers one); chat_adapter, what CodeCompanion's
-- own chats use, is acp_adapter, else the first key profile, else nil
-- (CodeCompanion's own default). Both are fixed at load. http_adapter,
-- api_key and model are the key profile's and follow :AI key.

-- Check a provider list and derive the tables above from it. Pure: nothing
-- is assigned, so a spec can feed it any list. Raises at level 0, with
-- "AI providers: …" saying which entry, on an empty list, a missing name or
-- label, a name listed twice, a provider with no part, a cli_api_key that is
-- not a string, a tui.kind not implemented or already offered, an acp
-- without adapter and command, an api without adapter, or an adapter or api
-- name used twice; and through check_key_profile on an api_key that is not
-- NVIM_*.
config.build(list)  --> { providers, agents, agent_names, key_profiles, key_names, acp }

-- Specs only: run with another list in-process, as if lua/ai/config.lua held
-- it. `auto` resolves again, and a pinned key the new list lacks falls back
-- to it; what a plugin read at its load (CodeCompanion's adapters) stays.
config._set_providers(list)

-- Every way to start a chat, available or not, for the new-chat picker:
-- the terminals, then the ACP chats, then the API chats, each in provider
-- order. Reads PATH and the environment only; loads no plugin.
--   { id = "claude"|"codex"|"acp:<adapter>"|"api:<profile>",
--     kind = "native"|"acp"|"http", provider, agent?, adapter?, command?,
--     profile?, api_key?, model?, label, available, why?, warn? }
-- `provider` is the providers entry's name; `label` names transport and
-- billing ("Codex · terminal · subscription", "OpenAI · CodeCompanion API ·
-- API credits"); `why` says what is missing; `warn` names a CLI billing
-- variable that is set.
config.backends()

-- The directory an agent session belongs to: the Git root of `path`'s
-- directory ("" or nil: of the cwd), else the cwd. Codex starts there, and
-- Claude does too under claude_cwd = "git_root". ai.selection makes paths
-- relative to it, and the transcripts find their project by it.
config.project_root(path)

config.use_key(name)       -- "auto" resolves now (auto_key), a profile name pins it
config.key_setting()       -- "auto" or the pinned profile name
config.http_adapter_spec() -- inline/cmd adapter: name, or { name, model }
config.check_key_profile(name, profile) -- error unless api_key is NVIM_*, never a CLI's own

-- Which native agent a terminal command runs (any CLI a provider's `tui`
-- offers), and which agent handed over a prompt file, from the temp path its
-- CLI chose: nil for a path none uses (an agent's pane running `git commit`).
-- Nothing falls back to a provider picked for the user.
config.agent_of_command(cmd)     -- the TUI kind ("claude" / "codex") or nil
config.agent_of_prompt(path)     -- the TUI kind ("claude" / "codex") or nil
config.is_native_command(cmd)

local switch = require("ai.switch")
switch.key(name)            -- :AI key [name]; nil opens the picker
switch.pick()               -- vim.ui.select over auto and every profile (<leader>ax)
switch.info()               -- :AI info / :AIInfo
```

`:AI` is the chat switcher (`<leader>al`), `:AI new` the new-chat picker
(`<leader>an`); `:AI provider` is gone and says so, pointing at `:AI new` and
the order of `lua/ai/config.lua`. A key switch runs `use_key`, then
`require("ai").apply_keymaps()` (relabels
`<leader>ae`, the one key whose description names a profile), then
`require("ai.companion").sync()` (CodeCompanion's live inline and cmd
adapters), then fires `User AIStateChanged` with `data = { axis = "key",
from, to }` -- lualine listens to it. An invalid name is an error
notification and changes nothing. CodeCompanion's `opts` is a function, so a
plugin loaded after a switch starts from the switched key; its chat adapter is
`codecompanion.chat_adapter`, set then and never changed, and nothing writes
`vim.g.codecompanion_adapter`. `:AI info` loads no plugin: it lists the
providers in order with the parts each offers (terminal · ACP · API, `✗`
where one cannot start here), the adapter CodeCompanion's own chats use, the
key, every profile's variable (set or not), the CLIs' own key variables, and
every open chat with where it is.

Both native backends answer `running()`, `buf()`, `window()` (any tabpage),
`visible()` (current tabpage), `hide()` (current tabpage only; the job stays)
and `reveal()` (show here and focus, starting it when none runs; never
hides), without loading claudecode.nvim -- what the slot (`ai.slot`, below)
is built on. `add_path(path, modified)` mentions a file, warning when the
buffer has unsaved changes, since both agents read the saved file. Claude's
`send_range(path, l1, l2)` mentions captured lines through claudecode's
`send_at_mention`, and Codex's `send_text(text)` types a captured draft into
its box as one paste; neither submits. A backend's `asks_first` names the
methods whose cold start asks something before it shows a window (Claude's
`select_model`, claudecode's model question): nothing is hidden for them
until the terminal shows.

```lua
local ai = require("ai")

-- Call one agent's backend method by name, whatever is on the right. A
-- method that feeds the panel (edit_prompt, send_selection, tree_add) first
-- makes room for *that* agent's panel: every other AI window of this tabpage
-- gives way to it (unless it is on screen somewhere already). Review feedback
-- reaches the round's agent this way. An unknown agent or a method its
-- backend lacks is a WARN; a method that raises, an ERROR.
ai.feed(agent, method, ...)

-- What review feedback sends: the backend stages `seed` for that agent
-- (ai.editor.stage_seed) and presses the TUI's own ctrl+g.
ai.feed("claude", "edit_prompt", { seed = text, on_consumed = fn, on_expired = fn, ttl_ms = 10000 })

-- Images go to the agent that owns the prompt, never to one guessed at: a
-- prompt that names no agent (nil) has its staged files deleted, attached to
-- nothing, saying so.
ai.attach_images(paths, agent)

ai.info()  -- the data :AI info prints: providers (in order, each part with
           -- whether it can start here), key, profiles, cli_keys,
           -- codecompanion (its own chats' and inline adapters), chats
```

Both backends' `edit_prompt(opts)` take `{ seed?, on_consumed?, on_expired?,
ttl_ms? }` and pass them to `stage_seed` with their own agent; `<leader>ai`
passes only `seed`.

## AI Slot (`ai.slot`)

Per tabpage the right shows at most one AI window: native Claude, native
Codex or a CodeCompanion chat -- a "chat" in the keys' words. What is open is
computed from live state on every call, never registered; nothing here loads
claudecode.nvim or CodeCompanion to answer. Showing one hides the others in
the current tabpage through their own owner's hide (claudecode's `cc_hide`,
Snacks' hide, CodeCompanion's `ui:hide`): never a stop, close or wipe, never
edgy's hide/close, never another tabpage. A window its owner cannot hide
(claudecode's copy of its terminal in a diff tabpage) is left alone and still
counts as shown here. A `BufWinEnter` guard holds the rule for upstream's own
paths (`<leader>ao`, a typed `:CodeCompanionChat`, the action palette, the
chat CodeCompanion shows in place of one ended with `,q`, claudecode
re-showing its terminal, a model picked at claudecode's question): it
records the tabpage when the event fires, ignores floats, and the latest AI
window entered in a tick wins.

#### API Reference

```lua
local slot = require("ai.slot")

-- Items: { id = "native:<agent>" | "cc:<buf>:<chat id>", kind = "native"|"chat",
--          agent?, chat?, win? }
slot.list()               -- every open chat: running agents, then live chats
slot.shown(tab?)          -- the items a non-floating window shows in `tab`
slot.label(item)          -- "Codex · terminal · subscription", a chat's adapter,
                          -- kind and name
slot.where(item)          -- "● here", "tab N" or "hidden"
slot.state(item)          -- the owner's window: "here", "elsewhere" or "hidden"

-- The chat on the right, read off the windows: the one shown here; from a
-- prefix-blocking view (CodeDiff), the one shown in util.window.origin_tab --
-- which becomes the current tabpage; of several, the current window's.
slot.target(cb, opts?)    -- cb(item, from); else asks: the switcher, or the
                          -- new-chat picker when none is open. A cancel calls
                          -- nothing and goes back to the tabpage it came from.
slot.target_now()         -- the one shown here (of several, the current
                          -- window's), without asking; nil otherwise
slot.shown_here()         -- also from a view, without asking or moving (the
                          -- review loop's owner fallbacks)
slot.native_target(cb, opts?) -- the native agent on the right, else asks which
                          -- (installed ones in provider order; none asked with
                          -- one installed)

-- Asking.
slot.pick_new(cb, opts?)  -- the new-chat picker: available backends in
                          -- ai.config.backends() order; a native entry is that
                          -- agent's one session ("running", "● here"), never a
                          -- second
slot.switch(cb, opts?)    -- the switcher: open chats (here first, then by use)
                          -- and "New chat…"

-- Showing and hiding.
slot.reveal(item)         -- show here and focus (terminal input, chat prompt);
                          -- one shown in another tabpage is gone to
slot.make_room(item, opts?) --> "here" | "elsewhere" | "room" | nil
                          -- before a backend shows `item`: go where it is
                          -- shown, or hide the rest here; a cold start goes to
                          -- util.window.editor_win first; nil when refused.
                          -- opts: jump, editor, hide (false: leave the rest to
                          -- the guard), quiet (no "went there" notice)
slot.cover(keep?)         -- hide every AI window here an owner can hide, but keep's
slot.jump(item, opts?)    -- to the tabpage showing it; says so unless quiet
slot.went(item, from)     -- "Sent to X (tab N)" when a delivery changed tabpage
slot.toggle(), slot.focus()  -- <leader>ac (and q in a chat) / <leader>af

-- The pieces the facade (ai) and ai.companion build on.
slot.native_item(agent), slot.chat_item(chat)  -- an item for one agent / chat
slot.buf_of(item)         -- its buffer; nil once it is gone
slot.item_of_buf(buf)     -- the item `buf` shows, if it is an AI buffer
slot.home()               --> shown, from: the items on the right of the tabpage
                          -- the keys act in (this one, or a view's origin,
                          -- which becomes current) and the tabpage pressed in
slot.victims(keep?)       -- { item, win? } for each AI window here an owner
                          -- can hide, but keep's
slot.chat_window_here(item) -- another chat's window here, for `item` (a chat)
                          -- to take over in place
slot.hide(item, opts?)    -- through its owner; a chat mid-turn says so.
                          -- opts.keep_window: leave a chat's window for the next
slot.around(keep, open)   -- run open() with the rest hidden: before it, or after
                          -- it when they are all this tabpage has (E444)
slot.remember(item)       -- vim.t.ai_slot_last = item.id
slot.setup()              -- the BufWinEnter guard and the approval notice
```

`vim.t.ai_slot_last` remembers the last chat a tabpage showed, for
`<leader>ac`/`af` to bring back -- never to deliver to. Hiding a chat that is
replying or waiting for a tool approval says so, and a hidden chat that asks
for an approval (`User CodeCompanionToolApprovalRequested`) is announced.
Hide comes first and show second, except when the windows to hide are all the
tabpage has (E444), when the order turns round. `tests/ai_slot_spec.lua`
pins it with stand-in agents and real API chats that never send.

## AI Companion Chats (`ai.companion`)

CodeCompanion's two chat kinds, as the slot puts them on screen: `acp` (an
agent CLI over ACP, on the subscription) and `http` (a key profile over HTTP,
on API credits). Upstream's Toggle and Add only know `last_chat`, so this
module creates a chat of exactly the backend asked for and shows exactly the
chat asked for. It never calls upstream's `Chat.open` without a window: that
path closes `last_chat` wherever it is shown, another tabpage included. The
module requires nothing from CodeCompanion at load; the first call that needs
it does, and that is what loads the plugin.

#### API Reference

```lua
local companion = require("ai.companion")

companion.preflight(what)      -- false (and an ERROR) when an "http" backend's
                               -- NVIM_* key is unset or an "acp" bridge is missing;
                               -- `what` is one ai.config.backends() entry, or
                               -- "http" for the key profile's HTTP adapter
                               -- (<leader>ae), refused when no provider offers an
                               -- API key
companion.create(spec, extra?) -- a chat on one ai.config.backends() entry, created
                               -- hidden from the editor window and announced
                               -- ("New chat: <label>"); nil when refused
companion.show(chat, opts?)    -- shown here: focus; shown in another tabpage: go
                               -- there; else take a chat window here in place, or
                               -- split one after the slot made room.
                               -- opts: focus (default true), toggled, quiet
companion.hide(chat, opts?)    --> ok, err: ui:hide, never raising; keep_window
                               -- leaves the window for the next chat
companion.chats()              -- every live chat, with buf_get_chat()'s entry
companion.chat_of(buf), companion.key(chat), companion.buf(chat)
companion.label(chat), companion.name(chat)
companion.win(chat), companion.win_here(chat), companion.where(chat)
companion.add_capture(chat, cap) --> true | false, why
                               -- a captured selection (ai.selection.capture),
                               -- fenced with its source; never submits
companion.focus_prompt(chat, insert?) -- show it, cursor at the end of its prompt;
                               -- Insert mode unless it is replying
companion.inline_keys()        -- ":CodeCompanion " or "<Ignore>" (the <leader>ae expr)
companion.sync()               -- write the live inline/cmd adapters, never the chat's

-- For review feedback, aimed at one exact chat:
companion.busy(chat)           -- mid-turn: a request in flight, a tool loop between
                               -- two steps, or a buffer that is not modifiable
companion.add_text(chat, text) --> true | false, "gone"|"busy"|"failed", err?
                               -- append to that chat's prompt; never submits
companion.show_input(chat)     -- focus_prompt(chat, true)
```

`add_text` writes to the chat CodeCompanion still keeps for `chat.bufnr`
with the same `chat.id` -- never a newer chat that reuses the buffer -- and
refuses, changing nothing, while that chat is busy or gone. `prompt:add`
writes at the buffer's last column, so text that is to follow what the user
already typed starts with `"\n"`; review feedback always does. A chat whose
buffer is gone is not busy, it is gone.

`preflight` only guards what starts something: creating a chat (an agent chat
spawns its bridge at once, an API chat already fetches the model list with the
key) and the inline prompt. Showing, hiding or adding to an existing chat
sends nothing. Its notification is scheduled, because `<leader>ae` asks from an
expr mapping, under textlock.

The module reads CodeCompanion's internals: `chat.adapter`, `chat.ui`
(`is_visible`, `is_visible_non_curtab`, `open`, `hide({ keep_window })`,
`winnr`), `chat.title`, `chat.bufnr`, `chat.id`, `chat.prompt:add`,
`interactions.chat.open({ ui, winnr })`, the `hidden` chat argument and
`buf_get_chat()`'s entries; `busy`, `add_text` and `show_input` also read
`chat.current_request` and the private `chat._turn_in_progress`: between two
steps of a tool loop `current_request` is already nil and the buffer editable
again, and only that flag is still set. Each is read in a pcall, so a rename
upstream loses one signal rather than raising. `tests/companion_spec.lua`
pins the module and `tests/review_feedback_spec.lua` the mid-loop refusal.

## AI Panel Input (`ai.terminal`)

Buffer-local input rules for every native agent panel -- whichever agent
runs in it -- applied through one `TermOpen` hook because both
agents open through Snacks — the per-backend
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
of scrolling the near-empty buffer again. A wheel event that reaches tmux
directly is bound to `copy-mode -e` rather than `-eu`: the page jump `-u` adds
belongs to `<PageUp>`, not to one notch of the wheel, which then scrolls 2 lines
per event because Ghostty sends three of them per notch. That automatic
transition is marked for one event so it preserves copy-mode; any later
`TermEnter` -- whether from `i`, `a`, another terminal-input entry key, or
automatic focus -- runs `tmux copy-mode -q` and returns the panel to its live
bottom.

## AI Selection (`ai.selection`)

Builds agent-ready text from the live visual selection. It sits outside the
backends because the two agents attach selections through different channels:
Codex pastes text, while Claude's `<leader>as` goes over the IDE WebSocket as a
mention of the lines and produces no text at all. `<leader>ai` needs text for
both agents to seed the input box, so the text form has exactly one producer.
`capture()` takes the selection whole, once, for every route it may take
after a question: Claude's lines, Codex's draft, a chat's fenced block.

#### API Reference

```lua
local selection = require("ai.selection")

---@return string|nil draft   nil when the selection could not be read
---@return string|nil err     reason, set only when draft is nil
---@return string|nil notice  informational message the caller may surface
local draft, err, notice = selection.draft()

-- The selection taken whole, before anything asks where it goes, then out of
-- Visual mode: { buf, win, mode, l1, l2, lines, path, modified, filetype,
-- tree, draft?, err?, notice? }. vim.ui.select is asynchronous, so a key that
-- asks captures first; CodeCompanion's utils.context.get is no substitute
-- afterwards (it reads the current buffer's marks).
local cap, err = selection.capture()
selection.is_tree(buf?)  -- a directory listing, whose selection names files
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

The staging directory is named after the pid, and pids are reused, so the
first `staging_dir()` call in a process empties it: a new Nvim never starts
with a dead one's images.

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
editor.EDIT_KEY              -- the byte both TUIs bind to "edit in $EDITOR" (0x07)
editor.tui_ready(buf)        -- has the agent TUI in buf drawn its input prompt?
editor.when_ready(get_buf, action, on_timeout)

-- Text to add to the next prompt `opts.agent` hands this Nvim. The
-- agent is required: a seed has an addressee, and no agent gets one by
-- default. One slot per agent; nil or "" only clears that slot.
editor.stage_seed(text, { agent = ..., on_consumed = fn, on_expired = fn, ttl_ms = ... })

-- Bring an already-open prompt float back into focus, appending `text`.
-- With `agent`, only that agent's prompt counts; without, the one open in
-- this tabpage wins, else the one opened last -- no agent outranks the other.
-- false when no (such) prompt is open.
editor.focus_open(text, agent)     --> boolean
editor.open_here()                 --> open, owner?: a prompt float in this tabpage
editor.is_prompt_win(win)          -- is `win` one of the open prompt floats?

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
the buffer instead has no ordering to lose, and needs no paste sanitising.

A seed has an addressee, so each provider has a slot of its own, taken
unconditionally by the first `open` of that provider's prompt
(`config.agent_of_prompt`): an unanswered request cannot leak its seed
into a later `ctrl+g`, and review feedback staged for Claude never lands in a
prompt Codex opens meanwhile, or the other way round. The stager hears what
happened through exactly one callback, at most once: `on_consumed` once the
text is in a prompt on screen; `on_expired` when it never will be -- replaced
by a newer seed, cleared, not taken within `ttl_ms`, or handed to a prompt
that failed to open. Without `ttl_ms` a seed waits for that provider's next
prompt, as a `<leader>ai` selection always has. A plain `<leader>ai` stages
into the same slot, so it replaces a pending feedback seed, which then
expires and keeps its draft.

### Images

`<C-v>` stages the clipboard image through `ai.clipboard` and nothing is written
into the buffer — the prompt file is plain markdown, and only the CLI can put
image bytes into its request. On return, the staged files are replayed through
the TUI's own `ctrl+v` (`ai.attach_images`), and the CLI writes its own
`[Image #N]` marker. They go to the agent that owns the prompt, read from the
temp path its CLI chose (`config.agent_of_prompt`: `claude-prompt-*.md` for
Claude, `$CODEX_HOME/editor/*.md` for Codex), so a Codex prompt hands its images
to Codex whatever is on the right. The float's title names the same owner. A
prompt whose path names neither agent (a `git commit` run in an agent's pane)
has no owner: it takes no seed, `<C-v>` refuses, and its title is " Prompt ".

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

## AI Review (`ai.review.*`)

The review loop's modules, as other modules call them: a round is a baseline
(`util.baseline`, kind `"round"`) plus the conversation that owns it and the
root it was taken in; `<leader>av` shows what changed since, and `,C` /
`<C-d>` send feedback back to that conversation. AGENTS.md ("Agent Hooks",
"One Round Model") has the invariants and docs/MANUAL.md the workflow.
Nothing here is loaded at startup but `ai.review.config` and
`ai.review.hook`, which load no plugin and run no git.

### Settings (`ai.review.config`)

```lua
local cfg = require("ai.review.config")

cfg.get()        -- the effective settings: vim.g.ai_review merged over the defaults
cfg.defaults()   -- the defaults alone, a deep copy
cfg.overrides()  -- { ["retention.rounds"] = true, ... }: what vim.g.ai_review set
```

`get()` merges again on every call and returns a fresh table, so a change
applies from the next use and a caller may keep or change what it got. Assign
`vim.g.ai_review` as a whole table: `vim.g` hands out copies, so
`vim.g.ai_review.retention.rounds = 30` is lost. A key that is not a setting,
a value of the wrong type and one outside its domain each warn once (title
"AI review") and fall back to the default; the rest of the table still
applies, and a bad entry of `always_confirm` is dropped on its own. The
warnings are scheduled, so `get()` also works in a `vim.system` callback. A
rejected value is not in `overrides()`.

| Key | Default | Read by |
|---|---|---|
| `retention.rounds`, `retention.saved` | `20`, `10` | `util.baseline.prune` |
| `max_file_size` | `10485760` (10 MiB) | `util.baseline.snapshot`, util.codediff's notices |
| `sources.claude`, `sources.codex` | `true` | the hook injection, `ai.review.hook.event` |
| `sources.codecompanion_acp`, `sources.codecompanion_http` | `true` | `rounds.attach_chat`, every chat submit |
| `hook_wait_ms` | `2500` (`0`: never wait) | `scripts/agent-hook` (argv), the chat callback |
| `claude_cwd` | `"git_root"` (or `"cwd"`) | claudecode's `cwd_provider` |
| `unknown_session` | `"confirm"` (or `"refuse"`) | `rounds.resolve_sink` |
| `always_confirm` | `{}` (entries `"claude"`, `"codex"`) | `rounds.resolve_sink` |
| `redirect` | `true` | `rounds.resolve_sink` |
| `seed_ttl_ms` | `10000` | `ai.review.feedback`, native delivery |
| `history_limit` | `100` (`false`: no limit) | the `<leader>gh`/`gH` desc, util.codediff's history patch |

### Native hooks (`ai.review.hook`)

```lua
local hook = require("ai.review.hook")

hook.script()           -- absolute path of scripts/agent-hook
hook.claude_settings()  -- Claude's --settings JSON: UserPromptSubmit, async SessionStart
hook.codex_override()   -- Codex's -c value: hooks={UserPromptSubmit=[...],state={...}}
hook.codex_trust_hash(event_key, command, timeout)  --> "sha256:<hex>"
hook.CODEX_TRUST_KEY    -- "/<session-flags>/config.toml:user_prompt_submit:0:0"

-- The RPC receiver scripts/agent-hook calls.
hook.event(agent, event, payload_path, done_path)  --> status
```

`claude_settings` and `codex_override` read `hook_wait_ms` when called, put
it into the script's argv, and give the hook a timeout of
`max(10, ceil(wait / 1000) + 5)` seconds. `codex_trust_hash` is sha256 over
the sorted, compact JSON of the normalized handler, as Codex computes it;
`codex_override` embeds the hash of exactly the command it injects.

`event` answers at once: `"ok"`; `"ignored"` for an event that carries
`agent_id`; `"disabled"` when that agent's source is off; `"missed"` when the
script had already given up (a submit then may notify that its prompt has no
baseline); `"error:usage"` / `"error:payload"`. An accepted event goes to
`rounds.native_event` on the next tick. A submit is held until that handler
calls `done` (once the baseline's tree is written) or the script stops
waiting, which deletes the payload -- `gave_up()` reads that; a session event
is released at once.

### Rounds and delivery checks (`ai.review.rounds`)

```lua
local rounds = require("ai.review.rounds")

-- Every source opens rounds here.
rounds.submit(ev)        -- { source, conversation?, root, turn?, gave_up?, done?, force?, on_round? }
rounds.native_event(ev)  -- from ai.review.hook: { agent, event, payload, done, gave_up };
                         -- Claude waking itself (a task notification, an agent's
                         -- hand-back) opens no round
rounds.start(opts)       -- <leader>aV; opts.buf (default: the current buffer)

-- The registry (this Nvim only, in memory), fed from ai.setup()'s autocmds.
rounds.track_terminal(buf, cwd)  -- TermOpen; agent terminals only, root fixed now
rounds.chat_created(data)        -- User CodeCompanionChatCreated
rounds.chat_closed(data)         -- User CodeCompanionChatClosed
rounds.attach_chat(chat)         -- register a chat, hook its on_before_submit

-- Asking.
rounds.select_round(root, cb, opts)  -- cb(entry, why) | cb(nil, err?)
rounds.review_vars(entry)        --> vim.t.ai_review for a round entry, else nil
rounds.conversation_of(buf)      --> conversation?, root?, bound
rounds.live_conversations(root)  --> the sessions this Nvim could deliver to there
rounds.label(conversation)       --> "Claude Code session 7f0c1a2b…", and the like
rounds.toplevel(path)            --> realpath of the Git toplevel, no git run
rounds.source_label(source)      --> "Claude" for a Source trailer's "claude", nil for none
rounds.prompted_at(conversation) --> when a native session was last prompted here
                                 --  (epoch seconds, fraction kept), or nil
rounds.running(conversation)     --> true while an agent terminal here runs that session
rounds.nonce()                   --> this process's nonce in cc: ids
rounds.draft_path(root, id)      --> stdpath("state")/ai-review/<12 hex>/<id>.md

-- Delivering.
rounds.resolve_sink(conversation, root, cb)  -- cb(target) | cb(nil, reason)
```

`submit(ev)`: `source` is `"claude"`, `"codex"`, `"cc-acp"`, `"cc-http"` or
`"manual"`; `conversation` is the owner (`claude:<session>`,
`codex:<session>`, `cc:<nonce>:<chat.id>`; none for an unbound
`<leader>aV`); `turn` a Codex turn id. The round rules: a root outside Git
opens nothing; the same conversation's same Codex turn, or a repeat within a
second, opens nothing (`force` skips this); the snapshot goes first in its
queue and `done` fires once its tree is written, the round being Late when
`gave_up()` is true by then; a tree equal to the conversation's last round in
this process keeps that round; otherwise a round is saved with
`Source`/`Conversation`/`Root`/`Late` trailers and retention runs. `done` is
always called, exactly once, also when the submit is dropped; `on_round(round,
reused)` hears the round opened or kept.

`select_round`: the newest round of the current buffer's conversation, then of
the chat on the right's (`ai.slot.shown_here`), then the newest this process
opened in `root`, then the newest there at all; `why` is `"buffer"`,
`"right"`, `"process"` or `"latest"`. `conversation_of` answers an agent terminal's
current session or a chat's id, `bound` being true for such a buffer even
before its terminal reported a session. `live_conversations` lists running
agent terminals and open chats in `root`, the chat on the right first: `{
kind = "native"|"cc", conversation?, agent?, chat?, buf, root, label,
session_known?, dirty? }`. `toplevel` takes the nearest ancestor holding a
`.git` directory or file, or the directory itself outside Git.

`resolve_sink(conversation, root, cb)`: `root` may be a list (the view's and
the draft header's) whose realpaths must agree. It checks, in order, the
root, the conversation, that a chat is not busy, and an owner that is gone
(AGENTS.md, "One Round Model"), sending its own notices (WARN, title "AI
review") and asking through `vim.ui.select`; with no owner it opens the
same-root picker at once. `cb(target)` with `{ kind = "native"|"cc",
conversation?, agent?, chat?, buf, root, label, owner?, redirected }`, or
`cb(nil, reason)` with `"root"`, `"owner-gone"`, `"unknown-session"`,
`"busy"`, `"cancelled"`, `"no-session"` or `"unknown"`. Asynchronous whenever
anything is asked.

### Baseline labels (`ai.review.labels`)

```lua
local labels = require("ai.review.labels")

labels.describe(entries, cb, opts)    -- cb(labels): labels[i] = { label, display } or nil
labels.current_name(root, cb, opts)   -- cb(name|nil): the session at work in root (<leader>gK)
labels.stamp(t, now)                  --> "11:16:38" today, "11-09 23:08", "2025-12-31 23:50"
labels.span(start, ended, open, now)  --> "11:16:38 - 11:43:18", "11-09 23:50 - 11-10 00:20",
                                      --  "11:39:25 - …"
labels.shorten(name, width)           --> one line, cut to `width` columns (NAME_WIDTH, 40)
```

`describe` labels `util.baseline.list` entries for the `<leader>g` pickers:
`display` is the picker's line -- `"<session>: <Source> <start> - <end>"` for
a round, `"<name>: Saved <time>"` for a saved baseline -- and `label` the
view's, with the start alone, since a view shows everything since the start.
`labels[i]` is nil where the caller keeps its own (a round with no `Source`,
an unknown kind). A round's session is its `Conversation`; its name is the
first title its records hold and its end the last turn end at or after its
start and before the session's next round, both from `ai.transcript.marks`,
compared to the millisecond (`util.baseline.time_of`). `…` marks a session's
newest round when the session was prompted after its last turn end -- by
this round's own prompt (a non-Late round whose `Source` is the agent) or a
later one `rounds.prompted_at` heard -- and is alive: `rounds.running`, or
records written within `LIVE_SECONDS` (30 minutes). It reads each session
twice, once for the name alone, so a name is there even when the turns miss
the budget; it waits up to `opts.budget_ms` (`BUDGET_MS`, 300) and labels
without what is still being read; `cb` runs once, on the main loop.
`current_name` takes the first native session `rounds.live_conversations(root)`
lists, reads its name alone, loads nothing when `ai.review.rounds` was never
loaded, and answers nil past the same budget. `opts.now` is the clock for the
formatting and the liveness check.

### The view and its feedback (`ai.review`, `ai.review.feedback`)

```lua
local review = require("ai.review")
review.open()       -- <leader>av: the round's baseline against the working tree
review.attach(tab)  -- ,C on every buffer of a Git CodeDiff view (User CodeDiffKeys)

local feedback = require("ai.review.feedback")  -- loaded by the first ,C
feedback.comment({ tab = ..., win = ..., buf = ..., mode = "n"|"v",
  range = { first = <line>, last = <line> } })  -- range: 1-based, inclusive, read only with mode = "v"
feedback.deliver(buf)  -- <C-d> in the draft float
feedback.hide(buf)     -- q: hide the float in this tabpage; the draft stays
```

`open` is asynchronous: it picks a root and a round, snapshots, and opens the
view through `util.codediff.open` with `vim.t.ai_review` and
`vim.t.codediff_baseline` once git has answered, or says why not. `attach`
only hands `,C` to `util.codediff.set_keys` under its own `"review"` scope,
so `util.codediff_actions`' keys on the same buffers stay alone; a directory
or file diff without a repository gets none. `comment` and `deliver` never
raise: every failure is a warning, and a refused or cancelled delivery keeps
the draft.

Drafts are markdown files at `rounds.draft_path(root, id)` -- `<round-id>.md`,
or `unowned.md` for a view that is no round's, with `<id>.last-sent.md`, the
last delivery, beside it -- read and written by every Nvim. Line 1 is the
header, `<!-- nvim-review n=<nonce> round=<id> sha=<sha> conversation=<id>
root="<path>" -->` (an unowned draft has neither sha nor conversation),
written again from the draft's metadata at every save; delivery checks
against it alone, so a draft still delivers after retention pruned its
round's ref. Each intro and each entry opens with a marker line,
`<!-- nvim-review-intro n=<nonce> id=<id> -->` or
`<!-- nvim-review-item n=<nonce> id=<id> path="..." side="new|old|file"
digest="sha256:<hex>|none" -->`; only a marker carrying the draft's own nonce
is structure, so quoted code and typed text -- another draft's header and
markers included -- stay text. Delivery sends everything but the header and
those markers. Two Nvims' versions merge block by block, by id, and a block
both changed line by line against the version both started from; where both
changed the same lines of a block, or this Nvim edited a block that was
delivered or deleted elsewhere, the file keeps its version and this Nvim's
goes to `<id>.conflict.md` (then `.conflict-2.md`, ...), with a warning. A
draft with no feedback left is an empty file, which no longer spares its
round from retention.

## AI Transcript (`ai.transcript`)

Renders one native agent's recorded sessions into a read-only buffer: the
agent on the right, else the one asked for (`ai.slot.native_target`).

#### API Reference

```lua
local transcript = require("ai.transcript")

-- `agent` is required ("claude" / "codex"); anything else is an error,
-- "a transcript belongs to a native agent". Nothing falls back to a default.
transcript.open_current(agent)  -- newest session for the project (<leader>at)
transcript.pick(agent)          -- Snacks picker over this project's sessions (<leader>aT)
transcript.refresh(buf)    -- re-read and re-render in place (`R` in the buffer)
```

Provider knowledge lives in `ai.transcript.claude` and `ai.transcript.codex`,
which share one `Adapter` contract: `sessions(root)` and `parse(path, cap)`.
`ai.transcript.render` turns their common `Entry` list into lines plus a parallel
fold-level array, and never learns which provider produced them. Both read
`$CLAUDE_CONFIG_DIR` / `$CODEX_HOME` when set, as the CLIs do, else
`~/.claude` / `~/.codex`.

#### Session marks (`ai.transcript.marks`)

```lua
local marks = require("ai.transcript.marks")
-- agent "claude" or "codex": cb({ title?, ends, turns, mtime? }) | cb(nil)
marks.read(agent, id, cb, opts)

local time = require("ai.transcript.time")
time.epoch("2026-11-10T03:43:18.085Z")  --> 1794282198.085 (UTC by arithmetic, offsets applied)
time.hhmm(timestamp)                    --> local "HH:MM"
```

A session's name and the ends of its turns, for `ai.review.labels`. The
adapters say where and what: `sources(id)` lists `{ path, patterns, mark,
turns?, titles?, decompress? }` -- Claude's transcript, found as
`projects/*/<id>.jsonl`; Codex's `session_index.jsonl` (names, `turns =
false`) and its rollout (`titles = false`), looked for first under the day
its UUIDv7 id was created, and read through `zstd -dc` (`decompress`) when
Codex has compressed it to `.jsonl.zst` and zstd is installed. Both remember
a path they found (checked with one stat) and a miss for `MISS_TTL` (60 s).
`mark(record)` turns a decoded record into `{ title }`, `{ id, title }` (the
index) or `{ ended }`: Claude's `ai-title` and `custom-title`, its
`turn_duration` and an interrupted turn's user record (never a sidechain's);
Codex's `task_complete` and `turn_aborted`.

`read` decodes only lines holding one of `patterns`, reads on libuv's thread
pool `SLICE` bytes per job in `CHUNK`-sized blocks (collecting each block's
garbage in the worker), keeps the offset it reached so a later call reads
only what was appended (a file that shrank, was replaced or now starts
differently is read again; a compressed one is read whole, again only when
it changes), skips any line over `MAX_LINE`, and keeps a session's first
title. `title` is that name, `ends` every turn end ascending (epoch seconds),
`turns` whether a file of turns was read, `mtime` when the newest of those was
last written; nil when the records say nothing of the session. With
`opts.titles` only the name is wanted: files without names are not read, and
it answers as soon as the name is found. `cb` runs once, on the main loop.

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
