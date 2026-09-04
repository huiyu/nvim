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
comes from a picker, a tree, or something else — you press it because you want
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
| `g` | go somewhere / about the thing under the cursor | `gd` definition · `gr` references · `gI` implementation · `gy` type · `K` docs · `gx` open URL · `gS` split / join · `gv` reselect |
| `z` | folds and spelling | `zR` open all · `zM` close all · `za` toggle · `z=` suggestions · `zg` add to dictionary |
| `Ctrl` | act now, no questions, the same in every mode | `<C-h/j/k/l>` windows · `<C-/>` terminal · `<C-o>` back the way you came · `<C-a>` `<C-x>` increment / decrement · `<C-r>` redo |

**which-key:** press `[`, `]`, `g`, or `z` and wait half a second — the popup
lists the drawer.

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
s  windows                 \  this filetype only
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
| `;F` | Find file next to the current one |
| `;r` | Recently opened |
| `;b` | Open buffers |
| `;g` | Files tracked by git |
| `;n` | Files in this Neovim config |
| `;p` | Switch project |
| `;a` | **Alternate file** — bounce between the last two files. The implementation/test loop. |
| `;;` | Reopen the last search, with its results intact |

`;<Space>` is the one to build a habit around. It learns which files you touch
and floats them to the top.

### Text and symbols

| Key | Does |
|---|---|
| `;/` | Search the whole project |
| `;w` | Search the word under the cursor |
| `;l` | Search lines in this file |
| `;D` | Search this directory |
| `;s` | Symbols (functions, classes) in this file |
| `;S` | Symbols across the project |
| `;c` | **Who calls this?** — incoming calls for the symbol under the cursor |

### Browsing

| Key | Does |
|---|---|
| `;e` | File tree sidebar |
| `;d` | Browse the current file's directory |
| `;o` | **oil** — edit the directory as text (see below) |
| `-` | oil, on the parent directory |

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
| `,n` | Generate a docstring / annotation |
| `,x` | Run this file |
| `,O` | Outline of this file |

`,a` and `,r` only exist where a language server is running — in a plain text
file they are simply not there.

### Moving lines

| Key | Does |
|---|---|
| `,j` / `,k` | Move the line (or selection) down / up |
| `,h` / `,l` | Dedent / indent |

Works on a Visual selection too.

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

**Moving between windows does not use `s`** — it is one key:

```
Ctrl-h  Ctrl-j  Ctrl-k  Ctrl-l     left, down, up, right
Ctrl-,                             straight to the editor, and back again
```

Those work from inside a terminal too, which matters when an AI panel or shell
is open beside your code.

---

## This filetype: `\`

`\` holds actions that only mean something in the file you are in. The same key
does different things in different filetypes, which is the point.

| Filetype | Keys |
|---|---|
| Go | `\o` organize imports · `\G` rebuild the gopls index |
| Python | `\o` organize imports · `\v` select virtualenv |
| C/C++ | `\h` switch between source and header |
| Markdown | `\p` toggle preview · `\r` toggle in-editor rendering |
| LaTeX | `\b` build · `\v` view PDF · `\t` table of contents · `\e` errors · `\k` clean |
| Diffview | `\e` focus file panel · `\co` / `\ct` resolve conflict (ours/theirs) |

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
| `<Space>m` | Manage | help, man, keymaps, Lazy, Mason, LSP status |
| `<Space>s` | Session | save / restore a working layout |
| `<Space>y` | Yank | copy file path, yank history, registers |
| `<Space>u` | Toggle/UI | wrap, spell, diagnostics, colorscheme |
| `<Space><Tab>` | Tab | tab pages |
| `<Space>q` | Quit | quit all |

---

## Workflows

### Reading unfamiliar code

```
;/  search for something you recognise
gd  jump to the definition
gd  again, and again — follow it down
Ctrl-o  walk back up the way you came
;c  who calls this?
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

### Terminals and AI

```
Ctrl-/       toggle a terminal
Ctrl-1 … 9   jump straight to terminal 1-9, even from inside another one
<Space>ac    open the AI panel
<Space>ai    write a prompt in a real Neovim buffer
```

`Ctrl-]` leaves terminal input without disturbing the program running in it —
useful because `Esc` belongs to the AI CLIs themselves.

---

## When you forget a key

1. **Press the prefix and wait.** `;`, `,`, `s`, `\` or `<Space>` all show a
   menu after a moment. This is the fastest answer.
2. **`<Space>?`** — one page listing every prefix and the common keys.
3. **`<Space>mk`** — search all keymaps by description.
4. **`;;`** — reopens whatever you searched last, if you lost a result list.

The menus are generated from the configuration itself, so they cannot drift out
of date the way a document can.
