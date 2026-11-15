# Neovim 配置

[English](README.md)

基于 Lua 和 [lazy.nvim](https://github.com/folke/lazy.nvim) 构建的现代 Neovim 配置。键位和插件选择与 [LazyVim](https://www.lazyvim.org/) 对齐，支持 Go、C/C++、Python、Java、Rust、Web、Bash、JSON、YAML、LaTeX 开发。

### 环境要求

**必装：**
- **Neovim** >= 0.12.5（refactoring.nvim 的最低要求；nvim-treesitter 的 `main` 分支需要 0.12）
- **Git**（[审阅轮次](docs/MANUAL_CN.md#审阅一轮-agent-修改)需要 2.26 或更新版本）
- [Nerd Font](https://www.nerdfonts.com/)（图标显示）
- **ripgrep** (`rg`) — `Snacks.picker.grep` / `live_grep` / `:grep` 的底层
- **fd** — 文件查找（`venv-selector` 和部分 picker 用到）
- **[tree-sitter CLI](https://github.com/tree-sitter/tree-sitter/blob/master/crates/cli/README.md)** >= 0.26.1 和一个 C 编译器 — nvim-treesitter 的 `main` 分支用 `tree-sitter build` 编译每个 parser。请用包管理器安装（Homebrew 里叫 `tree-sitter-cli`），不要用 npm

**可选（按功能）：**
- **[lazygit](https://github.com/jesseduffield/lazygit)** — `<leader>gg`（仓库）/ `<leader>gf`（当前文件历史）
- **[tmux](https://github.com/tmux/tmux)** — 把 Native Agent 的 TUI 包到 `:terminal` 里，避免残影和帧撕裂；自动检测（详见[终端集成](#终端集成)）
- **[GitHub CLI](https://cli.github.com/)** — 已认证的 `gh`，供 `<leader>G` GitHub picker 与状态使用
- **[Codex](https://developers.openai.com/codex/cli/)** — 原生 coding agent；和可选的 CodeCompanion Chat 一样用 `<leader>an` 新建（见 [AI Chat 与 Provider](#ai-chat-与-provider)）
- **Node.js >= 22 + npm** — CodeCompanion Agent Chat 背后的 ACP bridge
- `NVIM_ANTHROPIC_API_KEY` 或 `NVIM_OPENAI_API_KEY` — 可选；用该 key profile 的 CodeCompanion API Chat，以及用当前 key profile 的 Inline/命令 Prompt（见 [API key](#api-key)；不是 `ANTHROPIC_API_KEY` / `OPENAI_API_KEY`）
- **[llama.cpp](https://github.com/ggml-org/llama.cpp)** — `llama-server` 及其 7B 代码模型（一次性下载约 8 GB），供[行内 AI 补全](#行内-ai-补全)使用
- **[cowsay](https://en.wikipedia.org/wiki/Cowsay)** + **lolcat** — 启动页 banner（任一个缺失都会静默跳过）

**macOS 一键安装：**
```bash
brew install neovim git gh ripgrep fd tree-sitter-cli lazygit tmux cowsay lolcat node llama.cpp
brew install --cask font-jetbrains-mono-nerd-font  # 任意 Nerd Font 都行
gh auth login                                      # 首次为 GitHub picker 认证
npm install -g @agentclientprotocol/claude-agent-acp @agentclientprotocol/codex-acp
llama-server --fim-qwen-7b-default                 # 一次性：下载灰色补全模型（约 8 GB），listening 后 Ctrl-C
```

**语言工具链** — *只有想用对应的 Mason 包时才需要：*
- **Go** — `gopls`、`gofumpt`、`delve` 都依赖
- **Python >= 3.10** — `black` 需要（`pyenv` 或 `uv` 管理的解释器都可以）
- **Node.js + npm** — `eslint-lsp`、`css-lsp`、`html-lsp`、`json-lsp`、`yaml-language-server`、`tailwindcss-language-server`、`vtsls`、`bash-language-server` 都依赖
- **Rust（rustup）** — Mason 安装的 `rust-analyzer` 需要 `cargo`，格式化用的是工具链自带的 `rustfmt`（`rustup component add rustfmt`）；`rust-src` 由 rust-analyzer 自己通过 rustup 补装
- **JDK 25+** — 用来运行 `jdtls`（Java）；项目本身仍可面向更早的版本。依次从 `$JAVA_HOME`、[SDKMAN!](https://sdkman.io/)（`~/.sdkman/candidates/java`）、PATH 中查找（见 [`lua/plugin/lang/java.lua`](lua/plugin/lang/java.lua)）
- **TeX Live + Skim**（LaTeX）— `brew install --cask mactex-no-gui` 提供 `latexmk`/`latexindent`/`chktex`，`brew install --cask skim` 提供支持 SyncTeX 的 PDF 阅读器；`texlab` 由 Mason 安装。反向跳转需在 Skim → 偏好设置 → Sync 中选 Custom：命令填 `nvim`，参数填 `--headless -c "VimtexInverseSearch %line '%file'"`

如果 Mason 安装失败，运行 `:Mason`（UI）或 `:MasonLog`（原始日志）查看具体错误。最常见的原因是上面这些工具链没装。

### 安装

```bash
mv ~/.config/nvim ~/.config/nvim.backup
git clone https://github.com/huiyu/nvim.git ~/.config/nvim
nvim
```

打开文件（`vi 路径/文件` 或 `nvim`）会把 cwd 设为 Git 根目录，非 Git 文件使用
文件所在目录。打开目录则使用该目录；无参数启动保留 shell 的 cwd。
详见[使用手册](docs/MANUAL_CN.md#文件)。

### 项目结构

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

### 常用命令

在 `~/.config/nvim` 下运行；直接执行 `make` 会列出全部命令。

| 命令 | 作用 |
|---|---|
| `make test` | 跑 `tests/` 下全部 spec（约 5 分钟）；`make test S="hunk_actions codediff"` 只跑指定的几个 |
| `make startup` | headless 启动，有任何启动错误即失败 |
| `make check` | 检查未暂存和已暂存改动里的空白错误 |
| `make verify` | 依次执行 `check`、`startup`、`test`：即 CI 所做的检查，也是改动合入前该跑的 |
| `make health` | 在终端里输出 `:checkhealth config` |
| `make profile` | headless 启动中最慢的步骤 |
| `make deps` | 安装 spec 所需的一切：缺失的插件、Mason 工具包、CodeDiff 的原生库 |

spec 刻意逐个运行：有些 spec 依赖同一时间只有一个 Nvim 在用的资源（`llama_service` 共享的 llama-server、git 与 gitsigns 的时序）。

### 插件列表

#### 界面

| 插件 | 说明 |
|------|------|
| [solarized-osaka](https://github.com/craftzdog/solarized-osaka.nvim) | 配色方案 |
| [lualine](https://github.com/nvim-lualine/lualine.nvim) | 状态栏，显示 `● REC @q` 宏录制标识、按了一半的命令或 Visual 选区大小（`2d`、`3x12`）、当前 buffer 的 git 改动行数（取自 gitsigns）和语言服务器（忙碌时显示转圈） |
| [incline](https://github.com/b0o/incline.nvim) | 文件窗口右上角的文件名标签；当前窗口显示粉色，`[+]` 表示未保存的修改 |
| [bufferline](https://github.com/akinsho/bufferline.nvim) | 缓冲区标签页（固定/关闭/选择，`;B` 按标签字母选一个）；`<leader>bh` 关掉所有 tabpage 里都没有窗口在显示的 buffer |
| [noice](https://github.com/folke/noice.nvim) | 命令行和消息：`:` 在屏幕上方的弹窗里输入，补全菜单跟在下面；`/` 和 `?` 留在最底一行；Vim 的消息和报错以通知弹出（由下面的 snacks 显示）；`:w`、撤销、quickfix 的确认以小字显示在右下角；`:messages` / `g<` 在分屏里查看；不再出现 "Press ENTER" 提示 |
| [treesitter](https://github.com/nvim-treesitter/nvim-treesitter) | 语法高亮、文本对象 |
| [treesitter-context](https://github.com/nvim-treesitter/nvim-treesitter-context) | 粘性函数/类头（`<leader>uC`） |
| [nvim-ts-autotag](https://github.com/windwp/nvim-ts-autotag) | HTML/JSX 自动闭合标签 |
| [nvim-ufo](https://github.com/kevinhwang91/nvim-ufo) | 现代代码折叠 |
| [statuscol](https://github.com/luukvbaal/statuscol.nvim) | 行号栏：断点、诊断、git 标记各占固定位置；点击标记、行号或折叠符号即可操作 |
| [todo-comments](https://github.com/folke/todo-comments.nvim) | TODO/FIXME 高亮 |
| [illuminate](https://github.com/RRethy/vim-illuminate) | 光标下单词高亮；`]r` / `[r` 跳到它的下一处 / 上一处引用 |
| [colorizer](https://github.com/catgoose/nvim-colorizer.lua) | Hex/RGB/HSL、CSS 变量颜色预览；前端文件支持 Tailwind 颜色 |
| [render-markdown](https://github.com/MeanderingProgrammer/render-markdown.nvim) | 编辑器内 Markdown 渲染（`,m`） |

#### 编辑器

| 插件 | 说明 |
|------|------|
| [flash](https://github.com/folke/flash.nvim) | 快速跳转导航 |
| [which-key](https://github.com/folke/which-key.nvim) | 键位提示弹窗 |
| [snacks](https://github.com/folke/snacks.nvim) | Picker、启动页、终端、通知（历史 `<leader>mnh`）、缩进线、平滑滚动、重命名、专注模式（`sz`）、把 git permalink 复制到剪贴板（`<leader>yg`） |
| [aerial](https://github.com/stevearc/aerial.nvim) | 代码大纲 |
| [grug-far](https://github.com/MagicDuck/grug-far.nvim) | 搜索替换 |
| [harpoon](https://github.com/ThePrimeagen/harpoon) | 在一小组文件间快速跳转（`;H` 加入，`;1`-`;9`，`;h` 打开菜单） |
| [yanky](https://github.com/gbprod/yanky.nvim) | Yank 历史环 |
| [dial](https://github.com/monaqa/dial.nvim) | 递增/递减布尔值、日期等；JS/TS 中切换 `let` / `const` |
| [refactoring](https://github.com/ThePrimeagen/refactoring.nvim) | 提取函数/变量、内联（`,e…` / `,i`） |
| [mini.ai](https://github.com/echasnovski/mini.ai) | 增强文本对象 |
| [mini.splitjoin](https://github.com/echasnovski/mini.splitjoin) | 单行/多行切换（`gS`） |
| [mini.bracketed](https://github.com/echasnovski/mini.bracketed) | 补充 `[`/`]` 跳转，只占用本配置未使用的后缀（`x` 冲突、`i` 缩进、`j` 跳转表、`o` oldfile、`u` undo） |
| [nvim-surround](https://github.com/kylechui/nvim-surround) | 包围符号操作 |
| [nvim-autopairs](https://github.com/windwp/nvim-autopairs) | 自动配对括号 |
| [persistence](https://github.com/folke/persistence.nvim) | 会话管理 |
| [guess-indent](https://github.com/NMAC427/guess-indent.nvim) | 自动检测缩进 |
| [oil](https://github.com/stevearc/oil.nvim) | 把目录当 buffer 编辑：改行名即重命名，`dd`/`p` 即移动文件，新增一行即创建文件。`-` 打开上级目录，`;o` 开浮窗 |

#### LSP 与开发工具

| 插件 | 说明 |
|------|------|
| [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig) | LSP 配置 |
| [mason](https://github.com/mason-org/mason.nvim) | LSP/DAP/Linter/Formatter 安装管理 |
| [blink.cmp](https://github.com/saghen/blink.cmp) | 补全引擎，含 [friendly-snippets](https://github.com/rafamadriz/friendly-snippets)；输入函数调用时显示参数提示 |
| [conform](https://github.com/stevearc/conform.nvim) | 代码格式化（支持自动格式化开关） |
| [nvim-lint](https://github.com/mfussenegger/nvim-lint) | 代码检查 |
| [nvim-dap](https://github.com/mfussenegger/nvim-dap) | 调试适配器协议 |
| [neotest](https://github.com/nvim-neotest/neotest) | 测试框架 |
| [neogen](https://github.com/danymat/neogen) | 自动生成注释/文档 |
| [SchemaStore](https://github.com/b0o/SchemaStore.nvim) | JSON/YAML schema 验证 |
| [lazydev](https://github.com/folke/lazydev.nvim) | Lua 开发（类型补全） |
| [inc-rename](https://github.com/smjonas/inc-rename.nvim) | 带实时预览的 LSP 重命名，绑在 `,r` |
| [CodeCompanion](https://github.com/olimorris/codecompanion.nvim) | 走 ACP、按订阅计费的 [Agent Chat](#codecompanion-的两种-chat)，以及走 HTTP、按 key profile 计费的 API Chat，都从 `<leader>an` 新建；另有用 key profile 的 Inline/命令 Prompt |
| [codecompanion-history](https://github.com/ravitemer/codecompanion-history.nvim) | 自动保存、按项目感知的 CodeCompanion Chat 历史 |
| [minuet-ai](https://github.com/milanglacier/minuet-agent_workbench.nvim) | 边输入边出现的 AI 灰色补全，模型在本机运行（[行内 AI 补全](#行内-ai-补全)） |

#### 版本控制

| 插件 | 说明 |
|------|------|
| [gitsigns](https://github.com/lewis6991/gitsigns.nvim) | Git 标记、块操作、blame、当前文件的行内 diff（`<leader>gD`） |
| [CodeDiff](https://github.com/esmuellert/codediff.nvim) | Diff、历史与[审阅](docs/MANUAL_CN.md#审阅一轮-agent-修改)视图（`<leader>g`、`<leader>av`）。diff 由一个原生库计算，首次使用时从它的 GitHub release 下载，旁边还有一个文件监视器；`:CodeDiff install!` 重新安装（[排错](docs/DIAGNOSTICS.md#diff-views-codediff)） |

### 语言支持

| 语言 | LSP | 格式化 | 检查 | 测试 | 调试 |
|------|-----|--------|------|------|------|
| C / C++ | clangd | clang-format | - | - | codelldb |
| Go | gopls | gopls 整理 imports + gofumpt | golangci-lint | neotest-golang | nvim-dap-go |
| Python | basedpyright, ruff | black | ruff | neotest-python | nvim-dap-python |
| Java | jdtls (+ Lombok) | jdtls | - | java-test | java-debug-adapter |
| Rust | rust-analyzer | rustfmt（经 rust-analyzer） | cargo check（经 rust-analyzer，保存时） | Cargo test (DAP) | codelldb + Cargo |
| Dart / Flutter | - | - | - | SDK test (DAP) | SDK DAP |
| TypeScript/JS | vtsls（`gs` 跳到源码定义） | prettier | eslint | Vitest (DAP) | js-debug-adapter |
| HTML/CSS | html, cssls, tailwindcss | prettier | - | - | - |
| JSON | jsonls + SchemaStore | prettier | - | - | - |
| YAML | yamlls + SchemaStore | prettier | - | - | - |
| Bash | bashls | shfmt | - | - | - |
| LaTeX | texlab (+ VimTeX) | latexindent | chktex | - | - |
| Lua | lua_ls | - | - | - | - |

#### 调试

`<leader>df` 调试当前文件，`<leader>tM` 调试当前测试用例，`<leader>tF`
调试当前测试文件（`tm`/`tf` 不经调试器直接运行）。各语言使用统一快捷键，目标选择逻辑由各语言模块分别实现
（JS/TS 测试使用 Vitest）。

`<leader>dA` / `:DapAttach` 附加已有进程，提供 Go、Python、Java、C/C++、Rust、
Node/Chrome、Dart/Flutter 和 Electron 的预设。

`<leader>d` 提供断点、单步和会话操作：`de` 异常断点、`dL` 日志断点、
`dR` 重启、`dD` 断开并保留目标、`du` 调试视图开关、`dw` 表达式/选区求值、
`dW` 添加 Watch。调试视图开在独立的 tabpage 里，会话不会打乱你正在编辑的
窗口；步进停留在你所在的 tabpage。各语言的依赖、launch/attach 命令、测试操作及项目
`launch.json` 示例见[调试工作流](docs/MANUAL_CN.md#调试)。
Dart/Flutter SDK 需单独安装。

#### LaTeX 工作流

LaTeX 分工给两个工具:**VimTeX** 负责编译/预览/文本对象,**texlab** 负责 LSP 智能(补全、跳转、label 重命名)和 `chktex` lint。两者刻意不重叠——texlab 自带的 build 已关闭,只由 VimTeX 编译。

**一次性配置**

```bash
brew install --cask mactex-no-gui   # TeX Live:latexmk、latexindent、chktex
brew install --cask skim            # 支持 SyncTeX 的 PDF 阅读器
```

`texlab` 在第一次打开文件时由 Mason 自动安装,无需额外步骤。反向跳转(在 PDF 里点一下 → 跳回源码)需设置 **Skim → 偏好设置 → Sync → Preset 选 Custom**,Command 填 `nvim`,Arguments 填:

```
--headless -c "VimtexInverseSearch %line '%file'"
```

**日常使用** — 打开任意 `.tex` 文件,然后:

- `,Ll` — 连续编译开关（运行期间保存即重编）
- `,Lv` — 正向跳转：打开/定位 Skim 到光标所在行
- `,Lt` — 目录；`,Lc` 清理、`,Le` 错误列表
- 保存文件即用 `latexindent` 自动格式化(可用 `<leader>uf` 开关当前文件，`<leader>uF` 开关全局)

日常操作也提供少按一个键的入口，显示在 `,` 的 which-key 弹窗的 LaTeX 分区里：

| 键位 | 操作 |
|------|------|
| `,b` | 编译(连续模式开关) |
| `,v` | 用 Skim 看 PDF |
| `,s` | 停止编译 |
| `,K` | 清理辅助文件 |
| `,t` | 目录开关 |
| `,E` | 错误列表 |
| `,x` | 一次性 `latexmk` 出 PDF（通用的"运行当前文件"键） |

TeX 缓冲区还默认开启软 `wrap` 和 `spell`(可用 `<leader>uw` / `<leader>us` 开关)。

### 键位

**Leader**：`Space` · **操作 / Local leader**：`,` · **速查表**：`<leader>?`

每个键都在回答一个问题，前缀决定是哪一个：

| 前缀 | 问题 | 例子 |
|------|------|------|
| `;` | 我要去哪个文件 / 符号 / 位置？ | `;<space>` 智能查找、`;f` 找文件、`;/` 全局搜索、`;s` 符号、`;c` git hunk、`;1`-`;9` Harpoon 文件 |
| `,` | 当前文件 / 视图能做什么？ | `,a` code action、`,f` 格式化、`,r` 重命名、`,o` 整理导入（Go/Python）；终端内的 `,1`-`,9` |
| `s` | 这个窗口怎么办？ | `ss`/`sv` 分屏、`sd` 关闭、`se` 跳编辑器、`s=` 均分 |
| `<leader>` | 其余，按领域分组 | `g` git、`G` GitHub、`d` 调试、`t` 测试、`a` AI、`x` 诊断、`m` 管理、`s` 会话、`y` 复制（路径、`path:line`、permalink）、`u` 开关、`b` buffer、`q` 退出 |

常用操作使用短键，相关命令可放进子组，例如 `,e…` 提取重构、`,L…` VimTeX；
`<leader>` 按全局领域分组。按下任一前缀等一下，which-key 会列出当前映射。

`,` 菜单分别显示通用编辑、当前语言的操作类别（导入/环境、编译/预览、运行控制）
和视图操作。CodeDiff 视图会在源文件的语言分区旁增加两个分区：它的面板、布局和冲突键，
以及审阅键（`,C` 反馈、`,S` / `,U` 暂存 / 取消暂存一个 hunk、`,X` 把一个 hunk 丢弃回基线）。
搜索替换面板的专用操作放在 `,S…` 子组。
完整键表见[文件类型与视图操作](docs/MANUAL_CN.md#文件类型与视图操作)。
Local leader 共用逗号菜单，不额外占用一个前缀。

值得记住的无前缀键：

| 键 | 作用 |
|----|------|
| `f` / `F` | Flash 跳转 / Treesitter 跳转（Normal + Visual；`df-`、`ct)` 仍走原生） |
| `x` | 删除一个字符，不碰系统剪贴板和 yank 历史（Normal；交换两个字符用 `dlp`，不再是 `xp`） |
| `<C-h/j/k/l>` | 窗口移动——在终端输入状态下同样可用 |
| Insert 中的 `<C-l>` | 接受灰色的 [AI 补全建议](#行内-ai-补全) |
| `<C-,>` | 跳到编辑器区域，再按一次跳回 |
| `<C-/>` | 开关终端；文件中用 `3<C-/>` 打开终端 3；终端 Normal 模式下用 `,1`-`,9` 切换 |
| `<S-h>` / `<S-l>` · `[b` / `]b` | 上/下一个 buffer |
| `[B` / `]B` | 第一个 / 最后一个 buffer（按 buffer 栏顺序） |
| `<leader>b<` / `<leader>b>` | 把 buffer 左移 / 右移 |
| `g` · `[` / `]` · `z` | 跳转 + LSP（从光标下的符号出发）· 上/下一个某物 · 折叠与拼写 |
| `-` | 用 oil 打开当前目录（可当文本编辑） |
| `q` · `g?` · `<C-s>` / `<C-v>` / `<C-t>` · `<M-p>` | 在 picker、oil 或大纲里：关闭 · 列出它的键 · 在下方 / 旁边 / 新 tab 打开（大纲没有 tab）· 开关预览（picker、oil）。隐藏文件：picker 里 `<M-.>`，oil 里 `g.` |
| `jk`（lazygit 除外）· `<C-]>` / `<C-\>` | 输入法安全退出；在 Normal 中切回其输入源 |

Diff 视图都在 `<leader>g` 下，各自开在独立的 tabpage 里（CodeDiff）：

| 键 | 打开 |
|----|------|
| `gv` | Diff 视图：状态视图（已暂存、未暂存、未跟踪、冲突） |
| `gm` / `gM` | 对比 main 分支 / 对比选中的基线或 ref（分支、tag、commit）… |
| `gk` | 任选两端对比（工作区/index/基线/ref）… |
| `gK` | 保存基线…（起个名字），供 `gk` 和 `gM` 对比 |
| `gh` / `gH` | 文件 / 仓库历史（最近 100 个，不含 merge） |
| `gq` | 关闭本 tab 的 diff 视图 |

`gd` / `gD` 仍是 gitsigns 对当前文件的 diff，分别以分屏和行内显示；再按一次即关闭，
分屏也可以用 `gq` 关闭。视图里 `;`、`s` 和会换掉窗口 buffer 的键（`H` / `L`、
`[b` / `]b`、`[B` / `]B`（第一个 / 最后一个 buffer）、`<C-^>`，以及状态视图文件面板以外的 `-`——在那里它是暂存）都被禁用，
因为 picker、切换 buffer 或窗口键会弄坏它的窗格；在它的文件面板里按 `q` 也能关闭视图。
每种视图的 `,` 键做什么，见[使用手册](docs/MANUAL_CN.md#git)。

**→ [docs/MANUAL_CN.md](docs/MANUAL_CN.md) 有完整讲解**，从键位背后的组合规则讲起。

### 终端集成

Native coding-agent terminal 进入 Terminal-mode 时不再自动 resize，因此通过
`<C-h/j/k/l>` 切入时不会出现一行高度的闪动。如果 TUI 发生漂移，先用
`<C-]>`（或 `jk`）退出输入状态，再以 `<leader>md` 手动修复。打开编号底部终端
后，仍会修复因布局变化而受影响的可见 agent。

`<C-]>` 是统一且不受中文预编辑影响的退出键：在 Editor Insert 模式中等同
`<Esc>`；在包括 Codex 面板在内的所有终端中进入 terminal-Normal，
不会把该按键发送给子进程。在 Normal 中它仍是 Escape 而不是原生 tag jump，
同时会把手动打开的输入法切回 Normal 布局，因此不会把光标下的文字拿去查 tag
并产生 `E426`。
`help` 与 `man` 缓冲区例外，保留原生 tag jump——`<C-]>` 是它们跟随链接的
唯一方式；在那里清除搜索高亮仍可用 `<Esc>` 或 `<C-\>`。

Neovim 在 Normal 和 terminal-input 模式下都会接管 `<C-h/j/k/l>`，因此可以
直接在编辑器与终端窗口之间移动。这会覆盖 TUI 原有的 Ctrl 快捷键：向后删除
可用 Backspace，输入换行可用 `<S-Enter>`，picker 导航可用方向键。
`<C-S-l>` 会把原始 Ctrl+L 字节转发给终端，用于重绘 Codex
TUI；Nvim 自身的清屏重绘（`:mode`）则移到 Normal 模式的 `<leader>ur`。处在布局边缘时该键不做任何事、保持终端输入；浮动终端（lazygit、float 形态的
`<C-/>` shell）视为四面都是边缘——否则 shell 自己的 `<C-h>`、`<C-l>` 会从浮窗底
下跳出去。

由于 `<C-\>` 紧挨 `<C-]>`，它在 Normal、Insert、Visual 和 terminal-input 中都
执行同样的安全退出。在 Normal 中连续按既不会切换模式，也不会覆盖等待恢复的输入
源，因此两个相邻组合都不会因误触而突然切换窗口。

`<C-,>` 可以从 terminal input 或侧栏直接跳到编辑器窗口；在编辑器中再按一次会
回到来源窗口。它依赖 Ghostty 与 Nvim 协商的扩展键盘协议，以便和普通逗号区分；
如果 Nvim 外面还有一层 tmux，需要为其启用 `extended-keys`。在拿不到该协议的
环境里(原生 Terminal.app、ssh 会话、较老的 tmux),用 `se` 完成同样的
跳转。终端编号则完全不依赖该协议：终端内的 `,1`-`,9` 是普通按键，因为在外层 tmux 下
Ghostty 会把 Ctrl+数字编码成旧式字节，原来的 `<C-1>`-`<C-9>` 根本传不到 Nvim。

编号映射只存在于终端 buffer 的 Normal 模式下（在终端输入中先按 `jk` 或
`<C-]>`）。普通文件在同一个逗号菜单里显示语言操作；从文件用 `<C-/>` 重开上次的终端，
或用 `3<C-/>` 直接打开终端 3。

在 agent 面板里，`<Esc>` 属于 agent 而不是 Nvim。两个 CLI 都把快速双击 Esc 读作
「回到上一条消息」，因此 Snacks 的双击映射和全局 `<Esc><Esc>` 在面板里都不生效；
`<C-]>` 或相邻的 `<C-\>` 都只进入 terminal-Normal，不带修饰键的 `jk` 同理，
`<C-,>` 则直接回到编辑器。普通 `:terminal` 仍保留 `<Esc><Esc>`。

在 agent 面板里点击鼠标同样会保持 terminal-input 状态。只有当终端任务自己申请了
鼠标上报，Nvim 才会把鼠标事件转发给它，而两个 TUI 都不申请 —— 所以在此之前，任何
一次点击（包括切换 app 后点回终端窗口的那一下）都会让面板掉回 Normal 模式。启用
tmux wrapper 时由 tmux 申请并自行处理点击；未启用时，落在面板内的点击由 Nvim 吞掉。
点击其他窗口仍然会正常切过去。

agent 启动失败时，面板会保留、把它自己的报错留在屏幕上，按一次 `<Enter>` 才关闭。
两个 wrapper 的 tmux 收尾都会向 Nvim 报告成功（无论 agent 怎么退出的），所以在此
之前面板会静默关闭，报错随 tmux 服务器一起消失，`:messages` 里也什么都不剩。

两个 agent 的翻历史方式完全一致：两个 wrapper 的 tmux 都启用了 `mouse on` 和
50000 行 history。真实 transcript 归 tmux 所有，Nvim 的终端 buffer 里只有 tmux
最后合成的那一屏，所以滚动要走 tmux。保持 terminal-input 状态，以鼠标滚轮或
`<PageUp>` 进入 tmux copy-mode；用滚轮或 `<PageDown>` 向下查看，按 `q` 或
`<Esc>` 返回 agent 输入。也可以先退出 terminal input，再通过任意 Normal-mode
入口键（`i`、`a`、`I`、`A` 等）重新进入；这会自动退出 copy-mode 并回到实时
底部。如果已经处于 terminal-Normal mode，同一组滚动键（外加
`<C-u>`/`<C-d>`）会转发给 tmux，并在不退出 copy-mode 的前提下恢复 terminal
input，让下一次滚轮事件继续浏览历史。使用 `CLAUDE_WRAP_TMUX=0` 或
`CODEX_WRAP_TMUX=0` 时没有 tmux 可用，请先按 `jk`，再使用 Nvim 的普通滚动命令。

Nvim 内的 Codex 会使用 `--no-alt-screen --yolo`。YOLO 模式会绕过 Codex 的
审批与内置沙箱；`--no-alt-screen` 则让已完成的聊天输出进入 wrapper 的 tmux
history。

#### AI 快捷键

首期原生终端只启用 **Codex**。自定义
[agent-workbench.nvim](local-plugin/agent-workbench.nvim/README.md) 由 lazy.nvim
正常引用。Claude 后续扩展；当前移除 claudecode.nvim，以及 `aa`/`ad`/Oil `aS` 键。

每个 tab 右侧最多显示一个原生终端或 CodeCompanion chat。以下键作用于当前可见的
chat；从 CodeDiff 操作则使用来源 tab。没有可见目标时，投递会询问使用哪个 chat。

| `<leader>` 后的键 | 模式 | 作用 |
| --- | --- | --- |
| `an` / `al` | n,x | 新建 / 切换 chat；Visual 选区一并带入 |
| `ac` / `af` | n | 隐藏或恢复上次 chat / 聚焦 |
| `ab` / `as` | n / x | 加入文件 / 提前捕获的选区，不自动发送 |
| `ai` | n,x | 在本 Nvim 编辑 prompt；Visual 选区作为初始内容 |
| `ar` / `aR` / `am` | n | resume / continue / 选模型；复用运行中的会话 |
| `at` / `aT` | n | 阅读当前 / 选择历史原生 transcript |
| `av` / `aV` | n | 审阅本轮基线之后的修改 / 手动建立轮次 |
| `ae` / `ax` | n,x / n | HTTP 行内编辑 / 切换 HTTP key profile |
| `ao` | n | 浏览已保存的 CodeCompanion chat |

`an` 提供 Codex terminal、已安装 `codex-acp` 的 Codex ACP，以及设置了
`NVIM_OPENAI_API_KEY` 的 OpenAI HTTP。每个入口标明传输方式和计费来源。
原生会话每个 Nvim 只有一个，再次选择会复用。可在 `config/ai.lua` 增加 HTTP
profile；仅增加配置不能启用尚未实现的原生 Claude 后端。

#### 在 buffer 里编辑 prompt

`<leader>ai` 与 Codex 自己的 `ctrl+g` 使用同一个 `$EDITOR` 路径：
`local-plugin/agent-workbench.nvim/scripts/agent-editor`。TUI 传入真实输入草稿，
在普通 buffer 中编辑后以 `<C-d>` 写回并关闭；取消保留原输入。
`<C-v>` 可暂存剪贴板图片。`git commit` 等其他程序的编辑请求没有 agent owner，
不会接收 agent seed 或图片。

运行中的会话按选模型键时只会聚焦并提示使用 `/model`，避免提交已有草稿或回答
审批；全新会话可以把 `/model` 提交到空输入框。resume/continue 不会隐藏运行中的会话。

#### `@` 文件引用

`ab` 插入相对文件路径，Codex 从磁盘读取；buffer 未保存时会提示。
`as` 在异步 picker 出现前捕获选区：已保存选区使用文件和行范围引用，未保存内容
发送精确文本并说明。二者都不按 Enter。当前不支持发送目录列表选区。
CodeCompanion HTTP chat 接收 buffer 文本，ACP chat 接收路径并提示未保存的修改。

#### 附加图片

原生 prompt editor 中的 `<C-v>` 捕获剪贴板图片；投递时在 editor 关闭后交给
Codex 自身的粘贴通道。附件属于对应 prompt，取消或失败会清理。图片粘贴与 picker
中的 `<C-v>` 垂直分屏是不同动作，键位声明不混用。

#### 阅读历史输出

`at` 读取 Codex JSONL transcript，`aT` 选择历史记录。它们是只读视图，
独立于终端滚动历史。旧 Claude transcript 解析保留供历史审阅标签使用，
不代表启用了原生 Claude。

#### AI Chat 与 Provider

编辑 `lua/config/ai.lua`。有序 providers 可声明原生 `tui`、ACP、HTTP `api`。
新建 picker 按 terminal、ACP、HTTP 分组，各组沿用 provider 顺序。启动参数不选择
默认后端。`:AI` 切换 chat，`:AI new` 新建，`:AI info` / `:AIInfo` 查看状态与计费，
`:AI key [name]` 仅切换行内编辑和命令 prompt 的 HTTP key，不持久化。

`terminal.provider` 支持本配置默认的 `"snacks"`、无需 Snacks 的 `"native"`，以及
自定义内嵌 terminal provider。会话身份和状态由插件持有，Snacks 只负责可选的视图。
`native.codex` 声明 executable、argv、tmux 偏好；保留现有
`--no-alt-screen --yolo` 默认值。

切换仅隐藏本 tab 的其他 chat，保留进程与会话。目标在其他 tab 可见时会跳转并提示。
本 tab 的终端副本仍是此处的目标，不会隐藏另一 tab 的 owner 窗口。
唯一普通窗口不能隐藏，通知和预览浮窗不算额外普通窗口。

本地原生插件由 `plugin_dirs` 或 `NVIM_AI_PLUGIN_DIR` 指定，仅在原生启动时解析安装。
Codex 安装使用临时 CLI home，共享真实 plugin cache；不写用户 CLI 配置，也不全局启用插件。

#### CodeCompanion 的两种 Chat

ACP 通过 CLI bridge 使用订阅，HTTP 消耗 API credits；它们作为额外 chat/行内工作流
共享同一 tab 槽位。Chat 创建后 adapter 固定。HTTP adapter 读取 `NVIM_*` key；
Codex ACP 使用 `auth_method = "chat-gpt"`。`OPENAI_API_KEY` 等 CLI 计费变量可能改变
CLI 的计费方式，界面会提示。切 HTTP key 不启动、停止或移动原生终端和已有 chat。

codecompanion-history 保存本地 transcript；恢复 ACP agent 的有状态会话是另外的
`/resume` 流程。CodeCompanion 自带 review 关闭，统一使用 `refs/nvim-review/` 基线。

#### `Shift+Enter`（iTerm2）

外层终端应将修改后的 Enter 以 CSI u 送入 TUI，需要时设置 iTerm2 对应键位；
tmux wrapper 会保留该编码。终端 `<C-h/j/k/l>` 仍用于窗口导航，prompt editor 的
`<C-d>` 用于提交，与 picker 打开动作分开。

#### Native Agent 的 tmux 包裹

Codex 的 tmux renderer 合成同步 TUI 帧并保存滚动历史，与 terminal provider
独立；native 和 Snacks 都可使用。`CODEX_WRAP_TMUX=0` 或
`native.codex.wrap_tmux = false` 关闭它。保留 `EDITOR`、`VISUAL`、`NVIM`、
CLI 参数、CJK 和修改后的 Enter。`agent-run` 保留启动错误，`agent-teardown`
和 watchdog 清理所属 server 及后代进程。隐藏保留会话；stop 或退出 Nvim 才清理。

#### macOS 输入法

安装 `macism` 后，Nvim 会让 Normal 与 Terminal-Normal 模式保持在自动探测到的
拉丁键盘布局。进入 Insert 或终端输入模式时恢复离开前使用的输入源；离开这些
输入模式时先记录当前输入源，再切回英文。因此原先是英文就保持英文，原先是
搜狗/苹果拼音则会在回到文字输入时恢复。

如果已经在 Normal 模式时手动打开了输入法，按 `<C-\>`，或在 `help`/`man` 之外按
`<C-]>`，即可在不离开 Normal 的情况下记录它并切回 Normal 布局。只有 Nvim 确实
执行过这次关闭，下一次进入 Insert 或终端输入时才会恢复该输入源。重复按键是幂等
的；如果本来就是 Normal 布局，进入输入模式不会套用陈旧的已保存输入源。

Normal 模式的布局优先读取 `NVIM_ENGLISH_INPUT_SOURCE`，未设置时回退到 macOS
已启用的键盘布局（优先选拉丁布局，而不是系统列出的第一个；必要时再使用最近
布局）。配置刻意不监听 `FocusGained` /
`FocusLost`，所以在 Nvim 与其他应用之间切换不会改写其他应用的输入法状态。

`NVIM_MACISM_WAIT_TIME_MS=0` 会关闭 macism 临时抢焦点窗口，从而消除 Ghostty
可见的焦点闪动。代价是关闭 macism 的 CJK 激活 workaround，在 macOS 26 上开头
几个字符可能仍按英文输入；不设置该变量则使用 macism 内置等待（当前为 150ms）。

### 行内 AI 补全

在文件里打字时，光标后会出现一段灰色文字，是对这一行剩余部分的建议。
`<C-l>` 接受；继续打字时，只要你打的内容还和建议对得上，建议就跟着走，
对不上就换成新的建议。建议来自在本机 llama.cpp 里运行的 Qwen2.5-Coder 7B：
不需要账号和 API key，代码不出本机；它和 AI provider、右侧的 Chat 都无关。

模型只需下载一次（见[环境要求](#环境要求)里的 `llama-server` 那一行），存放在
Hugging Face 缓存 `~/.cache/huggingface/hub`。第一次在文件里进入 Insert 时会启动一个
所有 Nvim 共用的 `llama-server`，加载需要几秒，加载完成后不用再按键，光标处的建议
就会出现。它以 `--offline` 运行，
不会访问网络，也不会自行换成新版本的模型。沿着一行打字时，每条建议约 0.35 秒，
换到新位置约 0.8 秒。空闲五分钟后，服务释放模型，下一条建议到来时再重新加载，
约半秒；最后一个 Nvim 退出几秒后服务也会退出。Headless Nvim 不会启动它。

Markdown、纯文本、提交信息和 rebase 列表不自动出建议；没有 filetype 的 buffer
（`:enew` 之后、`:setf` 之前）以及终端、picker 和面板也不会。
`:Minuet virtualtext toggle` 可为当前文件 buffer 打开或关闭建议。排查见
[`docs/DIAGNOSTICS.md`](docs/DIAGNOSTICS.md#inline-completion-ghost-text)。

### API key

原生 Codex 与 Codex ACP 使用 ChatGPT 登录。OpenAI HTTP chat 和行内/命令 prompt
才读取 `NVIM_OPENAI_API_KEY` 并消耗 API credits。`OPENAI_API_KEY` 属于 CLI 自己，
可能覆盖订阅登录的计费方式，picker 和 health 会提示；本配置不写计费环境变量。

`key_profile = "auto"` 选择第一个设置了 key 的 HTTP profile，否则选第一个。
非空 `NVIM_AI_KEY_PROFILE` > `vim.g.ai_key_profile` > 配置文件。`:AI key <name>`
在当前进程固定 profile，`:AI key auto` 重新解析。额外 API-only profile 可读取其他
`NVIM_*` 变量。恢复历史 chat 时，内置 Anthropic/OpenAI adapter 也读取 `NVIM_*`，
不会静默回退到 CLI 的计费 key。

### 配置项

编辑 `lua/config/` 的声明后重启。校验与应用由 local plugin 负责，通过 lazy.nvim
spec 初始化；读取配置数据本身不安装映射、不启动进程。

| 文件 | 用户可修改的内容 |
| --- | --- |
| `options.lua`、`behaviors.lua` | 编辑偏好和可选行为 |
| `keymaps.lua` | 核心/AI 键位、共享打开动作、leader、幽灵文本接受键 |
| `theme.lua`、`dashboard.lua` | 主题、UI 偏好、dashboard 内容 |
| `ai.lua`、`review.lua` | provider/terminal/原生启动选择，轮次和投递策略 |
| `git.lua` | 历史数量、快照大小、保存基线保留数量 |
| `completion.lua` | 本地模型、argv、端口、幽灵文本偏好 |
| `whichkey_spec.lua` | 展示分组和分区；真实映射无需 which-key 也能工作 |

保留运行时 `vim.g.ai_review` 覆盖；其中历史 Git 字段继续优先，但可编辑默认值
统一放在 `git.lua`。`vim.g.terminal_position` 仍为启动时的 `"float"` 或 `"bottom"`。
安全规则、终端兼容、窗口归属和插件协调所需的内部值收在运行时 owner 中。
各 local package 与 [UTILITIES](docs/UTILITIES.md) 说明开放的插件接口。

### 环境变量

| 变量 | 说明 |
|------|------|
| `NVIM_AI_KEY_PROFILE` | 启动时的 HTTP key profile：`auto`（默认，取第一个已设置 `NVIM_*` key 的 provider）、`anthropic`、`openai`，或 `lua/config/ai.lua` 里其他 provider 的 `api.name`；名字不存在时给出警告并退回 `auto`。运行中用 `:AI key` 切换 |
| `NVIM_ANTHROPIC_API_KEY` | `anthropic` profile 的 key，供 CodeCompanion 的 API Chat 和 Inline/命令 Prompt 使用，见 [API key](#api-key) |
| `NVIM_OPENAI_API_KEY` | `openai` profile 的 key |
| `NVIM_ENGLISH_INPUT_SOURCE` | Normal 模式使用的 macOS 输入源 ID；未设置时使用 macOS 已启用的拉丁键盘布局 |
| `NVIM_MACISM_WAIT_TIME_MS` | 可选的 macism CJK workaround 等待时间；设为 `0` 可去掉临时焦点窗口，但可能出现首字符竞态 |
| `NVIM_LOG_LEVEL` | `editor_core.logger` 日志级别：`DEBUG`/`INFO`/`WARN`/`ERROR`（默认 `WARN`） |
| `NVIM_DEV=1` | 把 `editor_core.logger` 设为 `DEBUG`（更详细的日志） |
| `CODEX_WRAP_TMUX` | `1`/`0` — 覆盖 Codex 的 tmux 包裹默认行为。默认开。详见 [Native Agent 的 tmux 包裹](#native-agent-的-tmux-包裹)。 |

### 诊断

排查问题（启动慢、LSP 不挂载、格式化不生效等）见 [`docs/DIAGNOSTICS.md`](docs/DIAGNOSTICS.md)。运行 `:checkhealth config` 检查外部依赖、关键 Mason 包、Neovim 版本。

### 自定义

每个模块集中负责一个功能。AI 的可编辑默认值放在 `ai/config.lua` 和
`ai/review/config.lua`，运行状态与解析分别由 `ai/state.lua` 和
`ai/review/settings.lua` 管理；插件 spec 负责装配，各语言模块负责对应语言的完整集成。

**添加插件** — 在对应 `lua/plugin/*/` 目录下创建文件。

**添加语言支持、LSP 服务器或格式化工具** — 在 `lua/plugin/lang/` 中创建或修改
对应语言贡献。语言文件负责扩展共享的 nvim-lspconfig、Conform、lint、
Treesitter、DAP 和测试 spec；`lua/plugin/coding/` 只放编辑器级公共默认配置。

**添加、删除或调整 AI provider 的顺序** — 修改 `lua/config/ai.lua` 里的
`providers` 列表（见 [AI Chat 与 Provider](#ai-chat-与-provider)）。`acp` 和 `api`
用的是 CodeCompanion 已有 adapter 的 provider，只需加一项配置；新 kind 的 Native
终端需要写代码。

**调整文件/grep 搜索范围** — `;f` 与 `;/` 默认显示隐藏和被
gitignore 的文件；`.git/` 始终排除，`node_modules`、`target`、`.venv`、
`Pods` 等重型目录由 `lua/plugin/editor/snacks.lua` 的 `search_exclude` 统一
过滤。这个过滤不区分是否被 Git 跟踪，因此不要随意加入 `bin`、`out`、
`vendor` 这类可能包含源码的通用目录名。

`;i`（文件）和 `;?`（文本）遵守 `.gitignore`，仍显示隐藏文件，并取消额外的
目录排除。管理组中的 `<leader>mf` 搜索这份配置，`<leader>mF` 搜索已安装插件的源码。

## 许可

本配置按原样提供，仅供个人使用。
