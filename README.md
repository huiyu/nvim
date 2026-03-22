# Neovim Configuration

[中文文档](README_CN.md)

A modern Neovim configuration built with Lua and [lazy.nvim](https://github.com/folke/lazy.nvim). Aligned with [LazyVim](https://www.lazyvim.org/) conventions for keybindings and plugin choices, with support for Go, Python, Java, Web, Bash, JSON, and YAML development.

### Requirements

- **Neovim** >= 0.10.0
- **Git**
- A [Nerd Font](https://www.nerdfonts.com/) for icon display
- **ripgrep** (`rg`) for grep and live search
- **fd** for file finder
- Language toolchains as needed (Go, Python, Node.js, Java)

### Installation

```bash
# Backup existing config
mv ~/.config/nvim ~/.config/nvim.backup

# Clone
git clone <repository-url> ~/.config/nvim

# Launch Neovim — lazy.nvim auto-installs all plugins
nvim
```

### Project Structure

```
~/.config/nvim/
├── init.lua                  # Entry point
├── lua/
│   ├── options.lua           # Vim options
│   ├── mappings.lua          # Core keymaps + which-key groups + toggle/UI
│   ├── autocmds.lua          # Autocommands
│   ├── bootstrap.lua         # lazy.nvim setup
│   ├── lang/                 # Language-specific configs
│   │   ├── bash.lua
│   │   ├── go.lua
│   │   ├── java.lua
│   │   ├── json.lua
│   │   ├── python.lua
│   │   ├── web.lua
│   │   └── yaml.lua
│   ├── plugin/
│   │   ├── editor/           # Editor enhancement plugins
│   │   ├── lsp/              # LSP, completion, formatting, debugging
│   │   ├── ui/               # UI and theme plugins
│   │   └── vcs/              # Git integration
│   └── util/                 # Utility modules
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
| [nvim-ts-autotag](https://github.com/windwp/nvim-ts-autotag) | Auto-close HTML/JSX tags |
| [nvim-ufo](https://github.com/kevinhwang91/nvim-ufo) | Modern code folding |
| [todo-comments](https://github.com/folke/todo-comments.nvim) | TODO/FIXME highlights |
| [illuminate](https://github.com/RRethy/vim-illuminate) | Highlight word under cursor |
| [colorizer](https://github.com/norcalli/nvim-colorizer.lua) | Color code highlighting |
| [render-markdown](https://github.com/MeanderingProgrammer/render-markdown.nvim) | In-editor markdown rendering |

#### Editor

| Plugin | Description |
|--------|-------------|
| [telescope](https://github.com/nvim-telescope/telescope.nvim) | Fuzzy finder |
| [flash](https://github.com/folke/flash.nvim) | Fast navigation with labels |
| [which-key](https://github.com/folke/which-key.nvim) | Keybinding help popup |
| [snacks](https://github.com/folke/snacks.nvim) | Dashboard, file explorer, terminal, indent guides, smooth scroll, notifications |
| [aerial](https://github.com/stevearc/aerial.nvim) | Code outline / symbol navigation |
| [trouble](https://github.com/folke/trouble.nvim) | Diagnostics panel |
| [grug-far](https://github.com/MagicDuck/grug-far.nvim) | Search and replace |
| [harpoon](https://github.com/ThePrimeagen/harpoon) | Quick file navigation (`<leader>1-9`) |
| [yanky](https://github.com/gbprod/yanky.nvim) | Yank history ring |
| [dial](https://github.com/monaqa/dial.nvim) | Enhanced increment/decrement (booleans, dates, etc.) |
| [refactoring](https://github.com/ThePrimeagen/refactoring.nvim) | Extract function/variable, inline |
| [mini.ai](https://github.com/echasnovski/mini.ai) | Enhanced text objects |
| [mini.splitjoin](https://github.com/echasnovski/mini.splitjoin) | Toggle single-line/multi-line (`gS`) |
| [nvim-surround](https://github.com/kylechui/nvim-surround) | Surround manipulation |
| [mini.comment](https://github.com/echasnovski/mini.comment) | Comment toggle |
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
| [claudecode](https://github.com/coder/claudecode.nvim) | AI code assistance (Claude Code) |

#### Version Control

| Plugin | Description |
|--------|-------------|
| [gitsigns](https://github.com/lewis6991/gitsigns.nvim) | Git signs, hunk actions, blame |
| [diffview](https://github.com/sindrets/diffview.nvim) | Diff and file history viewer |

### Language Support

| Language | LSP | Formatter | Linter | Test | Debug |
|----------|-----|-----------|--------|------|-------|
| Go | gopls | goimports, gofumpt | golangci-lint | neotest-golang | nvim-dap-go |
| Python | basedpyright, ruff | black | ruff | neotest-python | nvim-dap-python |
| Java | jdtls (+ Lombok) | jdtls | - | java-test | java-debug-adapter |
| TypeScript/JS | vtsls | prettier | eslint | - | - |
| HTML/CSS | html, cssls, tailwindcss | prettier | - | - | - |
| JSON | jsonls + SchemaStore | prettier | - | - | - |
| YAML | yamlls + SchemaStore | prettier | - | - | - |
| Bash | bashls | shfmt | - | - | - |
| Lua | lua_ls | - | - | - | - |

### Keybinding Reference

**Leader**: `Space` | **Local leader**: `\` | **Keybinding guide**: `<leader>?`

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
| `<C-h/j/k/l>` | Window navigation |
| `<C-Up/Down/Left/Right>` | Window resize |
| `<A-j>` / `<A-k>` | Move line up/down (n, i, v) |
| `<S-h>` / `<S-l>` | Prev / Next buffer |
| `<leader><space>` | Find files |
| `<leader>/` | Grep |
| `<leader>,` | Buffers |
| `<leader>:` | Command history |
| `<leader>?` | Keybinding guide |
| `<leader>l` | Lazy (plugin manager) |
| `<leader>n` | Notification history |
| `<leader>e` / `<leader>E` | File tree / File explorer |
| `<leader>-` / `<leader>\|` | Split below / right |
| `<leader>1-9` | Harpoon: jump to file 1-9 |
| `<leader>h` / `<leader>H` | Harpoon quick menu / add file |

#### Leader Groups

| Group | Key | Description |
|-------|-----|-------------|
| Find/Files | `<leader>f` | `ff` files, `fb` buffers, `fr` recent, `fg` git files, `fc` config, `fn` new, `ft/fT` terminal, `fp` projects |
| Search | `<leader>s` | `sg` grep, `sw` word, `sb` buffer lines, `sm` marks, `sR` resume, `sh` help, `sk` keymaps, `sr` replace, `sW` replace word, `st/sT` todos, `ss/sS` symbols, `sn` noice |
| Code | `<leader>c` | `ca` action, `cr` rename, `cf` format, `cd` diagnostics, `cm` Mason, `cl` LSP info, `cn` generate annotations, `co` organize imports, `cO` outline, `cs/cS` symbols (Trouble), `cv` select venv |
| Buffer | `<leader>b` | `bd` delete, `bo` delete others, `bD` delete+window, `bl/br` delete left/right, `bj` pick, `bp` pin, `bP` close unpinned |
| Debug | `<leader>d` | `db` breakpoint, `dc` continue, `di` step into, `do` step out, `dO` step over, `dt` terminate, `dl` run last |
| Git | `<leader>g` | `gs` status, `gb` branches, `gc/gC` commits, `gl/gL` blame, `gp` preview, `gr/gR` reset, `gS` stage, `gu` undo stage, `gd` diff, `gv/gV` diffview, `gB` browse |
| Test | `<leader>t` | `tm` test method, `td` debug method, `tf` test file, `tS` summary, `to` output |
| Toggle/UI | `<leader>u` | `uf/uF` autoformat, `us` spell, `uw` wrap, `ul/uL` numbers, `ud` diagnostics, `uh` inlay hints, `uT` treesitter, `uc` conceal, `ub` background, `un` dismiss notifs, `uR` markdown render |
| Diagnostics | `<leader>x` | `xx/xX` diagnostics, `xL` loclist, `xQ` quickfix, `xt/xT` todos |
| Refactor | `<leader>r` | `rf` extract function, `rx` extract variable, `ri` inline, `rb` extract block, `rs` select |
| AI | `<leader>a` | `ac` toggle, `af` focus, `ar` resume, `aR` continue, `am` model, `ab` add buffer, `as` send, `aa/ad` accept/deny diff |
| Window | `<leader>w` | `wd` delete, `wo` close others, `w=` equalize, `wm` zoom |
| Quit/Session | `<leader>q` | `qq/qQ` quit, `qs` save session, `ql` load last, `q.` load current |
| Tab | `<leader><tab>` | `<tab><tab>` new, `d` close, `]/[` next/prev, `l/f` last/first, `o` close others |

#### Yanky (Enhanced Yank/Paste)

| Key | Action |
|-----|--------|
| `y` / `p` / `P` | Yank / Put (with history) |
| `[y` / `]y` | Cycle through yank history |
| `<leader>p` | Open yank history (Telescope) |

### Terminal Integration (iTerm2)

When running terminal apps inside Neovim (e.g. Claude Code), `Shift+Enter` requires iTerm2 configuration:

**iTerm2 setup**: Settings → Profiles → Keys → Key Mappings → Add:
- **Shortcut**: `Shift + Return`
- **Action**: `Send Escape Sequence`
- **Value**: `[13;2u`

### Environment Variables

| Variable | Description |
|----------|-------------|
| `NVIM_DEV=1` | Enable dev tools (`:DevReload`, `:DevTest`, `:DevValidate`, `:DevInfo`, `:DevPlugins`, `:DevProfile`) |

### Customization

**Add a plugin** — create a file in the appropriate `lua/plugin/*/` directory.

**Add language support** — create a file in `lua/lang/`.

**Add an LSP server** — edit `lua/plugin/lsp/lsp.lua`, add to the `servers` table.

**Add a formatter** — edit `lua/plugin/lsp/conform.lua`, add to `formatters_by_ft`.

## License

This configuration is provided as-is for personal use.
