# Neovim Configuration / Neovim 配置

[English](#english) | [中文](#中文)

---

<a id="english"></a>

## English

A modern Neovim configuration built with Lua and [lazy.nvim](https://github.com/folke/lazy.nvim). Features lazy-loaded plugins, distributed keybinding architecture, and support for Go, Python, Java, Web, and Bash development.

### Requirements

- **Neovim** >= 0.10.0
- **Git**
- A [Nerd Font](https://www.nerdfonts.com/) for icon display
- **ripgrep** (`rg`) for Telescope live grep
- **fd** for Telescope file finder
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
│   ├── mappings.lua          # Core keymaps + which-key groups
│   ├── autocmds.lua          # Autocommands
│   ├── bootstrap.lua         # lazy.nvim setup
│   ├── lang/                 # Language-specific configs
│   │   ├── bash.lua
│   │   ├── go.lua
│   │   ├── java.lua
│   │   ├── python.lua
│   │   └── web.lua
│   ├── plugin/
│   │   ├── editor/           # Editor enhancement plugins
│   │   ├── lsp/              # LSP, completion, formatting, debugging
│   │   ├── ui/               # UI and theme plugins
│   │   └── vcs/              # Git integration
│   └── util/                 # Utility modules
├── after/ftplugin/           # Filetype overrides
└── test/                     # Config tests
```

### Plugins

#### UI

| Plugin | Description |
|--------|-------------|
| [solarized-osaka](https://github.com/craftzdog/solarized-osaka.nvim) | Colorscheme |
| [lualine](https://github.com/nvim-lualine/lualine.nvim) | Status line |
| [bufferline](https://github.com/akinsho/bufferline.nvim) | Buffer tabs |
| [noice](https://github.com/folke/noice.nvim) | Enhanced cmdline, messages, popupmenu |
| [treesitter](https://github.com/nvim-treesitter/nvim-treesitter) | Syntax highlighting, text objects |
| [nvim-ufo](https://github.com/kevinhwang91/nvim-ufo) | Modern code folding |
| [todo-comments](https://github.com/folke/todo-comments.nvim) | TODO/FIXME highlights |
| [illuminate](https://github.com/RRethy/vim-illuminate) | Highlight word under cursor |
| [colorizer](https://github.com/norcalli/nvim-colorizer.lua) | Color code highlighting |

#### Editor

| Plugin | Description |
|--------|-------------|
| [telescope](https://github.com/nvim-telescope/telescope.nvim) | Fuzzy finder |
| [flash](https://github.com/folke/flash.nvim) | Fast navigation with labels |
| [which-key](https://github.com/folke/which-key.nvim) | Keybinding help popup |
| [snacks](https://github.com/folke/snacks.nvim) | Dashboard, file explorer |
| [aerial](https://github.com/stevearc/aerial.nvim) | Code outline / symbol navigation |
| [trouble](https://github.com/folke/trouble.nvim) | Diagnostics panel |
| [grug-far](https://github.com/MagicDuck/grug-far.nvim) | Search and replace |
| [mini.ai](https://github.com/echasnovski/mini.ai) | Enhanced text objects |
| [nvim-surround](https://github.com/kylechui/nvim-surround) | Surround manipulation |
| [mini.comment](https://github.com/echasnovski/mini.comment) | Comment toggle |
| [nvim-autopairs](https://github.com/windwp/nvim-autopairs) | Auto-close pairs |
| [persistence](https://github.com/folke/persistence.nvim) | Session management |
| [toggleterm](https://github.com/akinsho/toggleterm.nvim) | Floating terminal |
| [guess-indent](https://github.com/NMAC427/guess-indent.nvim) | Auto-detect indentation |

#### LSP & Development

| Plugin | Description |
|--------|-------------|
| [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig) | LSP configuration |
| [mason](https://github.com/williamboman/mason.nvim) | LSP/DAP/linter/formatter installer |
| [blink.cmp](https://github.com/saghen/blink.cmp) | Completion engine (Rust-based) |
| [conform](https://github.com/stevearc/conform.nvim) | Code formatting |
| [nvim-lint](https://github.com/mfussenegger/nvim-lint) | Linting |
| [nvim-dap](https://github.com/mfussenegger/nvim-dap) | Debug Adapter Protocol |
| [neotest](https://github.com/nvim-neotest/neotest) | Testing framework |
| [fidget](https://github.com/j-hui/fidget.nvim) | LSP progress notifications |
| [lazydev](https://github.com/folke/lazydev.nvim) | Lua development (type completion) |
| [copilot](https://github.com/coder/claudecode.nvim) | AI code assistance (Claude Code) |

#### Version Control

| Plugin | Description |
|--------|-------------|
| [gitsigns](https://github.com/lewis6991/gitsigns.nvim) | Git signs, hunk actions, blame |
| [diffview](https://github.com/sindrets/diffview.nvim) | Diff and file history viewer |

### Language Support

| Language | LSP | Formatter | Test | Debug |
|----------|-----|-----------|------|-------|
| Go | gopls | goimports, gofumpt | neotest-go | nvim-dap-go |
| Python | pyright | ruff | neotest-python | nvim-dap-python |
| Java | jdtls | google-java-format | - | - |
| TypeScript/JS | ts_ls | prettierd | - | - |
| HTML/CSS | html, cssls, tailwindcss | prettierd | - | - |
| Bash | bashls | shfmt | - | - |
| Lua | lua_ls | stylua | - | - |

### Keybinding Reference

Leader key: `Space` | Local leader: `\`

#### General

| Key | Mode | Action |
|-----|------|--------|
| `jk` / `<C-c>` | Insert | Exit insert mode |
| `j` / `k` | Normal | Smart cursor movement (respects wrapped lines) |
| `<` / `>` | Visual | Indent and reselect |
| `<A-j>` / `<A-k>` | Visual | Move selected lines up/down |
| `p` | Visual | Paste without overwriting register |

#### Search (`<leader>s`)

| Key | Action |
|-----|--------|
| `<leader>f` | Find file |
| `<leader>b` | Find buffer |
| `<leader>r` | Recent files |
| `<leader>\` | Live grep (project) |
| `<leader>ss` | Search current buffer |
| `<leader>sp` | Search project |
| `<leader>sm` | Buffer symbols |
| `<leader>sM` | Workspace symbols |
| `<leader>st` | Treesitter symbols |
| `<leader>sr` | Search and replace |
| `<leader>sw` | Replace current word |

#### Code (`<leader>c`)

| Key | Action |
|-----|--------|
| `<leader>ca` | Code action |
| `<leader>cr` | Rename |
| `<leader>cf` | Format |
| `<leader>ch` | Hover doc |
| `<leader>cH` | Signature help |
| `<leader>cg` | Go to definition |
| `<leader>ct` | Type definition |
| `<leader>ce` | References |
| `<leader>ci` | Implementations |
| `<leader>cd` | Buffer diagnostics |
| `<leader>cD` | Workspace diagnostics |
| `<leader>cI` | Incoming calls |
| `<leader>co` | Outgoing calls |
| `<leader>cq` | Quickfix |
| `<leader>cS` | Code outline (Aerial) |

#### Debug (`<leader>d`)

| Key | Action |
|-----|--------|
| `<leader>db` | Toggle breakpoint |
| `<leader>dB` | Conditional breakpoint |
| `<leader>dc` | Run / Continue |
| `<leader>da` | Run with args |
| `<leader>dC` | Run to cursor |
| `<leader>di` | Step into |
| `<leader>dO` | Step over |
| `<leader>do` | Step out |
| `<leader>dP` | Pause |
| `<leader>dt` | Terminate |
| `<leader>dr` | Toggle REPL |
| `<leader>dl` | Run last |
| `<leader>dw` | Widgets |

#### Git (`<leader>g`)

| Key | Action |
|-----|--------|
| `<leader>gj` / `<leader>gk` | Next / Previous hunk |
| `<leader>gs` | Stage hunk |
| `<leader>gu` | Undo stage |
| `<leader>gr` | Reset hunk |
| `<leader>gR` | Reset buffer |
| `<leader>gp` | Preview hunk |
| `<leader>gl` | Blame line |
| `<leader>gL` | Blame buffer |
| `<leader>gd` | Diff |
| `<leader>gv` | Diff view |
| `<leader>gV` | File history |
| `<leader>go` | Git status |
| `<leader>gb` | Branches |
| `<leader>gc` | Buffer commits |
| `<leader>gC` | Project commits |
| `<leader>gf` | Git files |

#### Test (`<leader>t`)

| Key | Action |
|-----|--------|
| `<leader>tm` | Test current method |
| `<leader>td` | Debug current method |
| `<leader>tf` | Test current file |
| `<leader>tS` | Toggle test summary |
| `<leader>to` | Toggle test output |
| `<leader>tD` | Show test diagnostic |
| `<leader>th` | Hide test diagnostic |

#### Diagnostics (`<leader>x`)

| Key | Action |
|-----|--------|
| `<leader>xx` | Toggle diagnostics |
| `<leader>xX` | Buffer diagnostics |
| `<leader>xL` | Location list |
| `<leader>xQ` | Quickfix list |
| `<leader>xs` | Symbols |

#### Window (`<leader>w`) & Navigation

| Key | Action |
|-----|--------|
| `<C-h/j/k/l>` | Navigate windows |
| `<leader>wv` | Split vertically |
| `<leader>ws` | Split horizontally |
| `<leader>wc` | Close window |
| `<leader>wo` | Close other windows |
| `<leader>w+` / `<leader>w-` | Adjust height |
| `<leader>w>` / `<leader>w<` | Adjust width |
| `<leader>w=` | Equalize windows |

#### Buffer Navigation

| Key | Action |
|-----|--------|
| `[b` / `]b` | Previous / Next buffer |
| `<S-h>` / `<S-l>` | Previous / Next buffer (bufferline) |
| `<leader>bp` | Pin buffer |
| `<leader>bP` | Close unpinned buffers |
| `[d` / `]d` | Previous / Next diagnostic |
| `[t` / `]t` | Previous / Next TODO |

#### Flash Navigation

| Key | Mode | Action |
|-----|------|--------|
| `s` | Normal/Visual/Operator | Flash jump |
| `S` | Normal/Visual/Operator | Flash Treesitter |
| `r` | Operator | Remote Flash |
| `R` | Operator/Visual | Treesitter search |

#### Folding

| Key | Action |
|-----|--------|
| `zR` | Open all folds |
| `zM` | Close all folds |
| `zK` | Peek fold |

#### Session & Quit (`<leader>q`)

| Key | Action |
|-----|--------|
| `<leader>qs` | Save session |
| `<leader>q.` | Load current dir session |
| `<leader>ql` | Load last session |
| `<leader>qw` | Save file |
| `<leader>qW` | Save all files |
| `<leader>qq` | Quit |
| `<leader>qQ` | Force quit all |
| `<leader>qu` | Update plugins |

#### Help (`<leader>h`)

| Key | Action |
|-----|--------|
| `<leader>hn` | Clear search highlight |
| `<leader>hh` | Help tags |
| `<leader>hm` | Man pages |
| `<leader>hk` | Keymaps |
| `<leader>hr` | Registers |
| `<leader>hj` | Jumps |
| `<leader>hx` | Commands |
| `<leader>hX` | Command history |
| `<leader>ht` | TODOs |

#### File Explorer

| Key | Action |
|-----|--------|
| `<leader>e` | File tree |
| `<leader>E` | File explorer |

### Environment Variables

| Variable | Description |
|----------|-------------|
| `NVIM_DEV=1` | Enable dev tools (`:DevReload`, `:DevTest`, `:DevValidate`, `:DevInfo`, `:DevPlugins`, `:DevProfile`) |

### Customization

**Add a new plugin** — create a file in the appropriate `lua/plugin/*/` directory:

```lua
-- lua/plugin/editor/my-plugin.lua
return {
  "author/plugin-name",
  event = "VeryLazy",  -- or cmd, keys, ft for lazy loading
  opts = {},
}
```

**Add language support** — create a file in `lua/lang/`:

```lua
-- lua/lang/rust.lua
return {
  {
    "neovim/nvim-lspconfig",
    opts = { servers = { rust_analyzer = {} } },
  },
}
```

**Add an LSP server** — edit `lua/plugin/lsp/lsp.lua`, add to the `servers` table.

**Add a formatter** — edit `lua/plugin/lsp/conform.lua`, add to `formatters_by_ft`.

---

<a id="中文"></a>

## 中文

基于 Lua 和 [lazy.nvim](https://github.com/folke/lazy.nvim) 构建的现代 Neovim 配置。支持插件懒加载、分布式键位架构，以及 Go、Python、Java、Web、Bash 开发。

### 环境要求

- **Neovim** >= 0.10.0
- **Git**
- [Nerd Font](https://www.nerdfonts.com/) 字体（用于图标显示）
- **ripgrep** (`rg`) 用于 Telescope 全文搜索
- **fd** 用于 Telescope 文件查找
- 按需安装语言工具链（Go、Python、Node.js、Java）

### 安装

```bash
# 备份现有配置
mv ~/.config/nvim ~/.config/nvim.backup

# 克隆仓库
git clone <repository-url> ~/.config/nvim

# 启动 Neovim — lazy.nvim 会自动安装所有插件
nvim
```

### 项目结构

```
~/.config/nvim/
├── init.lua                  # 入口文件
├── lua/
│   ├── options.lua           # Vim 选项设置
│   ├── mappings.lua          # 核心键位映射 + which-key 分组
│   ├── autocmds.lua          # 自动命令
│   ├── bootstrap.lua         # lazy.nvim 初始化
│   ├── lang/                 # 语言专属配置
│   │   ├── bash.lua
│   │   ├── go.lua
│   │   ├── java.lua
│   │   ├── python.lua
│   │   └── web.lua
│   ├── plugin/
│   │   ├── editor/           # 编辑器增强插件
│   │   ├── lsp/              # LSP、补全、格式化、调试
│   │   ├── ui/               # 界面和主题插件
│   │   └── vcs/              # Git 集成
│   └── util/                 # 工具模块
├── after/ftplugin/           # 文件类型覆盖配置
└── test/                     # 配置测试
```

### 插件列表

#### 界面 (UI)

| 插件 | 说明 |
|------|------|
| [solarized-osaka](https://github.com/craftzdog/solarized-osaka.nvim) | 配色方案 |
| [lualine](https://github.com/nvim-lualine/lualine.nvim) | 状态栏 |
| [bufferline](https://github.com/akinsho/bufferline.nvim) | 缓冲区标签页 |
| [noice](https://github.com/folke/noice.nvim) | 增强命令行、消息、弹出菜单 |
| [treesitter](https://github.com/nvim-treesitter/nvim-treesitter) | 语法高亮、文本对象 |
| [nvim-ufo](https://github.com/kevinhwang91/nvim-ufo) | 现代代码折叠 |
| [todo-comments](https://github.com/folke/todo-comments.nvim) | TODO/FIXME 高亮 |
| [illuminate](https://github.com/RRethy/vim-illuminate) | 光标下单词高亮 |
| [colorizer](https://github.com/norcalli/nvim-colorizer.lua) | 颜色代码高亮 |

#### 编辑器 (Editor)

| 插件 | 说明 |
|------|------|
| [telescope](https://github.com/nvim-telescope/telescope.nvim) | 模糊查找器 |
| [flash](https://github.com/folke/flash.nvim) | 快速跳转导航 |
| [which-key](https://github.com/folke/which-key.nvim) | 键位提示弹窗 |
| [snacks](https://github.com/folke/snacks.nvim) | 启动页、文件浏览器 |
| [aerial](https://github.com/stevearc/aerial.nvim) | 代码大纲 / 符号导航 |
| [trouble](https://github.com/folke/trouble.nvim) | 诊断面板 |
| [grug-far](https://github.com/MagicDuck/grug-far.nvim) | 搜索替换 |
| [mini.ai](https://github.com/echasnovski/mini.ai) | 增强文本对象 |
| [nvim-surround](https://github.com/kylechui/nvim-surround) | 包围符号操作 |
| [mini.comment](https://github.com/echasnovski/mini.comment) | 注释切换 |
| [nvim-autopairs](https://github.com/windwp/nvim-autopairs) | 自动配对括号 |
| [persistence](https://github.com/folke/persistence.nvim) | 会话管理 |
| [toggleterm](https://github.com/akinsho/toggleterm.nvim) | 浮动终端 |
| [guess-indent](https://github.com/NMAC427/guess-indent.nvim) | 自动检测缩进 |

#### LSP 与开发工具

| 插件 | 说明 |
|------|------|
| [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig) | LSP 配置 |
| [mason](https://github.com/williamboman/mason.nvim) | LSP/DAP/Linter/Formatter 安装管理 |
| [blink.cmp](https://github.com/saghen/blink.cmp) | 补全引擎（Rust 实现） |
| [conform](https://github.com/stevearc/conform.nvim) | 代码格式化 |
| [nvim-lint](https://github.com/mfussenegger/nvim-lint) | 代码检查 |
| [nvim-dap](https://github.com/mfussenegger/nvim-dap) | 调试适配器协议 |
| [neotest](https://github.com/nvim-neotest/neotest) | 测试框架 |
| [fidget](https://github.com/j-hui/fidget.nvim) | LSP 进度通知 |
| [lazydev](https://github.com/folke/lazydev.nvim) | Lua 开发（类型补全） |
| [claudecode](https://github.com/coder/claudecode.nvim) | AI 代码助手（Claude Code） |

#### 版本控制

| 插件 | 说明 |
|------|------|
| [gitsigns](https://github.com/lewis6991/gitsigns.nvim) | Git 标记、块操作、blame |
| [diffview](https://github.com/sindrets/diffview.nvim) | Diff 与文件历史查看 |

### 语言支持

| 语言 | LSP | 格式化 | 测试 | 调试 |
|------|-----|--------|------|------|
| Go | gopls | goimports, gofumpt | neotest-go | nvim-dap-go |
| Python | pyright | ruff | neotest-python | nvim-dap-python |
| Java | jdtls | google-java-format | - | - |
| TypeScript/JS | ts_ls | prettierd | - | - |
| HTML/CSS | html, cssls, tailwindcss | prettierd | - | - |
| Bash | bashls | shfmt | - | - |
| Lua | lua_ls | stylua | - | - |

### 键位参考

Leader 键: `Space` | Local Leader: `\`

#### 通用

| 键位 | 模式 | 功能 |
|------|------|------|
| `jk` / `<C-c>` | 插入 | 退出插入模式 |
| `j` / `k` | 普通 | 智能光标移动（支持折行） |
| `<` / `>` | 可视 | 缩进并保持选中 |
| `<A-j>` / `<A-k>` | 可视 | 上下移动选中行 |
| `p` | 可视 | 粘贴且不覆盖寄存器 |

#### 搜索 (`<leader>s`)

| 键位 | 功能 |
|------|------|
| `<leader>f` | 查找文件 |
| `<leader>b` | 查找缓冲区 |
| `<leader>r` | 最近文件 |
| `<leader>\` | 全文搜索（项目） |
| `<leader>ss` | 搜索当前缓冲区 |
| `<leader>sp` | 搜索项目 |
| `<leader>sm` | 缓冲区符号 |
| `<leader>sM` | 工作区符号 |
| `<leader>st` | Treesitter 符号 |
| `<leader>sr` | 搜索替换 |
| `<leader>sw` | 替换当前单词 |

#### 代码 (`<leader>c`)

| 键位 | 功能 |
|------|------|
| `<leader>ca` | 代码操作 |
| `<leader>cr` | 重命名 |
| `<leader>cf` | 格式化 |
| `<leader>ch` | 悬浮文档 |
| `<leader>cH` | 签名帮助 |
| `<leader>cg` | 跳转到定义 |
| `<leader>ct` | 类型定义 |
| `<leader>ce` | 引用 |
| `<leader>ci` | 实现 |
| `<leader>cd` | 缓冲区诊断 |
| `<leader>cD` | 工作区诊断 |
| `<leader>cI` | 调入调用 |
| `<leader>co` | 调出调用 |
| `<leader>cq` | Quickfix |
| `<leader>cS` | 代码大纲 (Aerial) |

#### 调试 (`<leader>d`)

| 键位 | 功能 |
|------|------|
| `<leader>db` | 切换断点 |
| `<leader>dB` | 条件断点 |
| `<leader>dc` | 运行 / 继续 |
| `<leader>da` | 带参数运行 |
| `<leader>dC` | 运行到光标 |
| `<leader>di` | 步入 |
| `<leader>dO` | 步过 |
| `<leader>do` | 步出 |
| `<leader>dP` | 暂停 |
| `<leader>dt` | 终止 |
| `<leader>dr` | 切换 REPL |
| `<leader>dl` | 重新运行 |
| `<leader>dw` | 变量检查 |

#### Git (`<leader>g`)

| 键位 | 功能 |
|------|------|
| `<leader>gj` / `<leader>gk` | 下一个 / 上一个 hunk |
| `<leader>gs` | 暂存 hunk |
| `<leader>gu` | 撤销暂存 |
| `<leader>gr` | 重置 hunk |
| `<leader>gR` | 重置缓冲区 |
| `<leader>gp` | 预览 hunk |
| `<leader>gl` | 行 blame |
| `<leader>gL` | 缓冲区 blame |
| `<leader>gd` | Diff |
| `<leader>gv` | Diff 视图 |
| `<leader>gV` | 文件历史 |
| `<leader>go` | Git 状态 |
| `<leader>gb` | 分支 |
| `<leader>gc` | 缓冲区提交 |
| `<leader>gC` | 项目提交 |
| `<leader>gf` | Git 文件 |

#### 测试 (`<leader>t`)

| 键位 | 功能 |
|------|------|
| `<leader>tm` | 测试当前方法 |
| `<leader>td` | 调试当前方法 |
| `<leader>tf` | 测试当前文件 |
| `<leader>tS` | 切换测试摘要 |
| `<leader>to` | 切换测试输出 |
| `<leader>tD` | 显示测试诊断 |
| `<leader>th` | 隐藏测试诊断 |

#### 诊断 (`<leader>x`)

| 键位 | 功能 |
|------|------|
| `<leader>xx` | 切换诊断 |
| `<leader>xX` | 缓冲区诊断 |
| `<leader>xL` | 位置列表 |
| `<leader>xQ` | Quickfix 列表 |
| `<leader>xs` | 符号 |

#### 窗口 (`<leader>w`) 与导航

| 键位 | 功能 |
|------|------|
| `<C-h/j/k/l>` | 窗口导航 |
| `<leader>wv` | 垂直分屏 |
| `<leader>ws` | 水平分屏 |
| `<leader>wc` | 关闭窗口 |
| `<leader>wo` | 关闭其他窗口 |
| `<leader>w+` / `<leader>w-` | 调整高度 |
| `<leader>w>` / `<leader>w<` | 调整宽度 |
| `<leader>w=` | 均分窗口 |

#### 缓冲区导航

| 键位 | 功能 |
|------|------|
| `[b` / `]b` | 上一个 / 下一个缓冲区 |
| `<S-h>` / `<S-l>` | 上一个 / 下一个缓冲区 (bufferline) |
| `<leader>bp` | 固定缓冲区 |
| `<leader>bP` | 关闭未固定缓冲区 |
| `[d` / `]d` | 上一个 / 下一个诊断 |
| `[t` / `]t` | 上一个 / 下一个 TODO |

#### Flash 快速导航

| 键位 | 模式 | 功能 |
|------|------|------|
| `s` | 普通/可视/操作符 | Flash 跳转 |
| `S` | 普通/可视/操作符 | Flash Treesitter |
| `r` | 操作符 | Remote Flash |
| `R` | 操作符/可视 | Treesitter 搜索 |

#### 折叠

| 键位 | 功能 |
|------|------|
| `zR` | 打开所有折叠 |
| `zM` | 关闭所有折叠 |
| `zK` | 预览折叠 |

#### 会话与退出 (`<leader>q`)

| 键位 | 功能 |
|------|------|
| `<leader>qs` | 保存会话 |
| `<leader>q.` | 加载当前目录会话 |
| `<leader>ql` | 加载上次会话 |
| `<leader>qw` | 保存文件 |
| `<leader>qW` | 保存所有文件 |
| `<leader>qq` | 退出 |
| `<leader>qQ` | 强制退出全部 |
| `<leader>qu` | 更新插件 |

#### 帮助 (`<leader>h`)

| 键位 | 功能 |
|------|------|
| `<leader>hn` | 清除搜索高亮 |
| `<leader>hh` | 帮助标签 |
| `<leader>hm` | Man 手册 |
| `<leader>hk` | 键位映射 |
| `<leader>hr` | 寄存器 |
| `<leader>hj` | 跳转列表 |
| `<leader>hx` | 命令 |
| `<leader>hX` | 命令历史 |
| `<leader>ht` | TODO 列表 |

#### 文件浏览器

| 键位 | 功能 |
|------|------|
| `<leader>e` | 文件树 |
| `<leader>E` | 文件浏览器 |

### 环境变量

| 变量 | 说明 |
|------|------|
| `NVIM_DEV=1` | 启用开发工具（`:DevReload`、`:DevTest`、`:DevValidate`、`:DevInfo`、`:DevPlugins`、`:DevProfile`） |

### 自定义

**添加插件** — 在对应 `lua/plugin/*/` 目录下创建文件：

```lua
-- lua/plugin/editor/my-plugin.lua
return {
  "author/plugin-name",
  event = "VeryLazy",  -- 或 cmd, keys, ft 实现懒加载
  opts = {},
}
```

**添加语言支持** — 在 `lua/lang/` 目录下创建文件：

```lua
-- lua/lang/rust.lua
return {
  {
    "neovim/nvim-lspconfig",
    opts = { servers = { rust_analyzer = {} } },
  },
}
```

**添加 LSP 服务器** — 编辑 `lua/plugin/lsp/lsp.lua`，添加到 `servers` 表中。

**添加格式化工具** — 编辑 `lua/plugin/lsp/conform.lua`，添加到 `formatters_by_ft`。

---

## License

This configuration is provided as-is for personal use.
