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
- **[Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview)** 和/或 **[Codex](https://developers.openai.com/codex/cli/)** — Native coding agent；两者都能运行，和 CodeCompanion Chat 一样用 `<leader>an` 新建（见 [AI Chat 与 Provider](#ai-chat-与-provider)）
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
- **JDK 25+** — 用来运行 `jdtls`（Java）；项目本身仍可面向更早的版本。依次从 `$JAVA_HOME`、[SDKMAN!](https://sdkman.io/)（`~/.sdkman/candidates/java`）、PATH 中查找（见 [`lua/lang/java.lua`](lua/lang/java.lua)）
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

```
~/.config/nvim/
├── AGENTS.md                # Coding agent 的仓库级约定
├── CLAUDE.md                # Claude Code 对 AGENTS.md 的导入
├── init.lua                  # 入口文件
├── lua/
│   ├── options.lua           # Vim 选项
│   ├── mappings.lua          # 命令式核心键位（副作用）
│   ├── whichkey_spec.lua     # which-key 分组、弹窗分区、spec 键位（数据）
│   ├── autocmds.lua          # 自动命令
│   ├── bootstrap.lua         # lazy.nvim 初始化
│   ├── ai/                    # AI 状态、Chat 槽位、Native Claude/Codex 后端、CodeCompanion Chat、审阅轮次（ai/review/）
│   ├── config/
│   │   └── health.lua        # `:checkhealth config` 提供者
│   ├── lang/                 # 语言专属配置
│   │   ├── bash.lua
│   │   ├── dart.lua
│   │   ├── rust.lua
│   │   ├── c.lua             # C / C++
│   │   ├── frontend.lua      # HTML / CSS / Tailwind
│   │   ├── go.lua
│   │   ├── java.lua
│   │   ├── json.lua
│   │   ├── python.lua
│   │   ├── tex.lua           # LaTeX（VimTeX + texlab）
│   │   ├── typescript.lua    # JS / TS 语言（LSP、格式化、DAP）
│   │   └── yaml.lua
│   ├── plugin/
│   │   ├── editor/           # 编辑器增强插件
│   │   ├── lsp/              # LSP、补全、格式化、调试
│   │   ├── ui/               # 界面和主题插件
│   │   └── vcs/              # Git 集成
│   └── util/                 # 工具模块
├── .github/workflows/       # CI：spec 套件 + 一次 headless 启动检查
├── scripts/                 # Agent TUI 辅助脚本、共享 llama-server 的守护脚本
├── tests/                   # Headless spec 套件（tests/run.sh）
├── Makefile                 # 日常命令：make test、make verify 等
└── docs/                     # MANUAL.md, DIAGNOSTICS.md, UTILITIES.md
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

spec 刻意逐个运行：有些 spec 依赖同一时间只有一个 Nvim 在用的资源（`util.llama` 共享的 llama-server、git 与 gitsigns 的时序）。

### 插件列表

#### 界面

| 插件 | 说明 |
|------|------|
| [solarized-osaka](https://github.com/craftzdog/solarized-osaka.nvim) | 配色方案 |
| [lualine](https://github.com/nvim-lualine/lualine.nvim) | 状态栏，显示 `● REC @q` 宏录制标识、当前 buffer 的 git 改动行数（取自 gitsigns）和语言服务器（忙碌时显示转圈） |
| [incline](https://github.com/b0o/incline.nvim) | 文件窗口右上角的文件名标签；当前窗口显示粉色，`[+]` 表示未保存的修改 |
| [bufferline](https://github.com/akinsho/bufferline.nvim) | 缓冲区标签页（固定/关闭/选择，`;B` 按标签字母选一个）；`<leader>bh` 关掉所有 tabpage 里都没有窗口在显示的 buffer |
| [treesitter](https://github.com/nvim-treesitter/nvim-treesitter) | 语法高亮、文本对象 |
| [treesitter-context](https://github.com/nvim-treesitter/nvim-treesitter-context) | 粘性函数/类头（`<leader>uC`） |
| [nvim-ts-autotag](https://github.com/windwp/nvim-ts-autotag) | HTML/JSX 自动闭合标签 |
| [nvim-ufo](https://github.com/kevinhwang91/nvim-ufo) | 现代代码折叠 |
| [statuscol](https://github.com/luukvbaal/statuscol.nvim) | 行号栏：断点、诊断、git 标记各占固定位置；点击标记、行号或折叠符号即可操作 |
| [todo-comments](https://github.com/folke/todo-comments.nvim) | TODO/FIXME 高亮 |
| [illuminate](https://github.com/RRethy/vim-illuminate) | 光标下单词高亮；`]r` / `[r` 跳到它的下一处 / 上一处引用 |
| [colorizer](https://github.com/catgoose/nvim-colorizer.lua) | Hex/RGB/HSL、CSS 变量颜色预览；前端文件支持 Tailwind 颜色 |
| [render-markdown](https://github.com/MeanderingProgrammer/render-markdown.nvim) | 编辑器内 Markdown 渲染（`,m`） |

命令行和消息用的是 Neovim 自带的 ui2（实验性功能，见 `:help ui2`）：不再出现
"Press ENTER" 提示；放不下的输出收起为 `[+N]`，用 `g<` 或 `:messages` 在分页
窗口中查看（`q` 关闭）。通知由下面的 snacks 负责。

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
| [claudecode](https://github.com/coder/claudecode.nvim) | Native Claude Code 集成（始终声明，首次使用时才加载） |
| [CodeCompanion](https://github.com/olimorris/codecompanion.nvim) | 走 ACP、按订阅计费的 [Agent Chat](#codecompanion-的两种-chat)，以及走 HTTP、按 key profile 计费的 API Chat，都从 `<leader>an` 新建；另有用 key profile 的 Inline/命令 Prompt |
| [codecompanion-history](https://github.com/ravitemer/codecompanion-history.nvim) | 自动保存、按项目感知的 CodeCompanion Chat 历史 |
| [minuet-ai](https://github.com/milanglacier/minuet-ai.nvim) | 边输入边出现的 AI 灰色补全，模型在本机运行（[行内 AI 补全](#行内-ai-补全)） |

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
`<Esc>`；在包括 Claude/Codex 面板在内的所有终端中进入 terminal-Normal，
不会把该按键发送给子进程。在 Normal 中它仍是 Escape 而不是原生 tag jump，
同时会把手动打开的输入法切回 Normal 布局，因此不会把光标下的文字拿去查 tag
并产生 `E426`。
`help` 与 `man` 缓冲区例外，保留原生 tag jump——`<C-]>` 是它们跟随链接的
唯一方式；在那里清除搜索高亮仍可用 `<Esc>` 或 `<C-\>`。

Neovim 在 Normal 和 terminal-input 模式下都会接管 `<C-h/j/k/l>`，因此可以
直接在编辑器与终端窗口之间移动。这会覆盖 TUI 原有的 Ctrl 快捷键：向后删除
可用 Backspace，输入换行可用 `<S-Enter>`，picker 导航可用方向键。
`<C-S-l>` 会把原始 Ctrl+L 字节转发给终端，用于重绘 Codex 或 Claude Code
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

AI 相关的键都在 `<leader>a` 下；唯一出现在别的弹窗里的是 Git 视图逗号菜单中的 `,C`（审阅反馈），它的描述以 `[AI]` 开头。Chat 类的键作用于当前 tabpage **右侧的 Chat**——Native Claude Code、Native Codex 或 CodeCompanion Chat，右侧显示的是哪个就是哪个（见 [AI Chat 与 Provider](#ai-chat-与-provider)）——所以这些键的描述不写 agent 名。`ae` 的描述写明它计费所用的 key profile，并随 `:AI key` 更新；只属于 Claude 的 `aa` / `ad` 和 oil 里的 `aS` 写明 "Claude"。描述以 "…" 结尾的键会先询问再执行（`an`、`al`、`ar`、`am`、`ae`、`ax`、`ap`）；`aR` 不询问，右侧没有 Chat 时各 Chat 键都可能问的那个问题（发给哪个 Chat 或 agent）不算在内。

| 键 | 模式 | 作用 |
|----|------|------|
| `an` | n, x | 新建 Chat：选一个后端——Native 终端、ACP Chat 或 API Chat（`:AI new`） |
| `al` | n, x | 切换到另一个已打开的 Chat（`:AI`） |
| `ac` / `af` | n | 隐藏或重新显示 / 聚焦右侧的 Chat |
| `ab` / `as` | n / x | 把当前文件 / 选区加到右侧的 Chat |
| `ai` | n, x | [在 buffer 里撰写 prompt](#在-buffer-里编辑-prompt) |
| `ar` / `aR` | n | Native Agent：恢复过去的会话（选择器）/ 接着最近一次继续 |
| `am` | n | Native Agent：选择模型 |
| `at` / `aT` | n | Native Agent：[阅读 transcript](#阅读历史输出) / 浏览过去的 transcript |
| `av` / `aV` | n | [审阅自本轮基线以来的改动](docs/MANUAL_CN.md#审阅一轮-agent-修改) / 立即开始一轮；每条 prompt 都会开始一轮 |
| `aa` / `ad` | n | 接受 / 拒绝 Claude 的 diff（claudecode.nvim 加载之后才有） |
| `aS` | n（oil） | 把光标下的文件加给右侧的 Claude |
| `ae` | n, x | Inline 编辑（`:CodeCompanion`），用 API key profile |
| `ax` | n | 切换 API key profile（`:AI key`） |
| `ap` | n, x | CodeCompanion 操作面板 |
| `ao` | n | 浏览已保存的 CodeCompanion Chat（Chat 里的 `gh` 是同一个浏览器） |

在 Visual 模式下，`an` 和 `al` 会把选区带给它们打开的 Chat。Native Agent 类的键作用于
右侧的 Native Agent，右侧没有时询问用哪一个。

#### 在 buffer 里编辑 prompt

`<leader>ai` 打开右侧 Chat 的 prompt。CodeCompanion Chat 的输入区本来就是 buffer，
光标直接过去（从 Visual 模式调用时先加入选区）。Native Agent 的 prompt 开在一个浮动
buffer 里，长 prompt 就能用整个编辑器来写，而不是挤在 TUI 的输入框里。它存在的原因
是 Terminal 模式把 `<C-h/j/k/l>` 给了窗口导航，而那正是 agent TUI 的编辑键。

| 按键 | 行为 |
|------|------|
| `<C-d>` | 把 prompt 交回 agent（insert 模式下可用） |
| `<C-v>` | 附加剪贴板图片 |
| `<C-c>` | 取消，输入框保持原样 |
| `:wq` / `ZZ` | 交回 prompt |
| `:q!` | 取消 |

输入框里**已有的内容会带过来**；从 Visual 模式调用则先把选区加进去，形式与
`<leader>as` 键入 Codex 输入框的相同：`@path lines X-Y`，buffer 有未保存修改时则是
带围栏的精确文本。全程不提交——关闭 buffer 只是把文本交回输入框，回车仍然由你自
己按。

浮窗是**模态**的：窗口导航键（`<C-h/j/k/l>`、`<C-w>`）和相邻的退出按键
（`<C-\>`）都不会离开它，绕过这一层的焦点变化也会被拉回来。浮窗开着时 agent
正阻塞在编辑器上、不读 pty，否则一旦
出去就再也回不来——再按一次 `<leader>ai` 会回到已打开的 prompt（Visual 选区会追加
进去），而不是发一个会被 TUI 吞掉的 `ctrl+g`。Claude Code 和 Codex 可以同时各开
一个 prompt，焦点归较新的那个。

这不是我们自建的 buffer，而是 agent 自带的 `ctrl+g`（「在 `$EDITOR` 里编辑当前
prompt」），Claude Code 和 Codex 都实现了它。`$EDITOR` 指向
`scripts/agent-editor`，它把 prompt 开在**当前这个** nvim 里，而不是在
`:terminal` 里再套一个。`<leader>ai` 只是向 TUI 发送 `ctrl+g`，所以在 TUI 里直接
按 `ctrl+g` 效果完全相同。

走 CLI 这条路才能做到精确：CLI 把输入框写进一个临时 `.md` 文件，等编辑器退出，再
重新读回——换行原样保留，回写也由 CLI 自己完成。从终端屏幕上刮内容则做不到：两个
TUI 里**真换行和软换行渲染完全相同**（都是缩进两格的续行），刮下来的文本永远无法
可靠还原。

能走通靠的是 `$NVIM`：nvim 会在每个 `:terminal` 子进程里设置它，指向拥有该终端的
实例的 RPC socket。wrapper 用哨兵文件轮询而非 `--remote-wait`，因为 Neovim 没实现
后者（`E5600: Wait commands not yet implemented in Nvim`）。

如果 agent 没在运行，`<leader>ai` 会启动它并**等到输入框就绪**再发送按键——打进
一个还在启动的 TUI 的 `ctrl+g` 会被静默吞掉。就绪判断是唯一一处读取渲染后屏幕的
地方，且只用作触发信号：判断错的代价是丢一次按键，而不是弄坏 prompt 内容。

#### `@` 文件引用

输入 `@` 加片段即可补全项目文件，和 TUI 自己的输入框一样。候选来自这个 Nvim 所在
的项目根目录，且遵守 `.gitignore`——依次尝试 `git ls-files`、`fd`、`rg --files`，
一个都没有时菜单保持为空。过滤匹配完整相对路径（斜杠也算），接受后插入
`@path/to/file`。

紧跟在英文单词字符后面的 `@` 不算引用，所以 `jeff@gmail.com` 仍是邮箱；其他文字算
作边界，所以 `看看@init` 能补全。两个 agent 对这段文本的处理不同：Claude Code 在
提交时把 `@path` 解析成真正的文件引用，Codex 把它当作路径、由 agent 自己去读——
最终都会读到文件。补全源在 `lua/ai/mention.lua`，只对这类 prompt buffer 启用，普
通 markdown 完全不受影响。

#### 附加图片

在 prompt buffer 里按 `<C-v>` 暂存剪贴板图片，交回 prompt 时一并附加。已暂存的图
片以**虚拟行**显示在 buffer 末尾——虚拟行不属于 buffer 内容，所以写 prompt 时看得
见，又不会被当成正文发出去。直接在 TUI 里按 `ctrl+v` 同样有效。仅 macOS。

buffer 里不会写入任何占位文字：图片没法走 prompt 文件（那是纯 markdown），而且只
有 CLI 能把图片字节放进它的请求。所以做法是把暂存文件通过 TUI 自己的 `ctrl+v` 重
放一次，由 CLI 写它自己的 `[Image #N]` 标记。

重放必须等 buffer 关闭之后。实测：prompt 开着时 agent 正阻塞在编辑器上并会丢弃
pty 输入，此时发的 `ctrl+v` 收不到，退出后发的才收得到。取消编辑会丢弃暂存文件，
而不是把它们挂到一个你刚扔掉的 prompt 上。

#### 阅读历史输出

`<leader>at` 把右侧 Native Agent（右侧没有时由你选择）在当前项目最新的会话渲染成
只读 Markdown buffer，`<leader>aT` 浏览该项目过去的 transcript。buffer 内 `R` 重新读盘，`q` 关闭。正文可见，thinking 与
工具调用折叠，`zR` 全部展开，`za` 展开单个。

数据源是 CLI 自己的 JSONL transcript，而非终端。Claude 运行在 alternate screen
上，其 tmux wrapper 完全不保留回滚内容——pane 里根本没东西可抓。读取落盘的
transcript 是唯一对两个 agent 都成立的方案，且重启 Nvim 后依然可查，也不需要
改动 tmux wrapper。

两家 CLI 都不会把推理文本落盘，所以折叠的 thinking 段落通常是不存在，而不是空的。

#### AI Chat 与 Provider

每个 tabpage 的右侧**最多只显示一个 AI 窗口**：Native Claude Code、Native Codex 或
一个 CodeCompanion Chat——按键说明里统称 *Chat*。显示一个，就会隐藏同一 tabpage
里的其他几个。隐藏从不等于停止：正在运行的 agent、正在回复的 Chat 都会继续（回复到
一半被隐藏、或在看不见时请求工具审批，都会提示一声）。其他 tabpage 不受影响。

- `<leader>an`（`:AI new`）在本机可用的任一后端上新建 Chat。每一项都写明在哪里运行、
  由谁计费：先是所有终端，再是所有 ACP Chat，最后是所有 API Chat，每组内按 provider
  的顺序（见下文）：

  ```text
  Claude Code · terminal · subscription
  Codex · terminal · subscription
  Claude Code · CodeCompanion ACP · subscription
  Codex · CodeCompanion ACP · subscription
  Anthropic · CodeCompanion API · API credits
  OpenAI · CodeCompanion API · API credits
  ```

  缺 CLI、缺 ACP bridge 或缺 `NVIM_*` key 的条目不会列出。每个 Native Agent 在一个
  Nvim 里只有一个会话：它的条目显示的就是这个会话（*running*、*● here*），不会再开
  第二个。由它新建的 Chat 或会话会弹出提示，并写明计费方式。
- `<leader>al`（`:AI`）列出已打开的 Chat——*● here*、*tab N* 或 *hidden*，附带计
  费方式——最后一项是 *New chat…*。显示在别的 tabpage 里的 Chat 会跳过去，不会被挪
  过来；隐藏的 Chat 会显示在当前 tabpage。
- `<leader>ac` 隐藏右侧的 Chat；右侧没有时，重新显示这个 tabpage 上次显示的那个
  （没有就用唯一打开的那个，否则询问）。`<leader>af` 进入右侧的 Chat——终端输入模式，
  或 Chat 的输入区——且从不隐藏它。
- `<leader>as`、`ab`、`ai` 发给右侧的 Chat。右侧没有时会询问：绝不会悄悄发给隐藏的
  Chat、别的 tabpage 的 Chat 或替你选定的 agent，取消则什么都不发。选区在询问之前就已取下，
  所以不会因为询问而丢失。Claude Code 收到所选行的文件引用，Codex 收到键入输入框的
  `@路径 lines X-Y` 引用，Chat 收到加进输入区的围栏代码块；都不会提交。两个 agent
  都读磁盘上已保存的文件，所以 buffer 有未保存修改时，Codex 改收精确的文本，Claude
  Code 则给出警告。`<leader>ab` 只给 Native Agent；Chat 用选区，或在自己的输入区里
  用 `#{buffer}`。
- 在 CodeDiff 视图里，这些键作用于打开该视图的那个页面，并切换到那里，视图里不会打开
  任何东西；在视图里取消询问会回到视图。
- Claude Code 隐藏时仍能看到编辑器里的选区：claudecode 的选区跟踪一直开着，与右侧
  显示什么无关。

`<leader>ar`、`aR`、`am`、`at`、`aT` 属于 Native Agent：右侧的那个，否则由你选择
（已安装的 agent 按 provider 顺序列出；只装了一个时就是它）。每个 Native Agent 在
一个 Nvim 里只有一个会话，所以 agent 已在运行时，`ar`、`aR`、`am` 只把它显示出来，
并提示在里面怎么做（`/resume`、`/model`），而不是再开一个会话；也不会往它的输入框里
打字，因为那里可能有草稿。由它们启动的会话会弹出提示。`at`、`aT` 从磁盘读取 agent
的记录，不管它是否在运行。

**Provider** 是 `lua/ai/config.lua` 里的一个有序列表，写法和 CodeCompanion 的
adapter 类似。每个 provider 写明一家厂商以及它提供的部分；没写的部分就不提供：

| 部分 | 提供什么 | 计费 |
|------|----------|------|
| `tui = { kind }` | Native 终端 agent。`kind` 只能是 `claude` 或 `codex`，每种最多出现一次；新的 kind 需要写代码（backend 模块、tmux wrapper、prompt hook、transcript 读取），不是加一项配置就行 | 订阅 |
| `acp = { adapter, command, auth_method? }` | 走 ACP 的 CodeCompanion Agent Chat：`adapter` 是 CodeCompanion 的 ACP adapter，`command` 是它需要在 PATH 里找到的 bridge | 订阅 |
| `api = { adapter, api_key, label?, model?, name? }` | 用内置 adapter `adapter` 走 HTTP 的 CodeCompanion API Chat，同时也是名为 `name`（默认为 `adapter`）的 key profile，名字不能重复 | API 额度，用 `api_key` 这个 `NVIM_*` 变量 |

默认是 Claude（`claude` 终端、经 `claude-agent-acp` 的 `claude_code`、用
`NVIM_ANTHROPIC_API_KEY` 的 `anthropic`），然后是 Codex（`codex` 终端、经
`codex-acp` 并使用 ChatGPT 登录的 `codex`、用 `NVIM_OPENAI_API_KEY` 的 `openai`）。
Nvim 启动时会检查这个列表，有问题的条目会让启动失败，并指出是哪个 provider。

没有默认后端：顺序就是唯一的偏好。`<leader>an` 先列终端，再列 ACP Chat，最后列 API
Chat，每组内按 provider 顺序；只有 Native Agent 才响应的键，在右侧没有 Native Agent
时按这个顺序列出已安装的终端供选择；CodeCompanion 自己那些不指定 adapter 的路径（手动
输入的 `:CodeCompanionChat`、操作面板）用第一个 `acp`，没有就用第一个 `api`。想让
Codex 排在前面，就把它的条目移到 Claude 之前。没有任何启动选项或环境变量用来选
agent：`NVIM_AI_PROVIDER` 和 `vim.g.ai_provider` 已不再读取，残留的值只会换来一次
警告。不做任何持久化：每个 Nvim 都按这个列表和自己的环境变量启动。

**key profile** 决定 Inline 编辑和命令 Prompt（`<leader>ae`、`:CodeCompanion`）用哪
把 API key 计费。每个 provider 的 `api` 就是一个 profile，名字是 `api.name`（默认为
`api.adapter`）。缺省的 `auto` 取 Nvim 启动时（或执行 `:AI key auto` 时，导出了新 key 之后它会重新选）第一个已设置
`NVIM_*` key 的 profile，都没设置就取第一个：按默认配置是 Anthropic，只设置了
`NVIM_OPENAI_API_KEY` 时是 OpenAI。`:AI key <name>` 和可选的 `NVIM_AI_KEY_PROFILE`
会固定一个。API Chat 用的是它在 `<leader>an` 里那一项所写的 profile。

| 命令 | 作用 |
|------|------|
| `:AI` / `<leader>al` | 切换到另一个已打开的 Chat |
| `:AI new` / `<leader>an` | 在任一可用后端上新建 Chat |
| `:AI key <profile>` / `<leader>ax` | 固定一个 key profile（不带名字时弹出选择器） |
| `:AI key auto` | 取消固定：回到第一个已设置 key 的 profile |
| `:AI info`（或 `:AIInfo`） | 按顺序列出各 provider 及其部分（terminal · ACP · API，在本机无法启动的标 ✗）、CodeCompanion 自己的 Chat 所用的 adapter、当前 key、每个 profile 的变量（只显示是否已设置，不显示值）、各 CLI 自己的 key 变量，以及每个已打开的 Chat 在哪里 |

切换 key 只影响 Inline 编辑和命令 Prompt：不会启动、停止、显示或隐藏任何 Chat、
终端或 ACP 连接，已打开的 Chat 保留创建时的 adapter。固定了 profile 时状态栏会显示
它（`󰌆 OpenAI`），点击可以再次切换。`:AI provider` 已经没有了：新 Chat 在
`<leader>an` 里选后端，顺序以 `lua/ai/config.lua` 为准。

运行 `:checkhealth config` 可检查每个 provider 的 CLI、ACP bridge 和 HTTP 凭据。
缺了 CLI 或 bridge 只是警告，因为选择器会直接不列出它；没设置的 `NVIM_*` key 只在
属于当前 key profile 时才算警告；只有什么都用不了时才报错。

`NVIM_AI_PLUGIN_DIR` 为 Claude/Codex 原生终端加载本地插件，多个目录用逗号分隔。
也可以填写包含两种宿主发行包的目录，见[原生终端的本地插件](docs/MANUAL_CN.md#原生终端的本地插件)。

#### CodeCompanion 的两种 Chat

CodeCompanion 的 Chat 是一个 Neovim buffer，分两种。打开后看起来差不多，但运行方式
和计费方式都不同。两种都从 `<leader>an` 新建，和 Native 终端共用右侧的位置：

| | Agent Chat · ACP | API Chat · HTTP |
|---|---|---|
| 选择器条目 | `Claude Code · CodeCompanion ACP · subscription`，Codex 同理 | `Anthropic · CodeCompanion API · API credits`，每个 key profile 一项 |
| 对接 | agent，经它的 ACP bridge（`claude-agent-acp` / `codex-acp`） | 该 profile 对应的 API，直接走 HTTP（`anthropic` / `openai`） |
| 计费 | 你的 Claude 或 ChatGPT 订阅 | [API 额度](#api-key)，用该 profile 的 `NVIM_*` key |
| 工具 | agent 自己的工具；`\` 补全它的斜杠命令 | CodeCompanion 的 `@` 工具，以及它的 MCP server（这里没有配置） |
| 长对话 | agent 自己管理上下文 | `/compact`，接近上下文上限时也会自动压缩 |
| 保存 | codecompanion-history（`<leader>ao`）；`/resume` 列出 agent 自己的会话 | 同样有 codecompanion-history，另有 CodeCompanion 自己的 session：`/save` 保存，`/resume` 恢复；还有 `/fork`、`/rename` |
| 回复标题 | `CodeCompanion (Claude Code · ACP)` | `CodeCompanion (Anthropic · API)` |

- Chat 保留创建时的后端；换后端就是另一个 Chat。两个 Chat 之间切换时，右侧的窗口原
  地交接。
- `<leader>as` 把 Visual 选区作为带围栏的代码块加进右侧的 Chat，不会提交；
  `<leader>ai` 把光标放进它的输入区（从 Visual 模式调用时先加入选区）。
- 在 Chat 里，`<CR>` 发送（Insert 模式下用 `<C-d>`），`<C-c>` 停止回复。`q`
  隐藏 Chat，与 `<leader>ac` 相同，再按 `<leader>ac` 即可带回；`,q` 结束它，
  CodeCompanion 会在它的窗口里显示另一个打开着的 Chat。`,X` 清空消息，`,z` 折叠
  代码块，`,s` 保存 Chat，`gf` 打开光标下的文件，`?` / `g?` 列出全部键。Insert 中的
  `<C-c>` 退出 Insert 模式，`gx` 打开 URL，`{` / `}` 按段落移动，与别处一致；换到
  另一个 Chat 用 `<leader>al`。
- `<leader>ae` 打开 `:CodeCompanion `（在 Visual 模式下带上范围），用的是 key
  profile，`<C-c>` 停止它的请求；不写提示词时会弹出浮窗，`<CR>`（Insert 模式下
  `<C-d>`）发送，`q` / `<Esc>` 关闭。`<leader>ap` 是操作面板。
- 缺 key 会在启动任何东西之前被发现：`NVIM_*` key 没设置的 API Chat、ACP bridge
  不在的 Agent Chat，`<leader>an` 都不会列出；`<leader>ae` 会直接提示，而不是发出
  请求再收到 401。从历史恢复的 Chat、操作面板（`<leader>ap`）里的 *Inline prompt*，
  以及手动输入的 `:CodeCompanion` 不经过这道检查。
- CodeCompanion 自己那些不指定 adapter 的命令（手动输入的 `:CodeCompanionChat`、操作
  面板里的 Chat）会按 provider 顺序用第一个 `acp` 新建 Chat（默认配置下是 Claude
  Code），没有 `acp` 时用第一个 `api`；右侧原有的内容会给它让位。
- Codex ACP 使用 ChatGPT 登录：不管 provider 列表里写了什么，CodeCompanion 内置的
  `codex` ACP adapter 都会设为 `auth_method = "chat-gpt"`，所以从历史恢复的 Chat
  也一样；provider 自己的 `acp.auth_method` 可以覆盖它。codex-acp 自己的默认值会改用
  `OPENAI_API_KEY` 计费。

codecompanion-history 会在发送消息和回复结束时保存每个 Chat，两种都存。用
`<leader>ao`（或 `:CodeCompanionHistory`）打开；Chat buffer 内也可按 `gh`。历史
列表使用 Snacks picker：`r` 重命名，`dd`（输入时用 `<C-x>`）删除，与 buffer picker
一致；为避免额外的模型请求，自动生成标题已关闭。
History 恢复的是 CodeCompanion 本地的 transcript；要继续 agent 真正的有状态会话，
请在新的 Agent Chat 中使用 `/resume`。

#### `Shift+Enter`（iTerm2）

在 Neovim 内运行终端应用（如 Claude Code）时，`Shift+Enter` 需配置 iTerm2：

Settings → Profiles → Keys → Key Mappings → 添加：
- **Shortcut**：`Shift + Return`
- **Action**：`Send Escape Sequence`
- **Value**：`[13;2u`

#### Native Agent 的 tmux 包裹

Claude Code 和 Codex 默认分别在 provider 专属的 tmux server 中启动，见
`lua/plugin/lsp/ai.lua` 与 `lua/ai/backend/codex.lua`。

**原因**：两个 TUI 都会发出 DEC mode 2026（Synchronized Output）序列来做
原子帧更新。Neovim 的 `:terminal` buffer 不识别该协议，因此半帧可能留下
重复状态栏或旧单元格。tmux 会先合成同步帧，再向 Nvim 输出普通终端更新。
这与 Ghostty / WezTerm / iTerm2 等宿主终端无关，相关层是 Nvim 内嵌的
libvterm。

**代价**：包了 tmux 之后，tmux、宿主终端和 Agent TUI 对 CJK 宽字符的
宽度判定可能不一致，带框 UI 可能有轻微错位。

**按键**：两个 wrapper 的 tmux 都设置了 `extended-keys always` 和
`extended-keys-format csi-u`。tmux 默认的 `extended-keys off` 会把 `<S-Enter>`
发出的 `ESC[13;2u` 压成普通回车，结果是直接发送消息而不是换行。`always` 让
tmux 不等 TUI 申请就保留修饰键，CSI u 则是 Claude Code 和 Codex 都能解析的
格式。其他有传统编码的按键到 TUI 时不受影响。

**收尾**：关闭面板或退出 Nvim 时会运行 `scripts/agent-teardown`：先杀掉 wrapper
的 tmux server，再清掉 agent 留在自己进程组里的东西——比如 Codex `exec_command`
起的 dev server、后台 Bash 任务——因为 tmux 只会给 pane 自己的进程发信号。agent
顺带拉起的共享守护进程（模拟器、Gradle daemon、容器运行时）会被放过；用
`NVIM_AGENT_TEARDOWN_IGNORE` 设一个 awk 正则可以改这份清单。每次运行记录在
`~/.local/state/nvim/agent-teardown.log`。

**覆盖配置**：
- `CLAUDE_WRAP_TMUX=0 nvim` — 一次性 A/B 测试
- `vim.g.claude_wrap_tmux = false` 写入 `init.lua` — 永久关闭
- `CODEX_WRAP_TMUX=0 nvim` / `vim.g.codex_wrap_tmux = false` — Codex 的对应开关
- 安装 tmux 时两个 wrapper 都默认开启

**提示——抑制 recap CJK 错位框**：Claude Code 的 session recap 是最显眼的 CJK 错位受害者。在 `~/.claude/settings.json` 设置 `"awaySummaryEnabled": false` 可关闭。注意这是 Claude Code 的全局配置，不属于 nvim。

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

Agent 本身不需要 key：Claude Code 和 Codex，无论是 Native 终端还是 Agent Chat，
都用你的 Claude 或 ChatGPT 登录（订阅）。key 只给 CodeCompanion 的 API Chat 以及
Inline 和命令 Prompt（`<leader>ae`、`:CodeCompanion`）用，它们直接调用 API：API Chat
用它在 `<leader>an` 里那一项所写的 profile，Inline 和命令 Prompt 用
[key profile](#ai-chat-与-provider)——`auto` 时是第一个已设置 key 的 provider（默认
配置下 Anthropic 在 OpenAI 之前）；`:AI key` 可以固定成别的。

| 变量 | Key profile | 在哪里创建 |
|------|-------------|-----------|
| `NVIM_ANTHROPIC_API_KEY` | `anthropic`，Claude 的 `api`（只要设置了就是 `auto`） | [Anthropic Console](https://platform.claude.com/) → API keys |
| `NVIM_OPENAI_API_KEY` | `openai`，Codex 的 `api`（只设置了它时是 `auto`） | [OpenAI Platform](https://platform.openai.com/api-keys) |

同一家 API 的第二把 key，就是在 `lua/ai/config.lua` 里再加一个只有 `api` 部分的
provider，配上自己的 `api.name` 和自己的 `NVIM_*` 变量（文件里有一个注释掉的示例）；
之后它会作为 API Chat 出现在 `<leader>an` 里，也会出现在 `:AI key` 里。

不要用 `ANTHROPIC_API_KEY` 或 `OPENAI_API_KEY`。它们是 CLI 自己的变量，
只要环境里有其中一个，从那个 shell 或 Nvim 启动的 agent 就可能改走 API 计费，
而不是你的订阅。本配置不读取它们，指向它们的 key profile 会在启动时直接报错；
两者任一被设置时，`:checkhealth config` 都会给出警告。CodeCompanion 内置的
`anthropic` 和 `openai` adapter 不管 provider 列表里写了什么，都改读
`NVIM_ANTHROPIC_API_KEY` 和 `NVIM_OPENAI_API_KEY`，所以从历史恢复的 Chat 也不会读
CLI 的变量。

1. 单独给 Nvim 建一个 key，方便单独吊销。消费上限设在 key 所属的容器上，
   而不是 key 本身：要限额，就在一个单独的 Anthropic workspace（或 OpenAI
   project）里创建 key，并给它设上限。Console 里的 identity federation 是给云端
   和 CI 工作负载用的，这里选 *Continue with an API key*。
2. 在一个不会提交的 shell 启动文件里导出它，例如被 `.zshrc` source、
   且已加入 gitignore 的文件：
   ```sh
   export NVIM_ANTHROPIC_API_KEY="sk-ant-..."
   export NVIM_OPENAI_API_KEY="sk-proj-..."   # 只有用 openai profile 时才需要
   ```
3. 打开一个新 shell，从这个 shell 启动 Nvim，运行 `:checkhealth config`：
   *AI backends* 一节会显示已找到 key。

这个变量名能防止 agent 拿它计费，但不能防止 agent 看到它：和所有导出的变量一样，
它会传给 Nvim 启动的每个进程，包括 agent 终端。不要把它放进任何会提交或分享的内容。

### 配置项

在 `init.lua` 里插件加载前设置。

| 选项 | 说明 |
|------|------|
| `vim.g.terminal_position` | `"float"`（默认）或 `"bottom"`，决定编号终端在哪里打开。只在启动时选定，不支持运行时切换——Snacks 在开窗那一刻定死窗口形态，edgy 又独立判断终端是否属于底部边栏，运行时切换意味着要在每一次隐藏、显示、重排里维持两者一致。 |
| `vim.g.ai_review` | 审阅闭环和 diff 视图的设置：保留多少轮次和基线、哪些对话会开启轮次、投递时如何确认、Native Claude 从哪里启动、`<leader>gh` / `<leader>gH` 列出多少历史。只写要改的键，例如 `{ retention = { rounds = 30 } }`；全部键和默认值见[使用手册](docs/MANUAL_CN.md#设置vimgai_review)。 |

### 环境变量

| 变量 | 说明 |
|------|------|
| `NVIM_AI_KEY_PROFILE` | 启动时的 HTTP key profile：`auto`（默认，取第一个已设置 `NVIM_*` key 的 provider）、`anthropic`、`openai`，或 `lua/ai/config.lua` 里其他 provider 的 `api.name`；名字不存在时给出警告并退回 `auto`。运行中用 `:AI key` 切换 |
| `NVIM_ANTHROPIC_API_KEY` | `anthropic` profile 的 key，供 CodeCompanion 的 API Chat 和 Inline/命令 Prompt 使用，见 [API key](#api-key) |
| `NVIM_OPENAI_API_KEY` | `openai` profile 的 key |
| `NVIM_ENGLISH_INPUT_SOURCE` | Normal 模式使用的 macOS 输入源 ID；未设置时使用 macOS 已启用的拉丁键盘布局 |
| `NVIM_MACISM_WAIT_TIME_MS` | 可选的 macism CJK workaround 等待时间；设为 `0` 可去掉临时焦点窗口，但可能出现首字符竞态 |
| `NVIM_LOG_LEVEL` | `util.logger` 日志级别：`DEBUG`/`INFO`/`WARN`/`ERROR`（默认 `WARN`） |
| `NVIM_DEV=1` | 把 `util.logger` 设为 `DEBUG`（更详细的日志） |
| `CLAUDE_WRAP_TMUX` | `1`/`0` — 覆盖 Claude Code 的 tmux 包裹默认行为。默认开。详见 [Native Agent 的 tmux 包裹](#native-agent-的-tmux-包裹)。 |
| `CODEX_WRAP_TMUX` | `1`/`0` — 覆盖 Codex 的 tmux 包裹默认行为。默认开。详见 [Native Agent 的 tmux 包裹](#native-agent-的-tmux-包裹)。 |
| `CLAUDE_CHROME` | `1`/`0` — 开关 Native Claude 进程的 Claude in Chrome。默认开。 |

### 诊断

排查问题（启动慢、LSP 不挂载、格式化不生效等）见 [`docs/DIAGNOSTICS.md`](docs/DIAGNOSTICS.md)。运行 `:checkhealth config` 检查外部依赖、关键 Mason 包、Neovim 版本。

### 自定义

**添加插件** — 在对应 `lua/plugin/*/` 目录下创建文件。

**添加语言支持、LSP 服务器或格式化工具** — 在 `lua/lang/` 中创建或修改
对应语言贡献。语言文件负责扩展共享的 nvim-lspconfig、Conform、lint、
Treesitter、DAP 和测试 spec；`lua/plugin/lsp/` 只放编辑器级公共默认配置。

**添加、删除或调整 AI provider 的顺序** — 修改 `lua/ai/config.lua` 里的
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
