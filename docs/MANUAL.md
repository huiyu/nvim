# Manual

A guide to actually using this configuration. If you are new to Vim, start at
[The idea](#the-idea) and read straight through. If you already know Vim and
just want the keys, jump to [The four prefixes](#the-four-prefixes).

The [README](../README.md) covers installing and what plugins are included.
This document covers *using* it.

---

## Contents

- [The idea](#the-idea)
- [The grammar of the keyboard](#the-grammar-of-the-keyboard)
- [The four prefixes](#the-four-prefixes)
- [Getting around: `;`](#getting-around-)
- [Current file and view actions](#current-file-and-view-actions)
- [Filetype and view actions](#filetype-and-view-actions)
- [Windows: `s`](#windows-s)
- [Everything else: `<leader>`](#everything-else-leader)
- [Workflows](#workflows)
- [Reviewing a round of agent changes](#reviewing-a-round-of-agent-changes)
- [When you forget a key](#when-you-forget-a-key)
- [Debugging](#debugging)

---

## The idea

Most editors put commands in menus, and you find them by reading. Vim puts them
on keys, and you find them by *knowing what you want to do*.

This configuration takes that literally. Every key you press starts by
answering one question:

| You want to… | Press | Because it means |
|---|---|---|
| be somewhere else | `;` | "which file / symbol / position?" |
| act on this file or view | `,` | "what can I do here?" |
| rearrange the screen | `s` | "what about this window?" |
| anything else | `<Space>` | git, tests, debugging, AI… |

Nothing is filed by which plugin provides it. `;f` finds a file whether that
comes from a picker, oil, or something else — you press it because you want
a file, not because you remember a plugin name.

Two consequences worth knowing up front:

- **The things you do constantly are two keys.** Find a file, format, jump to a
  definition. Rare things are allowed to be longer.
- **Each prefix has a stable purpose.** `,` acts on the current file or view;
  `;` searches for a destination. General actions keep their meaning across
  filetypes. Buffer-local additions may share a key: `,v` selects a Python
  environment or previews a LaTeX PDF, under the corresponding menu heading.

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

You do not have to be inside the object first: with the cursor before a pair,
`ci(` changes inside the **next** parentheses. An `l` (last) in between looks
backwards instead: `cil(` changes inside the previous ones. Visual `an` and
`in` are Neovim's builtin syntax-node selection: each `an` widens the selection
to the enclosing node, `in` narrows it back.

**which-key:** press `di` (or `da`, `vi`) and wait half a second — the popup
lists every object.

### 4. Doubled = this line; uppercase = wider or stronger

A verb typed twice acts on the current line: `dd` `yy` `cc` `>>` `gcc`.

An uppercase letter is the **same act** as its lowercase key, going the same
way but further: over a wider scope, or a stronger version of it. Vim's own
keys started it:

| Lowercase | Uppercase |
|---|---|
| `d` `c` to somewhere | `D` `C` to end of line (= `d$` `c$`) |
| `i` `a` insert before / after the cursor | `I` `A` insert at start / end of line |
| `w` `b` `e` by word | `W` `B` `E` by WORD (whitespace-delimited, bigger) |

and this configuration's own pairs read the same way, lowercase narrow or
plain, uppercase wide or strong:

| Lowercase | Uppercase |
|---|---|
| `;s` symbol in this file | `;S` symbol in the workspace |
| `<Space>gl` blame the line · `<Space>gr` discard the hunk | `<Space>gL` blame the file · `<Space>gR` discard the file's changes |
| `<Space>gc` / `<Space>gh` this file's commits / history | `<Space>gC` / `<Space>gH` the repository's |
| `<Space>uf` autoformat for this file | `<Space>uF` autoformat for every file |
| `<Space>tm` / `<Space>tf` run the nearest test / the file's tests | `<Space>tM` / `<Space>tF` the same run under the debugger |
| `<Space>bd` delete the buffer | `<Space>bD` delete the buffer and its window |
| `<Space>qq` quit all | `<Space>qQ` force quit all |

A different object, or a scope that does not widen the lowercase key's, gets
a letter of its own instead: `<Space>xx` already lists every diagnostic, so
this file's are `<Space>xb` (**b**uffer), not `xX`. The exception is "from
here": `;F` and `;D` find a file and search text starting at the current
file's directory, where `;f` and `;/` start at the working directory. Vim's
direction pairs (`o`/`O`, `n`/`N`, `f`/`F`, `t`/`T`, `p`/`P`) are its own
use of case, kept as Vim has them.

In the `[` / `]` drawer ([rule 6](#6-single-letter-namespaces)) uppercase
goes to the end of the same list: the first / last entry for a list (`[Q`
/ `]Q` quickfix, `[D` / `]D` diagnostic, `[B` / `]B` buffer), and the end of
the object for a text object (`]m` next function start, `]M` its end).

The tabline, buffer cycling (`<S-h>`/`<S-l>`, `[b`/`]b`, and `[B`/`]B` to the
first / last), and buffer pickers skip terminal buffers. Use `<Space>af` to
focus the AI panel and `<C-/>` for shell terminals, so file navigation keeps
the editor window in place.
Clicking a file tab focuses the editor area in the current tabpage, leaving
chat and terminal panels visible. If only panels remain, it creates an editor
split for the file. The buffer keys do the same from a chat or another panel:
`]B`, `]b` or `;B` there goes to the editor area and acts on its buffer list,
and a cancelled `;B` stays where it was. So do Oil (`-`, `;o`), Harpoon (`;1`–`;9`,
`;h`), `gx` on a file path and the file and search pickers: what this config
opens from a panel goes to the editor area, never into the panel's own
window. The GitHub pickers do the same when the tab has an editor window; they
do not split one off, since most of their actions open nothing.

A few single keys are just abbreviations: `D` = `d$`, `C` = `c$`, and `x` =
`dl` with one difference: `x` deletes into the black hole register, so it
never replaces the system clipboard or adds an entry to the yank history
(`[y` / `]y`). The classic `xp` swap of two characters is therefore `dlp`;
`"ax` still deletes into register `a`.
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
| `[` `]` | previous / next X | `]d` diagnostic · `]e` error · `]h` git hunk · `]q` quickfix · `]r` reference · `]m` function · `]c` class · `]x` conflict · `]y` yank history. Uppercase = first / last: `[D` `]Q` `[B` `]B` |
| `g` | go somewhere / about the thing under the cursor | `gd` definition · `gr` references · `gb` implementation · `gy` type · `gC` callers · `gs` JS source (JS/TS) · `K` docs · `gx` open URL / file · `gS` split / join · `gv` reselect |
| `z` | folds and spelling | `zR` open all · `zM` close all · `za` toggle · `z=` suggestions · `zg` add to dictionary |
| `Ctrl` | act now, no questions, the same in every mode | `<C-h/j/k/l>` windows · `<C-/>` terminal · `<C-o>` back the way you came · `<C-a>` `<C-x>` increment / decrement · `<C-r>` redo |

List views and panels (a picker, oil, the outline, the panels on the right and
at the bottom) share a few keys that no popup lists. Where a view has the act,
it is on this key:

| Key | In a list view or panel |
|---|---|
| `q` | close it |
| `<C-c>` | stop a running request (a chat's reply, `<Space>ae`'s edit) |
| `<C-s>` / `<C-v>` / `<C-t>` | open the entry below / beside / in a tab |
| `<M-p>` · `<M-.>` | toggle the preview · hidden files (`g.` in oil) |
| `dd` · `<C-x>` | delete an item (open buffers, saved chats) · the same while typing in the picker |
| `R` | refresh (`gR` in oil, whose listing is text you edit) |
| `g?` | list the view's own keys (`?` too where it was already) |

**which-key:** press `[`, `]`, `g`, or `z` and wait half a second — the popup
lists the drawer, grouped under headings (`── diagnostics`, `── git`, …) with a
colour per group, so a long list reads as a few blocks rather than an alphabet.
The grouping is declared in `lua/config/whichkey_spec.lua`. In sectioned popups,
anything not explicitly assigned to a group sorts last under `── others`,
including new plugin keys and builtins. An empty `others` section is hidden;
popups without declared sections, such as `z`, keep the default layout.

Some buffers give these keys a meaning of their own, and the popup names that
one there. `]]` / `[[` (and `][` / `[]`) are the buffer's section motion
everywhere: Vim's own, or the filetype plugin's in Python, Go, Rust, Vim
script, TeX, Markdown, help and checkhealth buffers — top-level class or def in
Python, type or func in Go, function in Vim script. The next / previous
reference is `]r` / `[r`, except in TeX buffers, where `]r` / `[r` are
VimTeX's frame motions in every mode. Python's `]m` / `]M` are its class/def
motions, and VimTeX's are environments; VimTeX also adds `]n` / `]N` math
zones, `]R` frame ends and `]/` / `]*` comments (start / end). In a diff window
`]c` / `[c` are the next / previous hunk (the popup reads *Next class start
(diff: next hunk)*); in a CodeDiff view's panes `]c` / `[c` and `]h` / `[h`
both step through the hunks the view shows, through CodeDiff's own *Next hunk*. `gO` is *[LSP] Document symbols (Nvim
default)* in code, and *Show outline* — a list of the headings, no server
needed — in markdown, help, checkhealth and man buffers, under its own
`outline` heading.

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
`report.md)` on the next row. Quoted file paths can wrap too. A link longer
than the panel, which the terminal itself wrapped so its rest starts in column
0 of the next row, opens whole as well, enclosed or bare. The cursor can be on
any part. Leave terminal input with `Ctrl-\` or `jk` first.

Yanking from a terminal buffer copies text the terminal wrapped as the one line
the program printed, so `yi(` or `V` plus `y` on such a link puts the whole URL
on the clipboard, without the newline at the panel's edge. A motion that stays
on one row, such as `yiW` or `y$`, still stops at the row's end.

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

Every remaining key hangs under one of four prefixes, each answering one
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

## The four prefixes

```
;  go somewhere            ,  current file / view actions
s  windows                 <Space>  everything else
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
| `;f` | Find file by name under cwd |
| `;i` | Find files respecting `.gitignore`, including hidden files |
| `;F` | Find file next to the current one |
| `;r` | Recently opened, under cwd |
| `;b` | Open buffers |
| `;B` | Pick a buffer by its tab letter |
| `;g` | Files tracked by git |
| `;p` | Switch project |
| `;a` | **Last used buffer (alternate)** — return to the previous buffer in this window. |
| `;;` | Reopen the last search, with its results intact |

When started with a file (`vi /work/project/src/main.lua`), cwd becomes its
nearest Git root (`/work/project`), or the file's directory outside Git.
Worktrees and submodules are supported; symlinks use the target's repository.
For a new file whose parent does not exist, lookup starts at the nearest existing
ancestor. Multiple arguments use the first file. A directory argument uses that
exact directory, and no arguments or stdin keep the shell's cwd. This happens
once at startup; switching files does not move cwd. An explicit startup command
or restored session that changes cwd takes precedence. Use `:pwd` to check it
and `:cd /path/to/project` to change it; `;f` and `;/` search from cwd.

Nvim calls that previous buffer the **alternate buffer**. After opening A,
then B in the same window, `;a` goes back to A; another `;a` returns to B.
It uses the builtin `Ctrl-^` and is useful when alternating between an
implementation and its test.

`;<Space>` is the one to build a habit around. It learns which files you touch
and floats them to the top.

### Text and symbols

| Key | Does |
|---|---|
| `;/` | Search text under cwd |
| `;?` | Search text respecting `.gitignore`, including hidden files |
| `;w` | Search the word under the cursor |
| `;l` | Search lines in this file |
| `;D` | Search from here: this file's directory |
| `;s` | Symbols (functions, classes) in this file |
| `;S` | Symbols across the workspace |

`;f` and `;/` include gitignored files but skip common build/dependency
directories. `;i` and `;?` use `.gitignore` without those extra exclusions, so
tracked source inside a directory such as `build/` remains searchable.

Inside a picker, `<C-s>` / `<C-v>` / `<C-t>` open the entry below / beside /
in a tab, `<M-p>` toggles the preview and `<M-.>` hidden files (it was
`<M-h>`, which tmux takes for pane navigation); in Normal mode `g?` or `?`
lists the picker's keys. In `;p`, Insert-mode `<C-w>` deletes a word of the
query and Normal-mode `<C-w>` makes the project the tab's directory (`:tcd`).

### Browsing

There is no tree sidebar. Directories are browsed and edited through oil,
and files are reached through the pickers above.

| Key | Does |
|---|---|
| `;o` | **oil** — edit the directory as text (see below) |
| `-` | oil, on the current file's directory |

`;F` and `;D` use the file's directory or the displayed Oil directory.
From terminals and other panels, they use the current window/tab working directory.

From a terminal (including Codex), leave terminal input with `Ctrl-\`
or `jk`, then press `-` or `;o`. Oil opens with focus in the current tab's editor
area, creating an empty editor split if needed. `q` closes Oil and returns to
the editor; the terminal stays open.

From an unmodified Oil listing, `;f` opens the selected file in the same window;
cancelling keeps the listing and layout. Pending directory edits stay visible,
so the file picker uses another editor window or creates one when needed.

Inside Oil, `h/j/k/l` keep their normal cursor motions so filenames are easy to
edit. Use `-` to go to the parent directory, Enter to open the selected file or
directory, `g?` to see Oil's keymaps, and `q` to close. `<C-s>` opens the entry
below, `<C-v>` beside and `<C-t>` in a tab, the same chords as the pickers and
the outline; `<M-p>` toggles a preview, `gR` re-reads the listing and `g.`
shows hidden files. `<C-r>` is redo and `v<C-v>` starts blockwise Visual, as
in any buffer. Edit filenames or add/delete lines, then `:w` to review and
confirm the filesystem changes.

### Harpoon files

| Key | Does |
|---|---|
| `;H` | Add the current file to Harpoon |
| `;h` | Show the Harpoon menu |
| `;1` … `;9` | Jump straight to Harpoon file 1-9 |

Add the three or four files you are actively changing, then `;2` gets you there
without looking. Replace them when you move to another task. Harpoon's list is
not bufferline's pin (`<Space>bp`), which only keeps a tab at the left of the
tabline.

### Positions

`;j` jumplist · `;m` marks · `;c` git hunks · `;t` TODOs · `;T` TODO/FIX/FIXME

`;c` lists every changed hunk in the repository, staged and unstaged, with the
diff as its preview; Enter jumps there. `]h` / `[h` step through hunks from
the cursor instead. In this picker `<Tab>` stages or unstages the hunk, and
`<C-x>` **restores** it: after a Yes/No confirmation an unstaged hunk is
discarded from the working tree, and a staged one is taken out of the index.
It is the one destructive key there, on the pickers' "remove an item" chord;
`<C-r>` in the input inserts a register, as anywhere in Insert mode. The same
holds in `<leader>gs`.

---

## Current file and view actions

Press `,` for actions on the current file or view. General editing and language-specific
operations share this menu; headings show which context provides each action.

| Key | Does |
|---|---|
| `,a` | **Code action** — the fix-it menu (imports, quick fixes) |
| `,f` | Format |
| `,r` | Rename the symbol, everywhere, with live preview |
| `,c` | Run a codelens (gopls offers generate, test, tidy, govulncheck) |
| `,n` | Generate a docstring / annotation |
| `,x` | Run this file in a terminal split below |
| `,O` | Show / hide the outline of this file |

`,a`, `,r` and `,c` only exist where a language server is running — in a plain text
file they are simply not there.

In the outline, `j` / `k` move, `p` scrolls the source to the symbol, Enter
jumps to it and `<C-s>` / `<C-v>` open it below / beside; `<C-j>` / `<C-k>`
are window moves there, as everywhere.

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
| `,ef` / `,eF` | Extract into a function / into a function in another file |
| `,ex` | Extract an expression, and its other occurrences in the buffer, into a variable |
| `,i` | Inline the variable under the cursor into its references |
| `,R` | Refactoring menu: extract/inline variable, extract/inline function |
| `,w` | Find-and-replace the word under the cursor |
| `,F` | Full search-and-replace panel |

`,ef`/`,eF`/`,ex` act on a Visual selection. In Normal mode they are operators
and take a motion or text object, like `d`: `,ef_` extracts the current line,
`,efj` this line and the next, `,exi(` the inside of the parentheses. Each asks
for a name; `,eF` asks for the target file first. `,ex` replaces every
identical expression in the buffer, even in other functions, so review the
result. `,i` finds references through the language server, so it needs one
attached. `:Refactor extract_var total` runs an operation on the last Visual
selection, with the name given as an argument.


### Filetype and view actions

`<localleader>` is also comma. Filetype keys are buffer-local: the comma menu
shows Python's imports/environment in Python, LaTeX's build/preview sections in
TeX, and neither in plain text. These headings add no keystrokes. `[LSP]` marks
operations that need a language server, `[AI]` an AI key shown in a menu
other than `<Space>a`'s (today `,C`, review feedback in a Git view), and an
entry ending in "…" asks something first (a value or a choice) before it acts:
`,a`, `,r`, `,e…`, `,R`, Python's `,v`. Java test-debug keys appear after jdtls
and its debug adapter initialize. Dart reload/restart needs an active compatible
DAP session. Menu entries describe actions, not a guarantee that dependencies
or a running session are available.

| Context | Operation type | Keys |
|---|---|---|
| Go | Imports / language service | `,o` organize imports · `,G` rebuild gopls index |
| Python | Imports / environment | `,o` organize imports · `,v` select virtualenv |
| C/C++ | Related files | `,H` switch source/header |
| Dart / Flutter | Runtime control | `,dr` hot reload · `,dR` Flutter hot restart |
| Markdown | Preview | `,p` browser preview · `,m` in-editor rendering |
| CodeCompanion chat | Conversation / rendering | `,s` save · `,X` clear the messages · `,q` end the chat · `,z` fold code blocks · `,m` toggle Markdown rendering |
| Search-and-replace panel | Replace / sync / results / history | `,S…` panel actions; `g?` help |
| LaTeX | Compilation | `,b` continuous build toggle · `,s` stop · `,K` clean aux files · `,E` errors |
| LaTeX | Preview / tools | `,v` view PDF · `,t` toggle TOC · `,L…` VimTeX's full command set |
| CodeDiff | Panels / layout | `,P` focus the explorer (the file panel) · `,B` show / hide it · `,z` compact mode (fold unchanged lines) · `,I` diff layout: inline / side by side |
| CodeDiff | Conflicts | `,go` accept current (ours) · `,gt` incoming (theirs) · `,gb` keep base (drop both) · `,ga` both; uppercase final letters (`,gO`, `,gT`, `,gB`, `,gA`) apply to the whole file |
| CodeDiff | Review | `,C` feedback on the hunk / selection / file · `,S` / `,U` stage / unstage the hunk · `,X` discard the hunk back to baseline |
| Terminal | Sessions | `,1`–`,9` choose terminal 1–9 in Normal mode (`jk` first) |

CodeDiff is a view layered on a filetype: a Markdown diff keeps `,p`/`,m` and
adds its own sections. `,z` and `,I` work in every window of every view, its
file or history panel included; `,P` and `,B` exist only in a view with a file
panel (the status view and revision comparisons), not in a history. `,C` works
in every window of a view of a Git repository. `,S`, `,U` and `,X` stage,
unstage and discard a hunk — the status view's file panel `S` / `U` / `X` for
one hunk — and exist only where the view can do them safely; the table under
[Git](#git) says which. In a CodeDiff pane `,S` is that stage key, not the
search-and-replace panel's `,S…`, which exists only in that panel. Closing the view gives every
key back and preserves language keys. Terminal digits never appear in ordinary
files or intercept shell input.

General editing keeps its keys: `,h`/`,l` dedent/indent, `,k` moves up, `,r` renames,
`,c` runs codelens, and `,e…` extracts. The uppercase filetype keys, `,L…` and `,S…`
keep those short keys free of new prefix waits. Press `,` and wait for the
current operation sections.

### Search-and-replace panel: `,S`

Open grug-far with `,F`, or `,w` to prefill the word under the cursor. Enter the
search and replacement text; `Tab` / `Shift-Tab` move between input fields.
Review the results before applying changes. In Normal mode, `,S` shows the
panel's actions by operation type; `g?` opens its full help. These keys exist
only in the search panel, preserving general comma editing keys in its editable
results.

| Keys | Operation |
|---|---|
| `,Sr` | Apply replacement, including multiline replacements |
| `,Ss` / `,Sl` / `,Sv` | Write edited result text back to all files / current line / current file |
| `,Sj` / `,Sk` | Apply current change, remove its result, and open next / previous change |
| `,Sn` / `,Sp` | Sync current change and move to next / previous match |
| `,So` / `,Si` | Open / preview result location |
| `,Sq` | Send results to quickfix |
| `,St` / `,Sa` | Open search history / add current search to history |
| `,Sf` / `,Sb` | Refresh search / abort the active operation |
| `,Se` / `,Sx` | Switch search engine / replacement interpreter |
| `,Sw` | Toggle the search command display |
| `,Sc` | Close the panel |

### VimTeX commands under `,L`

In a `.tex` buffer, `,L` opens the full VimTeX command group. These 22 key
sequences supplement the direct LaTeX actions above. All work in Normal mode;
`,LL` also works in Visual mode. VimTeX exposes a subset in BibTeX buffers.

| Keys | Operation |
|---|---|
| `,Ll` | Toggle continuous compilation |
| `,LS` | Compile once |
| `,LL` | Compile selected lines; in Normal mode, follow with a motion/text object |
| `,Lk` / `,LK` | Stop compilation for this project / all open projects |
| `,Lo` | Open compiler output |
| `,Le` | Show errors and warnings |
| `,Lg` / `,LG` | Compilation status for this project / all open projects |
| `,Lc` / `,LC` | Clean auxiliary files / also remove output files |
| `,Lv` | View PDF and forward-search to the source position |
| `,Lt` / `,LT` | Open / toggle the table of contents |
| `,Li` / `,LI` | VimTeX information for this project / all open projects |
| `,Lq` | VimTeX message log |
| `,Lm` | List VimTeX's Insert-mode shortcuts |
| `,Lx` / `,LX` | Reload VimTeX scripts / current buffer state |
| `,Ls` | Toggle between the main project and the current subfile |
| `,La` | Context menu for the item under the cursor |

### Color previews

Color previews show hex, `rgb()`, `hsl()` and CSS `var(--name)` references.
CSS variable definitions are resolved within the buffer. Frontend files also
preview Tailwind classes, using the Tailwind LSP for project-specific colors
when it is attached. `:ColorizerToggle` toggles previews in the current buffer.

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

`ss` and `sv` are Vim's own `:split` and `:vsplit`. `splitbelow` and
`splitright` put every plain split below or to the right of the current
window, so `:new`, `:help` and the `,x` terminal open there too. Panels (the
agent, quickfix, the debug view) keep the edges edgy gives them.

In a panel, `q` closes it and the `<C-w>` resize keys work. edgy's own `Q` and
`<C-q>`, which would drop a panel for good, and its `]w` / `[w` window cycling
are off: `]w` / `[w` stay the warning jumps, `<C-q>` stays blockwise Visual,
and `Ctrl-h/j/k/l` move between panels.

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


## Everything else: `<leader>`

`<leader>` is the **Space** key. Press it and wait; each letter is a group.

| Key | Group | Contains |
|---|---|---|
| `<Space>g` | Git | status, blame, hunks, inline diff (`gD`), lazygit (`gg`), diff and history views (`gv`, `gm`, `gk`, `gh` / `gH`), saved baselines (`gK`) |
| `<Space>G` | GitHub | PRs, issues, reviews |
| `<Space>d` | Debug | breakpoints, step, inspect |
| `<Space>t` | Test | run / debug nearest (`tm` / `tM`) and file (`tf` / `tF`), summary, output, diagnostics |
| `<Space>x` | Diagnostics | error list, this file's (`xb`), quickfix, location list |
| `<Space>a` | AI | the chat on the right — Codex panels and CodeCompanion chats (`an` new, `al` switch, `ac` / `af`), prompts, transcript, review rounds (`av` / `aV`), API key (`ax`) |
| `<Space>b` | Buffer | delete, pin, move (`b<` / `b>`), delete others, delete the hidden ones (`bh`) |
| `<Space>m` | Manage | config, plugin source, help, man, keymaps, messages, Lazy, Mason, LSP status |
| `<Space>s` | Session | save / restore a working layout |
| `<Space>y` | Yank | copy file path, `path:line` (`yl`), git permalink (`yg`), yank history, registers |
| `<Space>u` | Toggle/UI | wrap, spell, diagnostics, inlay hints, colorscheme |
| `<Space><Tab>` | Tab | tab pages: new (`<Tab>n`), close, next / prev, first / last |
| `<Space>q` | Quit | quit all |

### Config and plugin files

| Key | Does |
|---|---|
| `<Space>mf` | Find files in this Neovim config |
| `<Space>mF` | Find source files in the lazy.nvim plugin installation directory |

These live under Manage because they maintain the editor itself.

### Messages and notifications

Typing `:` opens the command line in a popup near the top of the screen, with
its completion menu right under it; `/` and `?` search from the bottom row as
usual. Nothing waits for **Enter**: Vim's own messages and errors pop up at the
top right, the way notifications from plugins do, and fade on their own.
Confirmations of what just happened -- `:w`'s "written", an undo, `]q`'s
"(2 of 9)" -- show small at the bottom right for two seconds instead. A popup
cuts a long line off at its edge. A message of 20 lines or more opens in a
split at the bottom instead; `q` closes it from inside, and `<Space>un` closes
it together with the popups. A command you have started but not finished
(`2d`, `"a`) and the size of a Visual selection show in the status line.

| Key | Does |
|---|---|
| `g<` / `<Space>mnl` | The last command's output again, in a split |
| `:messages` / `<Space>mna` | Message history, in a split: `:echomsg`, `print()` and errors (a plain `:echo` is not kept) |
| `<Space>mnh` | Notification history: plugins' notifications, Vim's errors and warnings, and its latest ordinary message |
| `<Space>mnt` | Search notifications in a picker |
| `<Space>un` | Dismiss the notifications on screen |

A plugin's notification is only in the notification history. Vim's errors and
warnings are in both. Vim's ordinary messages share one popup that the next
one replaces, so `:messages` is the place to find an earlier one. Both
histories sit under the `<Space>mn` group, *Messages/notifications*.

---

## Workflows

### Reading unfamiliar code

```
;/  search for something you recognise
gd  jump to the definition
gd  again, and again — follow it down
Ctrl-o  walk back up the way you came
gC  who calls this?
]r  next place this symbol appears in the file
```

In TeX buffers `]r` is VimTeX's frame motion instead; `]]` is always the
section motion ([single-letter namespaces](#6-single-letter-namespaces)).

`K` shows documentation for whatever is under the cursor. `Ctrl-f` / `Ctrl-b`
scroll that popup while the cursor stays in the code; `KK` moves into it. `gr`
lists every reference. While you type a call, the parameter list appears above
it on its own.

In JavaScript and TypeScript, `gd` on something imported from a package stops
at the package's type declarations (`.d.ts`). `gs` goes on to the JavaScript
that actually runs, so you can read the implementation; Ctrl-o comes back as
after `gd`. A package that ships more than one build (CommonJS and ES modules)
can have several; they go to the quickfix list. `<Space>uh` turns on inlay hints — parameter names and inferred
types drawn inline — in every language whose server provides them; they start
off.

### The edit loop

```
;<Space>   open the file
,a         let the language server fix what it can
,f         format
<Space>tf  run the tests for this file
```

Language servers and linters mark problems in the gutter, with the icons the
statusline counts them with: `` error, `` warning, `` info, `` hint.
A line has room for one sign, so a line with several shows the most severe.
`]d` / `[d` jump to the next / previous one and show its message;
`<Space>xd` shows the current line's.

If you are bouncing between two files, `;a` toggles between them. If it is
three or four files, add them to Harpoon with `;H` and use `;1`-`;4`.

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
`<Space>gf` opens the current file's history. Both open a focused floating
terminal in input mode: `j`/`k` go straight to lazygit, even when typed quickly
together, and `q` quits it. Lazygit has no Vim-style Normal/Insert modes;
`Ctrl-]` deliberately leaves Neovim's terminal input mode, and `i` resumes it.
`;c` jumps to any changed hunk in the repository (see [Positions](#positions)).

The diff views are CodeDiff's. Each opens in a tabpage of its own, with a file
panel on the left and the two sides of the selected file beside it (a history,
`gh` / `gH`, lists its commits in a panel along the bottom instead):

| Key | Shows |
|---|---|
| `<Space>gv` | **Diff view** — the status view: Staged, Changes and Conflicts groups, untracked files included. The index against HEAD, the working tree against the index |
| `<Space>gm` | The working tree against `main` (else `master`, else `HEAD`) — the branch itself, not its merge base |
| `<Space>gM` | The working tree against a branch, tag, recent commit or baseline you pick |
| `<Space>gk` | **Compare two** ends: the working tree, the index, a baseline, a branch / tag / commit, or a revision you type |
| `<Space>gK` | Save the current code as a named baseline, for `gk` and `gM` to compare against later |
| `<Space>gh` / `<Space>gH` | This file's / the repository's history: the newest 100 non-merge commits (as `gc` / `gC` list its commits) |
| `<Space>gq` | Close the diff view in this tab, or `<Space>gd`'s split (below) |

A clean working tree makes `<Space>gv` say so instead of opening an empty view,
and pressed inside a view it points to `<Space>gq` — there it would only close
the view. Names are resolved to a commit first and only the label keeps them,
so a branch called `docs` or `history` compares like any other; a name that is
no commit is refused. History beyond 100 commits takes a range:
`:CodeDiff history origin/main..HEAD` (or set `history_limit`, under
[Settings](#settings-vimgai_review)).

`<Space>gk` asks twice: *Compare from*, then *Compare … with*. CodeDiff keeps
the live end — the working tree, else the index — on the right, so one picked
first swaps sides, and says so; the index against the working tree is the
status view, where its Changes group shows it. The same end twice is refused.
*Type a revision…* takes any revision, or a range of its own as the first end:
`main...feature` is `feature` against its merge base with `main`, and `main...`
the working tree against `main`'s merge base with `HEAD`. Two ends that hold
the same content say "no differences" and open nothing — unless the working
tree has untracked files too large to compare (below), which could differ
unseen: then the view opens and names them.

Inside a view, `]h` / `[h` (as everywhere) and `]c` / `[c` step through the
hunks the view shows, `]f` / `[f` through the
files, `do` / `dp` take or put a change as in vimdiff, `gf` opens the file in
the previous tab, and `g?` lists CodeDiff's keys. The `,` menu holds the rest
([Filetype and view actions](#filetype-and-view-actions)). The statusline names
what the view compares (`main → working tree`). Lines that one side lacks are
filled with `╱` hatching. Scrolling the mouse wheel over either diff pane keeps
the panes vertically aligned, including filler and folded regions, while
retaining keyboard focus; the file panel scrolls on its own. The view follows
the disk as files change, so an agent's writes show up while you look; the
cursor keeps its line number, not its place in the text.

The file panel, and the files under each commit in a history panel, show as a
directory tree. In the panel `i` toggles a flat list (for that view only),
`zo` / `zc` open or close the directory under the cursor and `zR` / `zM` all of
them. `,C` on a directory line asks for a file instead.

`;`, `s`, the buffer-switching keys `H` / `L`, `[b` / `]b`, `[B` / `]B` (first /
last buffer) and `<C-^>`, and
`-` (except in the status view's file panel, where it stages) are disabled in
every window of a view, with a notice. A `;` picker would open its file in the
working-tree pane and the view would lose track of it, and a buffer switched
into a pane or the panel does the same; most `s` keys close or reshape a pane,
and closing one tears the whole view down. `<C-w>` still moves between
windows, `gf` opens the file elsewhere, and `<Space>` keys work as everywhere.
`q` closes the view from its file or history panel only; in a diff pane it
records a macro as usual. In the status view's file panel `-` stages or
unstages a file, `S` / `U` stage / unstage everything and `X` discards a
file's changes, after asking; no other view has these four.

Which `,` review keys a view has depends on what it compares:

| View | `,S` | `,U` | `,X` |
|---|---|---|---|
| Status view, Changes group (index → working tree) | stage | — | — |
| Status view, Staged group (HEAD → index) | — | unstage, whole hunks | — |
| A baseline → the working tree (`<Space>av`, or a baseline picked in `gk` / `gM`) | stage | unstage | discard the hunk back to baseline |
| The same, for a file added or deleted since the baseline | — | — | how to undo it |
| Any other revision → the working tree (`gm`, `gM`, `gk`) | stage | unstage | — |
| Revision → revision, → the index, history, conflicts | — | — | — |

`,C` (feedback) is in all of them; [Reviewing a round of agent
changes](#reviewing-a-round-of-agent-changes) covers it.

`,S` and `,U` change the real index, through gitsigns, and stage exactly the
change on screen. Where the index (for `,U`, HEAD) differs from the view's
left side around the lines — an unstaged edit next to the agent's hunk, a line
already staged inside it, a branch's own commits inside a `gm` hunk — staging
"just this hunk" would take more than the view shows, so they refuse and point
to `<Space>gv`, which compares with the index itself. In Visual mode they take
the selected lines of the right pane.

`,X` discards one hunk of the working-tree file back to the baseline, so it
reads again the way the baseline had it, and writes that file. It skips the
formatter and every other before-write hook, so only the hunk changes; the
index is not touched, and `u` then `:w` undoes it. In Visual mode it takes
every hunk the selection touches, and refuses when one of them is only partly
selected. It works on hunks only: for
a file deleted since the baseline it prints the `git restore` command to
paste, and a new file you delete yourself.

All three refuse rather than act on something other than what is on screen:
unsaved edits in the right pane (`:w` or `:e!` first), a file that changed on
disk since it was drawn, a hunk that no longer computes the same, a symlink,
submodule, conflicted file, or a file with a `filter` attribute such as Git
LFS. The notice says why, and nothing changes.

A view against a revision lists what actually differs: a file the revision
tracks but your index does not shows as modified, a file moved with plain `mv`
as a rename, and non-ASCII names come out right. Ignored files never appear,
and a path still on disk is never listed as deleted; such paths, and untracked
files over 10 MiB, are named once per view in a "Not compared" notice. When a
buffer has unsaved edits and its file changed on disk underneath, the view
says so once — `:e!` takes the disk's version, `:w` keeps yours.

GitHub issue/PR buffers are reading views, with line numbers and the fold
column hidden. From an unmodified reading view, `;f` opens the selected file
in the same window; cancelling keeps the view and layout in place. An issue or
PR opened from `<Space>Gi`/`<Space>Gp` lands in the editor area the same way,
even when the picker was started from the chat or an agent panel, which keeps
its place on the right.

`<Space>gD` shows the current file's changes inside its own window: each line
removed since the index is drawn, read-only, where it used to be, so a changed
line has its old text right above it. `]h` / `[h` step through the changes;
`<Space>gD` again goes back to the plain file. `<Space>gd` shows the same comparison in a split instead, the index on
the left (for a file with conflicts, ours on the left and theirs on the right,
which `<Space>gD` opens too); the same key again, or `<Space>gq`, closes it.
Pressed in another window, `<Space>gd` moves the split there: Vim compares every
diff window of a tabpage with every other, so two files' splits side by side
would also compare the files; in a buffer Git does not track it says so and leaves
the split where it is. While the index side has unsaved edits it stays open:
`:w` there stages them, `:e!` drops them. The statusline
counts the buffer's changes against the index next to the branch, `+3 ~1 -2`
for added, changed and removed lines.

`<Space>yg` copies a permalink to the current line, or to the selected lines
in Visual mode, on the repository's remote (GitHub, GitLab, ...). It names the
last commit that changed the file, so the link keeps showing the same code
after the branch moves on, but the line numbers are that commit's: with
uncommitted changes above the cursor they drift, and the link only works once
the commit is pushed.

`<Space>bh` deletes every file buffer that no window shows, in any tabpage,
and leaves the windows alone; terminals and other special buffers stay.
`<Space>bo` keeps only the current buffer, replacing whatever the other splits
were showing.

### Terminals and AI

Use `<C-/>` for numbered shell terminals and `<Space>an` for a new AI chat.
`,1`–`,9` choose terminals in Normal mode; they never close one by repeating the
number. `<Space>al` switches AI chats, `<Space>ac` hides/restores the last one,
`<Space>af` focuses it, and `<Space>ai` opens its prompt editor.

The native backend in this release is Codex. CodeCompanion adds Codex ACP and
OpenAI HTTP chats. `<Space>an` shows transport and billing; a running native
entry reuses the session. Showing one target hides the others in this tab only,
keeping their buffers/processes. A target shown in another tab is gone to with
a notice. A terminal copy shown here remains the delivery target here. The
last normal window is never hidden; floats do not count as another window.

`as` captures Visual context before any picker and sends it without Enter.
A saved selection uses an absolute file/range reference, so another project's
active session reads the intended file; unsaved text is pasted exactly and
announced. `ab` adds the file, warning that native/ACP agents read disk.
A CodeCompanion HTTP chat receives buffer text. A directory listing is refused;
no Claude-only Oil action exists. From CodeDiff, chat keys use its origin tab.

`ai` uses Codex's `ctrl+g` and `$EDITOR` to edit the actual input draft in this
Nvim. `<C-d>` returns it; cancel preserves the original. `<C-v>` stages an image
for Codex's own attachment path after the editor closes. An editor request
from a different program has no agent owner and takes no agent seed or image.
`ar` resumes, `aR` continues, `am` chooses a model. On a running session these
focus it and type nothing, protecting drafts and approvals. `at`/`aT` read
native JSONL transcripts independently of terminal scrollback.

`lua/config/ai.lua` declares providers, HTTP profile, panel, native argv, local
plugin paths and terminal provider. `terminal.provider` may be `native`,
`snacks` or a custom embedded adapter. tmux frame composition is independent;
`CODEX_WRAP_TMUX=0` disables it. Its runner/watchdog/teardown preserve startup
errors, CJK and scrollback and clean owned descendants. No CLI config is written.

`<Space>ae` uses HTTP API credits; `<Space>ax` / `:AI key` switches that profile
for this process, without touching terminals or existing chats. Defaults use
OpenAI's `NVIM_OPENAI_API_KEY`; a CLI's `OPENAI_API_KEY` can change its billing
and produces a warning. ACP uses `chat-gpt` authentication. No key is silently
borrowed from a CLI variable. More detail: [AI keys](../README.md#ai-keys).

### Local native plugins

Set `plugin_dirs` in `config/ai.lua`, or override with `NVIM_AI_PLUGIN_DIR`.
Entries can be plugin directories or distribution roots with `codex/<plugin>`
packages. Resolution happens at native launch; nothing installs at startup or
for CodeCompanion. Codex refreshes local snapshots through `plugin add` using
a disposable `CODEX_HOME` sharing only the real plugin cache. Marketplace and
enabled overrides are invocation-local; global enablement/config stay intact.

### Three ways to ask an AI

| Workflow | Transport / billing | Use |
| --- | --- | --- |
| Native Codex | Native CLI / ChatGPT login | Full CLI TUI and prompt editor |
| Codex ACP chat | CodeCompanion + `codex-acp` / ChatGPT login | Chat UI with CLI tools |
| OpenAI API chat / inline | HTTP / API credits | Chat or `<Space>ae` inline edits |

The picker shows each distinction and availability. HTTP keys use `NVIM_*`.
CodeCompanion chat adapters are fixed at creation. Local transcript history and
resuming an agent's ACP session with `/resume` are separate things.

Ghost text is a fourth, independent service: a local llama-server, enabled only
with a UI and eligible file. `<C-l>` accepts the suggestion; ignoring it simply
continues typing. `config/completion.lua` owns model/service preferences;
`config/keymaps.lua` owns its accept key. Markdown/text/commit messages are
excluded by default; `:Minuet virtualtext toggle` changes the current buffer.

## Reviewing a round of agent changes

A round is an immutable worktree baseline attached to a conversation. It proves
that a change came **after the baseline**, not who made the change: user edits
and another agent's work in the same repository are included too. Review shows
changes since the round; it does not approve a future agent write.

### Where rounds come from

Native Codex's `UserPromptSubmit` hook takes a snapshot before the prompt runs.
CodeCompanion's `on_before_submit` callback does the same for ACP/HTTP chats.
`<Space>aV` takes a round manually; `<Space>gK` saves a separate, unowned baseline.
A steer with the same Codex turn id opens no extra round. Repeated submits are
deduplicated, unchanged trees reuse the previous round, and spawned threads with
`agent_id` belong to their parent. Each fresh changed turn opens a new round.

A native session's root is fixed at launch, a chat's at creation: the Git
toplevel of its initial cwd. An agent that later changes directory keeps that
root and is told once. The hook waits up to `hook_wait_ms` (2500 ms); a snapshot
that finishes later is marked **Late**, because the earliest writes may already
be included. If Nvim cannot serve the event before its deadline, no baseline is
taken after the fact. The prompt itself is never blocked by an integration error.

Hooks are injected per native process with `-c hooks=...` and a matching trust
record. User CLI configuration and other hooks are preserved. Codex reports the
current session only at a prompt; after a CLI resume/new/fork, Nvim cannot prove
the input box's owner until the next prompt. A delivery may therefore ask for
confirmation. A CLI started in a plain shell has no injected review hook.

### `<Space>av`: the review view

From a conversation buffer, prefer its newest round; otherwise prefer the chat
on this tab's right (or the CodeDiff origin tab), then this process's latest
round in the root, then the latest stored round. A file with no visible chat
never silently assigns the first provider as owner. One review tab per root is
kept; opening one root never rearranges another root's view.

The view uses CodeDiff against the immutable baseline SHA. Its title/header show
the source, round time, conversation, root and Late status. The baseline remains
the comparison even if retention later removes its ref. Global layout-sensitive
prefixes stay blocked within the view; its comma actions and file/LSP actions
remain scoped as documented in the Git workflow.

### `,C`: feedback

In a Git view, use `,C` to add a comment for the selected lines/hunk. Context and
text go into a review draft rather than directly to a chat. Open/edit the draft,
remove or revise entries and use `<C-d>` to deliver. Drafts are atomically stored
under `state/ai-review/<root hash>/`; unsent drafts survive closing a view or
restarting Nvim. Concurrent nonoverlapping edits merge; conflicting edits are
kept in a separate conflict file, with a notice, rather than overwritten.

A draft has a root/owner header. Losing its header is a refusal to deliver.
`<id>.last-sent.md` preserves the last acknowledged delivery; a pending draft is
cleared only after text actually arrived. A round with nonempty pending feedback
is exempt from retention.

### `<C-d>`: delivery

Native delivery stages the feedback for the exact Codex prompt editor. Its
consumption acknowledges delivery; cancel, timeout, replacement or failure keeps
the draft. The TUI's own editor handoff handles its actual input. HTTP/ACP delivery
adds text to the exact open CodeCompanion chat and acknowledges only success.
A busy chat, including a tool loop between requests, refuses without losing text.

### Who receives it

Checks happen in order:

1. View root, draft root and destination root must be the same realpath. There
   is no override or confirmation that bypasses a root mismatch.
2. The native terminal must run the owning session, or the chat must still be
   open in this Nvim. A native session not reported yet or typed into since its
   report asks first (`unknown_session = "refuse"` refuses instead).
3. A chat mid-turn refuses delivery. Its tools may still be running when no
   HTTP request is visible, so that interval is also busy.
4. An owner that is gone is refused. Unless `redirect = false`, choose a current
   same-root session/chat and confirm the owner change once. Cancel keeps the draft.

The destination is never guessed from provider order or a hidden chat. A
conversation id includes the native session id or a process nonce plus chat id,
so an identically numbered chat from another Nvim is not the same owner.
Historical Claude owners remain readable; without their backend they can only
be redirected through the same explicit same-root checks.

### Each agent's limits

| | Native Codex | ACP / HTTP chat |
| --- | --- | --- |
| Baseline | Before prompt, bounded wait | Before submit callback, bounded wait |
| Session known | At UserPromptSubmit | At chat creation |
| Confirmation | Before first prompt, after typed input, or always_confirm | No native-session question |
| After restart | Resume, then confirm or send a prompt | Old process's chat owner is gone |
| Before a write | Native CLI's configured policy | Chat's own tool approvals |

The shipped native argv remains `--no-alt-screen --yolo`. This Git review is a
post-change workflow, not an IDE proposal accept/reject mechanism. Claude IDE
protocol/openDiff and its approval keys belong to a later extension.

### Manual rounds, saved baselines and any two ends

`aV` makes a manual round. In a conversation buffer it belongs to that owner;
from a file it belongs to the visible same-root chat, else no conversation.
`gK` saves a named baseline without an owner; `gk` lists saved baselines and
`gM` compares two chosen ends. Session/title/time labels may read older native
records, including historical Claude JSONL. Renaming or hiding a session does
not change the immutable SHA used by an open comparison.

Snapshots use unique temporary indices and never modify HEAD, the real index,
branches, stash or their reflogs. Objects and `refs/nvim-review/<wtid>/...` are
lasting writes. Ignored files follow the current ignore rules; oversized
untracked files are excluded before hashing. Retention removes refs, leaving
objects to Git gc. See [diagnostics](DIAGNOSTICS.md#what-review-baselines-leave-in-a-repository)
for excluding these refs from all-branches graphs/mirrors.

### What each action changes

| Action | Meaning |
| --- | --- |
| `aV` | Snapshot now and associate a round owner when known |
| `av` | Compare working tree with a round baseline |
| `gK` | Save a separate baseline |
| `,C` | Capture feedback into a durable draft |
| `<C-d>` in draft | Deliver after destination checks; clear only on acknowledgement |
| `,X` in a supported baseline file | Discard a hunk to that baseline, with the view's safeguards |

### Settings: `vim.g.ai_review`

Editable defaults are in `config/review.lua`; shared Git values are in
`config/git.lua`. Runtime options are copied at setup. Assign a whole
`vim.g.ai_review` table for live overrides; changing a nested copy does nothing.
Unknown/wrong leaves warn once and retain valid siblings. `:checkhealth config`
shows effective settings.

| Key | Default | Meaning |
| --- | --- | --- |
| `retention.rounds` | 20 | Newest rounds retained per worktree; pending drafts exempt |
| `sources.codex` | true | Inject/receive native submit hooks |
| `sources.codecompanion_acp` / `codecompanion_http` | true | Capture chat submit rounds |
| `hook_wait_ms` | 2500 | Bounded baseline wait; 0 lets submit proceed immediately |
| `unknown_session` | `"confirm"` | `"refuse"` denies an unproven native owner |
| `always_confirm` | `{}` | `{ "codex" }` confirms every native delivery |
| `redirect` | true | Offer explicit same-root redirection when the owner is gone |
| `seed_ttl_ms` | 10000 | Prompt editor consumption deadline |

Git defaults: `max_file_size = 10485760`, `retention.saved = 10`,
`history_limit = 100` (or false). Legacy live overrides for these fields under
`vim.g.ai_review` remain supported. `sources.claude` and `claude_cwd` are removed.
Native hook changes apply at the next launch; disabling a source drops events
immediately. Chats created while a source is disabled are not retroactively
hooked. Setup edits require restart; HTTP key switches are process-local.

## When you forget a key

1. **Press the prefix and wait.** `;`, `,`, `s` or `<Space>` all show a
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

The debug view opens in a tabpage of its own, the way a diff does, so a
session never rearranges the windows you were editing in and ending one hands
that layout back untouched. Inside it, scopes, breakpoints, stacks and watches
dock on the left while the REPL and the program console join the terminal and
quickfix along the bottom. edgy places them, the same as every other panel
here, so `so` and the window keys treat them like the agent panel rather than
as a layout of their own. An adapter that drives several targets opens the view
once, not once per target.

Stepping stays in the tabpage you are in. Go back to the editor tab mid-session
and the debug keys keep working there, jumping in that tab while the panels
update out of sight; `<Space>du` brings the view back. The debug view is never
the thing that moves you between tabs.

| Key | Action |
|---|---|
| `<Space>dB` | Set a conditional breakpoint (asks for the condition) |
| `<Space>dA` / `:DapAttach` | Choose an attach configuration for an existing process |
| `<Space>dL` | Logpoint: print a message such as `value={value}` without stopping |
| `<Space>de` | Choose exception breakpoints from the active adapter's filters |
| `<Space>dR` | Restart the session, from the root of its tree |
| `<Space>dD` | Disconnect the session and its children, requesting that the target keep running |
| `<Space>dt` | Terminate the target, and the whole session tree it belongs to |
| `<Space>du` | Close or reopen the debug view |
| `<Space>dw` | Evaluate `<cexpr>` or the live Visual selection |
| `<Space>dW` | Add an editable expression to Watches |
| `<Space>ds` | List sessions; select a main/renderer/child session |
| `<Space>dq` / `<Space>dx` | List / clear all breakpoints |

The gutter and the panel controls take the mouse. Clicking a line number
toggles a breakpoint, and ctrl-clicking one prompts for a condition; the eight
icons above the console are buttons for continue/pause, the three steps, step
back, run last, terminate and disconnect. `mouse` is `nv`, so leave Insert or
Terminal mode first.

Gutter shapes read without colour: `●` breakpoint, `◉` conditional, `◆`
logpoint, `○` one the adapter has not verified, `󰁕` the line execution is
stopped on, which is also highlighted.

Character, line and block selections work for evaluation and watches without
yanking. Watch expressions persist in the current editor process; use `d` in
the Watches panel to remove one. Cancelling the watch or logpoint prompt changes
nothing. Exception choices are None, All, or an individual filter; their names
and support depend on the adapter. Set them after starting a session.
Disconnect sends `terminateDebuggee=false`; adapter support still determines
whether a particular target can continue independently. `dl` instead reruns the
last configuration.

Restart, disconnect and terminate all resolve the root of the current session
tree first. An adapter that owns several targets (js-debug driving a browser,
Electron) answers `startDebugging` with child sessions, and the current session
follows whichever child last stopped — acting on that child alone restarts or
releases one target and leaves the rest attached. A second session started on
its own is a separate tree and is left running; select it with `ds`.

### Current file and tests

| Key | Scope |
|---|---|
| `<Space>df` | Debug the current source file / its executable target |
| `<Space>tM` | Debug the test at the cursor (Go/Python/Java also find the nearest preceding test) |
| `<Space>tF` | Debug tests in the current file |
| `<Space>tm` / `<Space>tf` | Run nearest test / test file without debugging (neotest: Go/Python) |

Uppercase is the same run under the debugger: `tm` / `tM` the nearest test,
`tf` / `tF` the file. `<Space>ts` toggles neotest's summary panel (`g?`, or `?`,
there lists its keys), `<Space>to` shows the test output and `<Space>tx`
toggles the failures neotest shows as diagnostics.

Set a breakpoint with `<Space>db`, put the cursor inside a test, then press
`<Space>tM`. These direct entries save the current buffer first; an unsaved
unnamed buffer or failed write aborts. They use the same keys in every supported
language, with target logic in `lua/plugin/lang/*.lua`.

| Language | `df` | `tM` / `tF` |
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
on sibling files, choose **Debug Package** in `dc`. `tM`/`tF` use neotest-golang
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
`,v` when needed. `df` launches the script; `tM`/`tF` use neotest-python.
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

Install JDK 25+ (jdtls runs on it; projects may target older releases) and
Mason's `jdtls`, `java-debug-adapter`, and `java-test`.
Open the project and wait for jdtls to finish importing. `dc` discovers main
classes; `df` selects the main class corresponding to the current file.
An empty static main-class list before discovery is normal. Each project uses
its own jdtls workspace. `tM`/`tF` debug the nearest test / first discovered test
class.

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
`tM`/`tF` filter standard libtest tests as described above.

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
executable. The direct `df`/`tM`/`tF` entries are not registered for C/C++:
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
configuration. `tM`/`tF` use the nearest installed Vitest; nearest test needs v3+.

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
profile and installs the extension via CDP. See
[extension setup and diagnosis](DIAGNOSTICS.md).

### Dart CLI

Install the Dart SDK, or use the Dart SDK bundled with Flutter. Adapters prefer
the nearest `.fvm/flutter_sdk/bin`, then PATH. Run `dart pub get` in the package.
The SDK supplies `dart debug_adapter`; no Mason adapter is needed. `df` launches
the current entrypoint; `tM`/`tF` run its tests through the SDK test adapter.

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
`cwd` and `args`. Use `,dr` for supported hot reload; `dR` restarts a launched
CLI session. The SDK's [debugging tools](https://dart.dev/tools/dart-devtools)
explain VM service startup.

### Flutter

Install Flutter externally or use FVM. Run `flutter pub get`, then start a
simulator/device (`flutter devices`). `dc` provides **flutter: launch app**
(default `lib/main.dart`), **flutter: attach to running app**, and current-file
tests. `df` uses the current file as the entrypoint; `tM`/`tF` use the Flutter
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
flavor. Save edits, then use `,dr` for hot reload and `,dR` for Flutter hot
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

`dD` acts on the selected session and any children it spawned. Main and
renderer are separate trees here, so disconnect both if finished with the whole
app. The main endpoint is Node Inspector and the renderer endpoint is Chromium
CDP, so their ports cannot be interchanged. See
[Electron main-process debugging](https://www.electronjs.org/docs/latest/tutorial/debugging-main-process).

React Native/Hermes DAP is not supported by this configuration; use React Native
DevTools. For connection failures, unbound breakpoints,
SDK paths and platform permissions, see [DIAGNOSTICS.md](DIAGNOSTICS.md).
