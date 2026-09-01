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
- **[GitHub CLI](https://cli.github.com/)** — authenticated `gh` for `<leader>G` GitHub pickers and status
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
├── .github/workflows/       # CI: spec suite + both provider startups
├── scripts/                 # $EDITOR wrapper for the agent TUIs
├── tests/                   # Headless spec suite (tests/run.sh)
└── docs/                     # MANUAL.md, DIAGNOSTICS.md, UTILITIES.md
```

### Plugins

#### UI

| Plugin | Description |
|--------|-------------|
| [solarized-osaka](https://github.com/craftzdog/solarized-osaka.nvim) | Colorscheme |
| [lualine](https://github.com/nvim-lualine/lualine.nvim) | Status line |
| [incline](https://github.com/b0o/incline.nvim) | Per-window filename label, on every window but the focused one |
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
| [harpoon](https://github.com/ThePrimeagen/harpoon) | Pinned-file jumps (`;1`-`;9`, `;h` menu) |
| [yanky](https://github.com/gbprod/yanky.nvim) | Yank history ring |
| [dial](https://github.com/monaqa/dial.nvim) | Enhanced increment/decrement (booleans, dates, etc.) |
| [refactoring](https://github.com/ThePrimeagen/refactoring.nvim) | Extract function/variable, inline |
| [mini.ai](https://github.com/echasnovski/mini.ai) | Enhanced text objects |
| [mini.splitjoin](https://github.com/echasnovski/mini.splitjoin) | Toggle single-line/multi-line (`gS`) |
| [mini.bracketed](https://github.com/echasnovski/mini.bracketed) | Extra `[`/`]` motions on the suffixes this config leaves free (`x` conflict, `i` indent, `c` comment, `j` jump, `o` oldfile, `u` undo) |
| [nvim-surround](https://github.com/kylechui/nvim-surround) | Surround manipulation |
| [nvim-autopairs](https://github.com/windwp/nvim-autopairs) | Auto-close pairs |
| [persistence](https://github.com/folke/persistence.nvim) | Session management |
| [guess-indent](https://github.com/NMAC427/guess-indent.nvim) | Auto-detect indentation |
| [oil](https://github.com/stevearc/oil.nvim) | Edit a directory as a buffer: rename, move (`dd`/`p`) and create files as text. `-` for the parent directory, `;o` for a float |

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
| [inc-rename](https://github.com/smjonas/inc-rename.nvim) | LSP rename with live preview, on `grn` / `,r` |
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

The everyday actions are also on `<localleader>` directly, one key shorter, and show up in the `\` which-key popup:

| Key | Action |
|-----|--------|
| `\b` | Compile (toggle continuous) |
| `\v` | View PDF in Skim |
| `\s` | Stop compilation |
| `\k` | Clean aux files |
| `\t` | Toggle table of contents |
| `\e` | Show error list |
| `,x` | One-shot `latexmk` build to PDF (the generic "run this file" key) |

TeX buffers also enable soft `wrap` and `spell` by default (toggle with `<leader>uw` / `<leader>us`).

### Keybindings

**Leader**: `Space` · **Local leader**: `\` · **Cheat sheet**: `<leader>?`

Every key answers one question, and the prefix says which:

| Prefix | Question | Examples |
|--------|----------|----------|
| `;` | Which file / symbol / position do I want? | `;<space>` smart find, `;f` files, `;/` grep, `;s` symbols, `;1`-`;9` pinned files |
| `,` | What do I do to this code? | `,a` code action, `,f` format, `,r` rename, `,j`/`,k` move line, `,e*` extract |
| `s` | What about this window? | `ss`/`sv` split, `sd` close, `se` editor window, `s=` equalize |
| `\` | What does *this filetype* offer? | `\o` organize imports (Go/Python), VimTeX, diffview |
| `<leader>` | Everything else, by domain | `g` git, `G` GitHub, `d` debug, `t` test, `a` AI, `x` diagnostics, `m` manage, `s` session, `y` yank, `u` toggles, `b` buffer, `q` quit |

Frequency decides depth: what you reach for constantly is two keys, the rest
lives under `<leader>`. Press any prefix and wait — which-key lists what is
there, generated from the config itself.

Unprefixed keys worth knowing:

| Key | Action |
|-----|--------|
| `f` / `F` | Flash jump / Treesitter jump (Normal + Visual; `df-`, `ct)` stay native) |
| `<C-h/j/k/l>` | Move between windows — works from terminal input too |
| `<C-,>` | Jump to the editor area, press again to return |
| `<C-/>` · `<C-1>`-`<C-9>` | Toggle terminal · jump to terminal 1-9 |
| `<S-h>` / `<S-l>` · `<Tab>` / `<S-Tab>` | Previous / next buffer |
| `g` · `[` / `]` · `z` | Goto+LSP · prev/next thing · folds and spelling |
| `-` | Open the current directory in oil (edit it as text) |
| `jk` · `<C-]>` | Leave Insert / terminal input |

**→ [docs/MANUAL.md](docs/MANUAL.md) walks through all of it**, starting with the
composition rules the keys are built on.

### Terminal Integration

Native coding-agent terminals no longer resize automatically when entering
Terminal-mode, so moving into one with `<C-h/j/k/l>` does not produce a one-row
flash. If a TUI drifts, exit terminal input with `<C-]>` (or `jk`) and use
`<leader>td` to repair it. Opening a numbered bottom terminal still repairs the
visible agent after the layout changes.

`<C-]>` is the uniform, input-method-safe exit key: in Editor Insert mode it
acts as `<Esc>`; in every terminal, including Claude/Codex panels, it reaches
terminal-Normal without sending the chord to the child process. Repeating it in
Normal mode remains a harmless Escape instead of invoking Nvim's native tag
jump, so it never turns the word under the cursor into an `E426` lookup.
`help` and `man` buffers keep the builtin tag jump, since `<C-]>` is how they
follow a link and they have no second key for it; `<Esc>` and `<C-\>` still
clear the search highlight there.

`<C-h/j/k/l>` is owned by Neovim in both Normal and terminal-input mode, so it
can move directly between editor and terminal windows. This replaces the TUI's
original Ctrl shortcuts; use Backspace for delete-backward, `<S-Enter>` for a
newline in the agent's input box, and arrow keys in pickers. `<C-S-l>` forwards the original
Ctrl+L byte to redraw either the Codex or Claude Code TUI. At a layout edge the
key is a no-op that keeps terminal input active, and a floating terminal
(lazygit, a float-shaped `<C-/>` shell) counts as all edges — otherwise a
shell's own `<C-h>` or `<C-l>` would jump out from under the float.

Because `<C-\>` sits beside `<C-]>`, it performs the same safe Escape in Normal,
Insert, Visual, and terminal-input modes. Repeated presses remain harmless in
Normal mode, so either adjacent chord can be used without an accidental window
jump.

`<C-,>` jumps directly from terminal input or a sidebar to the editor window.
Pressing it from the editor returns to the source window. It relies on the
extended-key protocol negotiated by Ghostty and Nvim to remain distinct from a
plain comma; an outer tmux must have `extended-keys` enabled. Where that
protocol is unavailable — a bare Terminal.app, an ssh session, an older tmux —
`se` does the same jump with plain keys.

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

Scrollback works the same way under both providers, because both wrappers run
tmux with `mouse on` and a 50000-line history. tmux owns the real transcript;
Nvim's terminal buffer only holds the screenful tmux last composed, so scrolling
goes through tmux. Stay in terminal-input mode and use the mouse wheel or
`<PageUp>` to enter tmux copy-mode; scroll down with the wheel or `<PageDown>`,
then press `q` or `<Esc>` to return to the agent's input. If you are already in
terminal-Normal mode, the same keys -- plus `<C-u>`/`<C-d>` -- are forwarded to
tmux and terminal input is restored automatically, so the next wheel event
reaches copy-mode directly. With `CLAUDE_WRAP_TMUX=0` or `CODEX_WRAP_TMUX=0`
there is no tmux to ask, so use `jk` and Nvim's normal scroll commands instead.

Codex runs with `--no-alt-screen --yolo` inside Nvim. YOLO mode bypasses Codex
approvals and its built-in sandbox, while `--no-alt-screen` lets completed chat
output enter the wrapper tmux history.

#### Editing the prompt in a buffer

`<leader>ai` opens the agent's prompt in a floating buffer, so a long prompt is
written with the whole editor instead of the TUI's input box. It exists because
Terminal-mode gives `<C-h/j/k/l>` to window navigation, which are exactly the
agent TUI's editing keys.

| Key | Action |
|-----|--------|
| `<C-d>` | return the prompt to the agent (works from Insert mode) |
| `<C-v>` | attach the clipboard image |
| `<C-c>` | cancel, leaving the input box as it was |
| `:wq` / `ZZ` | return the prompt |
| `:q!` | cancel |

Whatever is already in the input box comes across, and from Visual mode the
selection is added to it first, using the same text form `<leader>as` produces.
Nothing is submitted — closing the buffer hands the text back to the box, and you
still press Enter yourself.

The float is modal: the window keys (`<C-h/j/k/l>`, `<C-w>`, `<C-\>`) do not
leave it, and a focus change that slips past that is undone. While it is open
the agent is blocked on the editor and ignores its pty, so there would be no way
back otherwise — `<leader>ai` pressed again returns to the open prompt (adding a
Visual selection to it) instead of sending a `ctrl+g` the TUI would swallow. Two
agents side by side may each have a prompt open; the newer one keeps focus.

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
What the agent does with the text differs per provider: Claude Code parses the
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

`<leader>at` renders the current project's newest session into a read-only
Markdown buffer, and `<leader>aT` picks from that project's session history.
Inside the buffer, `R` re-reads from disk and `q` closes it. Prose is visible;
thinking and tool calls are folded, so `zR` opens everything and `za` opens one.

The source is the CLI's own JSONL transcript, not the terminal. Claude runs on
the alternate screen, so its tmux wrapper keeps no scrollback at all — there is
nothing to capture from the pane. Reading the recorded transcript is the only
approach that works for both providers, it survives restarting Nvim, and it
needs no change to the tmux wrappers.

Neither CLI persists its reasoning text, so folded "thinking" sections will
normally be absent rather than empty.

#### AI provider selection

One Nvim process selects one provider at startup. Claude remains the default;
the native and CodeCompanion shortcuts stay unchanged. The shell aliases used
by this setup are:

```bash
vi                 # default provider (Claude unless overridden)
vic                # NVIM_AI_PROVIDER=claude nvim
vix                # NVIM_AI_PROVIDER=codex CODEX_HOME="$HOME/.codex-oauth" nvim
```

`<leader>as` attaches the visual selection to the native agent's input box and
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

#### macOS input method

When `macism` is available, Nvim keeps Normal and Terminal-Normal modes on the
detected Latin keyboard layout. Entering Insert or terminal-input mode
restores the input source that was active before leaving it; leaving those modes
captures the current source before switching back to English. This preserves
both cases: English stays English, while Sogou/Apple Pinyin is restored after
returning to text entry.

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

### Configuration

Set these in `init.lua` before plugins load.

| Option | Description |
|--------|-------------|
| `vim.g.terminal_position` | `"float"` (default) or `"bottom"`. Where `<C-1>`-`<C-9>` open. Chosen once, not toggled at runtime — Snacks fixes a window's shape when it opens one and edgy decides separately whether a terminal belongs to its bottom edge, so a runtime toggle means keeping those two in agreement through every hide, show and relayout. |

### Environment Variables

| Variable | Description |
|----------|-------------|
| `NVIM_AI_PROVIDER` | `claude` (default) or `codex`; selects the native agent, CodeCompanion ACP Chat, and HTTP inline adapter for this Nvim process |
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

**Tune file/grep search scope** — the file (`<leader>.`) and grep (`<leader>/`) pickers show hidden **and** gitignored files (`hidden`/`ignored` in `lua/plugin/editor/snacks.lua`). `.git/` is always excluded; heavy build/dependency dirs (`node_modules`, `target`, `.venv`, `Pods`, …) are skipped via the shared `search_exclude` list in the same file. Add a dir to that list to hide it, or remove one to search it. Note: `exclude` drops any dir of that name unconditionally — even git-tracked source — so generic names (`bin`, `out`, `vendor`) are intentionally left out.

## License

This configuration is provided as-is for personal use.
