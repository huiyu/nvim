# Neovim 配置

[English](README.md)

基于 Lua 和 [lazy.nvim](https://github.com/folke/lazy.nvim) 构建的现代 Neovim 配置。键位和插件选择与 [LazyVim](https://www.lazyvim.org/) 对齐，支持 Go、C/C++、Python、Java、Web、Bash、JSON、YAML、LaTeX 开发。

### 环境要求

**必装：**
- **Neovim** >= 0.11.3（用到 `vim.lsp.config`/`vim.lsp.enable`、`vim.hl`、`vim.diagnostic.jump`）
- **Git**
- [Nerd Font](https://www.nerdfonts.com/)（图标显示）
- **ripgrep** (`rg`) — `Snacks.picker.grep` / `live_grep` / `:grep` 的底层
- **fd** — 文件查找（`venv-selector` 和部分 picker 用到）

**可选（按功能）：**
- **[lazygit](https://github.com/jesseduffield/lazygit)** — `<leader>gg`（项目）/ `<leader>gf`（当前文件历史）
- **[tmux](https://github.com/tmux/tmux)** — 把选中的 Native Agent TUI 包到 `:terminal` 里，避免残影和帧撕裂；自动检测（详见[终端集成](#终端集成)）
- **[GitHub CLI](https://cli.github.com/)** — 已认证的 `gh`，供 `<leader>G` GitHub picker 与状态使用
- **[Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview)** 或 **[Codex](https://developers.openai.com/codex/cli/)** — Native coding agent
- **Node.js >= 22 + npm** — CodeCompanion ACP bridge 进程
- `ANTHROPIC_API_KEY` 或 `OPENAI_API_KEY` — 可选；所选 provider 的 CodeCompanion HTTP Inline/命令 Prompt
- **[cowsay](https://en.wikipedia.org/wiki/Cowsay)** + **lolcat** — 启动页 banner（任一个缺失都会静默跳过）

**macOS 一键安装：**
```bash
brew install neovim git gh ripgrep fd lazygit tmux cowsay lolcat node
brew install --cask font-jetbrains-mono-nerd-font  # 任意 Nerd Font 都行
gh auth login                                      # 首次为 GitHub picker 认证
npm install -g @agentclientprotocol/claude-agent-acp @agentclientprotocol/codex-acp
```

**语言工具链** — *只有想用对应的 Mason 包时才需要：*
- **Go** — `gopls`、`gofumpt`、`gomodifytags`、`impl`、`delve` 都依赖
- **Python >= 3.10** — `black` 需要（`pyenv` 或 `uv` 管理的解释器都可以）
- **Node.js + npm** — `eslint-lsp`、`css-lsp`、`html-lsp`、`json-lsp`、`yaml-language-server`、`tailwindcss-language-server`、`vtsls`、`bash-language-server` 都依赖
- **JDK 17+** — `jdtls`（Java）需要。本配置假设走 [SDKMAN!](https://sdkman.io/)，路径写死在 `~/.sdkman/candidates/java/current`（见 [`lua/lang/java.lua`](lua/lang/java.lua)）
- **TeX Live + Skim**（LaTeX）— `brew install --cask mactex-no-gui` 提供 `latexmk`/`latexindent`/`chktex`，`brew install --cask skim` 提供支持 SyncTeX 的 PDF 阅读器；`texlab` 由 Mason 安装。反向跳转需在 Skim → 偏好设置 → Sync 中选 Custom：命令填 `nvim`，参数填 `--headless -c "VimtexInverseSearch %line '%file'"`

如果 Mason 安装失败，运行 `:Mason`（UI）或 `:MasonLog`（原始日志）查看具体错误。最常见的原因是上面这些工具链没装。

### 安装

```bash
mv ~/.config/nvim ~/.config/nvim.backup
git clone https://github.com/huiyu/nvim.git ~/.config/nvim
nvim
```

### 项目结构

```
~/.config/nvim/
├── AGENTS.md                # Coding agent 的仓库级约定
├── CLAUDE.md                # Claude Code 对 AGENTS.md 的导入
├── init.lua                  # 入口文件
├── lua/
│   ├── options.lua           # Vim 选项
│   ├── mappings.lua          # 命令式核心键位（副作用）
│   ├── whichkey_spec.lua     # which-key 分组 + spec 键位（数据）
│   ├── autocmds.lua          # 自动命令
│   ├── bootstrap.lua         # lazy.nvim 初始化
│   ├── ai/                    # Provider 配置 + Native Claude/Codex facade
│   ├── config/
│   │   └── health.lua        # `:checkhealth config` 提供者
│   ├── lang/                 # 语言专属配置
│   │   ├── bash.lua
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
├── .github/workflows/       # CI：spec 套件 + 两个 provider 启动检查
├── scripts/                 # Agent TUI 的 $EDITOR wrapper
├── tests/                   # Headless spec 套件（tests/run.sh）
└── docs/                     # MANUAL.md, DIAGNOSTICS.md, UTILITIES.md
```

### 插件列表

#### 界面

| 插件 | 说明 |
|------|------|
| [solarized-osaka](https://github.com/craftzdog/solarized-osaka.nvim) | 配色方案 |
| [lualine](https://github.com/nvim-lualine/lualine.nvim) | 状态栏 |
| [incline](https://github.com/b0o/incline.nvim) | 每个窗口右上角的文件名标签（当前窗口除外） |
| [bufferline](https://github.com/akinsho/bufferline.nvim) | 缓冲区标签页（固定/关闭/选择） |
| [noice](https://github.com/folke/noice.nvim) | 增强命令行、消息、通知 |
| [treesitter](https://github.com/nvim-treesitter/nvim-treesitter) | 语法高亮、文本对象 |
| [treesitter-context](https://github.com/nvim-treesitter/nvim-treesitter-context) | 粘性函数/类头（`<leader>uC`） |
| [nvim-ts-autotag](https://github.com/windwp/nvim-ts-autotag) | HTML/JSX 自动闭合标签 |
| [nvim-ufo](https://github.com/kevinhwang91/nvim-ufo) | 现代代码折叠 |
| [todo-comments](https://github.com/folke/todo-comments.nvim) | TODO/FIXME 高亮 |
| [illuminate](https://github.com/RRethy/vim-illuminate) | 光标下单词高亮 |
| [colorizer](https://github.com/catgoose/nvim-colorizer.lua) | 颜色代码高亮 |
| [render-markdown](https://github.com/MeanderingProgrammer/render-markdown.nvim) | 编辑器内 Markdown 渲染 |

#### 编辑器

| 插件 | 说明 |
|------|------|
| [flash](https://github.com/folke/flash.nvim) | 快速跳转导航 |
| [which-key](https://github.com/folke/which-key.nvim) | 键位提示弹窗 |
| [snacks](https://github.com/folke/snacks.nvim) | Picker（模糊查找）、启动页、文件浏览器、终端、缩进线、平滑滚动、通知、重命名 |
| [aerial](https://github.com/stevearc/aerial.nvim) | 代码大纲 |
| [grug-far](https://github.com/MagicDuck/grug-far.nvim) | 搜索替换 |
| [harpoon](https://github.com/ThePrimeagen/harpoon) | 钉住的文件快速跳转（`;1`-`;9`，`;h` 打开列表） |
| [yanky](https://github.com/gbprod/yanky.nvim) | Yank 历史环 |
| [dial](https://github.com/monaqa/dial.nvim) | 增强递增/递减（布尔值、日期等） |
| [refactoring](https://github.com/ThePrimeagen/refactoring.nvim) | 提取函数/变量、内联 |
| [mini.ai](https://github.com/echasnovski/mini.ai) | 增强文本对象 |
| [mini.splitjoin](https://github.com/echasnovski/mini.splitjoin) | 单行/多行切换（`gS`） |
| [mini.bracketed](https://github.com/echasnovski/mini.bracketed) | 补充 `[`/`]` 跳转，只占用本配置未使用的后缀（`x` 冲突、`i` 缩进、`c` 注释、`j` 跳转表、`o` oldfile、`u` undo） |
| [nvim-surround](https://github.com/kylechui/nvim-surround) | 包围符号操作 |
| [nvim-autopairs](https://github.com/windwp/nvim-autopairs) | 自动配对括号 |
| [persistence](https://github.com/folke/persistence.nvim) | 会话管理 |
| [guess-indent](https://github.com/NMAC427/guess-indent.nvim) | 自动检测缩进 |
| [oil](https://github.com/stevearc/oil.nvim) | 把目录当 buffer 编辑：改行名即重命名，`dd`/`p` 即移动文件。`-` 打开上级目录，`;o` 开浮窗 |

#### LSP 与开发工具

| 插件 | 说明 |
|------|------|
| [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig) | LSP 配置 |
| [mason](https://github.com/williamboman/mason.nvim) | LSP/DAP/Linter/Formatter 安装管理 |
| [blink.cmp](https://github.com/saghen/blink.cmp) | 补全引擎，含 [friendly-snippets](https://github.com/rafamadriz/friendly-snippets) |
| [conform](https://github.com/stevearc/conform.nvim) | 代码格式化（支持自动格式化开关） |
| [nvim-lint](https://github.com/mfussenegger/nvim-lint) | 代码检查 |
| [nvim-dap](https://github.com/mfussenegger/nvim-dap) | 调试适配器协议 |
| [neotest](https://github.com/nvim-neotest/neotest) | 测试框架 |
| [neogen](https://github.com/danymat/neogen) | 自动生成注释/文档 |
| [SchemaStore](https://github.com/b0o/SchemaStore.nvim) | JSON/YAML schema 验证 |
| [lazydev](https://github.com/folke/lazydev.nvim) | Lua 开发（类型补全） |
| [inc-rename](https://github.com/smjonas/inc-rename.nvim) | 带实时预览的 LSP 重命名，绑在 `grn` / `,r` |
| [claudecode](https://github.com/coder/claudecode.nvim) | Native Claude Code 集成（仅 Claude provider） |
| [CodeCompanion](https://github.com/olimorris/codecompanion.nvim) | 随 provider 选择的 ACP Chat，以及 HTTP Inline/命令 Prompt |
| [codecompanion-history](https://github.com/ravitemer/codecompanion-history.nvim) | 自动保存、按项目感知的 CodeCompanion Chat 历史 |

#### 版本控制

| 插件 | 说明 |
|------|------|
| [gitsigns](https://github.com/lewis6991/gitsigns.nvim) | Git 标记、块操作、blame |
| [diffview](https://github.com/sindrets/diffview.nvim) | Diff 与文件历史 |

### 语言支持

| 语言 | LSP | 格式化 | 检查 | 测试 | 调试 |
|------|-----|--------|------|------|------|
| C / C++ | clangd | clang-format | - | - | codelldb |
| Go | gopls | gopls 整理 imports + gofumpt | golangci-lint | neotest-golang | nvim-dap-go |
| Python | basedpyright, ruff | black | ruff | neotest-python | nvim-dap-python |
| Java | jdtls (+ Lombok) | jdtls | - | java-test | java-debug-adapter |
| TypeScript/JS | vtsls | prettier | eslint | - | js-debug-adapter |
| HTML/CSS | html, cssls, tailwindcss | prettier | - | - | - |
| JSON | jsonls + SchemaStore | prettier | - | - | - |
| YAML | yamlls + SchemaStore | prettier | - | - | - |
| Bash | bashls | shfmt | - | - | - |
| LaTeX | texlab (+ VimTeX) | latexindent | chktex | - | - |
| Lua | lua_ls | - | - | - | - |

#### LaTeX 工作流

LaTeX 分工给两个工具:**VimTeX** 负责编译/预览/文本对象,**texlab** 负责 LSP 智能(补全、跳转、label 重命名)和 `chktex` lint。两者刻意不重叠——texlab 自带的 build 已关闭,只由 VimTeX 编译。

**一次性配置**

```bash
brew install --cask mactex-no-gui   # TeX Live:latexmk、latexindent、chktex
brew install --cask skim            # 支持 SyncTeX 的 PDF 阅读器
```

`texlab` 首次启动时由 Mason 自动安装,无需额外步骤。反向跳转(在 PDF 里点一下 → 跳回源码)需设置 **Skim → 偏好设置 → Sync → Preset 选 Custom**,Command 填 `nvim`,Arguments 填:

```
--headless -c "VimtexInverseSearch %line '%file'"
```

**日常使用** — 打开任意 `.tex` 文件,然后:

- `<localleader>ll`(`\ll`)— 连续编译(保存即重编)
- `<localleader>lv`(`\lv`)— 正向跳转:打开/定位 Skim 到光标所在行
- `<localleader>lt`(`\lt`)— 目录;`\lk` 清理、`\le` 错误列表
- 保存文件即用 `latexindent` 自动格式化(可用 `<leader>uf` 开关)

日常操作也直接放在 `<localleader>` 上，少按一个键，并会出现在 `\` 的 which-key 弹窗里：

| 键位 | 操作 |
|------|------|
| `\b` | 编译(连续模式开关) |
| `\v` | 用 Skim 看 PDF |
| `\s` | 停止编译 |
| `\k` | 清理辅助文件 |
| `\t` | 目录开关 |
| `\e` | 错误列表 |
| `,x` | 一次性 `latexmk` 出 PDF（通用的"运行当前文件"键） |

TeX 缓冲区还默认开启软 `wrap` 和 `spell`(可用 `<leader>uw` / `<leader>us` 开关)。

### 键位

**Leader**：`Space` · **Local leader**：`\` · **速查表**：`<leader>?`

每个键都在回答一个问题，前缀决定是哪一个：

| 前缀 | 问题 | 例子 |
|------|------|------|
| `;` | 我要去哪个文件 / 符号 / 位置？ | `;<space>` 智能查找、`;f` 找文件、`;/` 全局搜索、`;s` 符号、`;1`-`;9` 钉住的文件 |
| `,` | 对眼前这段代码做什么？ | `,a` code action、`,f` 格式化、`,r` 重命名、`,j`/`,k` 移动行、`,e*` 提取 |
| `s` | 这个窗口怎么办？ | `ss`/`sv` 分屏、`sd` 关闭、`se` 跳编辑器、`s=` 均分 |
| `\` | **当前文件类型**有什么？ | `\o` 整理 import（Go/Python）、VimTeX、diffview |
| `<leader>` | 其余，按领域分组 | `g` git、`G` GitHub、`d` 调试、`t` 测试、`a` AI、`x` 诊断、`m` 管理、`s` 会话、`y` 复制、`u` 开关、`b` buffer、`q` 退出 |

频率决定深度：天天用的是两键，其余归到 `<leader>`。按下任一前缀等半秒，
which-key 会列出可用键——那个列表由配置本身生成，不会和文档脱节。

值得记住的无前缀键：

| 键 | 作用 |
|----|------|
| `f` / `F` | Flash 跳转 / Treesitter 跳转（Normal + Visual；`df-`、`ct)` 仍走原生） |
| `<C-h/j/k/l>` | 窗口移动——在终端输入状态下同样可用 |
| `<C-,>` | 跳到编辑器区域，再按一次跳回 |
| `<C-/>` · `<C-1>`-`<C-9>` | 切换终端 · 直达第 1-9 个终端 |
| `<S-h>` / `<S-l>` · `<Tab>` / `<S-Tab>` | 上/下一个 buffer |
| `g` · `[` / `]` · `z` | 跳转+LSP · 上/下一个某物 · 折叠与拼写 |
| `-` | 用 oil 打开当前目录（可当文本编辑） |
| `jk` · `<C-]>` | 退出 Insert / 终端输入 |

**→ [docs/MANUAL_CN.md](docs/MANUAL_CN.md) 有完整讲解**，从键位背后的组合规则讲起。

### 终端集成

Native coding-agent terminal 进入 Terminal-mode 时不再自动 resize，因此通过
`<C-h/j/k/l>` 切入时不会出现一行高度的闪动。如果 TUI 发生漂移，先用
`<C-]>`（或 `jk`）退出输入状态，再以 `<leader>md` 手动修复。打开编号底部终端
后，仍会修复因布局变化而受影响的可见 agent。

`<C-]>` 是统一且不受中文预编辑影响的退出键：在 Editor Insert 模式中等同
`<Esc>`；在包括 Claude/Codex 面板在内的所有终端中进入 terminal-Normal，
不会把该按键发送给子进程。在 Normal 中继续按仍是无副作用的 Escape，不再
触发原生 tag jump，因此不会把光标下的文字拿去查 tag 并产生 `E426`。
`help` 与 `man` 缓冲区例外，保留原生 tag jump——`<C-]>` 是它们跟随链接的
唯一方式；在那里清除搜索高亮仍可用 `<Esc>` 或 `<C-\>`。

Neovim 在 Normal 和 terminal-input 模式下都会接管 `<C-h/j/k/l>`，因此可以
直接在编辑器与终端窗口之间移动。这会覆盖 TUI 原有的 Ctrl 快捷键：向后删除
可用 Backspace，输入换行可用 `<S-Enter>`，picker 导航可用方向键。
`<C-S-l>` 会把原始 Ctrl+L 字节转发给终端，用于重绘 Codex 或 Claude Code
TUI。处在布局边缘时该键不做任何事、保持终端输入；浮动终端（lazygit、float 形态的
`<C-/>` shell）视为四面都是边缘——否则 shell 自己的 `<C-h>`、`<C-l>` 会从浮窗底
下跳出去。

由于 `<C-\>` 紧挨 `<C-]>`，它在 Normal、Insert、Visual 和 terminal-input 中都
执行同样的安全退出。在 Normal 中连续按也没有副作用，因此两个相邻组合都不会因
误触而突然切换窗口。

`<C-,>` 可以从 terminal input 或侧栏直接跳到编辑器窗口；在编辑器中再按一次会
回到来源窗口。它依赖 Ghostty 与 Nvim 协商的扩展键盘协议，以便和普通逗号区分；
如果 Nvim 外面还有一层 tmux，需要为其启用 `extended-keys`。在拿不到该协议的
环境里(原生 Terminal.app、ssh 会话、较老的 tmux),用 `se` 完成同样的
跳转。

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

两个 provider 的翻历史方式完全一致：两个 wrapper 的 tmux 都启用了 `mouse on` 和
50000 行 history。真实 transcript 归 tmux 所有，Nvim 的终端 buffer 里只有 tmux
最后合成的那一屏，所以滚动要走 tmux。保持 terminal-input 状态，以鼠标滚轮或
`<PageUp>` 进入 tmux copy-mode；用滚轮或 `<PageDown>` 向下查看，按 `q` 或
`<Esc>` 返回 agent 输入。如果已经处于 terminal-Normal mode，同样这些键（外加
`<C-u>`/`<C-d>`）会转发给 tmux 并自动恢复 terminal input，因此下一次滚轮事件会
直接落进 copy-mode。使用 `CLAUDE_WRAP_TMUX=0` 或 `CODEX_WRAP_TMUX=0` 时没有
tmux 可用，请先按 `jk`，再使用 Nvim 的普通滚动命令。

Nvim 内的 Codex 会使用 `--no-alt-screen --yolo`。YOLO 模式会绕过 Codex 的
审批与内置沙箱；`--no-alt-screen` 则让已完成的聊天输出进入 wrapper 的 tmux
history。

#### 在 buffer 里编辑 prompt

`<leader>ai` 把 agent 的 prompt 开在一个浮动 buffer 里，长 prompt 就能用整个编辑
器来写，而不是挤在 TUI 的输入框里。它存在的原因是 Terminal 模式把
`<C-h/j/k/l>` 给了窗口导航，而那正是 agent TUI 的编辑键。

| 按键 | 行为 |
|------|------|
| `<C-d>` | 把 prompt 交回 agent（insert 模式下可用） |
| `<C-v>` | 附加剪贴板图片 |
| `<C-c>` | 取消，输入框保持原样 |
| `:wq` / `ZZ` | 交回 prompt |
| `:q!` | 取消 |

输入框里**已有的内容会带过来**；从 Visual 模式调用则先把选区加进去，文本形式与
`<leader>as` 一致。全程不提交——关闭 buffer 只是把文本交回输入框，回车仍然由你自
己按。

浮窗是**模态**的：窗口导航键（`<C-h/j/k/l>`、`<C-w>`）和相邻的退出按键
（`<C-\>`）都不会离开它，绕过这一层的焦点变化也会被拉回来。浮窗开着时 agent
正阻塞在编辑器上、不读 pty，否则一旦
出去就再也回不来——再按一次 `<leader>ai` 会回到已打开的 prompt（Visual 选区会追加
进去），而不是发一个会被 TUI 吞掉的 `ctrl+g`。两个 agent 并排各开一个 prompt 也可
以，焦点归较新的那个。

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

`<leader>at` 把当前项目最新的会话渲染成只读 Markdown buffer，`<leader>aT` 从该
项目的会话历史中挑选。buffer 内 `R` 重新读盘，`q` 关闭。正文可见，thinking 与
工具调用折叠，`zR` 全部展开，`za` 展开单个。

数据源是 CLI 自己的 JSONL transcript，而非终端。Claude 运行在 alternate screen
上，其 tmux wrapper 完全不保留回滚内容——pane 里根本没东西可抓。读取落盘的
transcript 是唯一对两个 provider 都成立的方案，且重启 Nvim 后依然可查，也不需要
改动 tmux wrapper。

两家 CLI 都不会把推理文本落盘，所以折叠的 thinking 段落通常是不存在，而不是空的。

#### AI provider 选择

每个 Nvim 进程在启动时选择一个 provider，默认仍是 Claude；Native 与
CodeCompanion 快捷键在两个 provider 之间保持不变。当前 shell alias 为：

```bash
vi                 # 默认 provider（未覆盖时为 Claude）
vic                # NVIM_AI_PROVIDER=claude nvim
vix                # NVIM_AI_PROVIDER=codex CODEX_HOME="$HOME/.codex-oauth" nvim
```

`<leader>as` 会把可视选区附加到 Native Agent 的输入框，但不会提交，因此
可以继续补充要求。Codex 下，已保存的 buffer 会生成 `@路径 lines X-Y`
草稿；已修改或未命名的 buffer 则粘贴精确选区，因为 Codex 的文件引用读取
磁盘上的已保存内容。补充完指令后再自行按 Enter。

同一设置会为 CodeCompanion Chat 选择对应 ACP agent（`claude_code` /
`codex`）。Chat 因此使用 coding agent 的有状态协议和工具；Inline 与命令
Prompt 仍使用较轻量的 HTTP adapter（`anthropic` / `openai_responses`），
需要相应 API key。Codex ACP 使用 ChatGPT 登录，并继承 `vix` 的
`CODEX_HOME`。

codecompanion-history 会自动保存 Chat。用 `<leader>aph`（或
`:CodeCompanionHistory`）打开；Chat buffer 内也可按 `gh`。历史列表使用
Snacks picker，可以手动重命名；为避免额外模型请求，自动生成标题已关闭。
History 恢复的是 CodeCompanion 本地 transcript；要继续 agent 真正的有状态
ACP session，请在新的 ACP Chat 中使用 `/resume`。

运行 `:AIInfo` 可查看 Native/ACP/HTTP 最终映射；运行
`:checkhealth config` 可检查 CLI、ACP bridge 和 HTTP 凭据。

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

Normal 模式的布局优先读取 `NVIM_ENGLISH_INPUT_SOURCE`，未设置时回退到 macOS
已启用的键盘布局（优先选拉丁布局，而不是系统列出的第一个；必要时再使用最近
布局）。配置刻意不监听 `FocusGained` /
`FocusLost`，所以在 Nvim 与其他应用之间切换不会改写其他应用的输入法状态。

`NVIM_MACISM_WAIT_TIME_MS=0` 会关闭 macism 临时抢焦点窗口，从而消除 Ghostty
可见的焦点闪动。代价是关闭 macism 的 CJK 激活 workaround，在 macOS 26 上开头
几个字符可能仍按英文输入；不设置该变量则使用 macism 内置等待（当前为 150ms）。

### 配置项

在 `init.lua` 里插件加载前设置。

| 选项 | 说明 |
|------|------|
| `vim.g.terminal_position` | `"float"`（默认）或 `"bottom"`，决定 `<C-1>`-`<C-9>` 在哪里打开。只在启动时选定，不支持运行时切换——Snacks 在开窗那一刻定死窗口形态，edgy 又独立判断终端是否属于底部边栏，运行时切换意味着要在每一次隐藏、显示、重排里维持两者一致。 |

### 环境变量

| 变量 | 说明 |
|------|------|
| `NVIM_AI_PROVIDER` | `claude`（默认）或 `codex`；为当前 Nvim 进程选择 Native Agent、CodeCompanion ACP Chat 与 HTTP Inline adapter |
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

**调整文件/grep 搜索范围** — `;f` 与 `;/` 默认显示隐藏和被
gitignore 的文件；`.git/` 始终排除，`node_modules`、`target`、`.venv`、
`Pods` 等重型目录由 `lua/plugin/editor/snacks.lua` 的 `search_exclude` 统一
过滤。这个过滤不区分是否被 Git 跟踪，因此不要随意加入 `bin`、`out`、
`vendor` 这类可能包含源码的通用目录名。
