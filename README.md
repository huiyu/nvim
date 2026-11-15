# Neovim Configuration

[中文文档](README_CN.md)

A modern Neovim configuration built with Lua and [lazy.nvim](https://github.com/folke/lazy.nvim). Aligned with [LazyVim](https://www.lazyvim.org/) conventions for keybindings and plugin choices, with support for Go, C/C++, Python, Java, Rust, Web, Bash, JSON, YAML, and LaTeX development.

### Requirements

**Required:**
- **Neovim** >= 0.12.5 (refactoring.nvim's minimum; nvim-treesitter's `main` branch needs 0.12)
- **Git** (2.26 or later for the [review rounds](docs/MANUAL.md#reviewing-a-round-of-agent-changes))
- A [Nerd Font](https://www.nerdfonts.com/) for icon display
- **ripgrep** (`rg`) — powers `Snacks.picker.grep` / `live_grep` / `:grep`
- **fd** — file finder (used by `venv-selector` and some pickers)
- **[tree-sitter CLI](https://github.com/tree-sitter/tree-sitter/blob/master/crates/cli/README.md)** >= 0.26.1 and a C compiler — nvim-treesitter's `main` branch builds every parser with `tree-sitter build`. Install it from a package manager (`tree-sitter-cli` in Homebrew), not npm

**Optional (feature-specific):**
- **[lazygit](https://github.com/jesseduffield/lazygit)** — `<leader>gg` (repo) / `<leader>gf` (file history)
- **[tmux](https://github.com/tmux/tmux)** — wraps the native-agent TUIs inside `:terminal` to prevent stale or torn frames; auto-detected (see [Terminal Integration](#terminal-integration))
- **[GitHub CLI](https://cli.github.com/)** — authenticated `gh` for `<leader>G` GitHub pickers and status
- **[Codex](https://developers.openai.com/codex/cli/)** — native coding agent, alongside optional CodeCompanion chats, started with `<leader>an` ([AI chats](#ai-chats-and-providers))
- **Node.js >= 22 + npm** — the ACP bridges behind CodeCompanion's agent chat
- `NVIM_ANTHROPIC_API_KEY` or `NVIM_OPENAI_API_KEY` — optional; CodeCompanion API chats on that key profile, and inline/command prompts on the current one (see [API keys](#api-keys) — not `ANTHROPIC_API_KEY` / `OPENAI_API_KEY`)
- **[llama.cpp](https://github.com/ggml-org/llama.cpp)** — `llama-server` and its 7B coder model (one ~8 GB download) for [inline AI completion](#inline-ai-completion)
- **[cowsay](https://en.wikipedia.org/wiki/Cowsay)** + **lolcat** — dashboard banner (silently skipped if either is missing)

**Quick install (macOS):**
```bash
brew install neovim git gh ripgrep fd tree-sitter-cli lazygit tmux cowsay lolcat node llama.cpp
brew install --cask font-jetbrains-mono-nerd-font  # or any Nerd Font
gh auth login                                      # once, for GitHub pickers
npm install -g @agentclientprotocol/claude-agent-acp @agentclientprotocol/codex-acp
llama-server --fim-qwen-7b-default                 # once: ghost-text model (~8 GB); Ctrl-C when listening
```

**Language toolchains** — *only if you want the matching Mason packages to install:*
- **Go** — required for `gopls`, `gofumpt`, `delve`
- **Python >= 3.10** — required for `black` (a `pyenv` or `uv`-managed interpreter works)
- **Node.js + npm** — required for `eslint-lsp`, `css-lsp`, `html-lsp`, `json-lsp`, `yaml-language-server`, `tailwindcss-language-server`, `vtsls`, `bash-language-server`
- **Rust (rustup)** — `rust-analyzer` (installed by Mason) needs `cargo`, and formats with the toolchain's `rustfmt` (`rustup component add rustfmt`); it adds `rust-src` through rustup itself
- **JDK 25+** — runs `jdtls` (Java); projects may still target older releases. Found through `$JAVA_HOME`, then [SDKMAN!](https://sdkman.io/) (`~/.sdkman/candidates/java`), then PATH (see [`lua/plugin/lang/java.lua`](lua/plugin/lang/java.lua))
- **TeX Live + Skim** (LaTeX) — `brew install --cask mactex-no-gui` for `latexmk`/`latexindent`/`chktex`, and `brew install --cask skim` for the SyncTeX PDF viewer. `texlab` is installed by Mason. For inverse search set Skim → Preferences → Sync → Custom: command `nvim`, arguments `--headless -c "VimtexInverseSearch %line '%file'"`

If a Mason package fails to install, run `:Mason` (UI) or `:MasonLog` (raw log) to see the underlying error. The most common cause is a missing toolchain from the list above.

### Installation

```bash
# Backup existing config
mv ~/.config/nvim ~/.config/nvim.backup

# Clone
git clone https://github.com/huiyu/nvim.git ~/.config/nvim

# Launch Neovim — lazy.nvim auto-installs all plugins
nvim
```

Opening a file (`vi path/to/file`, or `nvim`) sets cwd to its Git root, falling
back to its directory outside Git. Opening a directory uses that directory;
starting without arguments keeps the shell's cwd. See the [manual](docs/MANUAL.md#files).

### Project Structure

```text
~/.config/nvim/
├── init.lua                    # vim.loader; enter config bootstrap
├── lua/
│   ├── config/                 # Editable values + minimal startup wiring
│   │   ├── options.lua         # Public editor preferences
│   │   ├── behaviors.lua       # Optional editor behaviors
│   │   ├── keymaps.lua         # Shared actions, core/AI keys, leaders
│   │   ├── theme.lua           # Theme and UI preferences
│   │   ├── ai.lua              # Codex/provider/terminal preferences
│   │   ├── review.lua          # Round/delivery policy
│   │   ├── git.lua             # Snapshot/history/saved retention policy
│   │   ├── completion.lua      # Local ghost-text model/service preferences
│   │   ├── dashboard.lua       # Dashboard content
│   │   ├── whichkey_spec.lua   # Display-only menu metadata
│   │   ├── health.lua          # Health aggregation
│   │   └── init.lua/cwd.lua/lazy.lua # Bootstrap, cwd recovery, lazy imports
│   ├── plugin/                 # lazy.nvim specs; import order is merge order
│   │   └── editor/, coding/, ai/, ui/, git/, lang/
│   └── util/                   # Small host helpers, inert on require
├── local-plugin/               # Cohesive runtime packages
│   ├── editor-core.nvim/       # Settings application, keys, windows, dashboard
│   ├── agent-workbench.nvim/   # Codex/session/provider/prompt/review runtime
│   ├── git-review.nvim/        # Immutable baselines, comparison, CodeDiff
│   └── llama-service.nvim/     # Shared local model lifecycle
├── tests/                      # Serial plugin/host integration tests
└── docs/                       # Manual, diagnostics, API/utility guide
```

### Commands

Run from `~/.config/nvim`; `make` lists them.

| Command | Does |
|---|---|
| `make test` | Every spec in `tests/` (about 5 minutes); `make test S="hunk_actions codediff"` runs some |
| `make startup` | Starts headless and fails on any startup error |
| `make check` | Whitespace errors in unstaged and staged changes |
| `make verify` | `check`, `startup` and `test`: what CI runs, and what to run before a change lands |
| `make health` | Prints `:checkhealth config` in the terminal |
| `make profile` | The slowest steps of a headless startup |
| `make deps` | Installs what the specs need: missing plugins, Mason packages, CodeDiff's native library |

The specs run one at a time on purpose: some share what one Nvim at a time
expects (the llama-server `llama_service` shares, git and gitsigns timing).

### Plugins

#### UI

| Plugin | Description |
|--------|-------------|
| [solarized-osaka](https://github.com/craftzdog/solarized-osaka.nvim) | Colorscheme |
| [lualine](https://github.com/nvim-lualine/lualine.nvim) | Status line with a `● REC @q` macro recording indicator, a pending command or Visual selection size (`2d`, `3x12`), the buffer's git change counts (from gitsigns) and its language servers (a spinner while one is busy) |
| [incline](https://github.com/b0o/incline.nvim) | Top-right filename labels in file windows; pink for the focused window, `[+]` for unsaved changes |
| [bufferline](https://github.com/akinsho/bufferline.nvim) | Buffer tabs with pin/close/pick (`;B` picks one by its tab letter); `<leader>bh` closes the buffers no window shows, in any tabpage |
| [noice](https://github.com/folke/noice.nvim) | Command line and messages: `:` in a popup near the top with its completion menu, `/` and `?` on the bottom row, Vim's messages and errors as notifications (snacks below), `:w` / undo / quickfix confirmations small at the bottom right, `:messages` / `g<` in a split; no "Press ENTER" prompt |
| [treesitter](https://github.com/nvim-treesitter/nvim-treesitter) | Syntax highlighting, text objects |
| [treesitter-context](https://github.com/nvim-treesitter/nvim-treesitter-context) | Sticky function/class header (`<leader>uC`) |
| [nvim-ts-autotag](https://github.com/windwp/nvim-ts-autotag) | Auto-close HTML/JSX tags |
| [nvim-ufo](https://github.com/kevinhwang91/nvim-ufo) | Modern code folding |
| [statuscol](https://github.com/luukvbaal/statuscol.nvim) | Gutter with fixed slots for breakpoints, diagnostics and git signs; click a sign, line number or fold to act on it |
| [todo-comments](https://github.com/folke/todo-comments.nvim) | TODO/FIXME highlights |
| [illuminate](https://github.com/RRethy/vim-illuminate) | Highlight word under cursor; `]r` / `[r` jump to its next / previous reference |
| [colorizer](https://github.com/catgoose/nvim-colorizer.lua) | Hex/RGB/HSL and CSS variable previews; Tailwind colors in frontend files |
| [render-markdown](https://github.com/MeanderingProgrammer/render-markdown.nvim) | In-editor markdown rendering (`,m`) |

#### Editor

| Plugin | Description |
|--------|-------------|
| [flash](https://github.com/folke/flash.nvim) | Fast navigation with labels |
| [which-key](https://github.com/folke/which-key.nvim) | Keybinding help popup |
| [snacks](https://github.com/folke/snacks.nvim) | Picker, dashboard, terminal, notifications (history `<leader>mnh`), indent guides, smooth scroll, rename, zen mode (`sz`), git permalinks copied to the clipboard (`<leader>yg`) |
| [aerial](https://github.com/stevearc/aerial.nvim) | Code outline / symbol navigation |
| [grug-far](https://github.com/MagicDuck/grug-far.nvim) | Search and replace |
| [harpoon](https://github.com/ThePrimeagen/harpoon) | Jumps to a short list of files (`;H` add, `;1`-`;9`, `;h` menu) |
| [yanky](https://github.com/gbprod/yanky.nvim) | Yank history ring |
| [dial](https://github.com/monaqa/dial.nvim) | Increment/decrement booleans, dates, etc.; `let` / `const` in JS/TS |
| [refactoring](https://github.com/ThePrimeagen/refactoring.nvim) | Extract function/variable, inline (`,e…` / `,i`) |
| [mini.ai](https://github.com/echasnovski/mini.ai) | Enhanced text objects |
| [mini.splitjoin](https://github.com/echasnovski/mini.splitjoin) | Toggle single-line/multi-line (`gS`) |
| [mini.bracketed](https://github.com/echasnovski/mini.bracketed) | Extra `[`/`]` motions on the suffixes this config leaves free (`x` conflict, `i` indent, `j` jump, `o` oldfile, `u` undo) |
| [nvim-surround](https://github.com/kylechui/nvim-surround) | Surround manipulation |
| [nvim-autopairs](https://github.com/windwp/nvim-autopairs) | Auto-close pairs |
| [persistence](https://github.com/folke/persistence.nvim) | Session management |
| [guess-indent](https://github.com/NMAC427/guess-indent.nvim) | Auto-detect indentation |
| [oil](https://github.com/stevearc/oil.nvim) | Edit a directory as a buffer: rename, move (`dd`/`p`) and create files as text. `-` for the parent directory, `;o` for a float |

#### LSP & Development

| Plugin | Description |
|--------|-------------|
| [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig) | LSP configuration |
| [mason](https://github.com/mason-org/mason.nvim) | LSP/DAP/linter/formatter installer |
| [blink.cmp](https://github.com/saghen/blink.cmp) | Completion engine with [friendly-snippets](https://github.com/rafamadriz/friendly-snippets); signature help while typing a call |
| [conform](https://github.com/stevearc/conform.nvim) | Code formatting (with autoformat toggle) |
| [nvim-lint](https://github.com/mfussenegger/nvim-lint) | Linting |
| [nvim-dap](https://github.com/mfussenegger/nvim-dap) | Debug Adapter Protocol |
| [neotest](https://github.com/nvim-neotest/neotest) | Testing framework |
| [neogen](https://github.com/danymat/neogen) | Generate annotations/docstrings |
| [SchemaStore](https://github.com/b0o/SchemaStore.nvim) | JSON/YAML schema validation |
| [lazydev](https://github.com/folke/lazydev.nvim) | Lua development (type completion) |
| [inc-rename](https://github.com/smjonas/inc-rename.nvim) | LSP rename with live preview, on `,r` |
| [CodeCompanion](https://github.com/olimorris/codecompanion.nvim) | [Agent chats](#codecompanion-agent-chat-and-api-chat) over ACP (on the subscription) and API chats over HTTP (on a key profile), started from `<leader>an`, plus inline/command prompts on the key profile |
| [codecompanion-history](https://github.com/ravitemer/codecompanion-history.nvim) | Auto-saved, project-aware CodeCompanion chat history |
| [minuet-ai](https://github.com/milanglacier/minuet-agent_workbench.nvim) | As-you-type AI ghost text from a local model ([inline AI completion](#inline-ai-completion)) |

#### Version Control

| Plugin | Description |
|--------|-------------|
| [gitsigns](https://github.com/lewis6991/gitsigns.nvim) | Git signs, hunk actions, blame, inline diff of the current file (`<leader>gD`) |
| [CodeDiff](https://github.com/esmuellert/codediff.nvim) | Diff, history and [review](docs/MANUAL.md#reviewing-a-round-of-agent-changes) views (`<leader>g`, `<leader>av`). Diffs through a native library it downloads from its GitHub release on first use, with a file watcher beside it; `:CodeDiff install!` reinstalls ([troubleshooting](docs/DIAGNOSTICS.md#diff-views-codediff)) |

### Language Support

| Language | LSP | Formatter | Linter | Test | Debug |
|----------|-----|-----------|--------|------|-------|
| C / C++ | clangd | clang-format | - | - | codelldb |
| Go | gopls | gopls organize imports + gofumpt | golangci-lint | neotest-golang | nvim-dap-go |
| Python | basedpyright, ruff | black | ruff | neotest-python | nvim-dap-python |
| Java | jdtls (+ Lombok) | jdtls | - | java-test | java-debug-adapter |
| Rust | rust-analyzer | rustfmt (via rust-analyzer) | cargo check (via rust-analyzer, on save) | Cargo test (DAP) | codelldb + Cargo |
| Dart / Flutter | - | - | - | SDK test (DAP) | SDK DAP |
| TypeScript/JS | vtsls (`gs` source definition) | prettier | eslint | Vitest (DAP) | js-debug-adapter |
| HTML/CSS | html, cssls, tailwindcss | prettier | - | - | - |
| JSON | jsonls + SchemaStore | prettier | - | - | - |
| YAML | yamlls + SchemaStore | prettier | - | - | - |
| Bash | bashls | shfmt | - | - | - |
| LaTeX | texlab (+ VimTeX) | latexindent | chktex | - | - |
| Lua | lua_ls | - | - | - | - |

#### Debugging

`<leader>df` debugs the current file, `<leader>tM` the nearest test, and
`<leader>tF` the current test file (`tm`/`tf` run them without the debugger).
These entries share keys across languages; each language owns its target
selection (JS/TS tests use Vitest).

`<leader>dA` / `:DapAttach` attaches to an existing process, with presets for
Go, Python, Java, C/C++, Rust, Node/Chrome, Dart/Flutter and Electron.

`<leader>d` covers breakpoints, stepping and sessions: `de` exception breakpoints,
`dL` logpoints, `dR` restart, `dD` disconnect while keeping the target running,
`du` the debug view, `dw` evaluate expression/selection, and `dW` add a watch.
The debug view opens in a tabpage of its own, so a session never rearranges
the windows you were editing in; stepping stays in whichever tabpage you are
in.
See the [debugging workflow](docs/MANUAL.md#debugging) for each language's
dependencies, launch/attach commands, tests and project `launch.json` examples.
Install the Dart/Flutter SDK separately.

#### LaTeX Workflow

LaTeX is split between two tools: **VimTeX** drives compilation/viewing/motions, while **texlab** provides LSP intelligence (completion, goto, label rename) and `chktex` linting. They are configured not to overlap — texlab's own build is disabled so only VimTeX compiles.

**One-time setup**

```bash
brew install --cask mactex-no-gui   # TeX Live: latexmk, latexindent, chktex
brew install --cask skim            # PDF viewer with SyncTeX
```

`texlab` installs itself through Mason the first time a file is opened — no extra step. For inverse search (click in the PDF → jump to source), set **Skim → Preferences → Sync → Preset: Custom**, Command `nvim`, Arguments:

```
--headless -c "VimtexInverseSearch %line '%file'"
```

**Daily use** — open any `.tex` file, then:

- `,Ll` — toggle continuous compilation (recompiles on save while running)
- `,Lv` — forward search: open/jump Skim to the cursor's line
- `,Lt` — table of contents; `,Lc` clean, `,Le` errors
- Save the file to auto-format with `latexindent` (toggle with `<leader>uf` for this file, `<leader>uF` for all)

The everyday actions are also one key shorter, in the LaTeX sections of the `,` which-key popup:

| Key | Action |
|-----|--------|
| `,b` | Compile (toggle continuous) |
| `,v` | View PDF in Skim |
| `,s` | Stop compilation |
| `,K` | Clean aux files |
| `,t` | Toggle table of contents |
| `,E` | Show error list |
| `,x` | One-shot `latexmk` build to PDF (the generic "Run file" key) |

TeX buffers also enable soft `wrap` and `spell` by default (toggle with `<leader>uw` / `<leader>us`).

### Keybindings

**Leader**: `Space` · **Actions / local leader**: `,` · **Cheat sheet**: `<leader>?`

Every key answers one question, and the prefix says which:

| Prefix | Question | Examples |
|--------|----------|----------|
| `;` | Which file / symbol / position do I want? | `;<space>` smart find, `;f` files, `;/` grep, `;s` symbols, `;c` git hunks, `;1`-`;9` Harpoon files |
| `,` | What can I do in this file / view? | `,a` code action, `,f` format, `,r` rename, `,o` organize imports (Go/Python); terminal-local `,1`-`,9` |
| `s` | What about this window? | `ss`/`sv` split, `sd` close, `se` editor window, `s=` equalize |
| `<leader>` | Everything else, by domain | `g` git, `G` GitHub, `d` debug, `t` test, `a` AI, `x` diagnostics, `m` manage, `s` session, `y` yank (paths, `path:line`, permalinks), `u` toggles, `b` buffer, `q` quit |

Frequent actions use short keys. Related commands can share a subgroup, such
as `,e…` for extraction and `,L…` for VimTeX; `<leader>` groups global domains.
Press any prefix and wait — which-key lists the current mappings.

The `,` menu separates general editing from the current language's operations
(imports/environment, compilation/preview, runtime control) and view actions.
A CodeDiff view adds two sections alongside the source file's language section:
its panel, layout and conflict keys, and the review keys (`,C` feedback, `,S`
/ `,U` stage / unstage a hunk, `,X` discard a hunk back to baseline).
The search-and-replace panel keeps its actions under `,S…`.
See the [filetype and view actions](docs/MANUAL.md#filetype-and-view-actions) for the full key list.
The local leader shares the comma menu; it is not a fifth prefix.

Unprefixed keys worth knowing:

| Key | Action |
|-----|--------|
| `f` / `F` | Flash jump / Treesitter jump (Normal + Visual; `df-`, `ct)` stay native) |
| `x` | Delete a character without touching the clipboard or yank history (Normal; swap two characters with `dlp`, not `xp`) |
| `<C-h/j/k/l>` | Move between windows — works from terminal input too |
| `<C-l>` in Insert | Accept the grey [AI suggestion](#inline-ai-completion) |
| `<C-,>` | Jump to the editor area, press again to return |
| `<C-/>` | Toggle terminal; `3<C-/>` selects terminal 3 from a file; `,1`-`,9` switch from terminal-Normal |
| `<S-h>` / `<S-l>` · `[b` / `]b` | Previous / next buffer |
| `[B` / `]B` | First / last buffer (bar order) |
| `<leader>b<` / `<leader>b>` | Move buffer left / right |
| `g` · `[` / `]` · `z` | Go to + LSP (from the symbol under the cursor) · prev/next thing · folds and spelling |
| `-` | Open the current directory in oil (edit it as text) |
| `q` · `g?` · `<C-s>` / `<C-v>` / `<C-t>` · `<M-p>` | In a picker, oil or the outline: close · list its keys · open below / beside / in a tab (the outline has no tab) · toggle the preview (picker, oil). Hidden files: `<M-.>` in a picker, `g.` in oil |
| `jk` (except lazygit) · `<C-]>` / `<C-\>` | Input-safe Escape; in Normal, use its input source |

Diff views live under `<leader>g`, each in a tabpage of its own (CodeDiff):

| Key | Opens |
|-----|-------|
| `gv` | Diff view: the status view (staged, unstaged, untracked, conflicts) |
| `gm` / `gM` | Diff against main branch / against a picked baseline or ref (branch, tag, commit)… |
| `gk` | Compare two (working tree/index/baseline/ref)… |
| `gK` | Save baseline… (named), for `gk` and `gM` |
| `gh` / `gH` | File / repo history (recent 100, no merges) |
| `gq` | Close the diff view in this tab |

`gd` / `gD` stay gitsigns' diff of the current file, in a split or inline;
either closes on a second press, and `gq` closes the split as well.
Inside a view `;`, `s` and the keys that switch a window's buffer (`H` / `L`,
`[b` / `]b`, `[B` / `]B` (first / last buffer), `<C-^>`, and `-` outside the
status view's file panel, where it stages) are disabled, since a picker, a
buffer switch or a window key would break its panes; `q` in its file panel closes it too. The
[manual](docs/MANUAL.md#git) has what each view's `,` keys do.

**→ [docs/MANUAL.md](docs/MANUAL.md) walks through all of it**, starting with the
composition rules the keys are built on.

### Terminal Integration

Native coding-agent terminals no longer resize automatically when entering
Terminal-mode, so moving into one with `<C-h/j/k/l>` does not produce a one-row
flash. If a TUI drifts, exit terminal input with `<C-]>` (or `jk`) and use
`<leader>md` to repair it. Opening a numbered bottom terminal still repairs the
visible agent after the layout changes.

`<C-]>` is the uniform, input-method-safe exit key: in Editor Insert mode it
acts as `<Esc>`; in every terminal, including Codex panels, it reaches
terminal-Normal without sending the chord to the child process. In Normal mode
it remains an Escape instead of invoking Nvim's native tag jump and also returns
a manually selected input method to the Normal-mode layout, so it never turns
the word under the cursor into an `E426` lookup.
`help` and `man` buffers keep the builtin tag jump, since `<C-]>` is how they
follow a link and they have no second key for it; `<Esc>` and `<C-\>` still
clear the search highlight there.

`<C-h/j/k/l>` is owned by Neovim in both Normal and terminal-input mode, so it
can move directly between editor and terminal windows. This replaces the TUI's
original Ctrl shortcuts; use Backspace for delete-backward, `<S-Enter>` for a
newline in the agent's input box, and arrow keys in pickers. `<C-S-l>` forwards the original
Ctrl+L byte to redraw the Codex TUI; Nvim's own
clear-and-repaint (`:mode`) moves to `<leader>ur` in Normal mode. At a layout edge the
key is a no-op that keeps terminal input active, and a floating terminal
(lazygit, a float-shaped `<C-/>` shell) counts as all edges — otherwise a
shell's own `<C-h>` or `<C-l>` would jump out from under the float.

Because `<C-\>` sits beside `<C-]>`, it performs the same safe Escape in Normal,
Insert, Visual, and terminal-input modes. Repeated presses remain harmless in
Normal mode: they neither change modes nor overwrite the source awaiting
restoration, so either adjacent chord can be used without an accidental window
jump.

`<C-,>` jumps directly from terminal input or a sidebar to the editor window.
Pressing it from the editor returns to the source window. It relies on the
extended-key protocol negotiated by Ghostty and Nvim to remain distinct from a
plain comma; an outer tmux must have `extended-keys` enabled. Where that
protocol is unavailable — a bare Terminal.app, an ssh session, an older tmux —
`se` does the same jump with plain keys. Terminal numbers avoid the protocol
altogether: terminal-local `,1`-`,9` are plain keys because Ghostty encodes Ctrl+digit as
legacy bytes under an outer tmux, so the old `<C-1>`-`<C-9>` chords never
arrived there.

The number mappings exist only in terminal buffers, in Normal mode (`jk` or
`<C-]>` first from terminal input). Ordinary files show their language actions
in the same comma menu. From a file, use `<C-/>` to reopen the last terminal, or `3<C-/>` to
select terminal 3 directly.

Inside an agent panel, `<Esc>` belongs to the agent, not to Nvim. Both CLIs read
a quick double Esc as "go back a message", so neither Snacks' double-tap nor the
global `<Esc><Esc>` applies there. `<C-]>` or the adjacent `<C-\>` reaches
terminal-Normal, `jk` does the same without a modifier, and `<C-,>` jumps
straight back to the editor. Ordinary `:terminal` buffers keep `<Esc><Esc>`.

A click inside an agent panel also stays in terminal-input mode. Nvim only hands
a mouse event to the terminal job when that job asked for mouse reporting, and
neither TUI does, so without this a click -- including the one that returns focus
to the terminal window after switching apps -- left the panel in Normal mode.
Under the tmux wrapper tmux asks for it and handles the click itself; without the
wrapper Nvim swallows clicks that land in the panel. Clicking a different window
still moves there.

An agent that fails to start keeps its panel open with its own error still on
screen, and closes on the next `<Enter>`. Both wrappers end with tmux teardown
that reports success to Nvim however the agent exited, so without this the panel
closed silently and the message went with the tmux server -- nothing reached
`:messages` either.

Scrollback works the same way under both agents, because both wrappers run
tmux with `mouse on` and a 50000-line history. tmux owns the real transcript;
Nvim's terminal buffer only holds the screenful tmux last composed, so scrolling
goes through tmux. Stay in terminal-input mode and use the mouse wheel or
`<PageUp>` to enter tmux copy-mode; scroll down with the wheel or `<PageDown>`,
then press `q` or `<Esc>` to return to the agent's input. Leaving terminal input
and entering it again by any Normal-mode entry key (`i`, `a`, `I`, `A`, and so
on) also exits copy-mode and snaps to the live bottom. If you are already in
terminal-Normal mode, the same scroll keys -- plus `<C-u>`/`<C-d>` -- are
forwarded to tmux and terminal input is restored without exiting copy-mode, so
the next wheel event continues through the history. With `CLAUDE_WRAP_TMUX=0`
or `CODEX_WRAP_TMUX=0` there is no tmux to ask, so use `jk` and Nvim's normal
scroll commands instead.

Codex runs with `--no-alt-screen --yolo` inside Nvim. YOLO mode bypasses Codex
approvals and its built-in sandbox, while `--no-alt-screen` lets completed chat
output enter the wrapper tmux history.

#### AI keys

The first release enables **Codex only** as a native CLI. The local
[agent-workbench.nvim](local-plugin/agent-workbench.nvim/README.md) is loaded by
lazy.nvim like the other plugins. Claude support is a later extension;
claudecode.nvim and its `aa`/`ad`/Oil `aS` keys are removed.

The right side of each tab shows at most one native terminal or CodeCompanion
chat. These keys act on that visible chat; from a CodeDiff view they use the
origin tab. With no visible target, delivery asks which open chat to use.

| Key after `<leader>` | Mode | Action |
| --- | --- | --- |
| `an` / `al` | n,x | New AI chat / switch open chat; Visual context goes along |
| `ac` / `af` | n | Hide/restore the last chat / focus it |
| `ab` / `as` | n / x | Add file / captured selection without submitting |
| `ai` | n,x | Edit the prompt in this Nvim; Visual context seeds it |
| `ar` / `aR` / `am` | n | Resume / continue / select model; running session is reused |
| `at` / `aT` | n | Read current / choose native transcript |
| `av` / `aV` | n | Review changes since a round / take a manual round baseline |
| `ae` / `ax` | n,x / n | HTTP inline edit / switch HTTP key profile |
| `ao` | n | Browse saved CodeCompanion chats |

`<leader>an` offers Codex terminal, Codex ACP (when `codex-acp` is installed),
and OpenAI HTTP (when `NVIM_OPENAI_API_KEY` is set). Entries show transport and
billing. The native session is one per Nvim; choosing it again reuses it.
Additional HTTP profiles can be declared in `config/ai.lua`. No native Claude
entry can be enabled by configuration alone.

#### Editing the prompt in a buffer

`<leader>ai` and Codex's own `ctrl+g` use the same `$EDITOR` handoff through
`local-plugin/agent-workbench.nvim/scripts/agent-editor`. The TUI supplies its
actual draft; edit in a normal buffer, then `<C-d>` writes it back and closes
the editor. Cancel keeps the previous input. `<C-v>` stages an image from the
clipboard for Codex. A prompt from another program (such as `git commit`) has
no agent owner and accepts no agent seed/image.

A running session's model key only focuses it and tells you to use `/model`;
it types nothing into a possible draft or approval. A cold model start can
submit `/model` into its fresh input box. Resume/continue do not toggle away an
already running session.

#### `@` file mentions

`<leader>ab` inserts a relative file reference. Codex reads a mention from disk;
a modified buffer produces a warning. `<leader>as` captures the selection
before any asynchronous picker. Saved selections use a file/range reference;
unsaved selections send their exact text and say so. Neither operation presses
Enter. Directory-listing selections are explicitly unsupported in this release.
CodeCompanion HTTP chats receive buffer text; ACP chats receive paths and warn
about unsaved changes.

#### Attaching images

Inside the native prompt editor, `<C-v>` captures a clipboard image. On delivery,
Codex's own paste path attaches it after the editor closes. Attachments belong
to that prompt's agent and are cleaned on cancellation/failure. File context and
image paste are separate actions from a picker's vertical-split `<C-v>`.

#### Reading past output

`<leader>at` reads Codex's JSONL transcript; `<leader>aT` chooses an older one.
The transcript is a read-only view, independent of terminal scrollback.
Historical Claude records are still parsed for older review labels/transcripts;
this does not enable a Claude terminal.

#### AI chats and providers

Edit `lua/config/ai.lua`. Its ordered providers offer any of native `tui`, ACP,
and HTTP `api`. The picker groups native terminals, ACP, HTTP, in provider order.
No launcher flag chooses a backend. `:AI` switches chats, `:AI new` creates one,
`:AI info` / `:AIInfo` show status and billing, and `:AI key [name]` switches the
HTTP key for inline/cmd prompts only. The profile is not persisted.

`terminal.provider` selects `"snacks"` (this host), `"native"` (no Snacks needed),
or a custom embedded provider table. The plugin owns identity/session state;
Snacks is an optional view adapter. `native.codex` declares executable, argv and
tmux preference. Existing `--no-alt-screen --yolo` defaults are retained.

Showing a chat hides another only in this tab and preserves its process/session.
A chat visible in another tab is gone to, with a notice. A terminal copy in this
tab stays the target here and cannot hide its owner's window elsewhere. The
last normal window is never hidden; notification/preview floats do not count.

Local native plugins come from `plugin_dirs` or `NVIM_AI_PLUGIN_DIR`; resolution
and installation happen only at native launch. Codex installation uses a
disposable CLI home sharing the real plugin cache. Nothing writes user CLI
configuration or globally enables a plugin.

#### CodeCompanion: agent chat and API chat

ACP runs the CLI bridge on the subscription; HTTP spends API credits. They are
additional chat/inline workflows, with the same per-tab slot. Their adapter is
fixed at chat creation. HTTP adapters use `NVIM_*` keys; Codex ACP uses
`auth_method = "chat-gpt"`. A CLI billing variable such as `OPENAI_API_KEY` may
change CLI billing and is shown as a warning. Switching an HTTP key never starts,
stops or moves the native terminal or an existing chat.

`codecompanion-history` stores local transcripts. Resuming the stateful ACP
agent session is a separate `/resume` operation. CodeCompanion's separate code
review is disabled; all review baselines use `refs/nvim-review/`.

#### `Shift+Enter` (iTerm2)

Terminal input must deliver modified Enter as CSI u to the TUI. Configure the
outer terminal's key mapping when needed; the tmux wrapper preserves it. Normal
terminal `<C-h/j/k/l>` remain window navigation and `<C-d>` remains the prompt
editor's submit action, rather than a picker-open action.

#### Native-agent tmux wrappers

Codex's tmux renderer composes synchronized TUI updates and keeps scrollback.
It is independent of `terminal.provider`; both built-in providers can use it.
`CODEX_WRAP_TMUX=0` or `native.codex.wrap_tmux = false` disables it. `EDITOR`,
`VISUAL`, `NVIM`, CLI arguments, CJK text and modified Enter are preserved.
`agent-run` keeps startup failures visible; `agent-teardown` and the watchdog
clean the owned server and descendant processes. Hide preserves the session;
explicit stop or quitting Nvim tears it down.

#### macOS input method

When `macism` is available, Nvim keeps Normal and Terminal-Normal modes on the
detected Latin keyboard layout. Entering Insert or terminal-input mode
restores the input source that was active before leaving it; leaving those modes
captures the current source before switching back to English. This preserves
both cases: English stays English, while Sogou/Apple Pinyin is restored after
returning to text entry.

If an input method is selected manually while already in Normal mode, press
`<C-\>` or (outside `help`/`man`) `<C-]>` to capture it and return to the Normal
layout without leaving Normal mode. The next Insert or terminal-input entry
restores that source only when Nvim actually switched it away. Repeating the
key is idempotent; if the Normal layout was already active, entering input mode
does not apply a stale saved source.

The Normal-mode layout comes from `NVIM_ENGLISH_INPUT_SOURCE`, falling back to
an enabled macOS keyboard layout — a Latin one in preference to whatever the
system lists first — and then to the last-used layout.
There are deliberately no `FocusGained`/`FocusLost` hooks, so moving between
Nvim and another application does not rewrite the other application's
input-source state.

`NVIM_MACISM_WAIT_TIME_MS=0` disables macism's temporary focus window and its
visible Ghostty focus flash. This trades away macism's CJK activation workaround
and may let the first characters through as English on macOS 26; leave the
variable unset to use macism's built-in wait (currently 150ms).

### Inline AI completion

While you type in a file, a grey suggestion for the rest of the line appears
after the cursor. `<C-l>` accepts it; typing on keeps it in step while your text
still matches, and otherwise a fresh one replaces it. The suggestions come from
Qwen2.5-Coder 7B running in llama.cpp on this machine — no account, no API key,
nothing leaves the computer — and have nothing to do with the AI providers or
the chat on the right.

The model is downloaded once (the `llama-server` line under
[Requirements](#requirements)) into the Hugging Face cache,
`~/.cache/huggingface/hub`. The first Insert in a file starts one
`llama-server` that every Nvim shares; it takes a few seconds to load, and the
suggestion for where the cursor stands then appears without another keystroke.
It runs with `--offline`, so
it never reaches the network or swaps in a newer model by itself. A suggestion
takes about 0.35 s while you type along a line and 0.8 s at a new position.
After five idle minutes the server releases the model and reloads it, in about
half a second, for the next suggestion; it exits a few seconds after the last
Nvim does. Headless Nvim never starts it.

Markdown, plain text, commit messages and rebase lists get no automatic
suggestions, and neither do buffers without a filetype (`:enew` until `:setf`)
or terminals, pickers and panels. `:Minuet virtualtext toggle` switches them on
or off for the current file buffer. Troubleshooting is in
[`docs/DIAGNOSTICS.md`](docs/DIAGNOSTICS.md#inline-completion-ghost-text).

### API keys

Native Codex and Codex ACP use the ChatGPT login. Set `NVIM_OPENAI_API_KEY`
only for OpenAI HTTP chats and inline/cmd prompts; these spend API credits.
`OPENAI_API_KEY` is the CLI's own billing variable and can override subscription
authentication. The picker and health check warn while it is set. No billing
variable is written by this config.

`key_profile = "auto"` selects the first configured HTTP profile with a key,
else the first profile. A nonempty `NVIM_AI_KEY_PROFILE` overrides
`vim.g.ai_key_profile`, then the data file. `:AI key <name>` pins a profile for
this process; `:AI key auto` resolves again. Extra API-only profiles may use
other `NVIM_*` variables. Built-in Anthropic/OpenAI adapters also use `NVIM_*`
when restoring historical chats; no CLI key is used as a silent fallback.

### Configuration

Edit data under `lua/config/`, then restart. Runtime validation and application
belong to the local plugins, initialized through their lazy.nvim specs.

| File | Editable policy |
| --- | --- |
| `options.lua`, `behaviors.lua` | Editor preferences and optional behaviors |
| `keymaps.lua` | Core/AI keys, shared open actions, leaders and ghost-text accept key |
| `theme.lua`, `dashboard.lua` | Colorscheme, UI preferences and dashboard content |
| `ai.lua`, `review.lua` | Provider/terminal/native launch choices and round/delivery policy |
| `git.lua` | History limit, snapshot size and saved-baseline retention |
| `completion.lua` | Local model, argv, port and ghost-text preferences |
| `whichkey_spec.lua` | Display groups/sections; actual mappings do not depend on which-key |

Live `vim.g.ai_review` remains supported. Legacy Git fields in that override
still take precedence, while their editable defaults now belong to `git.lua`.
`vim.g.terminal_position` remains `"float"` or `"bottom"`, chosen at startup.
Internal options required for safety, terminal compatibility, view ownership and
plugin coordination live with the runtime owner. Public plugin options and
independent usage are documented in each local package and [UTILITIES](docs/UTILITIES.md).

### Environment Variables

| Variable | Description |
|----------|-------------|
| `NVIM_AI_KEY_PROFILE` | Startup HTTP key profile: `auto` (default; the first provider whose `NVIM_*` key is set), `anthropic`, `openai`, or another provider's `api.name` in `lua/config/ai.lua`; an unknown name warns and falls back to `auto`. `:AI key` switches it |
| `NVIM_ANTHROPIC_API_KEY` | Key of the `anthropic` profile, for CodeCompanion's API chats and inline/command prompts. See [API keys](#api-keys) |
| `NVIM_OPENAI_API_KEY` | Key of the `openai` profile |
| `NVIM_ENGLISH_INPUT_SOURCE` | macOS input-source ID used in Normal mode; falls back to an enabled keyboard layout reported by macOS, preferring a Latin one |
| `NVIM_MACISM_WAIT_TIME_MS` | Optional macism CJK workaround wait; `0` removes the temporary focus window at the cost of possible first-character races |
| `NVIM_LOG_LEVEL` | `editor_core.logger` threshold: `DEBUG`/`INFO`/`WARN`/`ERROR` (default `WARN`) |
| `NVIM_DEV=1` | Sets `editor_core.logger` to `DEBUG` (verbose logging) |
| `CODEX_WRAP_TMUX` | `1`/`0` — override default Codex tmux wrap. Default on. See [native-agent tmux wrappers](#native-agent-tmux-wrappers). |

### Diagnostics

For troubleshooting (slow startup, LSP not attaching, missing formatter, etc.) see [`docs/DIAGNOSTICS.md`](docs/DIAGNOSTICS.md). Run `:checkhealth config` to verify external dependencies, key Mason packages, and the Neovim version.

### Customization

Each module owns one focused feature. Editable AI defaults live in
`ai/config.lua` and `ai/review/config.lua`; their runtime state/resolution lives
in `ai/state.lua` and `ai/review/settings.lua`. Plugin specs wire feature
modules together. Language modules own their complete language integration.

**Add a plugin** — create a file in the appropriate `lua/plugin/*/` directory.

**Add language support, an LSP server, or a formatter** — create or edit the
matching contribution in `lua/plugin/lang/`. Language files extend the shared
`nvim-lspconfig`, Conform, lint, Treesitter, DAP, and test specs; the files in
`lua/plugin/coding/` contain editor-wide defaults only.

**Add, remove or reorder an AI provider** — edit the `providers` list in
`lua/config/ai.lua` ([AI chats and providers](#ai-chats-and-providers)). A
provider whose `acp` and `api` name adapters CodeCompanion already has needs
only the entry; a native terminal of a new kind needs code.

**Tune file/grep search scope** — the file (`;f`) and grep (`;/`) pickers show hidden **and** gitignored files (`hidden`/`ignored` in `lua/plugin/editor/snacks.lua`). `.git/` is always excluded; heavy build/dependency dirs (`node_modules`, `target`, `.venv`, `Pods`, …) are skipped via the shared `search_exclude` list in the same file. Add a dir to that list to hide it, or remove one to search it. Note: `exclude` drops any dir of that name unconditionally — even git-tracked source — so generic names (`bin`, `out`, `vendor`) are intentionally left out.

Use `;i` (files) or `;?` (text) to respect `.gitignore` instead, with hidden files
still visible and no extra directory exclusions. Under Manage, `<leader>mf`
searches this configuration and `<leader>mF` searches installed plugin source files.

## License

This configuration is provided as-is for personal use.
