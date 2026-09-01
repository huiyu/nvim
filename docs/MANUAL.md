# Manual

A guide to actually using this configuration. If you are new to Vim, start at
[The idea](#the-idea) and read straight through. If you already know Vim and
just want the keys, jump to [The five prefixes](#the-five-prefixes).

The [README](../README.md) covers installing and what plugins are included.
This document covers *using* it.

---

## Contents

- [The idea](#the-idea)
- [Vim in five minutes](#vim-in-five-minutes)
- [The grammar](#the-grammar)
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

## Vim in five minutes

Skip this if you already know Vim.

Vim has **modes**. This is the whole trick, and the only thing that is strange
at first.

| Mode | You are… | Get there | Get out |
|---|---|---|---|
| **Normal** | giving commands | `Esc`, or `jk` | — |
| **Insert** | typing text | `i` | `Esc` or `jk` |
| **Visual** | selecting | `v` | `Esc` |

You start in Normal mode. Letters are commands, not text. `d` deletes, `y`
copies ("yank"), `p` pastes. To type, press `i` first.

**`jk` typed quickly is Escape.** It is on the home row, and it is what you will
use.

Movement:

```
h j k l    left, down, up, right
w  b       next / previous word
0  $       start / end of line
gg  G      top / bottom of file
```

**Undo is `u`. Redo is `Ctrl-r`.** Try things; you can always undo.

That is enough to survive. The next section is what makes Vim worth learning.

---

## The grammar

Vim is not a pile of shortcuts to memorise. It is a small language, and the
commands you have not learned yet are ones you can *derive*.

Every edit has the same shape:

```
operator  +  count  +  target
   d           2         w        delete 2 words
   c           _         i(       change inside parentheses
   y           3         j        copy this line and 3 below
```

### Operators — what to do

| | |
|---|---|
| `d` | delete |
| `c` | change (delete, then start typing) |
| `y` | yank (copy) |
| `>` `<` | indent / dedent |
| `gu` `gU` | lowercase / uppercase |
| `gc` | comment |
| `=` | auto-indent |

### Targets — what to do it to

A target is either a **motion** (from here to there) or a **text object**
(this whole thing, wherever the cursor is inside it).

**Motions** run from the cursor outward:

```
dw     delete to the start of the next word
d$     delete to end of line
d0     delete to start of line
dG     delete to end of file
d}     delete to the next blank line
df,    delete through the next comma
dt)    delete up to, but not including, the next )
```

**Text objects** do not care where the cursor sits inside them. They take
`i` (inside) or `a` (around, i.e. including the delimiters):

```
di(    delete inside the parentheses      foo(bar) → foo()
da(    delete around them                 foo(bar) → foo
ci"    change inside the quotes
dit    delete inside the HTML/XML tag
dap    delete this paragraph
```

The `i` / `a` distinction is the single highest-value thing to learn here:

```
"hello world"        cursor anywhere inside

ci"   →  ""          keeps the quotes, you type the new text
ca"   →              takes the quotes too
```

### Syntax-aware objects

This config adds treesitter-backed objects, so the target can be a real code
construct rather than a character pair:

| Target | Is |
|---|---|
| `if` / `af` | inside / around a **function** |
| `ic` / `ac` | inside / around a **class** |
| `ia` / `aa` | a **parameter** (`daa` deletes the argument *and* its comma) |
| `io` / `ao` | a **block**, conditional, or loop body |

```
dif    delete the body of this function, wherever the cursor is in it
daf    delete the whole function
caa    change this argument
vio    select the body of this if-statement
```

`daa` is worth noting: deleting an argument normally leaves a dangling comma.
The parameter object knows about the separator and takes it along.

### Why this matters

You do not learn `dif`. You learn `d` and you learn `if`, and the combination
already works — along with `cif`, `yif`, `>if`, `gcif`, `vif`. Six operators
times twenty targets is a hundred and twenty commands you never memorised.

When you want to do something new, ask two questions: *what operation?* and
*what should it apply to?* Then type them in that order.

### A few shortcuts that are just abbreviations

```
x   = dl      delete char             D   = d$    delete to end of line
s   = cl      change char             C   = c$    change to end of line
dd  = d_      delete this line        cc  = c_    change this line
```

Doubling the operator (`dd`, `yy`, `cc`, `gcc`) always means "this line".

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
| Markdown | `\p` toggle preview |
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
