# Neovim Configuration

[中文文档](README_CN.md)

A modern Neovim configuration built with Lua and [lazy.nvim](https://github.com/folke/lazy.nvim). Aligned with [LazyVim](https://www.lazyvim.org/) conventions for keybindings and plugin choices, with support for Go, C/C++, Python, Java, Web, Bash, JSON, YAML, and LaTeX development.

### Requirements

**Required:**
- **Neovim** >= 0.11.0 (uses `vim.lsp.config`/`vim.lsp.enable`, `vim.hl`, `vim.diagnostic.jump`)
- **Git**
- A [Nerd Font](https://www.nerdfonts.com/) for icon display
- **ripgrep** (`rg`) — powers `Snacks.picker.grep` / `live_grep` / `:grep`
- **fd** — file finder (used by `venv-selector` and some pickers)

**Optional (feature-specific):**
- **[lazygit](https://github.com/jesseduffield/lazygit)** — `<leader>gg` (project) / `<leader>gf` (file history)
- **[tmux](https://github.com/tmux/tmux)** — wraps the selected native-agent TUI inside `:terminal` to prevent stale or torn frames; auto-detected (see [Terminal Integration](#terminal-integration))
- **[GitHub CLI](https://cli.github.com/)** — authenticated `gh` for `<leader>gh` GitHub pickers and status
- **[Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview)** or **[Codex](https://developers.openai.com/codex/cli/)** — selected native coding agent
- **Node.js >= 22 + npm** — CodeCompanion ACP bridge processes
- `ANTHROPIC_API_KEY` or `OPENAI_API_KEY` — optional; selected provider's CodeCompanion HTTP inline/command prompts
- **[cowsay](https://en.wikipedia.org/wiki/Cowsay)** + **lolcat** — dashboard banner (silently skipped if either is missing)

**Quick install (macOS):**
```bash
brew install neovim git gh ripgrep fd lazygit tmux cowsay lolcat node
brew install --cask font-jetbrains-mono-nerd-font  # or any Nerd Font
gh auth login                                      # once, for GitHub pickers
npm install -g @agentclientprotocol/claude-agent-acp @agentclientprotocol/codex-acp
```

**Language toolchains** — *only if you want the matching Mason packages to install:*
- **Go** — required for `gopls`, `gofumpt`, `gomodifytags`, `impl`, `delve`
- **Python >= 3.10** — required for `black` (a `pyenv` or `uv`-managed interpreter works)
- **Node.js + npm** — required for `eslint-lsp`, `css-lsp`, `html-lsp`, `json-lsp`, `yaml-language-server`, `tailwindcss-language-server`, `vtsls`, `bash-language-server`
- **JDK 17+** — required for `jdtls` (Java). This config expects [SDKMAN!](https://sdkman.io/) at `~/.sdkman/candidates/java/current` (see [`lua/lang/java.lua`](lua/lang/java.lua))
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

### Project Structure

```
~/.config/nvim/
├── AGENTS.md                # Repository guidance for coding agents
├── CLAUDE.md                # Claude Code import of AGENTS.md
├── init.lua                  # Entry point
├── lua/
│   ├── options.lua           # Vim options
│   ├── mappings.lua          # Imperative core keymaps (side effects)
│   ├── whichkey_spec.lua     # which-key groups + spec-registered keymaps (data)
│   ├── autocmds.lua          # Autocommands
│   ├── bootstrap.lua         # lazy.nvim setup
│   ├── ai/                    # Provider config + native Claude/Codex facade
│   ├── config/
│   │   └── health.lua        # `:checkhealth config` provider
│   ├── lang/                 # Language-specific configs
│   │   ├── bash.lua
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
└── docs/                     # DIAGNOSTICS.md, UTILITIES.md
```

### Plugins

#### UI

| Plugin | Description |
|--------|-------------|
| [solarized-osaka](https://github.com/craftzdog/solarized-osaka.nvim) | Colorscheme |
| [lualine](https://github.com/nvim-lualine/lualine.nvim) | Status line |
| [bufferline](https://github.com/akinsho/bufferline.nvim) | Buffer tabs with pin/close/pick |
| [noice](https://github.com/folke/noice.nvim) | Enhanced cmdline, messages, notifications |
| [treesitter](https://github.com/nvim-treesitter/nvim-treesitter) | Syntax highlighting, text objects |
| [treesitter-context](https://github.com/nvim-treesitter/nvim-treesitter-context) | Sticky function/class header (`<leader>uC`) |
| [nvim-ts-autotag](https://github.com/windwp/nvim-ts-autotag) | Auto-close HTML/JSX tags |
| [nvim-ufo](https://github.com/kevinhwang91/nvim-ufo) | Modern code folding |
| [todo-comments](https://github.com/folke/todo-comments.nvim) | TODO/FIXME highlights |
| [illuminate](https://github.com/RRethy/vim-illuminate) | Highlight word under cursor |
| [colorizer](https://github.com/catgoose/nvim-colorizer.lua) | Color code highlighting |
| [render-markdown](https://github.com/MeanderingProgrammer/render-markdown.nvim) | In-editor markdown rendering |

#### Editor

| Plugin | Description |
|--------|-------------|
| [flash](https://github.com/folke/flash.nvim) | Fast navigation with labels |
| [which-key](https://github.com/folke/which-key.nvim) | Keybinding help popup |
| [snacks](https://github.com/folke/snacks.nvim) | Picker (fuzzy finder), dashboard, file explorer, terminal, indent guides, smooth scroll, notifications, rename |
| [aerial](https://github.com/stevearc/aerial.nvim) | Code outline / symbol navigation |
| [grug-far](https://github.com/MagicDuck/grug-far.nvim) | Search and replace |
| [harpoon](https://github.com/ThePrimeagen/harpoon) | Quick file navigation (`<leader>1-9`) |
| [yanky](https://github.com/gbprod/yanky.nvim) | Yank history ring |
| [dial](https://github.com/monaqa/dial.nvim) | Enhanced increment/decrement (booleans, dates, etc.) |
| [refactoring](https://github.com/ThePrimeagen/refactoring.nvim) | Extract function/variable, inline |
| [mini.ai](https://github.com/echasnovski/mini.ai) | Enhanced text objects |
| [mini.splitjoin](https://github.com/echasnovski/mini.splitjoin) | Toggle single-line/multi-line (`gS`) |
| [nvim-surround](https://github.com/kylechui/nvim-surround) | Surround manipulation |
| [nvim-autopairs](https://github.com/windwp/nvim-autopairs) | Auto-close pairs |
| [persistence](https://github.com/folke/persistence.nvim) | Session management |
| [guess-indent](https://github.com/NMAC427/guess-indent.nvim) | Auto-detect indentation |

#### LSP & Development

| Plugin | Description |
|--------|-------------|
| [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig) | LSP configuration |
| [mason](https://github.com/williamboman/mason.nvim) | LSP/DAP/linter/formatter installer |
| [blink.cmp](https://github.com/saghen/blink.cmp) | Completion engine with [friendly-snippets](https://github.com/rafamadriz/friendly-snippets) |
| [conform](https://github.com/stevearc/conform.nvim) | Code formatting (with autoformat toggle) |
| [nvim-lint](https://github.com/mfussenegger/nvim-lint) | Linting |
| [nvim-dap](https://github.com/mfussenegger/nvim-dap) | Debug Adapter Protocol |
| [neotest](https://github.com/nvim-neotest/neotest) | Testing framework |
| [neogen](https://github.com/danymat/neogen) | Generate annotations/docstrings |
| [SchemaStore](https://github.com/b0o/SchemaStore.nvim) | JSON/YAML schema validation |
| [lazydev](https://github.com/folke/lazydev.nvim) | Lua development (type completion) |
| [claudecode](https://github.com/coder/claudecode.nvim) | Native Claude Code integration (Claude provider only) |
| [CodeCompanion](https://github.com/olimorris/codecompanion.nvim) | Provider-aware ACP chat plus HTTP inline/command prompts |
| [codecompanion-history](https://github.com/ravitemer/codecompanion-history.nvim) | Auto-saved, project-aware CodeCompanion chat history |

#### Version Control

| Plugin | Description |
|--------|-------------|
| [gitsigns](https://github.com/lewis6991/gitsigns.nvim) | Git signs, hunk actions, blame |
| [diffview](https://github.com/sindrets/diffview.nvim) | Diff and file history viewer |

### Language Support

| Language | LSP | Formatter | Linter | Test | Debug |
|----------|-----|-----------|--------|------|-------|
| C / C++ | clangd | clang-format | - | - | codelldb |
| Go | gopls | gopls organize imports + gofumpt | golangci-lint | neotest-golang | nvim-dap-go |
| Python | basedpyright, ruff | black | ruff | neotest-python | nvim-dap-python |
| Java | jdtls (+ Lombok) | jdtls | - | java-test | java-debug-adapter |
| TypeScript/JS | vtsls | prettier | eslint | - | js-debug-adapter |
| HTML/CSS | html, cssls, tailwindcss | prettier | - | - | - |
| JSON | jsonls + SchemaStore | prettier | - | - | - |
| YAML | yamlls + SchemaStore | prettier | - | - | - |
| Bash | bashls | shfmt | - | - | - |
| LaTeX | texlab (+ VimTeX) | latexindent | chktex | - | - |
| Lua | lua_ls | - | - | - | - |

#### LaTeX Workflow

LaTeX is split between two tools: **VimTeX** drives compilation/viewing/motions, while **texlab** provides LSP intelligence (completion, goto, label rename) and `chktex` linting. They are configured not to overlap — texlab's own build is disabled so only VimTeX compiles.

**One-time setup**

```bash
brew install --cask mactex-no-gui   # TeX Live: latexmk, latexindent, chktex
brew install --cask skim            # PDF viewer with SyncTeX
```

`texlab` installs itself through Mason on first launch — no extra step. For inverse search (click in the PDF → jump to source), set **Skim → Preferences → Sync → Preset: Custom**, Command `nvim`, Arguments:

```
--headless -c "VimtexInverseSearch %line '%file'"
```

**Daily use** — open any `.tex` file, then:

- `<localleader>ll` (`\ll`) — start continuous compilation (recompiles on save)
- `<localleader>lv` (`\lv`) — forward search: open/jump Skim to the cursor's line
- `<localleader>lt` (`\lt`) — table of contents; `\lk` clean, `\le` errors
- Save the file to auto-format with `latexindent` (toggle with `<leader>uf`)

The same actions are mirrored under the **`<leader>c` (Code)** group for which-key discoverability:

| Key | Action |
|-----|--------|
| `<leader>cb` | Compile (toggle continuous) |
| `<leader>cv` | View PDF in Skim |
| `<leader>cs` | Stop compilation |
| `<leader>ck` | Clean aux files |
| `<leader>ct` | Toggle table of contents |
| `<leader>ce` | Show error list |
| `<leader>cx` | One-shot `latexmk` build to PDF |

TeX buffers also enable soft `wrap` and `spell` by default (toggle with `<leader>uw` / `<leader>us`).

### Keybinding Reference

**Leader**: `Space` | **Local leader**: `\` | **Keybinding guide**: `<leader>?`

#### Which Prefix? (Intent → Key)

One design rule governs everything: **the more frequent the action, the faster the prefix**. Modifier chords (`Ctrl`/`Shift`/`Alt`) are instant muscle memory; sequence prefixes (`g`, `[`/`]`, `z`) move the cursor; `<leader>` is the command palette — slowest, but which-key has your back.

Start from what you want to do:

| I want to… | Use | Examples |
|------------|-----|----------|
| Run a command / manage things | `<leader>` + domain letter | `<leader>gs` git status, `<leader>bd` delete buffer, `<leader>ca` code action |
| Step to the next/prev one of something | `]` / `[` + kind | `]d` diagnostic, `]h` hunk, `]b` buffer — repeat to iterate |
| Jump to something about the symbol under cursor | `g` | `gd` definition, `gr` references, `gI` implementation — one shot |
| Do an instant, every-minute action | `Ctrl` | `<C-h/j/k/l>` windows, `<C-s>` save, `<C-/>` terminal |
| Cycle through the bufferline | `Shift` | `<S-h>` / `<S-l>` |
| Move something (not the cursor) | `Alt` | `<A-j>` / `<A-k>` move line |
| Fly to any spot I can see | `s` | Flash jump: `s` + 2 chars + label |

Mnemonic: **Space commands, brackets step, g resolves, Ctrl acts, Shift cycles, Alt moves, s flies.**

Two distinctions worth training deliberately:

- **`]d` vs `gd`** — brackets answer *"where is the next one from here?"* (position-based, repeatable); `g` answers *"where is THE definition of this?"* (semantic, lands in one jump).
- **`<S-h>` is literally `H`** — it shadows native `H`/`L` (jump to top/bottom of visible screen). Deliberate trade: buffer switching is far more frequent, and `gg`/`G`/relative jumps cover the loss (`M` is untouched).

#### Trigger Key Prefixes

Press any prefix and wait for which-key popup to see available keys.

| Prefix | Category |
|--------|----------|
| `<leader>` | Main command palette (all groups below) |
| `g` | Goto / LSP (`gd` definition, `gr` references, `K` hover, `gI` impl, `gy` type def, `gD` declaration, `gK` signature, `gS` splitjoin) |
| `s` / `S` | Flash jump / Treesitter jump |
| `[` / `]` | Prev / Next navigation (`b` buffer, `d` diagnostic, `e` error, `w` warning, `h` hunk, `q` quickfix, `t` todo, `y` yank, `B` move buffer) |
| `z` | Folds / Spelling (`zR` open all, `zM` close all, `zK` peek) |
| `<C-w>` | Window operations |

#### Top-level Shortcuts

| Key | Action |
|-----|--------|
| `<C-s>` | Save file (all modes) |
| `<Esc>` | Clear search highlight |
| `<C-/>` | Toggle terminal |
| `<C-h/j/k/l>` | Window navigation (Normal + terminal input) |
| `<C-S-l>` | Redraw the active TUI (terminal input) |
| `<C-Up/Down/Left/Right>` | Window resize |
| `<A-j>` / `<A-k>` | Move line up/down (n, i, v) |
| `<S-h>` / `<S-l>` | Prev / Next buffer |
| `<leader><space>` | Smart find (buffers + recent + files, all filtered to cwd, frecency-boosted) |
| `<leader>.` | Find file in cwd (incl. hidden + gitignored; heavy build/dep dirs excluded) |
| `<leader>/` | Search project grep (incl. hidden + gitignored; heavy build/dep dirs excluded) |
| `<leader>,` | Buffers |
| `<leader>:` | Command history |
| `<leader>'` | Resume last picker |
| `<leader>\`` | Last buffer (alternate) |
| `<leader>?` | Keybinding guide |
| `<leader>l` | Lazy (plugin manager) |
| `<leader>n` | Notification history |
| `<leader>e` / `<leader>E` | File tree / File explorer |
| `<leader>-` / `<leader>\|` | Split below / right |
| `<leader>1-9` | Harpoon: jump to file 1-9 |
| `<leader>h` / `<leader>H` | Harpoon quick menu / add file |
| `<leader>p` | Yank history — see [Yanky](#yanky-enhanced-yankpaste) |

#### Leader Groups

| Group | Key | Description |
|-------|-----|-------------|
| Find/Files | `<leader>f` | `ff` files in cwd, `fF` from buffer dir, `fd` browse directory, `fe` explorer (with ignored), `fr` recent, `fb` buffers, `fg` git files, `fp` projects, `fc` nvim config, `fn` new, `fs/fS` save/save-as, `fR` rename, `fD` delete, `fy/fY` yank path (abs/project), `ft/fT` terminal |
| Search | `<leader>s` | `sb` buffer, `sB` open buffers, `sd` current dir, `sp` project, `sw` word, `ss/sS` symbols (buffer/workspace), `sR` resume, `sh` help, `sk` keymaps, `sm` marks, `sj` jumps, `sc/sC` cmd history/cmds, `s"` registers, `sM` man, `sr/sW` replace, `st/sT` todos, `sn{a,d,h,l,t}` noice (all/dismiss/history/last/pick) |
| Code | `<leader>c` | `ca` action, `cr` rename, `cf` format, `cd` diagnostics, `cm` Mason, `cl` LSP info, `cn` generate annotations, `co` organize imports, `cO` outline, `cs/cS` symbols (buffer/workspace), `cv` select venv (py), `cp` markdown preview (md), `cP` browse cwd markdown → preview, `cx` run current file (by filetype: go/c/cpp/py/js/ts/sh), `cR` rebuild gopls index (go) |
| Buffer | `<leader>b` | `bd` delete, `bo` delete others, `bD` delete+window, `bl/br` delete left/right, `bj` pick, `bp` pin, `bP` close unpinned |
| Debug | `<leader>d` | `db/dB` breakpoint/conditional, `dc/da` continue/with-args, `dC` run to cursor, `dg` goto line, `di` step into, `do` step out, `dO` step over, `dj/dk` down/up frame, `dP` pause, `dr` REPL, `ds` session, `dw` widgets, `dt` terminate, `dl` run last |
| Git | `<leader>g` | `gs` status, `gb` branches, `gc/gC` commits, `gl/gL` blame, `gp` preview, `gr/gR` reset, `gS` stage/unstage, `gT` toggle line blame, `gd` diff, `gv` diffview, `gm` diff main, `gM` diff pick ref, `gV` file history, `gH` git log, `gh*` GitHub |
| Test | `<leader>t` | `tm` test method, `td` debug method, `tf` test file, `tS` summary, `to` output, `tD/th` show/hide diagnostic |
| Terminal | `<leader>T` | `T1-9` open/toggle dedicated terminals, `Td` fix agent TUI drift, `Tx` close terminal buffer |
| Toggle/UI | `<leader>u` | `uf/uF` autoformat, `us` spell, `uw` wrap, `ul/uL` numbers, `ud` diagnostics, `uh` inlay hints, `uT` treesitter, `uc` conceal, `ub` background, `un` dismiss notifs, `uR` markdown render |
| Diagnostics | `<leader>x` | `xx/xX` diagnostics (project/buffer), `xL/xQ` loclist/quickfix picker, `xl/xq` toggle loclist/quickfix window, `xt/xT` todos |
| Refactor | `<leader>r` | `rf` extract function, `rF` extract function to file, `rx` extract variable, `ri` inline, `rb` extract block, `rB` extract block to file, `rs` select |
| AI | `<leader>a` | Native: `ac` toggle, `af` focus, `ar` resume picker, `aR` continue last, `am` model, `ab` add buffer, `as` attach selection (v). Claude-only: `aS`, `aa/ad`. CodeCompanion: `ap{c,t,a,i,b,h}` chat/toggle/actions/inline/add selection/history |
| Window | `<leader>w` | `ww` other window, `wd` delete, `wo` close others, `w=` equalize, `wm` zoom |
| Quit/Session | `<leader>q` | `qq/qQ` quit, `qs` save session, `ql` load last, `q.` load current |
| Tab | `<leader><tab>` | `<tab><tab>` new, `d` close, `]/[` next/prev, `` ` `` last used (alternate), `l/f` rightmost/first, `o` close others, `s` list all |

#### GitHub (`<leader>gh`)

| Key | Action |
|-----|--------|
| `f` / `F` | Open the current file/visual lines on its branch / as a commit permalink |
| `r` | Open the repository home page |
| `i` / `I` | Open issues / all issues in the Snacks GitHub picker |
| `p` / `P` | Open pull requests / all pull requests in the Snacks GitHub picker |
| `c` | Show the current branch PR and its available actions |
| `a` | Open the repository's GitHub Actions page |
| `n` | Open GitHub notifications |
| `s` | Show account-wide `gh status` in a floating window |

Issue and PR mutations are intentionally not assigned global mappings. In a
Snacks GitHub picker, press `<cr>` to choose an action such as opening details,
commenting, reviewing, or merging. These mappings require an authenticated
GitHub CLI (`gh auth status`); `:checkhealth config` reports whether it is found.

#### Diffview (in-view keys)

Launch keys live in the Git group (`<leader>gv/gm/gM/gV/gH`). Once inside a diff view these buffer-local keys apply — press `g?` for the full context-sensitive help:

| Key | Action |
|-----|--------|
| `<tab>` / `<s-tab>` | Next / previous file's diff |
| `[F` / `]F` | First / last file |
| `<leader>e` / `<leader>b` | Focus / toggle the file panel |
| `gf` | Open the file in the previous tabpage |
| `<C-w><C-f>` / `<C-w>gf` | Open the file in a split / new tab |
| `g<C-x>` | Cycle diff layout |
| `-` / `s`, `S` / `U` | (file panel) stage/unstage entry, stage/unstage all |
| `X` | (file panel) restore entry to the left side |
| `i` / `f` | (file panel) toggle list/tree, flatten empty dirs |
| `L` | (file panel) open commit log |
| `[x` / `]x` | Previous / next merge conflict |
| `<leader>c{o,t,b,a}` | Resolve conflict: ours / theirs / base / all (uppercase = whole file) |
| `dx` | Delete the conflict region |
| `y` | (file history) copy the commit hash |

**Disabled inside Diffview:** the file/buffer openers `<leader>f`, `<leader><space>`, `<leader>.`, `<leader>/`, `<leader>,` are neutralized in diff buffers — they would load a file into a diff window and break the layout, so they show a hint instead (exit with `<leader>gq` first). `<leader>b/e/c*` intentionally keep diffview's own actions rather than the global Buffer/Explorer/Code groups. Configured in `lua/plugin/vcs/diffview.lua`.

#### Yanky (Enhanced Yank/Paste)

| Key | Action |
|-----|--------|
| `y` / `p` / `P` | Yank / Put (with history) |
| `[y` / `]y` | Cycle through yank history |
| `<leader>p` | Open yank history (`:YankyRingHistory` via snacks ui-select) |
| `<leader>y` (v) | Yank selection to unnamed register |
| `<leader>Y` (v) | Yank selection to system clipboard (`+`) |

### Terminal Integration

Native coding-agent terminals no longer resize automatically when entering
Terminal-mode, so moving into one with `<C-h/j/k/l>` does not produce a one-row
flash. If a TUI drifts, exit terminal input with `<Esc><Esc>` and use
`<leader>Td` to repair it. Opening a numbered bottom terminal still repairs the
visible agent after the layout changes.

`<C-h/j/k/l>` is owned by Neovim in both Normal and terminal-input mode, so it
can move directly between editor and terminal windows. This replaces the TUI's
original Ctrl shortcuts; use Backspace for delete-backward, `<S-Enter>` for a
composer newline, and arrow keys in pickers. `<C-S-l>` forwards the original
Ctrl+L byte to redraw either the Codex or Claude Code TUI.

#### AI provider selection

One Nvim process selects one provider at startup. Claude remains the default;
the native and CodeCompanion shortcuts stay unchanged. The shell aliases used
by this setup are:

```bash
vi                 # default provider (Claude unless overridden)
vic                # NVIM_AI_PROVIDER=claude nvim
vix                # NVIM_AI_PROVIDER=codex CODEX_HOME="$HOME/.codex-oauth" nvim
```

`<leader>as` attaches the visual selection to the native agent's composer and
does not submit it, leaving room for an instruction. With Codex, a saved buffer
becomes an `@path lines X-Y` draft. For a modified or unnamed buffer, the exact
selected text is pasted instead because Codex file mentions read the saved file.
Add the instruction you want, then press Enter yourself.

The same setting selects CodeCompanion's ACP Chat agent (`claude_code` /
`codex`). Chat therefore uses the coding agent's stateful protocol and tools;
Inline and command prompts remain lightweight HTTP interactions
(`anthropic` / `openai_responses`) and require the matching API key. Codex ACP
uses ChatGPT authentication and inherits `CODEX_HOME` from `vix`.

CodeCompanion chats are auto-saved by codecompanion-history. Open them with
`<leader>aph` (or `:CodeCompanionHistory`); inside a chat, `gh` opens the same
history browser. Entries use the Snacks picker and can be renamed manually;
automatic model-generated titles are disabled to avoid an extra request.
History restores the local CodeCompanion transcript. To continue the agent's
actual stateful ACP session, use `/resume` from a fresh ACP chat.

Run `:AIInfo` to inspect the resolved Native/ACP/HTTP mapping and
`:checkhealth config` to see missing CLIs, ACP bridges, or HTTP credentials.

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

**Overrides**:
- `CLAUDE_WRAP_TMUX=0 nvim` — disable for one-off A/B testing
- `vim.g.claude_wrap_tmux = false` in `init.lua` — disable permanently
- `CODEX_WRAP_TMUX=0 nvim` / `vim.g.codex_wrap_tmux = false` — equivalent Codex overrides
- Both wrappers default to on when tmux is installed

**Tip — suppress the recap CJK box**: Claude Code's session recap is the most visible CJK width offender. Set `"awaySummaryEnabled": false` in `~/.claude/settings.json` to suppress it. This is Claude Code's global config, not nvim's.

### Environment Variables

| Variable | Description |
|----------|-------------|
| `NVIM_AI_PROVIDER` | `claude` (default) or `codex`; selects the native agent, CodeCompanion ACP Chat, and HTTP inline adapter for this Nvim process |
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

**Tune file/grep search scope** — the file (`<leader>.`) and grep (`<leader>/`) pickers show hidden **and** gitignored files (`hidden`/`ignored` in `lua/plugin/editor/snacks.lua`). `.git/` is always excluded; heavy build/dependency dirs (`node_modules`, `target`, `.venv`, `Pods`, …) are skipped via the shared `search_exclude` list in the same file. Add a dir to that list to hide it, or remove one to search it. Note: `exclude` drops any dir of that name unconditionally — even git-tracked source — so generic names (`bin`, `out`, `vendor`) are intentionally left out.

## License

This configuration is provided as-is for personal use.
