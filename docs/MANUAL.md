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

The tabline, buffer cycling (`<S-h>`/`<S-l>` and `[b`/`]b`), and buffer pickers
skip terminal buffers. Use `<Space>af` to focus the AI panel and `<C-/>` for
shell terminals, so file navigation keeps the editor window in place.
Clicking a file tab focuses the editor area in the current tabpage, leaving
chat and terminal panels visible. If only panels remain, it creates an editor
split for the file.

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
| `[` `]` | previous / next X | `]d` diagnostic · `]e` error · `]h` git hunk · `]q` quickfix · `]m` function · `]c` class · `]x` conflict · `]y` yank history. Uppercase = first / last: `[D` `]Q` |
| `g` | go somewhere / about the thing under the cursor | `gd` definition · `gr` references · `gb` implementation · `gy` type · `gC` callers · `gs` JS source (JS/TS) · `K` docs · `gx` open URL / file · `gS` split / join · `gv` reselect |
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
| `;f` | Find file by name in the project |
| `;i` | Find files respecting `.gitignore`, including hidden files |
| `;F` | Find file next to the current one |
| `;r` | Recently opened |
| `;b` | Open buffers |
| `;g` | Files tracked by git |
| `;p` | Switch project |
| `;a` | **Last used buffer (toggle)** — return to the previous buffer in this window. |
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

From an unmodified Oil listing, `;f` opens the selected file in the same window;
cancelling keeps the listing and layout. Pending directory edits stay visible,
so the file picker uses another editor window or creates one when needed.

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

`;j` jumplist · `;m` marks · `;c` git hunks · `;t` TODOs · `;T` TODO/FIX/FIXME

`;c` lists every changed hunk in the repository, staged and unstaged, with the
diff as its preview; Enter jumps there. `]h` / `[h` step through hunks from
the cursor instead. In this picker `<Tab>` stages or unstages the hunk, and
`<C-r>` **restores** it: after a Yes/No confirmation an unstaged hunk is
discarded from the working tree, and a staged one is taken out of the index.
It is the one destructive key there.

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
operations that need a language server, and `[AI]` an AI key shown in a menu
other than `<Space>a`'s (today `,C`, review feedback in a Git view); Java
test-debug keys appear after jdtls and its debug adapter initialize. Dart reload/restart needs an active compatible
DAP session. Menu entries describe actions, not a guarantee that dependencies
or a running session are available.

| Context | Operation type | Keys |
|---|---|---|
| Go | Imports / language service | `,o` organize imports · `,G` rebuild gopls index |
| Python | Imports / environment | `,o` organize imports · `,v` select virtualenv |
| C/C++ | Related files | `,H` switch source/header |
| Java | Test debugging | `,dt` debug nearest method · `,dT` debug class |
| Dart / Flutter | Runtime control | `,dr` hot reload · `,dR` Flutter hot restart |
| Markdown | Preview | `,p` browser preview · `,m` in-editor rendering |
| CodeCompanion | Chat rendering | `,m` toggle Markdown rendering |
| Search-and-replace panel | Replace / sync / results / history | `,S…` panel actions; `g?` help |
| LaTeX | Compilation | `,b` continuous build toggle · `,s` stop · `,K` clean aux files · `,E` errors |
| LaTeX | Preview / tools | `,v` view PDF · `,t` toggle TOC · `,L…` VimTeX's full command set |
| CodeDiff | Panels / layout | `,P` focus the file panel · `,B` show / hide it · `,z` fold unchanged lines · `,I` inline / side by side |
| CodeDiff | Conflicts | `,go` ours · `,gt` theirs · `,gb` base (drop both) · `,ga` both; uppercase final letters (`,gO`, `,gT`, `,gB`, `,gA`) apply to the whole file |
| CodeDiff | Review | `,C` feedback on the hunk / selection / file · `,u` / `,U` stage / unstage the hunk · `,X` put the hunk back to the baseline |
| Terminal | Sessions | `,1`–`,9` choose terminal 1–9 in Normal mode (`jk` first) |

