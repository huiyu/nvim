# Manual

A guide to actually using this configuration. If you are new to Vim, start at
[The idea](#the-idea) and read straight through. If you already know Vim and
just want the keys, jump to [The five prefixes](#the-five-prefixes).

The [README](../README.md) covers installing and what plugins are included.
This document covers *using* it.

---

## Contents

- [The idea](#the-idea)
- [The grammar of the keyboard](#the-grammar-of-the-keyboard)
- [The five prefixes](#the-five-prefixes)
- [Getting around: `;`](#getting-around-)
- [Changing code: `,`](#changing-code-)
- [Windows: `s`](#windows-s)
- [This filetype: `\`](#this-filetype-)
- [Everything else: `<leader>`](#everything-else-leader)
- [Workflows](#workflows)
- [When you forget a key](#when-you-forget-a-key)

---

## The idea

Most editors put commands in menus, and you find them by reading. Vim puts them
on keys, and you find them by *knowing what you want to do*.

This configuration takes that literally. Every key you press starts by
answering one question:

| You want to… | Press | Because it means |
|---|---|---|
| be somewhere else | `;` | "which file / symbol / position?" |
| change the code here | `,` | "what do I do to this?" |
| rearrange the screen | `s` | "what about this window?" |
| use something language-specific | `\` | "what does *this filetype* offer?" |
| anything else | `<Space>` | git, tests, debugging, AI… |

Nothing is filed by which plugin provides it. `;f` finds a file whether that
comes from a picker, oil, or something else — you press it because you want
a file, not because you remember a plugin name.

Two consequences worth knowing up front:

- **The things you do constantly are two keys.** Find a file, format, jump to a
  definition. Rare things are allowed to be longer.
- **A key means one thing.** If `,` is "change this code", then finding a file
  is never under `,`, no matter how tempting.

---

## The grammar of the keyboard

Vim is not a pile of shortcuts to memorise. It is a small language, and
**the commands you have not learned yet are ones you can derive**. And when a
derivation stalls halfway, which-key in this config lists what can come next.

The eight rules below are the whole grammar. Worth a skim even if you know Vim:
the later ones are this configuration's own conventions.

### 1. A key's meaning depends on the mode

You start in **Normal** mode: letters are commands, not text. `i` enters
**Insert** mode to type; `jk` typed quickly (or `Esc`) brings you back. `v`
enters **Visual** mode to select. Every rule below is about Normal-mode keys.

### 2. One edit = verb + target

```
verb   target
 d      w        delete to the next word
 c      i(       change inside the parentheses
 y      3j       copy this line and 3 below
 >      G        indent to end of file
 gc     ip       comment this paragraph
```

The **verbs** (operators) are few:

| | |
|---|---|
| `d` | delete |
| `c` | change (delete, then start typing) |
| `y` | yank (copy) |
| `>` `<` | indent / dedent |
| `gu` `gU` | lowercase / uppercase |
| `gc` | comment |
| `=` | auto-indent |

A **target** is either a motion (from the cursor to somewhere) or a text
object (rule 3). A motion on its own moves; after a verb it is the range:

```
h j k l    left, down, up, right          w  b  e     next word / previous word / end of word
0  ^  $    start / first non-blank / end  gg  G       top / bottom of file
}  {       next / previous blank line     t)  T(      up to the next ) / back to after the previous (
```

You do not learn `dw` `d$` `dG` `d}` `dt)` one by one: learn `d`, learn the
targets, and the combinations already exist.

**which-key:** press `d` (or `c`, `y`) and wait half a second — the popup lists
every target.

### 3. `i` inside, `a` around

Text objects do not care where the cursor sits inside them. The first letter
picks **i** (inside) or **a** (around, delimiters included); the second says
what kind of thing:

| Object | Is | From |
|---|---|---|
| `(` `[` `{` `<` | a bracket pair | builtin |
| `"` `'` `` ` `` | quotes | builtin |
| `t` | an HTML/XML tag | builtin |
| `w` `W` `s` `p` | word / WORD / sentence / paragraph | builtin |
| `f` | a **function** | treesitter |
| `c` | a **class** | treesitter |
| `a` | an **argument** — `daa` takes its comma along | treesitter |
| `o` | a **block**, conditional, or loop body | treesitter |

```
"hello world"    cursor anywhere inside
ci"   →  ""      keeps the quotes, you type the new text
ca"   →          takes the quotes too

dif    delete the body of this function, wherever the cursor is in it     daf    delete the whole function
caa    change this argument                                              vio    select the body of this if
```

`i`/`a` also accept an `n` (next) or `l` (last) in between: `cin(` changes
inside the **next** parentheses without moving there first.

**which-key:** press `di` (or `da`, `vi`) and wait half a second — the popup
lists every object.

### 4. Doubled = this line; uppercase = the variant

A verb typed twice acts on the current line: `dd` `yy` `cc` `>>` `gcc`.

An uppercase letter is the "bigger" or "opposite" version of the same key, at
every level:

| Lowercase | Uppercase |
|---|---|
| `d` `c` to somewhere | `D` `C` to end of line (= `d$` `c$`) |
| `i` `a` insert before / after the cursor | `I` `A` insert at start / end of line |
| `o` open a line below | `O` open a line above |
| `n` `t` forward | `N` `T` backward |
| `w` `b` `e` by word | `W` `B` `E` by WORD (whitespace-delimited, bigger) |
| `p` put after | `P` put before |
| `;f` find file · `;s` symbol here · `;t` todos | `;F` find from this directory · `;S` symbol in workspace · `;T` todo+fix |
| `]m` next function start | `]M` next function end |
| `<S-h>` `<S-l>` | previous / next buffer |

A few single keys are just abbreviations: `x` = `dl`, `D` = `d$`, `C` = `c$`.
`s` used to be `cl`; here it is the window prefix, so change one character
with `cl`.

### 5. A number = a count

Before the verb or before the target, either works: `3dd`, `d3w`, `5j`, `3>>`,
`10<C-a>`.

### 6. Single-letter namespaces

A few keys do nothing on their own; they open a drawer, and the next letter
picks from it:

| Drawer | Means | Examples |
|---|---|---|
| `[` `]` | previous / next X | `]d` diagnostic · `]e` error · `]h` git hunk · `]q` quickfix · `]m` function · `]c` class · `]x` conflict · `]y` yank history. Uppercase = first / last: `[D` `]Q` |
| `g` | go somewhere / about the thing under the cursor | `gd` definition · `gr` references · `gb` implementation · `gy` type · `gC` callers · `K` docs · `gx` open URL / file · `gS` split / join · `gv` reselect |
| `z` | folds and spelling | `zR` open all · `zM` close all · `za` toggle · `z=` suggestions · `zg` add to dictionary |
| `Ctrl` | act now, no questions, the same in every mode | `<C-h/j/k/l>` windows · `<C-/>` terminal · `<C-o>` back the way you came · `<C-a>` `<C-x>` increment / decrement · `<C-r>` redo |

**which-key:** press `[`, `]`, `g`, or `z` and wait half a second — the popup
lists the drawer, grouped under headings (`── diagnostics`, `── git`, …) with a
colour per group, so a long list reads as a few blocks rather than an alphabet.
The grouping is declared in `lua/whichkey_spec.lua`. In sectioned popups,
anything not explicitly assigned to a group sorts last under `── others`,
including new plugin keys and builtins. An empty `others` section is hidden;
popups without declared sections, such as `z`, keep the default layout.

`gx` opens the nearest HTTP(S) URL or existing local file on the current line:
URLs use the system browser; referenced files open in Nvim. From a terminal,
the file opens in an editor window in the current tab and the terminal stays
visible. Absolute paths, `~/…`, and relative paths work; relative paths use the
source file's directory, or the Snacks terminal's recorded working directory.
Put paths containing spaces inside quotes or backticks. If there is no target,
an ordinary file buffer retains the fallback of opening itself with the system
application; terminals do nothing.

In terminal-Normal mode, `gx` also joins targets enclosed in `(...)` or `<...>`
that wrap within a table column, including a report printed as `(/tmp/` then
`report.md)` on the next row. Quoted file paths can wrap too. The cursor can be
on either part. Leave terminal input with `Ctrl-\` or `jk` first.

### 7. Everything repeats, and everything backs out

Vim remembers what you just did. Whenever you learn a "repeat" key, learn its
"back out" key with it:

| Did | Repeat | Back out |
|---|---|---|
| an edit | `.` | `u` (redo `<C-r>`) |
| a `/` search | `n` | `N` |
| a `t` in-line search | `;` | `,` |
| a `:` command | `@:` | `u` |
| a macro `qq…q` | `@q` | `u` |
| the last selection | `gv` | — |
| the last picker | `;;` | — |
| put the wrong thing | `[y` `]y` cycle the yank history | — |

While recording a macro, the statusline shows a red `● REC @q` before the
filename (`q` is the current register). Press `q` in Normal mode to stop;
the indicator disappears. Which-key pauses its hints during recording.

The most valuable combination is **one key to move, one key to act**: `*`
searches the word under the cursor → `cwnew<Esc>` changes the first one →
`n.` `n.` `n.`, looking at each before deciding. `cgnnew<Esc>` then `.` `.` `.`
is the shorter form.

Two things differ from stock Vim here. In Normal mode `f` is a flash jump —
type two or three characters and pick a label — so use `t{char}` for the
classic single-character search within a line. And `;` and `,` are prefixes,
so as repeat keys they only fire after a one-second wait; repeat across lines
with `n.` instead.

### 8. A prefix = a question

Every remaining key hangs under one of five prefixes, each answering one
question — that is [The idea](#the-idea), and the next section walks through
them one by one.

### Why this matters

You do not learn `dif`. You learn `d` and you learn `if`, and the combination
already works — along with `cif`, `yif`, `>if`, `gcif`, `vif`. Six operators
times twenty targets is a hundred and twenty commands you never memorised.

When you want to do something new, ask two questions: *what operation?* and
*what should it apply to?* Then type them in that order. Forget halfway, wait
half a second, and the menu tells you.

---

## The five prefixes

```
;  go somewhere            ,  change this code
s  windows                 \  this filetype
<Space>  everything else
```

Press any of them and **wait half a second** — a menu appears showing what is
available. You never have to memorize this document; the menu is the
documentation.

`<Space>?` opens a one-page cheat sheet at any time.

---

## Getting around: `;`

Every way of reaching a file, a symbol, or a position.

### Files

| Key | Does |
|---|---|
| `;<Space>` | **Smart find** — recent + open + all files, ranked by how often you use them. Start here. |
| `;f` | Find file by name in the project |
| `;i` | Find files respecting `.gitignore`, including hidden files |
| `;F` | Find file next to the current one |
| `;r` | Recently opened |
| `;b` | Open buffers |
| `;g` | Files tracked by git |
| `;p` | Switch project |
| `;a` | **Last used buffer (toggle)** — return to the previous buffer in this window. |
| `;;` | Reopen the last search, with its results intact |

Nvim calls that previous buffer the **alternate buffer**. After opening A,
then B in the same window, `;a` goes back to A; another `;a` returns to B.
It uses the builtin `Ctrl-^` and is useful when alternating between an
implementation and its test.

`;<Space>` is the one to build a habit around. It learns which files you touch
and floats them to the top.

### Text and symbols

| Key | Does |
|---|---|
| `;/` | Search the whole project |
| `;?` | Search text respecting `.gitignore`, including hidden files |
| `;w` | Search the word under the cursor |
| `;l` | Search lines in this file |
| `;D` | Search this directory |
| `;s` | Symbols (functions, classes) in this file |
| `;S` | Symbols across the project |

`;f` and `;/` include gitignored files but skip common build/dependency
directories. `;i` and `;?` use `.gitignore` without those extra exclusions, so
tracked source inside a directory such as `build/` remains searchable.

### Browsing

There is no tree sidebar. Directories are browsed and edited through oil,
and files are reached through the pickers above.

| Key | Does |
|---|---|
| `;o` | **oil** — edit the directory as text (see below) |
| `-` | oil, on the current file's directory |

`;F` and `;D` use the file's directory or the displayed Oil directory.
From terminals and other panels, they use the current window/tab working directory.

From a terminal (including Claude/Codex), leave terminal input with `Ctrl-\`
or `jk`, then press `-` or `;o`. Oil opens with focus in the current tab's editor
area, creating an empty editor split if needed. `q` closes Oil and returns to
the editor; the terminal stays open.

Inside Oil, `h/j/k/l` keep their normal cursor motions so filenames are easy to
edit. Use `-` to go to the parent directory, Enter to open the selected file or
directory, `g?` to see Oil's keymaps, and `q` to close. Edit filenames or add/delete
lines, then `:w` to review and confirm the filesystem changes.

### Pinned files

| Key | Does |
|---|---|
| `;H` | Pin the current file |
| `;h` | Show the pinned list |
| `;1` … `;9` | Jump straight to pinned file 1-9 |

Pin the three or four files you are actively changing, then `;2` gets you there
without looking. Re-pin when you move to another task.

### Positions

`;j` jumplist · `;m` marks · `;t` TODOs · `;T` TODO/FIX/FIXME

---

## Changing code: `,`

Everything you do *to* the code in front of you.

| Key | Does |
|---|---|
| `,a` | **Code action** — the fix-it menu (imports, quick fixes) |
| `,f` | Format |
| `,r` | Rename the symbol, everywhere, with live preview |
| `,c` | Run a codelens (gopls offers generate, test, tidy, govulncheck) |
| `,n` | Generate a docstring / annotation |
| `,x` | Run this file |
| `,O` | Outline of this file |

`,a`, `,r` and `,c` only exist where a language server is running — in a plain text
file they are simply not there.

### Moving lines

| Key | Does |
|---|---|
| `,j` / `,k` | Move the line (or selection) down / up |
| `,h` / `,l` | Dedent / indent |

Works on a Visual selection too.

`Ctrl-a` / `Ctrl-x` increment and decrement numbers, dates, versions, booleans
and the configured logical operators. In JS/TS (including JSX/TSX), they also
cycle `let` / `const`; this keyword rule does not apply to other filetypes.

### Refactoring

| Key | Does |
|---|---|
| `,ef` | Extract selection into a function |
| `,ex` | Extract into a variable |
| `,eb` | Extract a block |
| `,i` | Inline a variable |
| `,R` | Menu of all refactorings |
| `,w` | Find-and-replace the word under the cursor |
| `,F` | Full search-and-replace panel |

The `,e*` extractions work on a Visual selection.

---

## Windows: `s`

| Key | Does |
|---|---|
| `ss` | Split below |
| `sv` | Split right |
| `sd` | Close this window |
| `so` | Close every other window |
| `sw` | Previous window |
| `se` | Jump to the editor area |
| `s=` | Equalize sizes |
| `sm` | Zoom this window / restore |
| `sz` | Toggle zen mode for the current file |

`sz` opens the file in a centered, 100-column view, covers the statusline and
tab bar, and dims code outside the current scope. Press it again to return to
the previous layout; file edits remain in the same buffer. Terminals and other
special buffers do not enter zen mode. `sm` remains the ordinary split zoom.

`scrolloff = 8` tries to keep eight screen lines above and below the cursor,
scrolling before you reach an edge. Files near their beginning/end and small
windows cannot always provide that much context. Terminal windows use zero.
`splitkeep = "screen"` keeps text on the same screen line when horizontal
splits open, close or resize; Edgy uses it to keep sidebar layout changes steady.
The alternative `"cursor"` keeps the relative cursor position, while `"topline"`
keeps each window's first visible line.

**Moving between windows does not use `s`** — it is one key:

```
Ctrl-h  Ctrl-j  Ctrl-k  Ctrl-l     left, down, up, right
Ctrl-,                             straight to the editor, and back again
```

Those work from inside a terminal too, which matters when an AI panel or shell
is open beside your code.

---

## This filetype: `\`

`\` holds actions that only mean something in the buffer you are in. The same
key does different things in different filetypes, which is the point. Terminal
buffers add `\1`-`\9` in Normal mode to choose a numbered terminal; those keys
do not appear in ordinary files, even while a terminal is open beside them.

| Filetype | Keys |
|---|---|
| Go | `\o` organize imports · `\G` rebuild the gopls index |
| Python | `\o` organize imports · `\v` select virtualenv |
| C/C++ | `\h` switch between source and header |
| Markdown | `\p` toggle preview · `\r` toggle in-editor rendering |
| LaTeX | `\b` build · `\v` view PDF · `\t` table of contents · `\e` errors · `\k` clean |
| Diffview | `\e` focus file panel · `\co` / `\ct` resolve conflict (ours/theirs) |
| Terminal | `\1`-`\9` choose terminal 1-9 (Normal mode) |

Color previews show hex, `rgb()`, `hsl()` and CSS `var(--name)` references.
CSS variable definitions are resolved within the buffer. Frontend files also
preview Tailwind classes, using the Tailwind LSP for project-specific colors
when it is attached. `:ColorizerToggle` toggles previews in the current buffer.

Press `\` and wait to see what the current file offers.

---

## Everything else: `<leader>`

`<leader>` is the **Space** key. Press it and wait; each letter is a group.

| Key | Group | Contains |
|---|---|---|
| `<Space>g` | Git | status, blame, hunks, lazygit (`gg`), diffview |
| `<Space>G` | GitHub | PRs, issues, reviews |
| `<Space>d` | Debug | breakpoints, step, inspect |
| `<Space>t` | Test | run file / nearest / debug, output panel |
| `<Space>x` | Diagnostics | error list, quickfix, location list |
| `<Space>a` | AI | Claude / Codex panels, prompts, transcript |
| `<Space>b` | Buffer | delete, pin, close others |
| `<Space>m` | Manage | config, plugin source, help, man, keymaps, Lazy, Mason, LSP status |
| `<Space>s` | Session | save / restore a working layout |
| `<Space>y` | Yank | copy file path, yank history, registers |
| `<Space>u` | Toggle/UI | wrap, spell, diagnostics, colorscheme |
| `<Space><Tab>` | Tab | tab pages |
| `<Space>q` | Quit | quit all |

### Config and plugin files

| Key | Does |
|---|---|
| `<Space>mf` | Find files in this Neovim config |
| `<Space>mF` | Find source files in the lazy.nvim plugin installation directory |

These live under Manage because they maintain the editor itself.

---

## Workflows

### Reading unfamiliar code

```
;/  search for something you recognise
gd  jump to the definition
gd  again, and again — follow it down
Ctrl-o  walk back up the way you came
gC  who calls this?
]]  next place this symbol appears in the file
```

`K` shows documentation for whatever is under the cursor. `gr` lists every
reference.

### The edit loop

```
;<Space>   open the file
,a         let the language server fix what it can
,f         format
<Space>tf  run the tests for this file
```

If you are bouncing between two files, `;a` toggles between them. If it is
three or four files, pin them with `;H` and use `;1`-`;4`.

### Reorganising files

`;o` opens the directory **as an editable buffer**. It is a normal Vim buffer:

```
rename a line        → renames the file
dd, then p elsewhere → moves the file
a new line           → creates a file (end it with / for a directory)
dd                   → deletes
:w                   → review the list, confirm, done
```

Moving a `.go` or `.ts` file this way tells the language server, so imports
that referenced it get rewritten instead of silently breaking.

### Git

`<Space>gg` opens lazygit — staging, committing and history in one place.
`<Space>gv` opens diffview for reviewing a branch. Inside diffview, `\` holds
its own actions and `<Space>gq` closes it.
Scrolling the mouse wheel over either diff pane keeps the panes vertically
aligned, including added/deleted-line filler and folded regions, while retaining
keyboard focus. The file/history panel scrolls independently.

### Terminals and AI

```
Ctrl-/       toggle a terminal
3<Ctrl-/>    select terminal 3 from a file (Normal mode)
\1 … \9      choose terminal 1-9 from a terminal buffer (jk first)
<Space>ac    open the AI panel
<Space>ai    write a prompt in a real Neovim buffer
```

`Ctrl-]` leaves terminal input without disturbing the program running in it —
useful because `Esc` belongs to the AI CLIs themselves.

The numbered `\` keys focus or create the selected terminal and never close
it when pressed again. `<C-/>` opens/closes the current or last-used terminal.

---

## When you forget a key

1. **Press the prefix and wait.** `;`, `,`, `s`, `\` or `<Space>` all show a
   menu after a moment. This is the fastest answer.
2. **`<Space>?`** — one page listing every prefix and the common keys.
3. **`<Space>mk`** — search all keymaps by description.
4. **`;;`** — reopens whatever you searched last, if you lost a result list.

The menus are generated from the configuration itself, so they cannot drift out
of date the way a document can.

## Debugging

Open a source file, set a breakpoint with `<Space>db`, then use `<Space>dc` to
choose a launch or attach configuration. The panels open when a session starts.
Step into with `di`, over with `dO`, and out with `do` (all after `<Space>`).

| Key | Action |
|---|---|
| `<Space>dB` | Conditional breakpoint |
| `<Space>dA` / `:DapAttach` | Choose an attach configuration for an existing process |
| `<Space>dL` | Logpoint: print a message such as `value={value}` without stopping |
| `<Space>de` | Choose exception breakpoints from the active adapter's filters |
| `<Space>dR` | Restart the current session |
| `<Space>dD` | Disconnect, requesting that the target keep running |
| `<Space>dt` | Terminate the target |
| `<Space>du` | Close or reopen debug panels |
| `<Space>dw` | Evaluate `<cexpr>` or the live Visual selection |
| `<Space>dW` | Add an editable expression to Watches |
| `<Space>ds` | List sessions; select a main/renderer/child session |
| `<Space>dq` / `<Space>dx` | List / clear all breakpoints |

Character, line and block selections work for evaluation and watches without
yanking. Watch expressions persist in the current editor process; use `d` in
the Watches panel to remove one. Cancelling the watch or logpoint prompt changes
nothing. Exception choices are None, All, or an individual filter; their names
and support depend on the adapter. Set them after starting a session.
Disconnect sends `terminateDebuggee=false`; adapter support still determines
whether a particular target can continue independently. Restart applies to the
selected session; `dl` instead reruns the last configuration.

### Current file and tests

| Key | Scope |
|---|---|
| `<Space>df` | Debug the current source file / its executable target |
| `<Space>td` | Debug the test at the cursor (Go/Python/Java also find the nearest preceding test) |
| `<Space>tF` | Debug tests in the current file |
| `<Space>tm` / `<Space>tf` | Run nearest test / test file without debugging (neotest: Go/Python) |

Set a breakpoint with `<Space>db`, put the cursor inside a test, then press
`<Space>td`. These direct entries save the current buffer first; an unsaved
unnamed buffer or failed write aborts. They use the same keys in every supported
language, with target logic in `lua/lang/*.lua`.

| Language | `df` | `td` / `tF` |
|---|---|---|
| Go | Current `.go` file | neotest-golang + Delve; nearest test / tests declared in this file |
| Python | Current script, using dap-python's environment | neotest-python + debugpy; pytest or unittest |
| Java | Main class matching the current filename, including nested main classes | jdtls nearest method / first test class discovered in the file |
| JS/TS | Current Node script | Project-local Vitest; nearest test requires Vitest 3+ |
| Rust | Cargo binary (choose when ambiguous) | Standard libtest harness, filtered to a function / functions in this source file |
| Dart/Flutter | Current file as entrypoint | SDK test adapter; `test` / `testWidgets` declaration or entire file |

JS/TS and Dart nearest-test selection uses Treesitter plus the framework's native
line filter. Keep the cursor in the test call; a suite/group alone does not select
a test. Parameterized declarations may run multiple generated cases. Custom test
wrappers need an explicit configuration. Node must be able to execute the chosen
JS/TS file; JSX/TSX, browser code and projects needing loaders/builds should use
their application configuration via `<Space>dc`.

Rust uses Cargo's executable list and `--list`/`--exact`, including inline modules
and conventional `foo.rs` / `foo/mod.rs` modules. Custom `#[path]` layouts,
macro-generated tests and non-libtest harnesses need a configuration via `dc`.
A Rust module is not an independent executable: `df` builds a Cargo binary.
Similarly, use Go's **Debug Package** via `dc` when a file needs sibling sources.
Dart picks Flutter when `pubspec.yaml` declares `sdk: flutter`; otherwise it uses
Dart. Run `pub get` first.
Java uses jdtls' class-level API: `tF` runs the first discovered test class,
including its methods; keep separate top-level test classes in separate files.

These entries do not invoke arbitrary business functions without arguments or
setup. Debug a function through a test or application caller. `<Space>dC` means
continue an existing session to the cursor, not call that function.

### Launch, attach, and project configuration

**Launch** starts a new program or test under the debugger. **Attach** connects
to a process you started elsewhere. All supported languages now have attach
entries; the direct file/test keys above remain launch actions.

1. Open the matching source file. For Java, wait for jdtls to attach.
2. Check `:pwd`; use `:cd /path/to/project` if needed. `${workspaceFolder}` and
   the automatic `.vscode/launch.json` lookup use Neovim's working directory.
3. Set a breakpoint with `<Space>db` on an executable line.
4. For launch, use a direct file/test key or choose a configuration with
   `<Space>dc`. For attach, run the terminal command from the language section
   below, then press **`<Space>dA`** or run **`:DapAttach`**.
5. Select the named attach configuration and supply its PID, port or service
   URI. A startup pause may need `<Space>dc` before the source breakpoint fires.
6. Inspect with `dw`/`dW`, step with `di`/`dO`/`do`, and select a session with
   `ds`. Use `dD` to disconnect while requesting that the process continue;
   `dt` terminates the target where the adapter supports it.

`DapAttach` lists only attach entries from the current filetype and the project's
launch.json. It starts a new session even if another session is active; it never
continues that other session. Cancelling makes no connection. If the source
buffer or working directory changes while the picker is open, reopen it.
Attach does not save, compile or replace the externally running program.

Create `.vscode/launch.json` for project-specific programs, arguments, environment
variables, ports and source maps. The file is read on demand, supports comments,
and needs no manual `load_launchjs()` call. Wrap the individual objects shown
below in this structure:

```jsonc
{
  "version": "0.2.0",
  "configurations": [
    // Paste a language's launch/attach object here.
  ]
}
```

Use the adapter names in this guide (`pwa-node`, `codelldb`, etc.), not arbitrary
VS Code extension names. `${file}`, `${workspaceFolder}` and
`${command:pickProcess}` are supported. VS Code `tasks.json`, `preLaunchTask`
and `compounds` are not executed by this setup: run builds/dev servers yourself;
start additional attach sessions with `dA`.

The examples bind debugger ports to loopback. To reach another host, keep its
listener on loopback and forward the relevant port, for example
`ssh -N -L 5005:127.0.0.1:5005 user@server`, then attach to `127.0.0.1:5005`.
Source paths still need the language's mapping option when the machines differ.
Mason adds tools to Neovim's PATH, not your existing shell. If a terminal cannot
find `dlv`, install it on PATH or add the directory shown by
`:echo stdpath('data') . '/mason/bin'` to the shell's PATH.

### Go

Install Go and Mason's `delve`. Launch the current file with `df`; if it depends
on sibling files, choose **Debug Package** in `dc`. `td`/`tF` use neotest-golang
and Delve for a single test or the tests declared in the current file.

For a local process, build with symbols, start it in a terminal, then choose
**Attach** in `dA` and select its PID:

```sh
go build -gcflags='all=-N -l' -o ./build/app .
./build/app
```

For a Delve server, start this from the target project's directory:

```sh
dlv debug . --headless --listen=127.0.0.1:38697 --api-version=2 --accept-multiclient
```

Choose **go: attach to remote Delve**, host `127.0.0.1`, port `38697`.
For an already-built binary replace `dlv debug .` with `dlv exec ./build/app`.
This is Delve's headless multi-client server, not a bare `dlv dap` invocation.
A project attach entry can preserve connection and path mapping details:

```jsonc
{
  "name": "Go server", "type": "go_remote", "request": "attach", "mode": "remote",
  "host": "127.0.0.1", "port": 38697,
  "substitutePath": [{ "from": "${workspaceFolder}", "to": "/srv/app" }]
}
```

The remote adapter accepts these `host`/`port` values; without them it prompts.
`dD` clears this editor's source breakpoints from remote Delve, resumes the
process, then disconnects; local breakpoints remain for reattachment. If that
preparation fails, the connection stays open and reports the error.

### Python

Install Python and Mason's `debugpy`; select your project environment with
`\v` when needed. `df` launches the script; `td`/`tF` use neotest-python.
The selected environment needs pytest for pytest tests; unittest uses the
standard library. An attach target needs debugpy in **its own** environment,
independently of Mason's adapter environment:

```sh
python -m pip install debugpy
python -m debugpy --listen 127.0.0.1:5678 --wait-for-client app.py
# Alternatively, debug a module or test process:
python -m debugpy --listen 127.0.0.1:5678 --wait-for-client -m pytest tests/test_app.py
```

Choose **python: attach to debugpy**, host `127.0.0.1`, port `5678`. Run only one
of the above target commands at a time. `--wait-for-client` prevents startup
code from executing before attachment. Project example:

```jsonc
{
  "name": "Python service", "type": "python", "request": "attach",
  "connect": { "host": "127.0.0.1", "port": 5678 },
  "justMyCode": false,
  "pathMappings": [{ "localRoot": "${workspaceFolder}", "remoteRoot": "/srv/app" }]
}
```

Omit `pathMappings` for a local process using the same paths. For launch-specific
arguments use `type: "python"`, `request: "launch"`, `program`, `args` and `cwd`;
for module launch replace `program` with `module`. See the
[debugpy CLI reference](https://github.com/microsoft/debugpy/wiki/Command-Line-Reference).

### Java

Install JDK 21+ and Mason's `jdtls`, `java-debug-adapter`, and `java-test`.
Open the project and wait for jdtls to finish importing. `dc` discovers main
classes; `df` selects the main class corresponding to the current file.
An empty static main-class list before discovery is normal. Each project uses
its own jdtls workspace. `td`/`tF` debug the nearest test / first discovered test
class. The Java-local aliases `\dt`/`\dT` remain available after attachment.

Start the target JVM with JDWP (adjust source path and fully qualified class):

```sh
javac -g -d out src/example/Main.java
java -agentlib:jdwp=transport=dt_socket,server=y,suspend=y,address=127.0.0.1:5005 -cp out example.Main
```

For a packaged application, use the same `-agentlib:jdwp=...` option followed by
`-jar build/app.jar`. Choose **java: attach to JDWP**, host `127.0.0.1`, port
`5005`. `suspend=y` waits before main runs; use `suspend=n` for a running service.
The Java file open in Neovim need not contain a main method for attachment.

```jsonc
{
  "name": "Java service", "type": "java", "request": "attach",
  "hostName": "127.0.0.1", "port": 5005, "cwd": "${workspaceFolder}"
}
```

For a custom launch use `request: "launch"`, `mainClass: "example.Main"`,
`cwd`, and optionally `projectName`, `args` and `vmArgs`. Keep the target sources
available to jdtls; specify `projectName` when a multi-project workspace is
ambiguous. Saving edits allows supported hot code replacement. After installing
missing bundles run `:JdtRestart`. See the
[Java debugger configuration](https://github.com/microsoft/vscode-java-debug/blob/main/Configuration.md).

### Rust

Install Cargo/rustc and Mason's `codelldb`. `dc` offers **rust: cargo build**
and **rust: cargo test**. Cargo builds asynchronously from the nearest manifest,
resolves actual executables including custom target directories, and prompts
when multiple targets exist. Failed builds abort. `df` launches a Cargo binary;
`td`/`tF` filter standard libtest tests as described above.

For attach, build and start the binary in a separate terminal. Replace `myapp`
with your Cargo binary target name and adjust the output path for custom targets:

```sh
cargo build --bin myapp
./target/debug/myapp
```

Choose **rust: attach to process** and its PID. Use a debug build with debug
symbols; optimized release builds can hide or rearrange variables and lines.
Attachment itself does not invoke Cargo or restart the binary.

```jsonc
{
  "name": "Rust running process", "type": "codelldb", "request": "attach",
  "pid": "${command:pickProcess}", "sourceLanguages": ["rust"]
}
```

For custom launch/build flags, run `cargo build --features ...` yourself and
set `request: "launch"`, `program` to its executable, `cwd` and `args`.
For moved build paths, add `sourceMap`, e.g. `{ "/build/project": "${workspaceFolder}" }`.

### C and C++

Install a C/C++ compiler and Mason's `codelldb`. Build with symbols first;
`dc` provides **LLDB: Launch** and **LLDB: Launch (args)**, which ask for the
executable. The direct `df`/`td`/`tF` entries are not registered for C/C++:
this config does not choose a project build system or test framework for them.

```sh
mkdir -p build
cc -g -O0 main.c -o build/app
# For C++, use this build command instead:
c++ -g -O0 main.cpp -o build/app
./build/app
```

While the program remains running, choose **c: attach to process** or
**cpp: attach to process** in `dA`, then select its PID. For projects, use the
project's debug build (for example CMake's Debug configuration).

```jsonc
{
  "name": "Native running process", "type": "codelldb", "request": "attach",
  "pid": "${command:pickProcess}"
}
```

For launch use `request: "launch"`, `program: "${workspaceFolder}/build/app"`,
`cwd` and `args`. Native PID attachment is local to the machine running CodeLLDB;
an SSH port tunnel alone does not turn a remote PID into a local one. Remote
native debugging requires an LLDB remote target configuration. Both native
languages and Rust use the
[CodeLLDB attach options](https://github.com/vadimcn/codelldb/blob/master/MANUAL.md#attaching-to-a-running-process).

### JavaScript and TypeScript (Node / Vitest)

Install Node and Mason's `js-debug-adapter`. `df` launches the current Node
script. For TypeScript requiring compilation, compile with source maps and run
the emitted JavaScript; JSX/TSX or a project-specific loader needs its own launch
configuration. `td`/`tF` use the nearest installed Vitest; nearest test needs v3+.

Start an inspector target, then choose **node: attach by host/port**:

```sh
node --inspect-brk=127.0.0.1:9229 app.js
# For compiled TypeScript, run the emitted entrypoint instead:
node --inspect-brk=127.0.0.1:9229 dist/app.js
# For a Vitest process started outside Neovim:
npx vitest run --inspect-brk=127.0.0.1:9229 --no-file-parallelism tests/app.test.ts
```

Run one target command at a time; use host `127.0.0.1`, port `9229`.
`--inspect-brk` pauses startup; `--inspect` lets the application start immediately.
**node: attach to process** is the local PID alternative.

```jsonc
{
  "name": "Node service", "type": "pwa-node", "request": "attach",
  "address": "127.0.0.1", "port": 9229,
  "cwd": "${workspaceFolder}", "sourceMaps": true,
  "outFiles": ["${workspaceFolder}/dist/**/*.js"]
}
```

Remove `outFiles` for plain JS; for remote sources add `localRoot`/`remoteRoot`.
A launch entry instead uses `request: "launch"`, `program`, `args`, `cwd`, and
possibly `runtimeExecutable`/`runtimeArgs` for a project loader. Vitest's direct
entries disable file parallelism so source breakpoints bind in test workers.

### Browser JavaScript and Chrome extensions

Run your frontend dev server separately. Start a dedicated Chrome debugging
instance (macOS command; use your Chrome executable path on other systems):

```sh
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --remote-debugging-port=9222 --user-data-dir="$HOME/.cache/nvim-chrome-debug" \
  http://localhost:5173
```

Choose **chrome: attach (port 9222)** in a JS/TS source buffer. A non-default
profile is required by
[current Chrome remote-debugging behavior](https://developer.chrome.com/blog/remote-debugging-port).
Use a project entry to change the port or constrain the page:

```jsonc
{
  "name": "Frontend page", "type": "pwa-chrome", "request": "attach",
  "port": 9222, "webRoot": "${workspaceFolder}",
  "urlFilter": "http://localhost:5173/*", "sourceMaps": true
}
```

For extensions, **chrome: debug extension (launch)** and
**chrome: debug extension (attach)** require the separately installed
`js-debug-webext` build; Mason's upstream adapter is insufficient. Keep the
extension build watcher running. Attach uses the dedicated Chrome instance above;
load the unpacked extension first, then select the attach preset from a source
buffer inside its package. Both presets find `.output/chrome-mv3-dev` above that
buffer automatically (WXT layout). For another layout, use a project config with
an explicit `extensionPath` pointing to the build output. Launch creates its own
profile and installs the extension via CDP. See [extension setup and diagnosis](DIAGNOSTICS.md) and
[the extension spike](../spikes/chrome-extension-dap/README.md).

### Dart CLI

Install the Dart SDK, or use the Dart SDK bundled with Flutter. Adapters prefer
the nearest `.fvm/flutter_sdk/bin`, then PATH. Run `dart pub get` in the package.
The SDK supplies `dart debug_adapter`; no Mason adapter is needed. `df` launches
the current entrypoint; `td`/`tF` run its tests through the SDK test adapter.

```sh
dart run --enable-vm-service=8181 --pause-isolates-on-start bin/main.dart
```

Choose **dart: attach to VM service** and paste the full printed VM service URI,
such as `http://127.0.0.1:8181/<token>/`. Keep its token and trailing path; a port
number or the DevTools web page URL is not the service URI. This attaches to an
existing VM rather than starting the current file.

```jsonc
{
  "name": "Dart VM", "type": "dart", "request": "attach",
  "cwd": "${workspaceFolder}", "vmServiceUri": "http://127.0.0.1:8181/REPLACE_TOKEN/"
}
```

The token changes across runs; the interactive preset avoids editing JSON each
time. For launch use `request: "launch"`, `program: "${workspaceFolder}/bin/main.dart"`,
`cwd` and `args`. Use `\dr` for supported hot reload; `dR` restarts a launched
CLI session. The SDK's [debugging tools](https://dart.dev/tools/dart-devtools)
explain VM service startup.

### Flutter

Install Flutter externally or use FVM. Run `flutter pub get`, then start a
simulator/device (`flutter devices`). `dc` provides **flutter: launch app**
(default `lib/main.dart`), **flutter: attach to running app**, and current-file
tests. `df` uses the current file as the entrypoint; `td`/`tF` use the Flutter
test adapter when the pubspec declares `sdk: flutter`.

```sh
flutter devices
flutter run --debug --start-paused -d macos
```

Replace `macos` with the intended device ID. Choose **flutter: attach to running
app**; enter the same device ID and optionally the printed VM service URI.
A blank URI requests device discovery; a blank device delegates selection to
Flutter. Use a debug-mode app, not a release build.

```jsonc
{
  "name": "Flutter existing app", "type": "flutter", "request": "attach",
  "cwd": "${workspaceFolder}", "toolArgs": ["-d", "macos"],
  "vmServiceUri": "http://127.0.0.1:PORT/REPLACE_TOKEN/"
}
```

Omit `vmServiceUri` for device discovery. For launch use `request: "launch"`,
`program: "${workspaceFolder}/lib/main.dart"` and `toolArgs` for device/flavor,
for example `["-d", "macos", "--flavor", "dev"]` when the project defines that
flavor. Save edits, then use `\dr` for hot reload and `\dR` for Flutter hot
restart. `dD` disconnects the editor; the terminal that started `flutter run`
continues to own its process.

### Electron

Install Electron in the project and build main/renderer code if required.
**electron: main + renderer** in `dc` launches `electron .` and then attaches a
renderer session. To attach to an externally started app, enable both endpoints:

```sh
./node_modules/.bin/electron --inspect=127.0.0.1:9230 --remote-debugging-port=9222 .
```

Choose **electron: attach main**, host `127.0.0.1`, port `9230`. Once a window
exists, use `dA` again and choose **electron: attach renderer (port 9222)**.
Both sessions remain available under `ds`. If a main-process breakpoint blocks
renderer initialization or evaluation, resume main with `dc` first. This command
allows startup to run before attachment; use the combined launch configuration
for startup breakpoints. For custom endpoints, create separate project entries:

```jsonc
{
  "name": "Electron main", "type": "pwa-node", "request": "attach",
  "address": "127.0.0.1", "port": 9230, "cwd": "${workspaceFolder}"
}
```

```jsonc
{
  "name": "Electron renderer", "type": "pwa-chrome", "request": "attach",
  "port": 9222, "webRoot": "${workspaceFolder}"
}
```

`dD` acts on the selected session; disconnect both if finished with the whole
app. The main endpoint is Node Inspector and the renderer endpoint is Chromium
CDP, so their ports cannot be interchanged. See
[Electron main-process debugging](https://www.electronjs.org/docs/latest/tutorial/debugging-main-process).

React Native is still a separate [feasibility spike](../spikes/react-native-dap/README.md),
not a supported Hermes DAP workflow. For connection failures, unbound breakpoints,
SDK paths and platform permissions, see [DIAGNOSTICS.md](DIAGNOSTICS.md).
