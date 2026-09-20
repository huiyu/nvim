# 使用手册

这份文档讲**怎么用**这套配置。如果你是 Vim 新手，从[核心思路](#核心思路)开始往下读；
已经熟悉 Vim、只想看键位的，直接跳到[五个前缀](#五个前缀)。

安装和插件清单在 [README_CN](../README_CN.md)，这里只讲使用。

---

## 目录

- [核心思路](#核心思路)
- [键盘的语法](#键盘的语法)
- [五个前缀](#五个前缀)
- [去某处：`;`](#去某处-)
- [改代码：`,`](#改代码-)
- [窗口：`s`](#窗口s)
- [当前文件类型：`\`](#当前文件类型-)
- [其余：`<leader>`](#其余leader)
- [工作流](#工作流)
- [忘了键位怎么办](#忘了键位怎么办)

---

## 核心思路

大多数编辑器把命令放进菜单，你靠**读**找到它。Vim 把命令放在键上，你靠
**知道自己想干什么**找到它。

这套配置把这一点做到底。每次按键，第一下就在回答一个问题：

| 你想…… | 按 | 因为它的含义是 |
|---|---|---|
| 去别的地方 | `;` | "哪个文件 / 符号 / 位置？" |
| 改眼前的代码 | `,` | "对它做什么？" |
| 调整屏幕布局 | `s` | "这个窗口怎么办？" |
| 用语言相关的功能 | `\` | "**当前文件类型**有什么？" |
| 其他一切 | `<Space>` | git、测试、调试、AI…… |

**没有一个键是按插件归类的。** `;f` 就是找文件，不管背后是 picker、oil 还是别的——
你按它是因为你想要一个文件，不是因为你记得某个插件名。

两个直接后果：

- **天天用的是两键。** 找文件、格式化、跳定义。少用的才允许长一点。
- **一个键只有一个含义。** `,` 是"改这段代码"，那找文件就永远不在 `,` 下面，
  哪怕字母再顺手。

---

## 键盘的语法

Vim 不是一堆要背的快捷键，它是一门小语言——**你没学过的命令，是可以推导出来的**。
而且推导到一半忘了也没关系：这套配置里的 which-key 会把剩下的选项列出来。

下面八条规则就是全部语法。已经会 Vim 的人也值得扫一眼，后面几条是这套配置自己的约定。

### 1. 键的含义取决于模式

打开就是 **Normal** 模式：字母是命令，不是文字。`i` 进入 **Insert** 模式打字，
快速连打 `jk`（或 `Esc`）回来；`v` 进入 **Visual** 模式选择。后面的规则说的都是
Normal 模式下的键。

### 2. 一次编辑 = 动词 + 目标

```
动词   目标
 d      w        删到下一个词
 c      i(       改括号里的内容
 y      3j       复制这行和下面 3 行
 >      G        缩进到文件末尾
 gc     ip       注释这一段
```

**动词**（操作符）就这几个：

| | |
|---|---|
| `d` | 删除 |
| `c` | 修改（删掉然后进入插入模式） |
| `y` | 复制 |
| `>` `<` | 增加 / 减少缩进 |
| `gu` `gU` | 转小写 / 大写 |
| `gc` | 注释 |
| `=` | 自动缩进 |

**目标**要么是动作（从光标到某处），要么是文本对象（规则 3）。动作单独按是移动，
跟在动词后面就是范围：

```
h j k l    左 下 上 右                 w  b  e     下一个词首 / 上一个词首 / 词尾
0  ^  $    行首 / 首个非空白 / 行尾     gg  G       文件开头 / 结尾
}  {       下 / 上一个空行             t)  T(      到下一个 ) 之前 / 上一个 ( 之后
```

`dw` `d$` `dG` `d}` `dt)` 不用分别学：学了 `d`，学了目标，组合自然成立。

**which-key：** 按下 `d`（或 `c`、`y`）停半秒，弹窗列出所有目标。

### 3. `i` 里面，`a` 连边界

文本对象不关心光标在它里面哪个位置。前一个字母选 **i**（inside，里面）还是
**a**（around，连边界一起），后一个字母说是什么东西：

| 对象 | 是什么 | 来自 |
|---|---|---|
| `(` `[` `{` `<` | 成对括号 | 内置 |
| `"` `'` `` ` `` | 引号 | 内置 |
| `t` | HTML/XML 标签 | 内置 |
| `w` `W` `s` `p` | 词 / 字串 / 句 / 段 | 内置 |
| `f` | **函数** | treesitter |
| `c` | **类** | treesitter |
| `a` | **参数**——`daa` 会连它的逗号一起删 | treesitter |
| `o` | **块**、条件分支、循环体 | treesitter |

```
"hello world"    光标在里面任意位置
ci"   →  ""      保留引号，直接开始打新内容
ca"   →          连引号一起拿掉

dif    删函数体，光标在函数里任意位置都行     daf    删整个函数
caa    改这个参数                             vio    选中这个 if 的分支体
```

`i`/`a` 后面还能插一个 `n`（next）或 `l`（last）：`cin(` 改**下一个**括号里的内容，
光标不必先进去。

**which-key：** 按 `di`（或 `da`、`vi`）停半秒，弹窗列出所有对象。

### 4. 连按两次 = 整行；大写 = 变体

动词连按两次就作用于当前行：`dd` `yy` `cc` `>>` `gcc`。

大写字母是同一个键的"更大"或"相反"版本，在哪一层都成立：

| 小写 | 大写 |
|---|---|
| `d` `c` 到某处 | `D` `C` 到行尾（= `d$` `c$`） |
| `i` `a` 光标前 / 后插入 | `I` `A` 行首 / 行尾插入 |
| `o` 下面开新行 | `O` 上面开新行 |
| `n` `t` 向前 | `N` `T` 向后 |
| `w` `b` `e` 按词 | `W` `B` `E` 按字串（空白分隔，更大） |
| `p` 粘到后面 | `P` 粘到前面 |
| `;f` 找文件 · `;s` 本文件符号 · `;t` TODO | `;F` 从当前目录找 · `;S` 全项目符号 · `;T` TODO+FIX |
| `]m` 下一个函数开头 | `]M` 下一个函数结尾 |
| `<S-h>` `<S-l>` | 上 / 下一个 buffer |

几个单键只是缩写：`x` = `dl`，`D` = `d$`，`C` = `c$`。`s` 本来是 `cl`，这里把它
让给了窗口前缀，改一个字符请用 `cl`。

### 5. 数字 = 次数

放在动词前或目标前都行：`3dd`、`d3w`、`5j`、`3>>`、`10<C-a>`。

### 6. 单字母命名空间

有几个键本身不做事，只是打开一个抽屉，后面再跟一个字母：

| 抽屉 | 含义 | 例子 |
|---|---|---|
| `[` `]` | 上一个 / 下一个 X | `]d` 诊断 · `]e` 错误 · `]h` git hunk · `]q` quickfix · `]m` 函数 · `]c` 类 · `]x` 冲突 · `]y` yank 历史。大写 = 第一个 / 最后一个：`[D` `]Q` |
| `g` | 去某处 / 关于光标下的东西 | `gd` 定义 · `gr` 引用 · `gb` 实现 · `gy` 类型 · `gC` 调用方 · `K` 文档 · `gx` 打开 URL / 文件 · `gS` 拆 / 合行 · `gv` 重选 |
| `z` | 折叠与拼写 | `zR` 全展开 · `zM` 全折叠 · `za` 切换 · `z=` 拼写建议 · `zg` 加进词典 |
| `Ctrl` | 立即执行，不问问题，任何模式都一样 | `<C-h/j/k/l>` 窗口 · `<C-/>` 终端 · `<C-o>` 原路返回 · `<C-a>` `<C-x>` 加减 · `<C-r>` 重做 |

**which-key：** 按 `[`、`]`、`g`、`z` 停半秒，弹窗列出抽屉里的东西，并按
类别加标题分块（`── diagnostics`、`── git` ……），每块一个颜色，长列表因此读起来
是几个区块而不是一串字母。分组在 `lua/whichkey_spec.lua` 里声明；启用分组的
菜单中，未显式归类的键（包括新增插件键和内置命令）统一放在最后的 `── others`
下，避免混入上一个分组。没有剩余条目时不显示 `others`；`z` 等未声明分组的
菜单保留默认布局。

`gx` 打开当前行离光标最近的 HTTP(S) 链接或已存在的本地文件：URL 交给系统
浏览器，引用的文件在 Nvim 内打开。从终端触发时，文件打开在当前 tab 的编辑窗口，
原终端保持可见。支持绝对路径、`~/…` 和相对路径；相对路径以源文件所在目录，
或 Snacks 终端记录的工作目录为基准。含空格的路径用引号或反引号包裹。
没有找到目标时，普通文件 buffer 仍用系统默认应用打开自身；终端不执行打开操作。

在终端 Normal 模式下，表格同一列中被换行拆开的 `(...)` 或 `<...>` 目标也会
完整打开，包括报告路径显示成 `(/tmp/`、下一行 `report.md)` 的情况。引号包裹的
文件路径也支持换行，光标放在任一段都可以。先按 `Ctrl-\` 或 `jk` 退出终端输入模式。

### 7. 做过的都能重复，也都能回退

Vim 记得你上一次做了什么。学一个"重复"键的时候，顺手记住它的"回退"键：

| 做什么 | 重复 | 回退 |
|---|---|---|
| 一次修改 | `.` | `u`（重做 `<C-r>`） |
| `/` 查找 | `n` | `N` |
| `t` 行内查找 | `;` | `,` |
| 一条 `:` 命令 | `@:` | `u` |
| 一段宏 `qq…q` | `@q` | `u` |
| 上次的选区 | `gv` | — |
| 上次的 picker | `;;` | — |
| 粘错了 | `[y` `]y` 翻 yank 历史 | — |

录制宏时，状态栏会在文件名前显示红色 `● REC @q`，其中 `q` 是当前录制的寄存器。
在 Normal 模式按 `q` 停止录制，标识随即消失。录制期间 which-key 会暂停快捷键提示。

最值钱的组合是**一键移动、一键执行**：`*` 搜光标下的词 → `cw新词<Esc>` 改第一处 →
`n.` `n.` `n.`，每处先看一眼再决定改不改。`cgn新词<Esc>` 然后一路 `.` 是更短的版本。

注意两处和原生 Vim 不同：`f` 在 Normal 模式是 flash 跳转——输入两三个字符、按标签飞过去，
要按原生方式在行内找单个字符用 `t{char}`；`;` 和 `,` 在这里是前缀，作为重复键要等一秒
才生效，跨行重复用 `n.`。

### 8. 前缀 = 一个问题

剩下的键都挂在五个前缀下面，每个前缀回答一个问题——这就是[核心思路](#核心思路)，
下一节逐个展开。

### 为什么这件事重要

你不需要"学会 `dif`"。你学的是 `d`，和 `if`，这个组合自然就成立了——
连带 `cif`、`yif`、`>if`、`gcif`、`vif` 也一起会了。
**6 个操作符 × 20 个目标 = 120 个你从没背过的命令。**

想做一件新事情时，只问两个问题：*什么操作？* 和 *作用在什么上？*
然后按这个顺序打出来。打到一半忘了，停半秒，菜单会告诉你。

---

## 五个前缀

```
;  去某处              ,  改这段代码
s  窗口                \  当前文件类型
<Space>  其余一切
```

按下任意一个，**等半秒**——会弹出菜单列出可用的键。你不需要背这份文档，
菜单本身就是文档。

任何时候按 `<Space>?` 打开一页速查表。

---

## 去某处：`;`

所有"到达某个文件、符号或位置"的方式。

### 文件

| 键 | 作用 |
|---|---|
| `;<Space>` | **智能查找**——最近 + 已开 + 全部文件，按你的使用频率排序。**从这个开始。** |
| `;f` | 按文件名找 |
| `;i` | 遵守 `.gitignore` 找文件，包含隐藏文件 |
| `;F` | 在当前文件所在目录找 |
| `;r` | 最近打开过的 |
| `;b` | 已打开的 buffer |
| `;g` | git 跟踪的文件 |
| `;p` | 切换项目 |
| `;a` | **上次使用的 buffer（来回切换）**——回到当前窗口上一个 buffer。 |
| `;;` | 重开上次的搜索，结果列表原样保留 |

Nvim 把这个上一个 buffer 称为 **alternate buffer（交替缓冲区）**。在同一窗口
先打开 A，再打开 B，按 `;a` 回到 A，再按一次回到 B。它对应原生 `Ctrl-^`，
适合在实现文件和测试文件之间来回编辑。

`;<Space>` 是最该养成习惯的一个：它会学习你常碰哪些文件并排到最前。

### 文本与符号

| 键 | 作用 |
|---|---|
| `;/` | 全项目搜索 |
| `;?` | 遵守 `.gitignore` 搜文本，包含隐藏文件 |
| `;w` | 搜光标下的词 |
| `;l` | 在当前文件里按行找 |
| `;D` | 搜当前目录 |
| `;s` | 当前文件的符号（函数、类） |
| `;S` | 全项目符号 |

`;f` 和 `;/` 包含被 Git 忽略的文件，但排除常见构建/依赖目录。`;i` 和 `;?`
按 `.gitignore` 过滤，不做额外目录排除，因此 `build/` 等目录内被跟踪的源码也能搜到。

### 浏览

没有文件树侧栏：目录一律用 oil 浏览和编辑，文件一律用上面的 picker 到达。

| 键 | 作用 |
|---|---|
| `;o` | **oil**——把目录当文本编辑（见下） |
| `-` | 用 oil 打开当前文件所在目录 |

`;F`、`;D` 使用当前文件所在目录或 Oil 正在显示的目录；
在终端等面板中则使用当前窗口/标签页的工作目录。

在终端（含 Claude/Codex）中，先用 `Ctrl-\` 或 `jk` 离开终端输入模式，
再按 `-` 或 `;o`。Oil 会在当前标签页的编辑区域打开并获得焦点；没有编辑窗口时
会新建一个空白分屏。`q` 关闭 Oil 并返回编辑区域，终端保持打开。

在 Oil 中，`h/j/k/l` 保留原生光标移动，方便编辑文件名。
用 `-` 返回上一级目录，回车打开选中的文件或进入目录；`g?` 查看 Oil 快捷键，`q` 关闭。
修改文件名或增删行后，用 `:w` 检查并确认文件操作。

### 钉住的文件

| 键 | 作用 |
|---|---|
| `;H` | 钉住当前文件 |
| `;h` | 查看钉住列表 |
| `;1` … `;9` | 直达第 1-9 个 |

把正在改的三四个文件钉住，之后 `;2` 不用看屏幕就能过去。换任务时重新钉。

### 位置

`;j` 跳转表 · `;m` 标记 · `;t` TODO · `;T` TODO/FIX/FIXME

---

## 改代码：`,`

所有**对**眼前代码执行的操作。

| 键 | 作用 |
|---|---|
| `,a` | **Code action**——修复菜单（补 import、快速修复） |
| `,f` | 格式化 |
| `,r` | 重命名符号，全项目生效，带实时预览 |
| `,c` | 运行 codelens（gopls 提供 generate、test、tidy、govulncheck） |
| `,n` | 生成文档注释 |
| `,x` | 运行当前文件 |
| `,O` | 当前文件大纲 |

`,a`、`,r` 和 `,c` 只在有语言服务器的地方存在——纯文本文件里它们根本不出现。

### 移动行

| 键 | 作用 |
|---|---|
| `,j` / `,k` | 把当前行（或选区）下移 / 上移 |
| `,h` / `,l` | 减少 / 增加缩进 |

对 Visual 选区同样有效。

`Ctrl-a` / `Ctrl-x` 递增、递减数字、日期、版本号、布尔值和已配置的逻辑运算符。
在 JS/TS（含 JSX/TSX）中，它们还可以循环切换 `let` / `const`；这个关键字规则
不会影响其他文件类型。

### 重构

| 键 | 作用 |
|---|---|
| `,ef` | 把选区提取成函数 |
| `,ex` | 提取成变量 |
| `,eb` | 提取成块 |
| `,i` | 内联变量 |
| `,R` | 所有重构操作的菜单 |
| `,w` | 替换光标下的词 |
| `,F` | 完整的搜索替换面板 |

`,e*` 系列作用于 Visual 选区。

---

## 窗口：`s`

| 键 | 作用 |
|---|---|
| `ss` | 下方分屏 |
| `sv` | 右侧分屏 |
| `sd` | 关闭当前窗口 |
| `so` | 关闭其他所有窗口 |
| `sw` | 上一个窗口 |
| `se` | 跳到编辑器区域 |
| `s=` | 均分大小 |
| `sm` | 缩放 / 还原 |
| `sz` | 切换当前文件的专注模式 |

`sz` 把文件放进居中的 100 列视图，遮住状态栏和顶部标签栏，并淡化当前作用域外的
代码。再按一次恢复原布局，编辑仍保留在同一个 buffer。终端等特殊 buffer 不进入
专注模式；`sm` 继续用于普通分屏缩放。

`scrolloff = 8` 尽量在光标上下各保留八行可见内容，接近边缘时提前滚动。
文件开头、末尾和较小的窗口不一定能留足八行；终端窗口使用零。
`splitkeep = "screen"` 在横向分屏打开、关闭或调整大小时，尽量让文本保持在屏幕
原来的行上，Edgy 依赖它减少侧栏布局变化造成的跳动。另两个值是 `"cursor"`
（保持光标在窗口内的相对位置）和 `"topline"`（保持窗口第一行显示的文本）。

**窗口之间移动不用 `s`**——那是一个键：

```
Ctrl-h  Ctrl-j  Ctrl-k  Ctrl-l     左 下 上 右
Ctrl-,                             直达编辑器，再按跳回
```

它们**在终端内部也能用**——当 AI 面板或 shell 开在代码旁边时，这一点很关键。

---

## 当前文件类型：`\`

`\` 放的是只在当前 buffer 里有意义的操作。同一个键在不同文件类型下含义不同，
这正是它的用途。终端 buffer 在 Normal 模式下提供 `\1`-`\9` 选择编号终端；
普通文件里不会出现这些键，即使旁边正开着终端。

| 文件类型 | 键 |
|---|---|
| Go | `\o` 整理 import · `\G` 重建 gopls 索引 |
| Python | `\o` 整理 import · `\v` 选择虚拟环境 |
| C/C++ | `\h` 在源文件和头文件间切换 |
| Markdown | `\p` 切换预览 · `\r` 切换编辑器内渲染 |
| LaTeX | `\b` 编译 · `\v` 看 PDF · `\t` 目录 · `\e` 错误 · `\k` 清理 |
| Diffview | `\e` 聚焦文件面板 · `\co` / `\ct` 解决冲突（用我方/对方） |
| 终端 | `\1`-`\9` 选择第 1-9 个终端（Normal 模式） |

颜色预览支持十六进制、`rgb()`、`hsl()` 和 CSS `var(--name)` 引用；CSS 变量定义
在当前 buffer 内解析。前端文件还会预览 Tailwind 类名；Tailwind LSP 连接后可提供
项目自定义颜色。`:ColorizerToggle` 切换当前 buffer 的颜色预览。

按 `\` 等一下，就能看到当前文件提供了什么。

---

## 其余：`<leader>`

`<leader>` 就是 **空格键**。按下等一秒，每个字母是一个分组。

| 键 | 分组 | 内容 |
|---|---|---|
| `<Space>g` | Git | 状态、blame、hunk、lazygit（`gg`）、diffview |
| `<Space>G` | GitHub | PR、issue、review |
| `<Space>d` | 调试 | 断点、单步、查看变量 |
| `<Space>t` | 测试 | 跑文件 / 跑最近的 / 调试、输出面板 |
| `<Space>x` | 诊断 | 错误列表、quickfix、location list |
| `<Space>a` | AI | Claude / Codex 面板、prompt、transcript |
| `<Space>b` | Buffer | 删除、固定、关其他 |
| `<Space>m` | 管理 | 配置、插件源码、help、man、键位、Lazy、Mason、LSP 状态 |
| `<Space>s` | 会话 | 保存 / 恢复工作布局 |
| `<Space>y` | 复制 | 复制文件路径、yank 历史、寄存器 |
| `<Space>u` | 开关 | 换行、拼写、诊断、配色 |
| `<Space><Tab>` | Tab | tab page |
| `<Space>q` | 退出 | 全部退出 |

### 配置和插件文件

| 键 | 作用 |
|---|---|
| `<Space>mf` | 在这份 Neovim 配置中找文件 |
| `<Space>mF` | 在 lazy.nvim 安装目录中找插件源码 |

这两个入口用于维护编辑器本身，放在管理组中。

---

## 工作流

### 读陌生代码

```
;/  搜一个你认得的词
gd  跳到定义
gd  再跳，再跳——顺着往下追
Ctrl-o  原路返回
gC  谁调用了它？
]]  当前文件里这个符号的下一处
```

`K` 显示光标下内容的文档，`gr` 列出所有引用。

### 编辑循环

```
;<Space>   打开文件
,a         让语言服务器修掉能修的
,f         格式化
<Space>tf  跑这个文件的测试
```

在两个文件之间来回用 `;a`；三四个文件就用 `;H` 钉住，然后 `;1`-`;4`。

### 整理文件

`;o` 把目录**当成可编辑的 buffer** 打开。它就是普通 Vim buffer：

```
改一行的文件名        → 重命名
dd，到别处 p          → 移动文件
写新的一行            → 新建（末尾加 / 就是目录）
dd                    → 删除
:w                    → 确认列表，执行
```

用这种方式移动 `.go` / `.ts` 文件时会通知语言服务器，**引用它的 import 会被自动改写**，
不会悄悄断掉。

### Git

`<Space>gg` 打开 lazygit——暂存、提交、历史都在一处。
`<Space>gv` 打开 diffview 做分支 review。在 diffview 内部，`\` 是它自己的操作，
`<Space>gq` 关闭。
鼠标滚轮放在任一对比窗口上，上下滚动都会让各侧保持同步，包括新增/删除行的
填充区域和折叠区域；键盘焦点保持原处。文件列表和历史面板独立滚动。

### 终端与 AI

```
Ctrl-/       切换终端
3<Ctrl-/>    从文件直接打开终端 3（Normal 模式）
\1 … \9      在终端 buffer 中选择第 1-9 个终端（先按 jk）
<Space>ac    打开 AI 面板
<Space>ai    在真正的 Neovim buffer 里写 prompt
```

`Ctrl-]` 退出终端输入但不打扰里面运行的程序——因为 `Esc` 属于 AI CLI 自己。

`\` 加编号会聚焦或创建对应终端，再按同一个编号也不会关闭它。
`<C-/>` 用来打开、关闭当前或上次使用的终端。

---

## 忘了键位怎么办

1. **按下前缀然后等。** `;`、`,`、`s`、`\`、`<Space>` 停顿一下都会弹菜单。最快。
2. **`<Space>?`** —— 一页列出所有前缀和常用键。
3. **`<Space>mk`** —— 按描述搜索所有键位。
4. **`;;`** —— 搜索结果列表丢了，用它原样找回来。

那些菜单是**从配置本身生成的**，不会像文档一样过期。

## 调试

打开源码，用 `<Space>db` 设置断点，再按 `<Space>dc` 选择启动或附加配置。
会话开始时自动打开面板。`<Space>di` 进入函数、`dO` 单步跳过、`do` 跳出函数。

| 键 | 作用 |
|---|---|
| `<Space>dB` | 条件断点 |
| `<Space>dA` / `:DapAttach` | 选择 attach 配置，附加已有进程 |
| `<Space>dL` | 日志断点，例如 `value={value}`，输出日志但不停下 |
| `<Space>de` | 从当前适配器提供的选项中选择异常断点 |
| `<Space>dR` | 从会话树的根重启会话 |
| `<Space>dD` | 断开会话及其子会话，并请求保留目标进程运行 |
| `<Space>dt` | 终止目标，连同它所属的整棵会话树 |
| `<Space>du` | 关闭或重新打开调试面板 |
| `<Space>dw` | 对光标处表达式或当前 Visual 选区求值 |
| `<Space>dW` | 输入或编辑表达式后添加到 Watches |
| `<Space>ds` | 列出会话，选择主进程、渲染进程或子会话 |
| `<Space>dq` / `<Space>dx` | 列出 / 清除所有断点 |

求值和 Watch 支持字符、整行、矩形选区，不影响寄存器。Watch 保留在当前编辑器
进程中，在 Watches 面板用 `d` 删除。取消 Watch 或日志断点输入不会改变已有内容。
异常断点提供 None、All 和单个过滤器，具体名称与能力取决于适配器，要先启动会话。
断开明确发送 `terminateDebuggee=false`，目标能否继续独立运行仍取决于适配器支持。
`dR`、`dD`、`dt` 都先解析出当前会话树的根再动作：一个适配器管多个目标时
（js-debug 驱动浏览器、Electron）会通过 `startDebugging` 派生子会话，当前会话
跟着最后停下的那个子会话走，只对它动作等于只重启或只释放一个目标。另外单独
起的会话属于另一棵树，不受影响，用 `ds` 选择。`dl` 则重新运行上一次配置。

### 当前文件与测试

| 键 | 范围 |
|---|---|
| `<Space>df` | 调试当前源码文件 / 它所属的可执行目标 |
| `<Space>td` | 调试光标所在用例（Go/Python/Java 也会寻找前面的最近用例） |
| `<Space>tF` | 调试当前文件里的测试 |
| `<Space>tm` / `<Space>tf` | 普通运行最近用例 / 测试文件（neotest：Go/Python） |

先用 `<Space>db` 打断点，把光标放进测试用例，再按 `<Space>td`。
这些直接入口会先保存当前文件；未命名 buffer 或保存失败时中止。
各语言使用同一套键位，目标选择逻辑分别放在 `lua/lang/*.lua`。

| 语言 | `df` | `td` / `tF` |
|---|---|---|
| Go | 当前 `.go` 文件 | neotest-golang + Delve：最近用例 / 此文件声明的测试 |
| Python | 当前脚本，使用 dap-python 的环境 | neotest-python + debugpy：pytest 或 unittest |
| Java | 与当前文件名对应的主类，包含嵌套主类 | jdtls：最近方法 / 当前文件发现的第一个测试类 |
| JS/TS | 当前 Node 脚本 | 项目本地的 Vitest；单用例入口要求 Vitest 3+ |
| Rust | Cargo 二进制，有歧义时选择目标 | 标准 libtest：按函数 / 当前源码文件内的函数精确筛选 |
| Dart/Flutter | 将当前文件作为入口 | SDK 测试适配器：`test` / `testWidgets` 声明或整个文件 |

JS/TS 与 Dart 用 Treesitter 定位，再使用框架原生的行号过滤。
光标应放在测试调用内，单独位于 suite/group 上不选择用例；参数化声明可能生成多个用例。
自定义测试包装函数需要显式配置。Node 必须能直接执行所选 JS/TS 文件；JSX/TSX、
浏览器代码或需要 loader/构建的项目，通过 `<Space>dc` 使用应用配置。

Rust 从 Cargo 产物和 `--list` 得到测试名，用 `--exact` 筛选，支持内联模块和常规
`foo.rs` / `foo/mod.rs` 布局。自定义 `#[path]`、宏生成测试和非 libtest 测试程序
通过 `dc` 使用专门配置。Rust 模块不能独立执行，`df` 会构建 Cargo 二进制。
Go 文件若依赖同包其他源码，也通过 `dc` 选择 **Debug Package**。
Dart 根据 `pubspec.yaml` 的 `sdk: flutter` 选择 Flutter，否则使用 Dart；先运行 `pub get`。
Java 使用 jdtls 的类级测试接口，`tF` 运行第一个发现的测试类及其方法；
多个顶层测试类应分别放在各自的文件中。

任意业务函数仍需参数和初始化环境，应通过测试或应用中的调用方进入调试。
`<Space>dC` 表示让已有会话运行到光标，不是直接调用该函数。

### Launch、attach 与项目配置

**Launch** 由调试器启动应用或测试，**attach** 连接你已在其他终端启动的进程。
所有已支持的调试语言都有 attach 入口；前面的当前文件、当前测试快捷键仍是 launch。

1. 打开对应语言的源码；Java 需要等待 jdtls 完成项目导入。
2. 用 `:pwd` 检查工作目录，必要时 `:cd /path/to/project`。
   `${workspaceFolder}` 和自动读取的 `.vscode/launch.json` 都以这个目录为准。
3. 在可执行源码行按 `<Space>db` 设置断点。
4. Launch 用当前文件/测试快捷键，或 `<Space>dc` 选择配置。Attach 先执行下方
   对应语言的终端命令，再按 **`<Space>dA`** 或执行 **`:DapAttach`**。
5. 选择对应 attach 配置，输入 PID、端口或服务 URI。如果程序先停在启动位置，
   按 `<Space>dc` 继续，直到源码断点。
6. `dw`/`dW` 求值或添加 Watch，`di`/`dO`/`do` 单步，`ds` 选择会话；
   `dD` 请求断开并保留进程运行，`dt` 请求终止目标，实际行为取决于适配器支持。
   `dt` 会向上找到当前会话树的根再逐级终止，一个适配器管多个目标时（js-debug、
   Electron）需要如此；另外单独起的无关会话不受影响。
   这些缩写均需先按 `<Space>`。

`DapAttach` 只列出当前文件类型的内置 attach 配置，以及项目 launch.json 中的
attach 配置。即使已有会话，也会新建附加会话；取消选择不会连接。如果选择期间
切换了源码 buffer 或工作目录，需要重新打开选择器。Attach 不会保存、编译或
替换已经运行的程序。

将项目专用的入口、参数、环境变量、端口和源码映射放在 `.vscode/launch.json`。
该文件按需读取，支持注释，无需手动调用 `load_launchjs()`。下方各语言给出的
单个配置对象放进这个结构的 `configurations` 数组：

```jsonc
{
  "version": "0.2.0",
  "configurations": [
    // 放入下面对应语言的 launch / attach 配置对象。
  ]
}
```

`type` 使用本指南中的适配器名，例如 `pwa-node`、`codelldb`。
支持 `${file}`、`${workspaceFolder}`、`${command:pickProcess}`。
本配置不执行 VS Code 的 `tasks.json`、`preLaunchTask` 或 `compounds`；
先在终端运行构建和开发服务器，再用 `dA` 添加其他附加会话。

示例中的调试端口监听本机地址。连接另一台主机时，可让远端继续监听本机地址，
通过 `ssh -N -L 5005:127.0.0.1:5005 user@server` 转发，再附加到
`127.0.0.1:5005`。两端源码路径不同还需配置对应语言的路径映射。
Mason 只为 Neovim 的 PATH 添加工具目录，不修改已有终端的环境；如果终端找不到
`dlv`，可自行安装到 PATH，或把 `:echo stdpath('data') . '/mason/bin'`
显示的目录加入终端 PATH。

### Go

安装 Go 和 Mason 的 `delve`。`df` 启动当前文件；如果它依赖同包其他文件，
在 `dc` 中选择 **Debug Package**。`td`/`tF` 通过 neotest-golang 和 Delve
调试单个测试或当前文件中声明的测试。

附加本地进程，先在终端编译并启动，再用 `dA` 选择 **Attach** 和对应 PID：

```sh
go build -gcflags='all=-N -l' -o ./build/app .
./build/app
```

连接 Delve 服务，在目标项目目录执行：

```sh
dlv debug . --headless --listen=127.0.0.1:38697 --api-version=2 --accept-multiclient
```

选择 **go: attach to remote Delve**，输入 `127.0.0.1`、`38697`。
已有二进制可把 `dlv debug .` 换成 `dlv exec ./build/app`。
这里使用 Delve 的 headless 多客户端服务，不能直接换成 `dlv dap`。
项目配置可保存连接地址与源码映射：

```jsonc
{
  "name": "Go server", "type": "go_remote", "request": "attach", "mode": "remote",
  "host": "127.0.0.1", "port": 38697,
  "substitutePath": [{ "from": "${workspaceFolder}", "to": "/srv/app" }]
}
```

适配器使用这里的 `host`/`port`，未设置时才询问。远程会话的 `dD` 会先从
Delve 移除当前编辑器的源码断点并恢复执行，然后断开；本地断点保留供再次附加。
准备步骤失败时会报告错误并保留连接。

### Python

安装 Python 和 Mason 的 `debugpy`，按需用 `\v` 选择项目环境。
`df` 调试脚本，`td`/`tF` 使用 neotest-python。pytest 测试需要在选中的环境安装
pytest；unittest 使用标准库。Attach 目标还需在**它自己的 Python 环境**安装
debugpy，这与 Mason 中运行适配器的环境分开：

```sh
python -m pip install debugpy
python -m debugpy --listen 127.0.0.1:5678 --wait-for-client app.py
# 或者调试模块、测试进程：
python -m debugpy --listen 127.0.0.1:5678 --wait-for-client -m pytest tests/test_app.py
```

以上目标命令每次运行一个。选择 **python: attach to debugpy**，输入
`127.0.0.1`、`5678`。`--wait-for-client` 让启动代码等到调试器连接后才执行。
项目配置示例：

```jsonc
{
  "name": "Python service", "type": "python", "request": "attach",
  "connect": { "host": "127.0.0.1", "port": 5678 },
  "justMyCode": false,
  "pathMappings": [{ "localRoot": "${workspaceFolder}", "remoteRoot": "/srv/app" }]
}
```

本地同路径进程可省略 `pathMappings`。自定义 launch 使用 `type: "python"`、
`request: "launch"`、`program`、`args`、`cwd`；按模块启动则用 `module`
替代 `program`。更多参数见 [debugpy 命令行文档](https://github.com/microsoft/debugpy/wiki/Command-Line-Reference)。

### Java

安装 JDK 21+，并在 Mason 中安装 `jdtls`、`java-debug-adapter`、`java-test`。
打开项目，等待 jdtls 导入完成。`dc` 动态发现主类，`df` 选择当前文件对应的
主类；发现前没有静态主类列表是正常的。每个项目使用独立的 jdtls workspace。
`td`/`tF` 调试最近的方法或第一个发现的测试类；jdtls 附加后也可用 `\dt`/`\dT`。

在终端带 JDWP 启动 JVM，按项目修改源码路径和完整类名：

```sh
javac -g -d out src/example/Main.java
java -agentlib:jdwp=transport=dt_socket,server=y,suspend=y,address=127.0.0.1:5005 -cp out example.Main
```

打包应用使用同样的 `-agentlib:jdwp=...`，随后改为 `-jar build/app.jar`。
选择 **java: attach to JDWP**，输入 `127.0.0.1`、`5005`。
`suspend=y` 在 main 执行前等待连接；常驻服务可用 `suspend=n` 立即启动。
Neovim 中打开的 Java 文件不必包含 main 方法。

```jsonc
{
  "name": "Java service", "type": "java", "request": "attach",
  "hostName": "127.0.0.1", "port": 5005, "cwd": "${workspaceFolder}"
}
```

自定义 launch 使用 `request: "launch"`、`mainClass: "example.Main"`、`cwd`，
可添加 `projectName`、`args`、`vmArgs`。确保 jdtls 能找到目标源码；多项目存在
歧义时设置 `projectName`。保存修改后可执行适配器支持的热替换；补装扩展后
运行 `:JdtRestart`。详见 [Java 调试器配置](https://github.com/microsoft/vscode-java-debug/blob/main/Configuration.md)。

### Rust

安装 Cargo/rustc 和 Mason 的 `codelldb`。`dc` 提供 **rust: cargo build**
与 **rust: cargo test**，从最近的 manifest 异步构建，解析实际产物（包括自定义
输出目录），有多个目标时询问；构建失败会取消启动。`df` 启动 Cargo 二进制，
`td`/`tF` 按前述规则筛选标准 libtest 测试。

Attach 先在其他终端编译并运行。把 `myapp` 换成 Cargo 二进制目标名，
自定义 target 目录还需调整产物路径：

```sh
cargo build --bin myapp
./target/debug/myapp
```

选择 **rust: attach to process** 和对应 PID。建议使用带调试符号的 debug
构建，优化后的 release 可能隐藏变量或改变源码行对应关系。附加操作本身不会
调用 Cargo，也不会重启二进制。

```jsonc
{
  "name": "Rust running process", "type": "codelldb", "request": "attach",
  "pid": "${command:pickProcess}", "sourceLanguages": ["rust"]
}
```

自定义构建参数时先执行 `cargo build --features ...`，再配置
`request: "launch"`、产物路径 `program`、`cwd` 和 `args`。
构建路径变化可加 `sourceMap`，例如 `{ "/build/project": "${workspaceFolder}" }`。

### C 和 C++

安装编译器和 Mason 的 `codelldb`，先生成带调试符号的程序。`dc` 提供
**LLDB: Launch**、**LLDB: Launch (args)**，按提示选择可执行文件。
C/C++ 尚未注册 `df`/`td`/`tF`，因为本配置不替项目选择构建系统和测试框架。

```sh
mkdir -p build
cc -g -O0 main.c -o build/app
# C++ 则改用这条编译命令：
c++ -g -O0 main.cpp -o build/app
./build/app
```

程序运行期间，在 `dA` 中选择 **c: attach to process** 或
**cpp: attach to process**，再选择 PID。实际项目使用对应构建系统的调试产物，
例如 CMake 的 Debug 构建。

```jsonc
{
  "name": "Native running process", "type": "codelldb", "request": "attach",
  "pid": "${command:pickProcess}"
}
```

Launch 则使用 `request: "launch"`、`program: "${workspaceFolder}/build/app"`、
`cwd`、`args`。PID 附加针对运行 CodeLLDB 的本机进程，单纯转发 SSH 端口
无法使用远端 PID；远程原生调试需另配 LLDB remote target。
C/C++ 和 Rust 的更多选项见 [CodeLLDB 附加配置](https://github.com/vadimcn/codelldb/blob/master/MANUAL.md#attaching-to-a-running-process)。

### JavaScript 和 TypeScript（Node / Vitest）

安装 Node 和 Mason 的 `js-debug-adapter`。`df` 启动当前 Node 脚本。
TypeScript 如果需要编译，生成 sourcemap 后运行输出的 JS；JSX/TSX 或专用
loader 需要项目 launch 配置。`td`/`tF` 使用最近安装的 Vitest，最近测试需 v3+。

在终端开启 Inspector，然后选择 **node: attach by host/port**：

```sh
node --inspect-brk=127.0.0.1:9229 app.js
# 编译后的 TypeScript 改用输出入口：
node --inspect-brk=127.0.0.1:9229 dist/app.js
# 从 Neovim 外启动 Vitest：
npx vitest run --inspect-brk=127.0.0.1:9229 --no-file-parallelism tests/app.test.ts
```

每次运行其中一个目标命令，附加到 `127.0.0.1`、`9229`。
`--inspect-brk` 会暂停启动，`--inspect` 则立即运行应用。
也可用 **node: attach to process** 按本地 PID 选择。

```jsonc
{
  "name": "Node service", "type": "pwa-node", "request": "attach",
  "address": "127.0.0.1", "port": 9229,
  "cwd": "${workspaceFolder}", "sourceMaps": true,
  "outFiles": ["${workspaceFolder}/dist/**/*.js"]
}
```

普通 JS 可去掉 `outFiles`，远程源码可添加 `localRoot`/`remoteRoot`。
Launch 配置改用 `request: "launch"`、`program`、`args`、`cwd`，项目 loader
可加 `runtimeExecutable`/`runtimeArgs`。Vitest 直接调试入口关闭文件并行，
让测试 worker 中的断点能够绑定。

### 浏览器 JavaScript 与 Chrome 扩展

先单独启动前端开发服务器，再启动专用 Chrome 调试实例。以下为 macOS 命令，
其他系统换成对应 Chrome 路径：

```sh
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --remote-debugging-port=9222 --user-data-dir="$HOME/.cache/nvim-chrome-debug" \
  http://localhost:5173
```

打开 JS/TS 源码，在 `dA` 中选择 **chrome: attach (port 9222)**。
[当前 Chrome 的远程调试行为](https://developer.chrome.com/blog/remote-debugging-port)
要求使用非默认用户目录。自定义端口或限定页面可以写入项目配置：

```jsonc
{
  "name": "Frontend page", "type": "pwa-chrome", "request": "attach",
  "port": 9222, "webRoot": "${workspaceFolder}",
  "urlFilter": "http://localhost:5173/*", "sourceMaps": true
}
```

Chrome 扩展的 **chrome: debug extension (launch)** 和
**chrome: debug extension (attach)** 需要另装 `js-debug-webext`，Mason 上游版
不足以调试扩展。保持扩展构建 watcher 运行；attach 使用上述专用浏览器，
先手动加载未打包扩展，再打开该包中的源码并选择 attach 预设。
两个预设都自动向上查找 `.output/chrome-mv3-dev`（WXT 布局）；其他布局
在项目配置中显式设置 `extensionPath`，指向构建输出目录。
Launch 会创建自己的 profile 并通过 CDP 安装扩展。
安装和排错见 [DIAGNOSTICS.md](DIAGNOSTICS.md) 与[扩展验证记录](../spikes/chrome-extension-dap/README.md)。

### Dart CLI

安装 Dart SDK，或使用 Flutter 自带的 Dart。适配器优先使用最近的
`.fvm/flutter_sdk/bin`，其次查找 PATH。先运行 `dart pub get`；直接调用
SDK 的 `dart debug_adapter`，不需 Mason 适配器。`df` 启动当前入口，
`td`/`tF` 通过 SDK 测试适配器调试用例。

```sh
dart run --enable-vm-service=8181 --pause-isolates-on-start bin/main.dart
```

选择 **dart: attach to VM service**，粘贴终端输出的完整 VM service URI，
例如 `http://127.0.0.1:8181/<token>/`。保留 token 和路径；单独端口号或
DevTools 网页地址都不是服务 URI。这个入口连接已有 VM。

```jsonc
{
  "name": "Dart VM", "type": "dart", "request": "attach",
  "cwd": "${workspaceFolder}", "vmServiceUri": "http://127.0.0.1:8181/REPLACE_TOKEN/"
}
```

Token 每次运行可能变化，交互入口更方便。Launch 使用 `request: "launch"`、
`program: "${workspaceFolder}/bin/main.dart"`、`cwd`、`args`。
`\dr` 请求支持的热重载，`<Space>dR` 重启通过 launch 启动的 CLI 会话。
VM 服务启动方式见 [Dart 调试工具文档](https://dart.dev/tools/dart-devtools)。

### Flutter

安装 Flutter 或使用 FVM，执行 `flutter pub get`，启动模拟器或连接设备，
用 `flutter devices` 查看。`dc` 提供 **flutter: launch app**（默认
`lib/main.dart`）、**flutter: attach to running app** 和当前测试文件。
`df` 使用当前文件作为入口；pubspec 声明 `sdk: flutter` 时，`td`/`tF`
使用 Flutter 测试适配器。

```sh
flutter devices
flutter run --debug --start-paused -d macos
```

把 `macos` 换成目标设备 ID。选择 **flutter: attach to running app**，输入
相同设备 ID，以及可选的 VM service URI。URI 留空则尝试设备发现，设备 ID
留空则由 Flutter 选择。目标应用须以 debug 模式运行。

```jsonc
{
  "name": "Flutter existing app", "type": "flutter", "request": "attach",
  "cwd": "${workspaceFolder}", "toolArgs": ["-d", "macos"],
  "vmServiceUri": "http://127.0.0.1:PORT/REPLACE_TOKEN/"
}
```

设备发现模式省略 `vmServiceUri`。Launch 配置使用 `request: "launch"`、
`program: "${workspaceFolder}/lib/main.dart"`，通过 `toolArgs` 选择设备和
flavor，例如项目已定义该 flavor 时使用 `["-d", "macos", "--flavor", "dev"]`。
保存后 `\dr` 热重载，`\dR` 执行 Flutter 热重启。
`dD` 断开编辑器，原来执行 `flutter run` 的终端继续管理应用进程。

### Electron

在项目中安装 Electron，按需构建主进程和渲染进程。
`dc` 中 **electron: main + renderer** 启动 `electron .` 后附加渲染进程。
连接外部启动的应用时，分别启用主进程和渲染进程端口：

```sh
./node_modules/.bin/electron --inspect=127.0.0.1:9230 --remote-debugging-port=9222 .
```

先选择 **electron: attach main**，输入 `127.0.0.1`、`9230`。
窗口创建后，再按 `dA` 选择
**electron: attach renderer (port 9222)**。两个会话都可以在 `ds` 中选择。
主进程断点阻塞渲染进程初始化或求值时，先用 `dc` 恢复主进程。
这条命令允许应用在附加前完成启动；需要捕获启动代码的断点时使用组合 launch 配置。
自定义端口使用两个独立项目配置：

```jsonc
{
  "name": "Electron main", "type": "pwa-node", "request": "attach",
  "address": "127.0.0.1", "port": 9230, "cwd": "${workspaceFolder}"
}
```

```jsonc
{
  "name": "Electron renderer", "type": "pwa-chrome", "request": "attach",
  "port": 9222, "webRoot": "${workspaceFolder}"
}
```

`dD` 作用于选中的会话及其派生的子会话。主进程和渲染进程是两棵独立的树，
整个应用调试结束时需要分别断开。
主进程使用 Node Inspector，渲染进程使用 Chromium CDP，端口不能互换。
更多说明见 [Electron 主进程调试文档](https://www.electronjs.org/docs/latest/tutorial/debugging-main-process)。

React Native 仍处于[独立可行性验证](../spikes/react-native-dap/README.md)，
尚未支持可用的 Hermes DAP 工作流。连接失败、断点未绑定、SDK 路径和系统权限
问题见 [DIAGNOSTICS.md](DIAGNOSTICS.md)。