CodeDiff is a view layered on a filetype: a Markdown diff keeps `,p`/`,m` and
adds its own sections. `,z` and `,I` work in every window of every view, its
file or history panel included; `,P` and `,B` exist only in a view with a file
panel (the status view and revision comparisons), not in a history. `,C` works
in every window of a view of a Git repository. `,u`, `,U` and `,X` exist only where the view can do them
safely — the table under [Git](#git) says which. Closing the view gives every
key back and preserves language keys. Terminal digits never appear in ordinary
files or intercept shell input.

General editing keeps its keys: `,h`/`,l` dedent/indent, `,k` moves up, `,r` renames,
`,c` runs codelens, and `,e…` extracts. The uppercase filetype keys, `,L…` and `,S…`
keep those short keys free of new prefix waits. Former backslash bindings are
removed; press `,` and wait for the current operation sections.

### Search-and-replace panel: `,S`

Open grug-far with `,F`, or `,w` to prefill the word under the cursor. Enter the
search and replacement text; `Tab` / `Shift-Tab` move between input fields.
Review the results before applying changes. In Normal mode, `,S` shows the
panel's actions by operation type; `g?` opens its full help. These keys exist
only in the search panel, preserving general comma editing keys in its editable
results. Its former backslash shortcuts now use `,S` plus the same final letter.

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
| `<Space>g` | Git | status, blame, hunks, inline diff (`gD`), lazygit (`gg`), diff and history views (`gv`, `gm`, `gk`, `gH`), saved baselines (`gK`) |
| `<Space>G` | GitHub | PRs, issues, reviews |
| `<Space>d` | Debug | breakpoints, step, inspect |
| `<Space>t` | Test | run file / nearest / debug, output panel |
| `<Space>x` | Diagnostics | error list, quickfix, location list |
| `<Space>a` | AI | the chat on the right — Claude / Codex panels and CodeCompanion chats (`an` new, `al` switch, `ac` / `af`), prompts, transcript, review rounds (`av` / `aV`), API key (`ax`) |
| `<Space>b` | Buffer | delete, pin, close others, close the hidden ones (`bh`) |
| `<Space>m` | Manage | config, plugin source, help, man, keymaps, messages, Lazy, Mason, LSP status |
| `<Space>s` | Session | save / restore a working layout |
| `<Space>y` | Yank | copy file path, `path:line` (`yl`), git permalink (`yg`), yank history, registers |
| `<Space>u` | Toggle/UI | wrap, spell, diagnostics, inlay hints, colorscheme |
| `<Space><Tab>` | Tab | tab pages |
| `<Space>q` | Quit | quit all |

### Config and plugin files

| Key | Does |
|---|---|
| `<Space>mf` | Find files in this Neovim config |
| `<Space>mF` | Find source files in the lazy.nvim plugin installation directory |

These live under Manage because they maintain the editor itself.

### Messages and notifications

Messages appear in the command-line row, and nothing waits for **Enter**.
Output taller than that row opens above it until the next key, then shrinks
back to its first line, marked `[+N]` for the lines it hides; a long error
shows only its first line from the start. Press **Enter** right after a command
to read its output in a pager instead; `q` closes the pager. Notifications from plugins pop up at the top right and fade on their own.

| Key | Does |
|---|---|
| `g<` / `<Space>mnl` | The last command's output again, in the pager |
| `:messages` / `<Space>mna` | Message history: `:echomsg`, `print()` and errors (a plain `:echo` is not kept) |
| `<Space>mnh` | Notification history |
| `<Space>mnt` | Search notifications in a picker |
| `<Space>mnd` / `<Space>un` | Dismiss the notifications on screen |

The two histories are separate. An error from Vim itself is in `:messages`; a
plugin's notification is only in the notification history.

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
`<Space>gf` opens the current file's history. Both open a focused floating
terminal in input mode: `j`/`k` go straight to lazygit, even when typed quickly
together, and `q` quits it. Lazygit has no Vim-style Normal/Insert modes;
`Ctrl-]` deliberately leaves Neovim's terminal input mode, and `i` resumes it.
`;c` jumps to any changed hunk in the repository (see [Positions](#positions)).

The diff views are CodeDiff's. Each opens in a tabpage of its own, with a file
panel on the left and the two sides of the selected file beside it (a history,
`gV` / `gH`, lists its commits in a panel along the bottom instead):

| Key | Shows |
|---|---|
| `<Space>gv` | **Diff view** — the status view: Staged, Changes and Conflicts groups, untracked files included. The index against HEAD, the working tree against the index |
| `<Space>gm` | The working tree against `main` (else `master`, else `HEAD`) — the branch itself, not its merge base |
| `<Space>gM` | The working tree against a branch, tag, recent commit or baseline you pick |
| `<Space>gk` | **Compare two** ends: the working tree, the index, a baseline, a branch / tag / commit, or a revision you type |
| `<Space>gK` | Save the current code as a named baseline, for `gk` and `gM` to compare against later |
| `<Space>gV` / `<Space>gH` | This file's / the repository's history: the newest 100 non-merge commits |
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

Inside a view, `]c` / `[c` step through the changes, `]f` / `[f` through the
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

`;` and `s` are disabled in every window of a view, with a notice. A `;`
picker would open its file in the working-tree pane and the view would lose
track of it; most `s` keys close or reshape a pane, and closing one tears the
whole view down. `<C-w>` still moves between windows, `gf` opens the file
elsewhere, and `<Space>` keys work as everywhere. `q` closes the view from its
file or history panel only; in a diff pane it records a macro as usual. In
the status view's file panel `-` stages or unstages a file, `S` / `U` stage /
unstage everything and `X` discards a file's changes; no other view has these
four.

Which `,` review keys a view has depends on what it compares:

| View | `,u` | `,U` | `,X` |
|---|---|---|---|
| Status view, Changes group (index → working tree) | stage | — | — |
| Status view, Staged group (HEAD → index) | — | unstage, whole hunks | — |
| A baseline → the working tree (`<Space>av`, or a baseline picked in `gk` / `gM`) | stage | unstage | put the hunk back |
| The same, for a file added or deleted since the baseline | — | — | how to undo it |
| Any other revision → the working tree (`gm`, `gM`, `gk`) | stage | unstage | — |
| Revision → revision, → the index, history, conflicts | — | — | — |

`,C` (feedback) is in all of them; [Reviewing a round of agent
changes](#reviewing-a-round-of-agent-changes) covers it.

`,u` and `,U` change the real index, through gitsigns, and stage exactly the
change on screen. Where the index (for `,U`, HEAD) differs from the view's
left side around the lines — an unstaged edit next to the agent's hunk, a line
already staged inside it, a branch's own commits inside a `gm` hunk — staging
"just this hunk" would take more than the view shows, so they refuse and point
to `<Space>gv`, which compares with the index itself. In Visual mode they take
the selected lines of the right pane.

`,X` puts one hunk of the working-tree file back the way the baseline had it,
and writes that file. It skips the formatter and every other before-write
hook, so only the hunk changes; the index is not touched, and `u` then `:w`
undoes it. In Visual mode it takes every hunk the selection touches, and
refuses when one of them is only partly selected. It works on hunks only: for
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
in the same window; cancelling keeps the view and layout in place.

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

```
Ctrl-/       toggle a terminal
3<Ctrl-/>    select terminal 3 from a file (Normal mode)
,1 … ,9      choose terminal 1-9 from a terminal buffer (jk first)
<Space>an    start an AI chat: Claude Code, Codex, or a CodeCompanion chat
<Space>al    switch to another open chat
<Space>ac    hide the chat on the right, or bring it back
<Space>ai    write a prompt in a real Neovim buffer
<Space>av    review what changed since your last prompt
Ctrl-l       (Insert) take the grey AI suggestion
```

`Ctrl-]` leaves terminal input without disturbing the program running in it —
useful because `Esc` belongs to the AI CLIs themselves.

The right side of a tabpage holds one AI window — the *chat on the right*:
Claude Code's or Codex's terminal, or a CodeCompanion chat. `<Space>an` starts
one on any backend you have (the list says how each is billed), `<Space>al`
switches to another open one, and the `<Space>a` keys that send something —
`as`, `ab`, `ai` — go to whichever is on the right. Showing one hides the
others in that tabpage without stopping them: an agent keeps working while it
is hidden, and `<Space>al` (or `<Space>ac`, for the last one shown here)
brings it back. With nothing on the right a key asks where to go; it never
sends to a hidden chat on its own. In a CodeDiff view the keys act on the page
the view was opened from.

The launch option (`vi --claude`, `vi --codex`) only picks the *default
backend*: the first entry of `<Space>an`, and the agent offered first when a
key has to ask. `:AI info` lists every open chat and where it is, and which API
key the inline prompts would use. Details: [AI chats and the default
backend](../README.md#ai-chats-and-the-default-backend).

To point an agent at some code, `<Space>yl` copies `path:12` (in Visual mode
`path:12-18` for the selected lines), relative to the repository root. Agent
prompts read that form, and so do `gF` and terminal links.

While you type in a file, a grey suggestion for the rest of the line may
appear after the cursor. It comes from a model running on this machine, not
from the agent in the panel (setup: [Inline AI completion](../README.md#inline-ai-completion)).
`Ctrl-l` takes it. Ignoring it costs nothing: keep typing and it either follows
along, while your text still matches it, or gives way to a fresh one. Markdown,
plain text, commit messages and buffers without a filetype are left alone;
`:Minuet virtualtext toggle` switches the current buffer either way.

The numbered `,` keys focus or create the selected terminal and never close
it when pressed again. `<C-/>` opens/closes the current or last-used terminal.

If text from a panel is left painted over the window beside it (typically
after scrolling through Devanagari such as Hindi strings), press `q` to return
the panel to live output, then `<Space>ur` to make Nvim clear and repaint the
screen.

### Three ways to ask an AI

`<Space>an` offers three different things. What they can do overlaps; where
the request goes, and who pays for it, does not:

| | Native panel | Agent chat | API chat |
|---|---|---|---|
| `<Space>an` entry | `Claude Code · terminal · subscription` | `Claude Code · CodeCompanion ACP · subscription` | `Anthropic · CodeCompanion API · API credits` |
| What it is | The agent's own terminal app | The same agent in a Neovim chat buffer (CodeCompanion over ACP) | A model's API in the same kind of buffer (CodeCompanion over HTTP) |
| Paid by | Subscription | Subscription | API credits |

Each has its Codex or OpenAI twin. Once started, all three are reached the same
way: they take turns on the right, and `as`, `ai`, `ac` and `af` act on
whichever is there.

Pick by what you are doing:

- **Hand over a task: the native panel.** It is the whole agent — it edits
  files and runs commands, and Claude's proposed edits come back as diffs, in
  a tabpage of their own (`<Space>aa` accepts, `<Space>ad` denies; the tab
  closes once Claude has the answer). `<Space>ai` writes the prompt in a real
  buffer.
- **Work through something in a buffer: the agent chat.** The same agent on
  the same subscription, but the conversation is a Markdown buffer you can
  search, yank from and edit like any other. In Visual mode `<Space>as` adds
  the selection to it.
- **Ask a model directly: the API chat.** No agent in between, billed to the
  API key (setup: [API keys](../README.md#api-keys)). It has CodeCompanion's
  own `@` tools, `/save` to keep a chat as a session and `/compact` for long
  ones. `<Space>ae` is its one-shot form: an instruction for the selection,
  or for the cursor position, typed on the command line, billed to the key
  profile `<Space>ax` picks.

Inside either chat, write below the last `## Me` heading and press `Enter` in
Normal mode (or `Ctrl-s`) to send; nothing goes out before that. The reply's
heading says which kind you are in — `CodeCompanion (Claude Code · ACP)` or
`CodeCompanion (Anthropic · API)` — and so do `<Space>al`'s labels. The keys
that spend API credits sit under the menu heading *HTTP · API credits*.

Two chats on the right hand the one window over in place. A chat keeps the
backend it was started on; another backend is another chat, from `<Space>an`.
`<Space>ao` reopens a saved chat of either kind. An API chat whose key is not
set is not offered, and `<Space>ae` says so and sends nothing.

Approving an edit and reviewing one are different things. `<Space>aa` /
`<Space>ad` answer one edit Claude *proposes*, before it reaches the disk; only
native Claude asks (Codex runs with `--yolo` and asks nothing, and the chats
have CodeCompanion's own tool approvals). Reviewing looks afterwards at
everything that changed on disk since you sent a prompt, whichever of the three
made it: `<Space>av` shows it, and from there you send feedback, stage, or put
a hunk back. The next chapter walks through it.

---

## Reviewing a round of agent changes

An agent edits files on its own, several of them per prompt. Reviewing means
looking at everything that changed since you asked, and telling the agent what
you think of it. Every prompt you submit starts a **round**: a snapshot of the
working tree taken just before the agent starts work, kept as a hidden Git
commit, the round's *baseline*. `<Space>av` shows what changed since it, `,C`
writes feedback on what you see, and `<C-d>` hands the feedback back to the
conversation the round belongs to.

```
(send a prompt)    round 11:22:33 starts: its baseline is the code as it was
<Space>av          the changes since that baseline, in a review tab
,C                 a comment on the hunk / selection / file under the cursor
,C …               more comments, collected in one draft
<C-d>              the draft goes into the agent's input, for you to send
(send it)          round 11:40:02 starts
<Space>av          the new round, in the same review tab
```

### Where rounds come from

Every kind of conversation starts rounds the same way:

| Conversation | A round starts when |
|---|---|
| Native Claude or Codex (`<Space>ac`) | you submit a prompt in the panel |
| Agent chat or API chat (`<Space>an`) | you send a message, or regenerate a reply |
| None in particular | you press `<Space>aV` |

The prompt waits for its snapshot, up to 2.5 s; on an ordinary repository the
snapshot takes a fraction of that. A snapshot that takes longer lets the prompt
go ahead, and its round is marked **Late**: its baseline may already contain the
agent's first edits, and the review view says so. Nothing else ever holds a
prompt up, and nothing is added to it — a failure here costs the round, never
the prompt.

A round covers one repository, the conversation's *root*: the Git root of the
directory the agent works in, fixed when it starts. Native Claude and Codex
start in the current file's repository, a chat in Nvim's working directory.
Edits the agent makes outside that repository are not part of any round.

- Each Claude prompt starts a round. A Codex message sent while a turn is still
  running belongs to that turn's round, and a chat's tool loop is one round:
  only what you send yourself counts.
- A prompt that finds nothing changed since the conversation's last round in
  this Nvim keeps that round instead of starting a twin.
- Subagents (Claude's Task agents, Codex's spawned threads) start nothing:
  their prompts are part of the parent's turn.
- Neither does Claude waking itself to go on with your work: when a
  background task it started (a long Bash command, a workflow) finishes, or
  a background agent it started hands its result back. What it changes, and
  where that work ends, belong to the conversation's newest round — your
  prompt's, unless you sent another prompt in the meantime. A wake-up Claude
  scheduled (`ScheduleWakeup`, `/loop`) is a prompt like any other.
- Outside Git nothing starts.

A snapshot holds the untracked files too, except those `.gitignore` excludes
at that moment and untracked files over 10 MiB, which are never read. An agent
that edits `.env` or `node_modules` therefore shows nothing.

A round proves only that a change came *after* its baseline. Your own edits in
the same worktree, or another agent's, show up as well — which is why every
message says "changes since round 11:22:33", never "the agent's changes".

Rounds survive restarts. Each worktree keeps its newest 20; a round whose draft
still holds feedback is kept beyond that.

### `<Space>av`: the review view

`<Space>av` opens the round's baseline against the working tree, in a CodeDiff
tab of its own. Which repository: the conversation's root when you press it in
an agent panel or a chat; otherwise the current file's repository (in a
CodeDiff view, the one it compares), otherwise the working directory's. Which
round, the first that exists:

1. the newest round of the conversation in the current panel or chat;
2. the newest round of the chat on the right (in a CodeDiff view, of the page
   the view came from);
3. the newest round this Nvim started in that repository;
4. the newest round there at all.

Each repository has one review tab. `<Space>av` on the round it already shows
focuses its file panel; on another round, the old review tab closes and the new
one opens in its place. No other tab changes. Once the view is up, a notice
says what it compares:

```
Changes since round 11:22:33 (baseline → working tree)
Root: ~/proj
Conversation: Claude Code session 7f0c1a2b…
```

and the statusline reads `Review · Claude · round 11:22:33 → working tree`.

- **Nothing changed yet.** If the conversation's previous round has changes —
  you sent the next prompt and the agent has not written anything yet — that
  round opens instead: "Round 11:40:02 has no changes yet; showing round
  11:22:33". Otherwise "No changes since round 11:22:33 in ~/proj", and nothing
  opens. Paths the view cannot compare do not count as changes; the notice
  names them.
- **No round at all.** The notice says so, offers `<Space>aV`, and points to
  `:checkhealth config` for the case where you did send a prompt
  ([troubleshooting](DIAGNOSTICS.md#review-rounds-and-agent-hooks)).

The view itself is an ordinary [CodeDiff view](#git) of a baseline against the
working tree: `,u` / `,U` stage and unstage, `,X` puts a hunk back to the
baseline. `<Space>gq`, or `q` in its file panel, closes the tab; the agents
keep running.

### `,C`: feedback

`,C` works in Normal and Visual mode in every window of every CodeDiff view of a
Git repository, not only the review view. Each press adds one entry to a
draft:

| Pressed on | The entry quotes |
|---|---|
| a hunk in a diff pane | the hunk as a diff of both sides, with three lines of context: `## src/parser.lua:42-47 (working tree) · was 40-43 at the baseline` |
| a diff pane, away from any hunk | the cursor line |
| a selection in the right pane | the selected lines, marked `unsaved buffer` when the file has unsaved edits |
| a selection in the left pane | the baseline's lines, marked `(baseline side, not on disk)` |
| a file in the file panel | its path and status only: `## src/new.lua (R src/old.lua→src/new.lua)` |
| a file under a commit in a history | the file, its status and the commit: `## src/new.lua (M in 1a2b3c4d)` |
| a commit in a single file's history (`<Space>gV`) | that file and the commit: `## src/new.lua (changed in 1a2b3c4d "Fix the parser")` |

A commit row of the repository's history (`<Space>gH`) stands for no one
file, so `,C` there asks for a file in the list instead. Paths are real paths relative to
the repository. The left side's line numbers
exist in no file on disk, so an entry quotes the code rather than pointing at
lines. A view of two revisions names both.

The draft opens in a float, the cursor on the new entry's `> ` line in Insert
mode, ready for your comment. Its title names the round, and its top line
where `<C-d>` will deliver:

| Key | In the draft |
|---|---|
| `<C-d>` | Deliver it (Normal or Insert mode) |
| `q` | Hide the float; the draft is kept |

The rest is an ordinary Markdown buffer: rewrite or delete entries freely, and
`@` completes the repository's files. Leaving the float in any way saves it,
and the next `,C` appends to the same draft and shows it again. The
`<!-- nvim-review … -->` lines are the draft's own: they record each entry's
file for the staleness check below and are never sent. Deleting one merges its
entry into the one above, and that entry's file is no longer checked.

A draft is a file, shared by every Nvim: one per round, and one per repository
for views that belong to no round (`gv`, `gm`, a `gk` without a round), under
`~/.local/state/nvim/ai-review/`. Comments added from two Nvims are merged,
and so are edits to different lines of one entry. Where both changed the same
lines of an entry, or one Nvim typed into an entry the other has since
delivered or deleted, the draft keeps the version saved first, and what was
typed in the other goes beside it as `<round>.conflict.md` (then
`.conflict-2.md`, …), with a warning naming it.

### `<C-d>`: delivery

`<C-d>` sends the draft, without its markers, to the conversation that owns the
round. It first switches to the tab that shows that agent's panel or chat —
from the review tab otherwise to the tab before it, the one it was opened
from.

- **Native Claude or Codex.** The feedback opens in that agent's own prompt
  editor — the float `<Space>ai` opens — after whatever was already typed in
  its input box. Read it over, `<C-d>` there puts it in the input box, and
  Enter sends it. If that agent's prompt editor is already open, the feedback
  is added to it directly.
- **A chat.** It is added to that exact chat's message, below anything you had
  typed there, with the chat shown and the cursor at the end in Insert mode.
  Send it as usual.

The draft is emptied only once the text has arrived, and a copy is kept as
`<round>.last-sent.md` (each delivery replaces it). If the agent does not open
its prompt editor within 10 seconds — usually because it is in the middle of a
turn — the delivery counts as failed: "Claude Code did not open its prompt
editor (busy?)", and the draft stays as it was. `<Space>ai` pressed for the same
agent while a delivery waits cancels it the same way. Feedback meant for Claude
is never picked up by Codex's prompt editor, or the other way round.

**Stale entries.** Each entry remembers its file as it was when you commented.
`<C-d>` checks the files again; an entry whose file changed since (or is gone)
gets `⚠ changed since this comment` in its heading, and you are asked: *Deliver
anyway* or *Edit first*. The check is per file, so it can flag an entry whose
hunk did not change; it never misses one that did.

### Who receives it

A round belongs to the conversation that started it, and `<C-d>` checks that
the feedback still reaches that conversation before anything is sent. Each
refusal keeps the draft and says why.

1. **The same repository.** The draft's repository, the view's and the target
   session's must be the same directory — a linked worktree is a different
   one. Nothing overrides this, and nothing asks.
2. **The same conversation.** A native agent has to be running in this Nvim,
   in the round's session. If you have typed into its terminal since it last
   reported the session (it might have been `/new`, `/resume` or `/fork`), or
   it has not reported a session yet, a notice explains and you are asked
   "… Deliver anyway?". A chat has to be open in this Nvim; a chat from before
   a restart is gone.
3. **Not busy.** A chat that is still replying, or between the steps of a tool
   loop, refuses: deliver once it is done. Whether a native agent is busy
   cannot be seen from here; the 10-second wait covers it.

| The notice starts | Because | Then |
|---|---|---|
| `Claude Code is not running in this Nvim.` | the owner's agent is not running | `<Space>ar` to resume the session, then `<C-d>` again |
| `Codex is not running in this Nvim.` | the same | `<Space>ar` (`codex resume`); Codex reports its session only at your first prompt, so the next `<C-d>` asks first |
| `Claude Code is in another session now.` | the panel runs another conversation | `/resume` the round's session in the TUI |
| `Claude Code runs in another root now:` | the agent was restarted from another repository | quit it, and resume the session from a file in the round's repository |
| `That chat is closed or belongs to an earlier Nvim.` | the chat is gone | send to a current session (below) |
| `Refused: the target session is in another root.` | the round's own session runs from another repository | resume it from a file in the round's repository; nothing overrides this |
| `The chat is replying.` | the chat is mid-turn | wait, then `<C-d>` |
| `No session to deliver to.` | no agent or chat runs in this repository | start one there |

When the owner is gone — the first five rows — the refusal also offers **Send to
a current session…**: a list of the sessions running in the same repository,
then one confirmation naming both ("This round belongs to Claude Code session
7f0c1a2b…", *Send to Codex · session 3e9a5d10…*). It changes where this one delivery
goes; the round keeps its owner. A draft with no owner at all — a `<Space>aV`
round that bound none, or a `gv` or `gm` view — opens that list at once; picking
is the confirmation.

### Each agent's limits

| | Native Claude | Native Codex | Agent chat (ACP) | API chat (HTTP) |
|---|---|---|---|---|
| The baseline | taken before the prompt runs; the prompt waits up to 2.5 s | the same | taken before the message leaves; it waits up to 2.5 s | the same |
| When Nvim learns the session | at start, `/clear`, `/resume`, `/compact` and every prompt | only at a prompt: after `/new`, `/clear`, `/fork`, `/resume` or a `codex resume` start, not until the next one | when the chat opens | the same |
| `<C-d>` asks first | after you typed in its terminal | before its first prompt, or after you typed | never | never |
| After restarting Nvim | `<Space>ar` resumes the same session, and delivery works | `<Space>ar`, then confirm the delivery (or send a prompt first) | the old chat is gone: send to a current session | the same |
| What stops its rounds | `--bare`, managed settings that turn hooks off, a folder whose trust prompt is still open | a Codex update that changes how it trusts hooks | — | — |
| Approval before a write | `<Space>aa` / `<Space>ad` | none (`--yolo`) | the chat's own tool approvals | the same |

The native agents learn about prompts through hooks this Nvim adds to the
agents it starts, and only to those: `--settings` for Claude, `-c` for Codex.
Nothing is written to `~/.claude` or `~/.codex`, a Claude or Codex started in a
plain shell starts no rounds, and the hook never prints, so the model sees
nothing of it. Chats need no hook; Nvim sees their messages leave.

Codex runs its session-start hook only when a thread's first turn starts. A
`/new`, `/fork` or `/resume`, or a Codex started with `codex resume`, therefore
switches threads without a word to Nvim until you next submit a prompt, and in
between nobody can tell which conversation its input box belongs to. That is
why a delivery to Codex then asks instead of refusing: refusing would make every
Codex restart wait for a prompt.

Codex also asks you to review a hook before running it ("hooks need review
before they can run"); this one never asks. Its trust record comes with it, in
the same `-c` option, so Codex treats it as reviewed without writing anything
to `~/.codex/config.toml`. `--dangerously-bypass-hook-trust` would have skipped
the question too, but for every hook, including any project's own
`.codex/hooks.json`. The `-c` has one visible cost: Codex notes at startup that
it runs "without the shared background server", because any `-c` makes it run
its own; `sources.codex = false` drops both the hook and the note.

Native Claude starts in the current file's Git root, as Codex does, so both
agents' rounds belong to the project you are in; `claude_cwd = "cwd"` brings
back Nvim's working directory. A Claude that `cd`s into another repository
keeps recording its rounds where it started, and says so once.

### Manual rounds, saved baselines and any two ends

- `<Space>aV` (*Start a review round*) takes a round now, without a prompt — say,
  before you edit by hand or before a task you start some other way. It
  belongs to the conversation of the panel or chat you press it in; else to the
  chat on the right, when it works in this repository and is a conversation
  this Nvim knows (an agent that has reported its session, or a chat); else to
  nobody, and `<C-d>` asks where its feedback goes. When
  nothing changed since that owner's last round, it says that round is already
  the current state.
- `<Space>gK` (*Save current code as a baseline*) saves a named snapshot that
  belongs to no conversation — "before refactor". It offers the name of the
  agent session at work in this repository (the chat on the right first);
  edit it, or clear it for the time. Each worktree keeps its newest 10, and a
  notice names any it removes.
- `<Space>gk` (*Compare two*) compares any two ends. Pick an older round's
  baseline against the working tree to see everything since an earlier
  prompt, several rounds at once: that view counts as the round's review tab,
  and `,C` files feedback for its owner. Any baseline against the working tree
  gets `,X` too. `<Space>gM` lists the baselines as well.

Both pickers name a round by its session, source and time:

```text
Scanner error messages: Claude 11:16:38 - 11:43:18   a round today
Parser cleanup: Claude 11-09 20:36 - 21:39            a round on another day
Config differences: Codex 07:48:39 - …                its session is still at it
Agent chat 09:03:20                                   no session records to read
before refactor: Saved 11-09 23:08                    a saved baseline
```

- **The name** is the first one the session had — Claude Code's generated
  title (what `/resume` lists) or a `/rename` made before it, a Codex thread's
  name — read from the agent's own records, and a later rename leaves it
  alone. Past 40 columns it is cut with `…`.
- **The start** is when the round's baseline was taken, as the prompt left.
- **The end** is when the session last finished a turn (or was interrupted)
  before its next round began. A prompt that changed nothing since the last
  round keeps that round, so the end can come from a later prompt, and a turn
  that ran past the next prompt leaves its round with no end.
- **`…`** means the session is at work on this round: it was prompted (or
  woken by a background task) after its last turn ended, and it is alive — its
  terminal runs in this Nvim, or its records were written in the last 30
  minutes. A session killed mid-turn therefore drops the `…`, and so does one
  working in another Nvim on a step that writes nothing for 30 minutes. A
  manual round (`<Space>aV`) is no prompt, so it shows `…` only once its
  session is prompted again.
- A chat, a manual round with no owner, or a session whose records are not
  on this machine shows its source and start alone. Codex compresses a
  rollout it has not touched for about ten days (`.jsonl.zst`); its turns are
  read through `zstd` when that is installed, else such a round shows its
  name and start.

The view a baseline opens is labelled with the start alone, `Scanner error
messages: Claude 11:16:38 → working tree`: it shows everything since then, up
to now, whatever the end says.

To start over with a conversation, send the next prompt or press `<Space>aV`;
`<Space>av` always picks the newest round.

### What each action changes

| Action | Keys | Changes | Leaves alone |
|---|---|---|---|
| Feedback | `,C`, then `<C-d>` | nothing in the repository: text appears in the agent's input or the chat, for you to send | everything |
| Stage / unstage | `,u` / `,U` | the real index — what `git commit` takes next | the working tree, the baseline |
| Put back | `,X` | one hunk of the working-tree file, written to disk | the index, the baseline, the rest of the file |
| Claude's approval | `<Space>aa` / `<Space>ad` | an edit Claude proposes, *before* it is written | the review view: unrelated |

None of them is called *accept* or *approve*, because none of them tells the
agent anything: staging is between you and Git, and only feedback reaches the
conversation, once you send it.

### Settings: `vim.g.ai_review`

Defaults suit most use. To change some, set only those keys in `init.lua`:

```lua
vim.g.ai_review = { retention = { rounds = 30 }, claude_cwd = "cwd" }
```

Assign the whole table: `vim.g` hands out copies, so
`vim.g.ai_review.retention.rounds = 30` changes nothing. A key that is not a
setting, or a value of the wrong type or range, warns once and keeps the
default; the rest of the table still applies. Each setting is read when it is
used, so a change made while Nvim runs counts from the next use, except where
the table says otherwise. `:checkhealth config` lists the values in effect.

| Key | Default | Meaning |
|---|---|---|
| `retention.rounds` | `20` | Rounds kept per worktree, newest first. A round whose draft still holds feedback is never removed |
| `retention.saved` | `10` | Saved baselines (`<Space>gK`) kept per worktree |
| `max_file_size` | `10485760` (10 MiB) | Untracked files larger than this many bytes are left out of every snapshot, never read |
| `sources.claude` | `true` | `false`: native Claude gets no hook, and its prompts start no rounds |
| `sources.codex` | `true` | The same for native Codex |
| `sources.codecompanion_acp` | `true` | `false`: agent chats start no rounds |
| `sources.codecompanion_http` | `true` | `false`: API chats start no rounds |
| `hook_wait_ms` | `2500` | How long a prompt waits for its baseline before going ahead with a Late round; `0` never waits |
| `claude_cwd` | `"git_root"` | Where native Claude starts: `"git_root"`, the current file's Git root, or `"cwd"`, Nvim's working directory |
| `unknown_session` | `"confirm"` | A native session `<C-d>` cannot confirm: `"confirm"` asks, `"refuse"` refuses |
| `always_confirm` | `{}` | Agents whose deliveries always ask, even with the session confirmed: `"claude"`, `"codex"` |
| `redirect` | `true` | `false`: an owner that is gone is refused without *Send to a current session…* |
| `seed_ttl_ms` | `10000` | How long a native agent has to open its prompt editor for a delivery |
| `history_limit` | `100` | Commits `<Space>gH` and `<Space>gV` list; `false` lists all |

When a change counts:

- Claude's hook is part of its command, fixed when claudecode.nvim loads, at
  the first Claude key. Turning `sources.claude` on, or a new `hook_wait_ms`,
  then needs a restart; turning it off works at once, since the events are
  dropped.
- Codex's command is built each time Codex starts, so its sources and waits
  count from the next start, and off counts at once.
- A chat opened while its source was off starts no rounds even after you turn
  it on; turning a source off counts at once.
- The `<Space>gH` / `<Space>gV` descriptions are written when the plugin specs
  load, so set `history_limit` before `require("bootstrap")` in `init.lua`;
  the lists themselves follow the setting.

---

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
| `<Space>dB` | Conditional breakpoint |
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
`,v` when needed. `df` launches the script; `td`/`tF` use neotest-python.
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
its own jdtls workspace. `td`/`tF` debug the nearest test / first discovered test
class. The Java-local aliases `,dt`/`,dT` remain available after attachment.

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
`cwd` and `args`. Use `,dr` for supported hot reload; `dR` restarts a launched
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

React Native is still a separate [feasibility spike](../spikes/react-native-dap/README.md),
not a supported Hermes DAP workflow. For connection failures, unbound breakpoints,
SDK paths and platform permissions, see [DIAGNOSTICS.md](DIAGNOSTICS.md).
