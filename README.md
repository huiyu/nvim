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
- **[Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview)** and/or **[Codex](https://developers.openai.com/codex/cli/)** — native coding agents; either can run, alongside CodeCompanion chats, started with `<leader>an` ([AI chats](#ai-chats-and-providers))
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
- **JDK 25+** — runs `jdtls` (Java); projects may still target older releases. Found through `$JAVA_HOME`, then [SDKMAN!](https://sdkman.io/) (`~/.sdkman/candidates/java`), then PATH (see [`lua/lang/java.lua`](lua/lang/java.lua))
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

```
~/.config/nvim/
├── AGENTS.md                # Repository guidance for coding agents
├── CLAUDE.md                # Claude Code import of AGENTS.md
├── init.lua                  # Entry point
├── lua/
│   ├── options.lua           # Vim options
│   ├── mappings.lua          # Imperative core keymaps (side effects)
│   ├── whichkey_spec.lua     # which-key groups, popup sections, spec keymaps (data)
│   ├── autocmds.lua          # Autocommands
│   ├── bootstrap.lua         # lazy.nvim setup
│   ├── ai/                    # AI state, the chat slot, native Claude/Codex backends, CodeCompanion chats, review rounds (ai/review/)
│   ├── config/
│   │   └── health.lua        # `:checkhealth config` provider
│   ├── lang/                 # Language-specific configs
│   │   ├── bash.lua
│   │   ├── dart.lua
│   │   ├── rust.lua
│   │   ├── c.lua             # C / C++
│   │   ├── frontend.lua      # HTML / CSS / Tailwind
│   │   ├── go.lua
│   │   ├── java.lua
│   │   ├── json.lua
│   │   ├── python.lua
│   │   ├── tex.lua           # LaTeX (VimTeX + texlab)
│   │   ├── typescript.lua    # JS / TS language (LSP, format, DAP)
│   │   └── yaml.lua
│   ├── plugin/
│   │   ├── editor/           # Editor enhancement plugins
│   │   ├── lsp/              # LSP, completion, formatting, debugging
│   │   ├── ui/               # UI and theme plugins
│   │   └── vcs/              # Git integration
│   └── util/                 # Utility modules
├── .github/workflows/       # CI: spec suite + a headless startup check
├── scripts/                 # Agent TUI helpers, shared llama-server supervisor
├── tests/                   # Headless spec suite (tests/run.sh)
├── Makefile                 # Everyday commands: make test, make verify, ...
└── docs/                     # MANUAL.md, DIAGNOSTICS.md, UTILITIES.md
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
expects (the llama-server `util.llama` shares, git and gitsigns timing).

### Plugins

#### UI

| Plugin | Description |
|--------|-------------|
| [solarized-osaka](https://github.com/craftzdog/solarized-osaka.nvim) | Colorscheme |
| [lualine](https://github.com/nvim-lualine/lualine.nvim) | Status line with a `● REC @q` macro recording indicator, the buffer's git change counts (from gitsigns) and its language servers (a spinner while one is busy) |
| [incline](https://github.com/b0o/incline.nvim) | Top-right filename labels in file windows; pink for the focused window, `[+]` for unsaved changes |
| [bufferline](https://github.com/akinsho/bufferline.nvim) | Buffer tabs with pin/close/pick (`;B` picks one by its tab letter); `<leader>bh` closes the buffers no window shows, in any tabpage |
| [treesitter](https://github.com/nvim-treesitter/nvim-treesitter) | Syntax highlighting, text objects |
| [treesitter-context](https://github.com/nvim-treesitter/nvim-treesitter-context) | Sticky function/class header (`<leader>uC`) |
| [nvim-ts-autotag](https://github.com/windwp/nvim-ts-autotag) | Auto-close HTML/JSX tags |
| [nvim-ufo](https://github.com/kevinhwang91/nvim-ufo) | Modern code folding |
| [statuscol](https://github.com/luukvbaal/statuscol.nvim) | Gutter with fixed slots for breakpoints, diagnostics and git signs; click a sign, line number or fold to act on it |
| [todo-comments](https://github.com/folke/todo-comments.nvim) | TODO/FIXME highlights |
| [illuminate](https://github.com/RRethy/vim-illuminate) | Highlight word under cursor; `]r` / `[r` jump to its next / previous reference |
| [colorizer](https://github.com/catgoose/nvim-colorizer.lua) | Hex/RGB/HSL and CSS variable previews; Tailwind colors in frontend files |
| [render-markdown](https://github.com/MeanderingProgrammer/render-markdown.nvim) | In-editor markdown rendering (`,m`) |

The command line and messages are Neovim's own ui2 (experimental, `:help ui2`):
no "Press ENTER" prompt; output that does not fit collapses to `[+N]`, and
`g<` or `:messages` opens it in a pager (`q` closes). Notifications come from
snacks below.

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
| [claudecode](https://github.com/coder/claudecode.nvim) | Native Claude Code integration (always declared, loaded on first use) |
| [CodeCompanion](https://github.com/olimorris/codecompanion.nvim) | [Agent chats](#codecompanion-agent-chat-and-api-chat) over ACP (on the subscription) and API chats over HTTP (on a key profile), started from `<leader>an`, plus inline/command prompts on the key profile |
| [codecompanion-history](https://github.com/ravitemer/codecompanion-history.nvim) | Auto-saved, project-aware CodeCompanion chat history |
| [minuet-ai](https://github.com/milanglacier/minuet-ai.nvim) | As-you-type AI ghost text from a local model ([inline AI completion](#inline-ai-completion)) |

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
acts as `<Esc>`; in every terminal, including Claude/Codex panels, it reaches
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
Ctrl+L byte to redraw either the Codex or Claude Code TUI; Nvim's own
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

AI keys live under `<leader>a`; the one in another popup, `,C` (review feedback) in a Git view's comma menu, starts its description with `[AI]`. The chat keys act on **the chat on the right** of the current tabpage — native Claude Code, native Codex or a CodeCompanion chat, whichever is shown there ([AI chats](#ai-chats-and-providers)) — so their descriptions name no agent. `ae`'s names the key profile it bills, and changes with `:AI key`; the Claude-only `aa` / `ad` and oil's `aS` say "Claude". A description ends in "…" when the key asks something before it acts (`an`, `al`, `ar`, `am`, `ae`, `ax`, `ap`); `aR` asks nothing, and the question every chat key may ask when nothing is on the right — which chat or agent — is not counted.

| Key | Mode | Does |
|-----|------|------|
| `an` | n, x | New chat: pick a backend — native terminal, ACP chat or API chat (`:AI new`) |
| `al` | n, x | Switch to another open chat (`:AI`) |
| `ac` / `af` | n | Toggle / focus the chat on the right |
| `ab` / `as` | n / x | Add the file / the selection to the chat on the right |
| `ai` | n, x | [Compose the prompt in a buffer](#editing-the-prompt-in-a-buffer) |
| `ar` / `aR` | n | Native agent: resume a past session (picker) / continue the latest |
| `am` | n | Native agent: select the model |
| `at` / `aT` | n | Native agent: [read the transcript](#reading-past-output) / browse past transcripts |
| `av` / `aV` | n | [Review the changes since the round's baseline](docs/MANUAL.md#reviewing-a-round-of-agent-changes) / start a round now; every prompt starts one |
| `aa` / `ad` | n | Accept / reject Claude's diff (once claudecode.nvim has loaded) |
| `aS` | n (oil) | Add the file under the cursor to Claude on the right |
| `ae` | n, x | Inline edit (`:CodeCompanion`) on the API key profile |
| `ax` | n | Switch the API key profile (`:AI key`) |
| `ap` | n, x | CodeCompanion action palette |
| `ao` | n | Browse saved CodeCompanion chats (a chat's `gh` is the same browser) |

From Visual mode `an` and `al` take the selection to the chat they open. The
native-agent keys act on the native agent on the right, else ask which one.

#### Editing the prompt in a buffer

`<leader>ai` opens the prompt of the chat on the right. A CodeCompanion chat's
prompt is a buffer already, so the cursor goes there (from Visual mode, after
the selection is added). A native agent's prompt opens in a floating buffer, so
a long prompt is written with the whole editor instead of the TUI's input box.
It exists because Terminal-mode gives `<C-h/j/k/l>` to window navigation,
which are exactly the agent TUI's editing keys.

| Key | Action |
|-----|--------|
| `<C-d>` | return the prompt to the agent (works from Insert mode) |
| `<C-v>` | attach the clipboard image |
| `<C-c>` | cancel, leaving the input box as it was |
| `:wq` / `ZZ` | return the prompt |
| `:q!` | cancel |

Whatever is already in the input box comes across, and from Visual mode the
selection is added to it first, in the form `<leader>as` types into Codex's box:
`@path lines X-Y`, or the exact text, fenced, from a buffer with unsaved changes.
Nothing is submitted — closing the buffer hands the text back to the box, and you
still press Enter yourself.

The float is modal: window navigation (`<C-h/j/k/l>`, `<C-w>`) and the adjacent
Escape chord (`<C-\>`) do not leave it, and a focus change that slips past that
is undone. While it is open
the agent is blocked on the editor and ignores its pty, so there would be no way
back otherwise — `<leader>ai` pressed again returns to the open prompt (adding a
Visual selection to it) instead of sending a `ctrl+g` the TUI would swallow.
Claude Code and Codex may each have a prompt open at once; the newer one keeps
focus.

This is not a buffer of ours: it is the agent's own `ctrl+g` ("edit this prompt
in `$EDITOR`"), which both Claude Code and Codex implement. `$EDITOR` points at
`scripts/agent-editor`, which opens the prompt in *this* Nvim instead of starting
a second one inside the `:terminal`. `<leader>ai` simply sends `ctrl+g` to the
TUI, so pressing `ctrl+g` there directly does the same thing.

Going through the CLI is what makes it exact. The CLI writes the box to a temp
`.md` file, waits for the editor, and re-reads it — so newlines survive, and the
CLI performs the write-back itself. Reading the box off the terminal screen
instead cannot work: a real newline and a soft wrap render identically in both
TUIs (a two-space-indented continuation line either way), so scraped text can
never be reassembled reliably.

`$NVIM` is what makes the round trip possible: Nvim sets it in every `:terminal`
child, and it holds the RPC socket back to the instance that owns the terminal.
The wrapper polls for a sentinel file rather than using `--remote-wait`, which
Nvim does not implement (`E5600: Wait commands not yet implemented in Nvim`).

If the agent is not running, `<leader>ai` starts it and waits for its input box
before sending the key — a `ctrl+g` fired at a booting TUI is swallowed with
nothing on screen to show for it. Readiness is the one thing read off the
rendered screen, and only as a trigger: being wrong costs a keystroke, not a
corrupted prompt.

#### `@` file mentions

Typing `@` plus a fragment completes project files, the way the TUIs' own input
box does. Candidates come from the project root this Nvim runs in and respect
`.gitignore` — `git ls-files`, falling back to `fd` and then `rg --files`; with
none of them available the menu simply stays empty. The query narrows over the
full relative path, slashes included, and accepting inserts `@path/to/file`.

An `@` directly after a word character is not a mention, so `jeff@gmail.com`
stays an email; other scripts do count as a boundary, so `看看@init` completes.
What the agent does with the text differs per agent: Claude Code parses the
returned `@path` into a real file mention on submit, Codex treats it as a path
its agent opens itself — both end up reading the file. The source lives in
`lua/ai/mention.lua` and is enabled only for these prompt buffers, so ordinary
markdown never sees it.

#### Attaching images

`<C-v>` in the prompt buffer stages the clipboard image; it attaches when you
return the prompt. Staged images show as virtual lines at the end of the buffer,
which are not buffer text — so they are visible while you write without being
sent as literal text. Pressing `ctrl+v` in the TUI itself still works too. macOS
only.

Nothing is written into the buffer, because the image cannot travel through the
prompt file — that is plain markdown, and only the CLI can put image bytes into
its request. So the staged file is replayed through the TUI's own `ctrl+v`, and
the CLI writes its own `[Image #N]` marker.

The replay waits until the buffer has closed. Measured: while the prompt is open
the agent is blocked on the editor and throws pty input away, so a `ctrl+v` sent
during the edit never arrives — the same one sent afterwards does. Cancelling
discards the staged files rather than bolting them onto a prompt you threw
away.

#### Reading past output

`<leader>at` renders the current project's newest session of the native agent
on the right (else the one you pick) into a read-only Markdown buffer, and
`<leader>aT` browses that project's past transcripts.
Inside the buffer, `R` re-reads from disk and `q` closes it. Prose is visible;
thinking and tool calls are folded, so `zR` opens everything and `za` opens one.

The source is the CLI's own JSONL transcript, not the terminal. Claude runs on
the alternate screen, so its tmux wrapper keeps no scrollback at all — there is
nothing to capture from the pane. Reading the recorded transcript is the only
approach that works for both agents, it survives restarting Nvim, and it
needs no change to the tmux wrappers.

Neither CLI persists its reasoning text, so folded "thinking" sections will
normally be absent rather than empty.

#### AI chats and providers

The right side of each tabpage shows at most **one AI window**: native Claude
Code, native Codex or a CodeCompanion chat — a *chat*, in the keys' words.
Showing one hides the others in that tabpage. Hidden is never stopped: a
running agent, or a chat in the middle of a reply, keeps going (and says so
when it is hidden mid-turn, or asks for a tool approval unseen). Other
tabpages are left alone.

- `<leader>an` (`:AI new`) starts a chat on any backend available here. Each
  entry says where it runs and who bills it: every terminal, then every ACP
  chat, then every API chat, each group in provider order (below):

  ```text
  Claude Code · terminal · subscription
  Codex · terminal · subscription
  Claude Code · CodeCompanion ACP · subscription
  Codex · CodeCompanion ACP · subscription
  Anthropic · CodeCompanion API · API credits
  OpenAI · CodeCompanion API · API credits
  ```

  A missing CLI, ACP bridge or `NVIM_*` key leaves its entry out. A native
  agent has one session per Nvim: its entry shows that session (*running*,
  *● here*) rather than start a second. A chat or session it starts is
  announced, billing included.
- `<leader>al` (`:AI`) lists the open chats — *● here*, *tab N* or *hidden*,
  with their billing — and *New chat…* last. A chat shown in another tabpage
  is gone to, never moved; a hidden one is shown here.
- `<leader>ac` hides the chat on the right; with nothing there it brings back
  the last one this tabpage showed (else the only open chat, else it asks).
  `<leader>af` goes into it — terminal input, or the chat's prompt — and
  never hides it.
- `<leader>as`, `ab` and `ai` go to the chat on the right. With none they
  ask: nothing is sent silently to a hidden chat, another tabpage's or an
  agent picked for you, and a cancel sends nothing. The selection is captured
  before the question, so it survives it. Claude Code gets a mention of the
  selected lines, Codex the `@path lines X-Y` mention typed into its box, a
  chat a fenced block in its prompt; nothing is submitted. Both agents read
  the saved file, so for a buffer with unsaved changes Codex gets the exact
  text instead and Claude Code a warning. `<leader>ab` is for the native
  agents; a chat takes a selection, or `#{buffer}` in its own prompt.
- From a CodeDiff view the keys act on the page the view was opened from,
  which becomes the current tabpage, so nothing opens inside the view; a
  question cancelled there goes back to it.
- Claude Code still sees the editor's selection while it is hidden:
  claudecode's selection tracking stays on, whatever the right shows.

`<leader>ar`, `aR`, `am`, `at` and `aT` belong to a native agent: the one on
the right, else the one you pick (the installed agents in provider order;
with one installed, that one). Each native agent has one session per Nvim, so
on an agent that is already running `ar`, `aR` and `am` show it and say how
to do it there (`/resume`, `/model`) instead of starting a second session;
nothing is typed into its box, which may hold a draft. A session they start
is announced. `at` and `aT` read the agent's records from disk, running or
not.

**Providers** are an ordered list in `lua/ai/config.lua`, set up the way
CodeCompanion's adapters are. Each names a vendor and the parts it offers; a
part left out is not offered:

| Part | Offers | Billed to |
|------|--------|-----------|
| `tui = { kind }` | A native terminal agent. `kind` is `claude` or `codex`, each at most once; another kind needs code (a backend module, a tmux wrapper, prompt hooks, a transcript reader), not just an entry | The subscription |
| `acp = { adapter, command, auth_method? }` | A CodeCompanion agent chat over ACP: `adapter` is CodeCompanion's ACP adapter, `command` the bridge it needs on PATH | The subscription |
| `api = { adapter, api_key, label?, model?, name? }` | A CodeCompanion API chat over HTTP on its built-in adapter `adapter`, and a key profile named `name` (default: `adapter`), which must be unique | API credits, on `api_key`, an `NVIM_*` variable |

The defaults are Claude (the `claude` terminal, `claude_code` through
`claude-agent-acp`, `anthropic` on `NVIM_ANTHROPIC_API_KEY`), then Codex (the
`codex` terminal, `codex` through `codex-acp` on the ChatGPT login, `openai` on
`NVIM_OPENAI_API_KEY`). The list is checked when Nvim starts, and a bad entry
stops startup with the provider's name.

There is no default backend: the order is the only preference. `<leader>an`
lists the terminals, then the ACP chats, then the API chats, each group in
provider order; a key only a native agent answers, with none on the right,
asks among the installed terminals in that order; CodeCompanion's own paths
that name no adapter (a typed `:CodeCompanionChat`, the action palette) use
the first `acp`, else the first `api`. To put Codex first, move its entry
above Claude's. No launch flag or environment variable picks an agent:
`NVIM_AI_PROVIDER` and `vim.g.ai_provider` are no longer read, and a leftover
value only earns a one-time warning. Nothing is saved: every Nvim starts from
the list and its environment.

The **key profile** decides which API key inline edits and command prompts
(`<leader>ae`, `:CodeCompanion`) bill. Each provider's `api` is one, named
`api.name` (default: `api.adapter`). `auto`, the default, is the first one
whose `NVIM_*` key is set when Nvim starts (or at `:AI key auto`, which
also picks again after a key was exported), else the first one: with the defaults, Anthropic, or OpenAI when only
`NVIM_OPENAI_API_KEY` is set. `:AI key <name>` and `NVIM_AI_KEY_PROFILE`
(optional) pin one. An API chat uses the profile its `<leader>an` entry names.

| Command | Does |
|---------|------|
| `:AI` / `<leader>al` | Switch to another open chat |
| `:AI new` / `<leader>an` | Start a chat on any available backend |
| `:AI key <profile>` / `<leader>ax` | Pin a key profile (without a name: a picker) |
| `:AI key auto` | Unpin: back to the first profile whose key is set |
| `:AI info` (or `:AIInfo`) | The providers in order with their parts (terminal · ACP · API, ✗ where one cannot start here), the adapter CodeCompanion's own chats use, the key, every profile's variable (set or not, never its value), the CLIs' own key variables, and every open chat with where it is |

A key switch moves inline edits and command prompts only: no chat, terminal or
ACP connection starts, stops, shows or hides, and an open chat keeps the
adapter it was created with. While a profile is pinned the statusline names it
(`󰌆 OpenAI`); click it to switch again. There is no `:AI provider` any more:
a new chat picks its backend in `<leader>an`, in the order of
`lua/ai/config.lua`.

Run `:checkhealth config` to see missing CLIs, ACP bridges, or HTTP
credentials, for every provider. A missing CLI or bridge is a warning, since
the picker just leaves it out; an unset `NVIM_*` key is one only for the
current key profile; only nothing available at all is an error.

`NVIM_AI_PLUGIN_DIR` loads comma-separated local plugin directories in the
native Claude/Codex terminals. A distribution root can supply separate host
packages; see [local native plugins](docs/MANUAL.md#local-native-plugins).

#### CodeCompanion: agent chat and API chat

CodeCompanion's chats live in a Neovim buffer, in two kinds that look alike
once open but run — and bill — differently. Both start from `<leader>an` and
take the same place on the right as the native terminals:

| | Agent chat · ACP | API chat · HTTP |
|---|---|---|
| Picker entries | `Claude Code · CodeCompanion ACP · subscription`, the same for Codex | `Anthropic · CodeCompanion API · API credits`, one per key profile |
| Talks to | The agent through its ACP bridge (`claude-agent-acp` / `codex-acp`) | The profile's API, directly over HTTP (`anthropic` / `openai`) |
| Billed to | Your Claude or ChatGPT subscription | [API credits](#api-keys), on the profile's `NVIM_*` key |
| Tools | The agent's own; `\` completes its slash commands | CodeCompanion's `@` tools, and its MCP servers (none are configured here) |
| Long chats | The agent manages its own context | `/compact`, and automatic compaction near the context limit |
| Saving | codecompanion-history (`<leader>ao`); `/resume` lists the agent's own sessions | codecompanion-history too, plus CodeCompanion's own sessions: `/save` stores the chat, `/resume` restores it; `/fork`, `/rename` |
| Reply header | `CodeCompanion (Claude Code · ACP)` | `CodeCompanion (Anthropic · API)` |

- A chat keeps the backend it was created with; another backend is another
  chat. Between two chats the window on the right is handed over in place.
- `<leader>as` adds a Visual selection to the chat on the right as a fenced
  code block, without submitting it; `<leader>ai` puts the cursor in its
  prompt (from Visual, after adding the selection).
- In a chat, `<CR>` sends (`<C-d>` from Insert mode) and `<C-c>` stops the
  reply. `q` hides the chat, as `<leader>ac` does, which brings it back;
  `,q` ends it, and CodeCompanion shows another open chat in its window.
  `,X` clears the messages, `,z` folds the code blocks, `,s` saves the chat,
  `gf` opens the file under the cursor and `?` / `g?` list every key.
  Insert `<C-c>` leaves Insert mode, `gx` opens a URL and `{` / `}` move by
  paragraph, as everywhere; another chat is `<leader>al`.
- `<leader>ae` opens `:CodeCompanion ` (with the range, from Visual mode) on
  the key profile, and `<C-c>` stops its request; with no prompt it asks in a
  float, where `<CR>` (or `<C-d>` from Insert mode) sends and `q` / `<Esc>`
  close. `<leader>ap` is the action palette.
- A missing key is caught before anything starts: `<leader>an` leaves out an
  API chat whose `NVIM_*` key is unset and an agent chat whose bridge is
  missing, and `<leader>ae` says so instead of a request that fails with 401.
  A chat restored from history, the action palette's *Inline prompt*
  (`<leader>ap`) and `:CodeCompanion` typed by hand skip this check.
- CodeCompanion's own commands that name no adapter (a typed
  `:CodeCompanionChat`, the palette's chat) start a chat on the first `acp` in
  provider order (Claude Code, with the defaults), else on the first `api`;
  whatever else was on the right gives way to it.
- Codex ACP uses the ChatGPT login: CodeCompanion's built-in `codex` ACP
  adapter gets `auth_method = "chat-gpt"` whatever the provider list holds, so
  a chat restored from history does too, and a provider's own
  `acp.auth_method` overrides it. codex-acp's own default would bill
  `OPENAI_API_KEY`.

codecompanion-history saves every chat, of either kind, when a message is
sent and when a reply finishes. Open one with `<leader>ao` (or
`:CodeCompanionHistory`); inside a chat, `gh` opens the same browser. Entries
use the Snacks picker: `r` renames one, `dd` (or `<C-x>` while typing)
deletes it, as in the buffer picker; model-generated titles are off to
avoid an extra request. History restores CodeCompanion's local transcript. To
continue the agent's actual stateful session, use `/resume` in a fresh agent
chat.

#### `Shift+Enter` (iTerm2)

When running terminal apps inside Neovim (e.g. Claude Code), `Shift+Enter` requires iTerm2 configuration:

**iTerm2 setup**: Settings → Profiles → Keys → Key Mappings → Add:
- **Shortcut**: `Shift + Return`
- **Action**: `Send Escape Sequence`
- **Value**: `[13;2u`

#### Native-agent tmux wrappers

Claude Code and Codex are launched inside provider-specific, dedicated tmux
servers. See `lua/plugin/lsp/ai.lua` and `lua/ai/backend/codex.lua`.

**Why**: both TUIs emit DEC mode 2026 (Synchronized Output) escape sequences for
atomic frame updates. Nvim's `:terminal` buffer does not understand this
protocol, so without a wrapper a partial frame can leave duplicated status bars
or stale cells. tmux composes the synchronized frame and sends ordinary terminal
updates to Nvim. This is independent of the host terminal because the relevant
layer is Nvim's embedded libvterm.

**Trade-off**: Inside the wrapped tmux, CJK wide-character widths can disagree
between tmux, the host terminal, and the agent TUI. This can produce minor
misalignment in box-bordered UI.

**Keys**: both wrappers run tmux with `extended-keys always` and
`extended-keys-format csi-u`. tmux's default (`extended-keys off`) turns the
`ESC[13;2u` that `<S-Enter>` sends into a bare Enter, which submits the message
instead of inserting a newline. `always` keeps the modifier without waiting for
the TUI to request it, and CSI u is the form both Claude Code and Codex parse.
Every key with a legacy encoding reaches the TUI unchanged.

**Teardown**: closing the panel or quitting Nvim runs `scripts/agent-teardown`,
which kills the wrapper server and then whatever the agent left running in
process groups of its own -- a Codex `exec_command` dev server, a background
Bash job -- since tmux only signals the pane's own process. Shared daemons the
agent may have started (emulator, Gradle daemon, container runtime) are spared;
set `NVIM_AGENT_TEARDOWN_IGNORE` to an awk regex to change that list. Runs are
logged to `~/.local/state/nvim/agent-teardown.log`.

**Overrides**:
- `CLAUDE_WRAP_TMUX=0 nvim` — disable for one-off A/B testing
- `vim.g.claude_wrap_tmux = false` in `init.lua` — disable permanently
- `CODEX_WRAP_TMUX=0 nvim` / `vim.g.codex_wrap_tmux = false` — equivalent Codex overrides
- Both wrappers default to on when tmux is installed

**Tip — suppress the recap CJK box**: Claude Code's session recap is the most visible CJK width offender. Set `"awaySummaryEnabled": false` in `~/.claude/settings.json` to suppress it. This is Claude Code's global config, not nvim's.

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

The agents need no key: Claude Code and Codex — the native terminal and the
agent chat alike — run on your Claude or ChatGPT login. A key is only for
CodeCompanion's API chats and its Inline and command prompts (`<leader>ae`,
`:CodeCompanion`), which call the API directly: an API chat with the profile
its `<leader>an` entry names, inline and command prompts with the
[key profile](#ai-chats-and-providers) — under `auto`, the first provider
whose key is set (Anthropic before OpenAI, with the defaults); `:AI key` pins
another.

| Variable | Key profile | Key from |
|----------|-------------|----------|
| `NVIM_ANTHROPIC_API_KEY` | `anthropic`, Claude's `api` (`auto` whenever it is set) | [Anthropic Console](https://platform.claude.com/) → API keys |
| `NVIM_OPENAI_API_KEY` | `openai`, Codex's `api` (`auto` when only this one is set) | [OpenAI Platform](https://platform.openai.com/api-keys) |

A second key for the same API is one more provider in `lua/ai/config.lua`
with only an `api` part: its own `api.name` and an `NVIM_*` variable of its
own (the file has a commented example). It then shows up in `<leader>an` as an
API chat and in `:AI key`.

Never use `ANTHROPIC_API_KEY` or `OPENAI_API_KEY` for this. They are the
CLIs' own variables, and with one in the environment the agents started from
that shell or from Nvim can bill the API instead of your subscription. This
config does not read them, refuses a key profile that names one, and
`:checkhealth config` warns while either is set. CodeCompanion's built-in
`anthropic` and `openai` adapters are pointed at `NVIM_ANTHROPIC_API_KEY` and
`NVIM_OPENAI_API_KEY` whatever the provider list holds, so a chat restored
from history never reads a CLI's variable either.

1. Create a key for Nvim alone, so it can be revoked on its own. Spend limits
   belong to the container, not the key: to cap it, create the key in an
   Anthropic workspace (or OpenAI project) of its own with a limit set. The
   Console's identity-federation option is for cloud and CI workloads; choose
   *Continue with an API key*.
2. Export it from a shell startup file that is never committed — for example a
   gitignored file your `.zshrc` sources:
   ```sh
   export NVIM_ANTHROPIC_API_KEY="sk-ant-..."
   export NVIM_OPENAI_API_KEY="sk-proj-..."   # only if you use the openai profile
   ```
3. Open a new shell, start Nvim from it, and run `:checkhealth config`: the
   *AI backends* section reports the key as found.

The name keeps the agents from billing against the key, but not from seeing
it: like any exported variable it reaches every process Nvim starts,
agent terminals included. Keep it out of anything you commit or share.

### Configuration

Set these in `init.lua` before plugins load.

| Option | Description |
|--------|-------------|
| `vim.g.terminal_position` | `"float"` (default) or `"bottom"`. Where numbered terminals open. Chosen once, not toggled at runtime — Snacks fixes a window's shape when it opens one and edgy decides separately whether a terminal belongs to its bottom edge, so a runtime toggle means keeping those two in agreement through every hide, show and relayout. |
| `vim.g.ai_review` | The review loop and the diff views: how many rounds and baselines to keep, which conversations open rounds, how delivery confirms, where native Claude starts, how much history `<leader>gh` / `<leader>gH` list. Name only the keys you change, e.g. `{ retention = { rounds = 30 } }`; every key and default is in the [manual](docs/MANUAL.md#settings-vimgai_review). |

### Environment Variables

| Variable | Description |
|----------|-------------|
| `NVIM_AI_KEY_PROFILE` | Startup HTTP key profile: `auto` (default; the first provider whose `NVIM_*` key is set), `anthropic`, `openai`, or another provider's `api.name` in `lua/ai/config.lua`; an unknown name warns and falls back to `auto`. `:AI key` switches it |
| `NVIM_ANTHROPIC_API_KEY` | Key of the `anthropic` profile, for CodeCompanion's API chats and inline/command prompts. See [API keys](#api-keys) |
| `NVIM_OPENAI_API_KEY` | Key of the `openai` profile |
| `NVIM_ENGLISH_INPUT_SOURCE` | macOS input-source ID used in Normal mode; falls back to an enabled keyboard layout reported by macOS, preferring a Latin one |
| `NVIM_MACISM_WAIT_TIME_MS` | Optional macism CJK workaround wait; `0` removes the temporary focus window at the cost of possible first-character races |
| `NVIM_LOG_LEVEL` | `util.logger` threshold: `DEBUG`/`INFO`/`WARN`/`ERROR` (default `WARN`) |
| `NVIM_DEV=1` | Sets `util.logger` to `DEBUG` (verbose logging) |
| `CLAUDE_WRAP_TMUX` | `1`/`0` — override default Claude Code tmux wrap. Default on. See [native-agent tmux wrappers](#native-agent-tmux-wrappers). |
| `CODEX_WRAP_TMUX` | `1`/`0` — override default Codex tmux wrap. Default on. See [native-agent tmux wrappers](#native-agent-tmux-wrappers). |
| `CLAUDE_CHROME` | `1`/`0` — enable or disable Claude in Chrome for the native Claude process. Default on. |

### Diagnostics

For troubleshooting (slow startup, LSP not attaching, missing formatter, etc.) see [`docs/DIAGNOSTICS.md`](docs/DIAGNOSTICS.md). Run `:checkhealth config` to verify external dependencies, key Mason packages, and the Neovim version.

### Customization

**Add a plugin** — create a file in the appropriate `lua/plugin/*/` directory.

**Add language support, an LSP server, or a formatter** — create or edit the
matching contribution in `lua/lang/`. Language files extend the shared
`nvim-lspconfig`, Conform, lint, Treesitter, DAP, and test specs; the files in
`lua/plugin/lsp/` contain editor-wide defaults only.

**Add, remove or reorder an AI provider** — edit the `providers` list in
`lua/ai/config.lua` ([AI chats and providers](#ai-chats-and-providers)). A
provider whose `acp` and `api` name adapters CodeCompanion already has needs
only the entry; a native terminal of a new kind needs code.

**Tune file/grep search scope** — the file (`;f`) and grep (`;/`) pickers show hidden **and** gitignored files (`hidden`/`ignored` in `lua/plugin/editor/snacks.lua`). `.git/` is always excluded; heavy build/dependency dirs (`node_modules`, `target`, `.venv`, `Pods`, …) are skipped via the shared `search_exclude` list in the same file. Add a dir to that list to hide it, or remove one to search it. Note: `exclude` drops any dir of that name unconditionally — even git-tracked source — so generic names (`bin`, `out`, `vendor`) are intentionally left out.

Use `;i` (files) or `;?` (text) to respect `.gitignore` instead, with hidden files
still visible and no extra directory exclusions. Under Manage, `<leader>mf`
searches this configuration and `<leader>mF` searches installed plugin source files.

## License

This configuration is provided as-is for personal use.
