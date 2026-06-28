# Neovim 配置

[English](README.md)

基于 Lua 和 [lazy.nvim](https://github.com/folke/lazy.nvim) 构建的现代 Neovim 配置。键位和插件选择与 [LazyVim](https://www.lazyvim.org/) 对齐，支持 Go、C/C++、Python、Java、Web、Bash、JSON、YAML 开发。

### 环境要求

**必装：**
- **Neovim** >= 0.11.0（用到 `vim.lsp.config`/`vim.lsp.enable`、`vim.hl`、`vim.diagnostic.jump`）
- **Git**
- [Nerd Font](https://www.nerdfonts.com/)（图标显示）
- **ripgrep** (`rg`) — `Snacks.picker.grep` / `live_grep` / `:grep` 的底层
- **fd** — 文件查找（`venv-selector` 和部分 picker 用到）

**可选（按功能）：**
- **[lazygit](https://github.com/jesseduffield/lazygit)** — `<leader>gg`（项目）/ `<leader>gf`（当前文件历史）
- **[tmux](https://github.com/tmux/tmux)** — 把 Claude Code TUI 包到 `:terminal` 里，防止闪屏；自动检测（详见[终端集成](#终端集成)）
- **[cowsay](https://en.wikipedia.org/wiki/Cowsay)** — 启动页 banner（缺失会静默跳过，不致命）

**macOS 一键安装：**
```bash
brew install neovim git ripgrep fd lazygit tmux cowsay
brew install --cask font-jetbrains-mono-nerd-font  # 任意 Nerd Font 都行
```

**语言工具链** — *只有想用对应的 Mason 包时才需要：*
- **Go** — `gopls`、`goimports`、`gofumpt`、`gomodifytags`、`impl`、`delve` 都依赖
- **Python >= 3.10** — `black` 需要（`pyenv` 或 `uv` 管理的解释器都可以）
- **Node.js + npm** — `eslint-lsp`、`css-lsp`、`html-lsp`、`json-lsp`、`yaml-language-server`、`tailwindcss-language-server`、`vtsls`、`bash-language-server` 都依赖
- **JDK 17+** — `jdtls`（Java）需要。本配置假设走 [SDKMAN!](https://sdkman.io/)，路径写死在 `~/.sdkman/candidates/java/current`（见 [`lua/lang/java.lua`](lua/lang/java.lua)）

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
├── init.lua                  # 入口文件
├── lua/
│   ├── options.lua           # Vim 选项
│   ├── mappings.lua          # 命令式核心键位（副作用）
│   ├── whichkey_spec.lua     # which-key 分组 + spec 键位（数据）
│   ├── autocmds.lua          # 自动命令
│   ├── bootstrap.lua         # lazy.nvim 初始化
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
│   │   ├── typescript.lua    # JS / TS 语言（LSP、格式化、DAP）
│   │   └── yaml.lua
│   ├── plugin/
│   │   ├── editor/           # 编辑器增强插件
│   │   ├── lsp/              # LSP、补全、格式化、调试
│   │   ├── ui/               # 界面和主题插件
│   │   └── vcs/              # Git 集成
│   └── util/                 # 工具模块
└── docs/                     # DIAGNOSTICS.md, UTILITIES.md
```

### 插件列表

#### 界面

| 插件 | 说明 |
|------|------|
| [solarized-osaka](https://github.com/craftzdog/solarized-osaka.nvim) | 配色方案 |
| [lualine](https://github.com/nvim-lualine/lualine.nvim) | 状态栏 |
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
| [harpoon](https://github.com/ThePrimeagen/harpoon) | 常用文件快速跳转（`<leader>1-9`） |
| [yanky](https://github.com/gbprod/yanky.nvim) | Yank 历史环 |
| [dial](https://github.com/monaqa/dial.nvim) | 增强递增/递减（布尔值、日期等） |
| [refactoring](https://github.com/ThePrimeagen/refactoring.nvim) | 提取函数/变量、内联 |
| [mini.ai](https://github.com/echasnovski/mini.ai) | 增强文本对象 |
| [mini.splitjoin](https://github.com/echasnovski/mini.splitjoin) | 单行/多行切换（`gS`） |
| [nvim-surround](https://github.com/kylechui/nvim-surround) | 包围符号操作 |
| [mini.comment](https://github.com/echasnovski/mini.comment) | 注释切换 |
| [nvim-autopairs](https://github.com/windwp/nvim-autopairs) | 自动配对括号 |
| [persistence](https://github.com/folke/persistence.nvim) | 会话管理 |
| [guess-indent](https://github.com/NMAC427/guess-indent.nvim) | 自动检测缩进 |

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
| [claudecode](https://github.com/coder/claudecode.nvim) | AI 代码助手（Claude Code） |

#### 版本控制

| 插件 | 说明 |
|------|------|
| [gitsigns](https://github.com/lewis6991/gitsigns.nvim) | Git 标记、块操作、blame |
| [diffview](https://github.com/sindrets/diffview.nvim) | Diff 与文件历史 |

### 语言支持

| 语言 | LSP | 格式化 | 检查 | 测试 | 调试 |
|------|-----|--------|------|------|------|
| C / C++ | clangd | clang-format | - | - | codelldb |
| Go | gopls | goimports, gofumpt | golangci-lint | neotest-golang | nvim-dap-go |
| Python | basedpyright, ruff | black | ruff | neotest-python | nvim-dap-python |
| Java | jdtls (+ Lombok) | jdtls | - | java-test | java-debug-adapter |
| TypeScript/JS | vtsls | prettier | eslint | - | - |
| HTML/CSS | html, cssls, tailwindcss | prettier | - | - | - |
| JSON | jsonls + SchemaStore | prettier | - | - | - |
| YAML | yamlls + SchemaStore | prettier | - | - | - |
| Bash | bashls | shfmt | - | - | - |
| Lua | lua_ls | - | - | - | - |

### 键位参考

**Leader**: `Space` | **Local Leader**: `\` | **键位指南**: `<leader>?`

#### 触发键前缀

按任意前缀稍等即可看到 which-key 弹窗。

| 前缀 | 类别 |
|------|------|
| `<leader>` | 主命令面板 |
| `g` | 跳转 / LSP（`gd` 定义, `gr` 引用, `K` 悬浮, `gI` 实现, `gy` 类型, `gD` 声明, `gK` 签名, `gS` 单行切换） |
| `s` / `S` | Flash 跳转 / Treesitter 跳转 |
| `[` / `]` | 前/后导航（`b` buffer, `d` 诊断, `e` 错误, `w` 警告, `h` hunk, `q` quickfix, `t` todo, `y` yank, `B` 移动 buffer） |
| `z` | 折叠 / 拼写 |
| `<C-w>` | 窗口操作 |

#### 顶层快捷键

| 键位 | 功能 |
|------|------|
| `<C-s>` | 保存（所有模式） |
| `<Esc>` | 清除搜索高亮 |
| `<C-/>` | 切换终端 |
| `<C-h/j/k/l>` | 窗口导航 |
| `<C-Up/Down/Left/Right>` | 窗口大小调整 |
| `<A-j>` / `<A-k>` | 移动行（n, i, v） |
| `<S-h>` / `<S-l>` | 上/下一个 buffer |
| `<leader><space>` | 智能查找（buffers + 最近 + cwd 文件，按 frecency 加权） |
| `<leader>.` | 在 cwd 查找文件 |
| `<leader>/` | 搜索项目（grep） |
| `<leader>,` | 缓冲区列表 |
| `<leader>:` | 命令历史 |
| `<leader>'` | 恢复上次 picker |
| `<leader>\`` | 上一个 buffer（alternate） |
| `<leader>?` | 键位指南 |
| `<leader>l` | Lazy 插件管理 |
| `<leader>n` | 通知历史 |
| `<leader>e` / `<leader>E` | 文件树 / 文件浏览器 |
| `<leader>-` / `<leader>\|` | 水平 / 垂直分屏 |
| `<leader>1-9` | Harpoon 跳转到文件 |
| `<leader>h` / `<leader>H` | Harpoon 快捷菜单 / 添加文件 |
| `<leader>p` | Yank 历史 — 见 [Yanky](#yanky增强复制粘贴) |

#### Leader 分组

| 分组 | 键 | 说明 |
|------|----|------|
| 查找 | `<leader>f` | `ff` cwd 文件, `fF` 当前 buffer 目录, `fd` 浏览目录, `fe` 浏览器（含被忽略文件）, `fr` 最近, `fb` buffer, `fg` git 文件, `fp` 项目, `fc` nvim 配置, `fn` 新建, `fs/fS` 保存/另存为, `fR` 重命名, `fD` 删除, `fy/fY` 复制路径（绝对/项目相对）, `ft/fT` 终端 |
| 搜索 | `<leader>s` | `sb` buffer, `sB` 所有开启 buffer, `sd` 当前目录, `sp` 项目, `sw` 当前词, `ss/sS` 符号（buffer/workspace）, `sR` 恢复, `sh` 帮助, `sk` 键位, `sm` 标记, `sj` 跳转, `sc/sC` 命令历史/命令, `s"` 寄存器, `sM` man, `sr/sW` 替换, `st/sT` todo, `sn{a,d,h,l,t}` noice（全部/清除/历史/最新/picker） |
| 代码 | `<leader>c` | `ca` 操作, `cr` 重命名, `cf` 格式化, `cd` 诊断, `cm` Mason, `cl` LSP 信息, `cn` 生成注释, `co` 整理导入, `cO` 大纲, `cs/cS` 符号（buffer/workspace）, `cv` 虚拟环境（py）, `cp` Markdown 预览（md）, `cx` 运行当前文件（按文件类型：go/c/cpp/py/js/ts/sh）, `cR` 重建 gopls 索引（go） |
| Buffer | `<leader>b` | `bd` 删除, `bo` 删除其他, `bD` 删除+窗口, `bl/br` 删除左/右, `bj` 选择, `bp` 固定, `bP` 关闭未固定 |
| 调试 | `<leader>d` | `db/dB` 断点/条件断点, `dc/da` 继续/带参运行, `dC` 运行到光标, `dg` 跳到行（不执行）, `di` 步入, `do` 步出, `dO` 步过, `dj/dk` 上/下栈帧, `dP` 暂停, `dr` REPL, `ds` 会话, `dw` 悬浮 widget, `dt` 终止, `dl` 重跑 |
| Git | `<leader>g` | `gs` 状态, `gb` 分支, `gc/gC` 提交, `gl/gL` blame, `gp` 预览, `gr/gR` 重置, `gS` 暂存/取消暂存, `gT` 切换行 blame, `gd` diff, `gv` diff 视图, `gm` diff 主分支, `gM` 选择 ref diff, `gV` 文件历史, `gH` git 日志, `gB` 浏览 |
| 测试 | `<leader>t` | `tm` 测试方法, `td` 调试方法, `tf` 测试文件, `tS` 摘要, `to` 输出, `tD/th` 显示/隐藏诊断 |
| 终端 | `<leader>T` | `T1-9` 切换专用终端 1-9, `Td` 修复 claude TUI 漂移, `Tx` 关闭终端 buffer |
| 切换 | `<leader>u` | `uf/uF` 自动格式化, `us` 拼写, `uw` 换行, `ul/uL` 行号, `ud` 诊断, `uh` inlay hints, `uT` treesitter, `uc` conceal, `ub` 背景, `un` 关闭通知, `uR` markdown 渲染 |
| 诊断 | `<leader>x` | `xx/xX` 诊断（项目/buffer）, `xL/xQ` loclist/quickfix picker, `xl/xq` 切换 loclist/quickfix 窗口, `xt/xT` todo |
| 重构 | `<leader>r` | `rf` 提取函数, `rF` 提取到文件, `rx` 提取变量, `ri` 内联, `rb` 提取块, `rB` 提取块到文件, `rs` 选择 |
| AI | `<leader>a` | `ac` 切换, `af` 聚焦, `ar` 恢复, `aR` 继续, `am` 模型, `ab` 添加 buffer, `aS` 从文件树添加, `as` 发送（v）, `aa/ad` 接受/拒绝 diff |
| 窗口 | `<leader>w` | `ww` 切到其它窗口, `wd` 删除, `wo` 关闭其他, `w=` 均分, `wm` 缩放 |
| 退出 | `<leader>q` | `qq/qQ` 退出, `qs` 保存会话, `ql` 加载上次, `q.` 加载当前 |
| 标签页 | `<leader><tab>` | `<tab><tab>` 新建, `d` 关闭, `]/[` 下/上一个, `l/f` 最后/第一个, `o` 关闭其他, `s` 列出全部 |

#### Yanky（增强复制/粘贴）

| 键位 | 功能 |
|------|------|
| `y` / `p` / `P` | Yank / Put（带历史） |
| `[y` / `]y` | 循环 yank 历史 |
| `<leader>p` | 打开 yank 历史（`:YankyRingHistory`，走 snacks ui-select） |
| `<leader>y`（v） | 选区 yank 到匿名寄存器 |
| `<leader>Y`（v） | 选区 yank 到系统剪贴板（`+`） |

### 终端集成

#### `Shift+Enter`（iTerm2）

在 Neovim 内运行终端应用（如 Claude Code）时，`Shift+Enter` 需配置 iTerm2：

Settings → Profiles → Keys → Key Mappings → 添加：
- **Shortcut**：`Shift + Return`
- **Action**：`Send Escape Sequence`
- **Value**：`[13;2u`

#### Claude Code 的 tmux 包裹

通过 [claudecode.nvim](https://github.com/coder/claudecode.nvim) 调起 Claude Code 时，默认会在一个专用的 tmux server 中启动——见 `lua/plugin/lsp/ai.lua`。

**原因**：Claude 的 Ink TUI 用 DEC mode 2026（Synchronized Output）实现原子帧更新。Neovim 的 `:terminal` buffer 不识别这个协议，**不包 tmux 会出现帧间撕裂**——状态栏双渲染、行间内容串到下一行。tmux 在中间消化掉 2026 序列、自己做整帧合成、再把普通 ANSI 输出给 `:terminal`，渲染就干净了。（与宿主终端无关：Ghostty / WezTerm / iTerm2 都会撞同一个问题，因为出问题的是 nvim `:terminal`。）

**代价**：包了 tmux 之后，tmux、宿主终端、Claude 的 `string-width` 三方对 CJK 宽字符的宽度判定可能不一致，带框 UI（TODO、diff 预览、session recap）会出现轻微错位。相比不包时的撕裂，可接受程度高得多。

**覆盖配置**：
- `CLAUDE_WRAP_TMUX=0 nvim` — 一次性 A/B 测试
- `vim.g.claude_wrap_tmux = false` 写入 `init.lua` — 永久关闭
- 默认：开

**提示——抑制 recap CJK 错位框**：Claude Code 的 session recap 是最显眼的 CJK 错位受害者。在 `~/.claude/settings.json` 设置 `"awaySummaryEnabled": false` 可关闭。注意这是 Claude Code 的全局配置，不属于 nvim。

### 环境变量

| 变量 | 说明 |
|------|------|
| `NVIM_LOG_LEVEL` | `util.logger` 日志级别：`DEBUG`/`INFO`/`WARN`/`ERROR`（默认 `WARN`） |
| `NVIM_DEV=1` | 把 `util.logger` 设为 `DEBUG`（更详细的日志） |
| `CLAUDE_WRAP_TMUX` | `1`/`0` — 覆盖 Claude Code 的 tmux 包裹默认行为。默认开。详见 [Claude Code 的 tmux 包裹](#claude-code-的-tmux-包裹)。 |

### 诊断

排查问题（启动慢、LSP 不挂载、格式化不生效等）见 [`docs/DIAGNOSTICS.md`](docs/DIAGNOSTICS.md)。运行 `:checkhealth config` 检查外部依赖、关键 Mason 包、Neovim 版本。

### 自定义

**添加插件** — 在对应 `lua/plugin/*/` 目录下创建文件。

**添加语言支持** — 在 `lua/lang/` 目录下创建文件。

**添加 LSP 服务器** — 编辑 `lua/plugin/lsp/lsp.lua`，添加到 `servers` 表。

**添加格式化工具** — 编辑 `lua/plugin/lsp/conform.lua`，添加到 `formatters_by_ft`。
