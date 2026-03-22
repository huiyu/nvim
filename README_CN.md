# Neovim 配置

[English](README.md)

基于 Lua 和 [lazy.nvim](https://github.com/folke/lazy.nvim) 构建的现代 Neovim 配置。键位和插件选择与 [LazyVim](https://www.lazyvim.org/) 对齐，支持 Go、Python、Java、Web、Bash、JSON、YAML 开发。

### 环境要求

- **Neovim** >= 0.10.0
- **Git**
- [Nerd Font](https://www.nerdfonts.com/)（图标显示）
- **ripgrep** (`rg`) 全文搜索
- **fd** 文件查找
- 按需安装语言工具链（Go、Python、Node.js、Java）

### 安装

```bash
mv ~/.config/nvim ~/.config/nvim.backup
git clone <repository-url> ~/.config/nvim
nvim
```

### 项目结构

```
~/.config/nvim/
├── init.lua                  # 入口文件
├── lua/
│   ├── options.lua           # Vim 选项
│   ├── mappings.lua          # 核心键位 + which-key 分组 + 切换/UI
│   ├── autocmds.lua          # 自动命令
│   ├── bootstrap.lua         # lazy.nvim 初始化
│   ├── lang/                 # 语言专属配置
│   │   ├── bash.lua
│   │   ├── go.lua
│   │   ├── java.lua
│   │   ├── json.lua
│   │   ├── python.lua
│   │   ├── web.lua
│   │   └── yaml.lua
│   ├── plugin/
│   │   ├── editor/           # 编辑器增强插件
│   │   ├── lsp/              # LSP、补全、格式化、调试
│   │   ├── ui/               # 界面和主题插件
│   │   └── vcs/              # Git 集成
│   └── util/                 # 工具模块
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
| [nvim-ts-autotag](https://github.com/windwp/nvim-ts-autotag) | HTML/JSX 自动闭合标签 |
| [nvim-ufo](https://github.com/kevinhwang91/nvim-ufo) | 现代代码折叠 |
| [todo-comments](https://github.com/folke/todo-comments.nvim) | TODO/FIXME 高亮 |
| [illuminate](https://github.com/RRethy/vim-illuminate) | 光标下单词高亮 |
| [colorizer](https://github.com/norcalli/nvim-colorizer.lua) | 颜色代码高亮 |
| [render-markdown](https://github.com/MeanderingProgrammer/render-markdown.nvim) | 编辑器内 Markdown 渲染 |

#### 编辑器

| 插件 | 说明 |
|------|------|
| [telescope](https://github.com/nvim-telescope/telescope.nvim) | 模糊查找器 |
| [flash](https://github.com/folke/flash.nvim) | 快速跳转导航 |
| [which-key](https://github.com/folke/which-key.nvim) | 键位提示弹窗 |
| [snacks](https://github.com/folke/snacks.nvim) | 启动页、文件浏览器、终端、缩进线、平滑滚动、通知 |
| [aerial](https://github.com/stevearc/aerial.nvim) | 代码大纲 |
| [trouble](https://github.com/folke/trouble.nvim) | 诊断面板 |
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
| `<leader><space>` | 查找文件 |
| `<leader>/` | 全文搜索 |
| `<leader>,` | 缓冲区列表 |
| `<leader>:` | 命令历史 |
| `<leader>?` | 键位指南 |
| `<leader>l` | Lazy 插件管理 |
| `<leader>n` | 通知历史 |
| `<leader>e` / `<leader>E` | 文件树 / 文件浏览器 |
| `<leader>-` / `<leader>\|` | 水平 / 垂直分屏 |
| `<leader>1-9` | Harpoon 跳转到文件 |
| `<leader>h` / `<leader>H` | Harpoon 快捷菜单 / 添加文件 |

#### Leader 分组

| 分组 | 键 | 说明 |
|------|----|------|
| 查找 | `<leader>f` | `ff` 文件, `fb` buffer, `fr` 最近, `fg` git 文件, `fc` 配置, `fn` 新建, `ft/fT` 终端, `fp` 项目 |
| 搜索 | `<leader>s` | `sg` grep, `sw` 当前词, `sb` buffer 行, `sm` 标记, `sR` 恢复, `sh` 帮助, `sk` 键位, `sr` 替换, `sW` 替换词, `st/sT` todo, `ss/sS` 符号, `sn` noice |
| 代码 | `<leader>c` | `ca` 操作, `cr` 重命名, `cf` 格式化, `cd` 诊断, `cm` Mason, `cl` LSP 信息, `cn` 生成注释, `co` 整理导入, `cO` 大纲, `cs/cS` 符号, `cv` 虚拟环境 |
| Buffer | `<leader>b` | `bd` 删除, `bo` 删除其他, `bD` 删除+窗口, `bl/br` 删除左/右, `bj` 选择, `bp` 固定, `bP` 关闭未固定 |
| 调试 | `<leader>d` | `db` 断点, `dc` 继续, `di` 步入, `do` 步出, `dO` 步过, `dt` 终止, `dl` 重跑 |
| Git | `<leader>g` | `gs` 状态, `gb` 分支, `gc/gC` 提交, `gl/gL` blame, `gp` 预览, `gr/gR` 重置, `gS` 暂存, `gu` 撤销暂存, `gd` diff, `gv/gV` diff 视图, `gB` 浏览 |
| 测试 | `<leader>t` | `tm` 测试方法, `td` 调试方法, `tf` 测试文件, `tS` 摘要, `to` 输出 |
| 切换 | `<leader>u` | `uf/uF` 自动格式化, `us` 拼写, `uw` 换行, `ul/uL` 行号, `ud` 诊断, `uh` inlay hints, `uT` treesitter, `uc` conceal, `ub` 背景, `un` 关闭通知, `uR` markdown 渲染 |
| 诊断 | `<leader>x` | `xx/xX` 诊断, `xL` loclist, `xQ` quickfix, `xt/xT` todo |
| 重构 | `<leader>r` | `rf` 提取函数, `rF` 提取到文件, `rx` 提取变量, `ri` 内联, `rb` 提取块, `rB` 提取块到文件, `rs` 选择 |
| AI | `<leader>a` | `ac` 切换, `af` 聚焦, `ar` 恢复, `aR` 继续, `am` 模型, `ab` 添加 buffer, `as` 发送, `aa/ad` 接受/拒绝 diff |
| 窗口 | `<leader>w` | `wd` 删除, `wo` 关闭其他, `w=` 均分, `wm` 缩放 |
| 退出 | `<leader>q` | `qq/qQ` 退出, `qs` 保存会话, `ql` 加载上次, `q.` 加载当前 |
| 标签页 | `<leader><tab>` | `<tab><tab>` 新建, `d` 关闭, `]/[` 下/上一个, `l/f` 最后/第一个, `o` 关闭其他 |

#### Yanky（增强复制/粘贴）

| 键位 | 功能 |
|------|------|
| `y` / `p` / `P` | Yank / Put（带历史） |
| `[y` / `]y` | 循环 yank 历史 |
| `<leader>p` | 打开 yank 历史（Telescope） |

### 终端集成（iTerm2）

在 Neovim 内运行终端应用（如 Claude Code）时，`Shift+Enter` 需配置 iTerm2：

Settings → Profiles → Keys → Key Mappings → 添加：
- **Shortcut**：`Shift + Return`
- **Action**：`Send Escape Sequence`
- **Value**：`[13;2u`

### 环境变量

| 变量 | 说明 |
|------|------|
| `NVIM_DEV=1` | 启用开发工具（`:DevReload`、`:DevTest`、`:DevValidate`、`:DevInfo`、`:DevPlugins`、`:DevProfile`） |

### 自定义

**添加插件** — 在对应 `lua/plugin/*/` 目录下创建文件。

**添加语言支持** — 在 `lua/lang/` 目录下创建文件。

**添加 LSP 服务器** — 编辑 `lua/plugin/lsp/lsp.lua`，添加到 `servers` 表。

**添加格式化工具** — 编辑 `lua/plugin/lsp/conform.lua`，添加到 `formatters_by_ft`。
