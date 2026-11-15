# 使用手册

这份文档讲**怎么用**这套配置。如果你是 Vim 新手，从[核心思路](#核心思路)开始往下读；
已经熟悉 Vim、只想看键位的，直接跳到[四个前缀](#四个前缀)。

安装和插件清单在 [README_CN](../README_CN.md)，这里只讲使用。

---

## 目录

- [核心思路](#核心思路)
- [键盘的语法](#键盘的语法)
- [四个前缀](#四个前缀)
- [去某处：`;`](#去某处)
- [当前文件与视图操作](#当前文件与视图操作)
- [文件类型与视图操作](#文件类型与视图操作)
- [窗口：`s`](#窗口s)
- [其余：`<leader>`](#其余leader)
- [工作流](#工作流)
- [审阅一轮 agent 修改](#审阅一轮-agent-修改)
- [忘了键位怎么办](#忘了键位怎么办)
- [调试](#调试)

---

## 核心思路

大多数编辑器把命令放进菜单，你靠**读**找到它。Vim 把命令放在键上，你靠
**知道自己想干什么**找到它。

这套配置把这一点做到底。每次按键，第一下就在回答一个问题：

| 你想…… | 按 | 因为它的含义是 |
|---|---|---|
| 去别的地方 | `;` | "哪个文件 / 符号 / 位置？" |
| 操作当前文件或视图 | `,` | "这里能做什么？" |
| 调整屏幕布局 | `s` | "这个窗口怎么办？" |
| 其他一切 | `<Space>` | git、测试、调试、AI…… |

**没有一个键是按插件归类的。** `;f` 就是找文件，不管背后是 picker、oil 还是别的——
你按它是因为你想要一个文件，不是因为你记得某个插件名。

两个直接后果：

- **天天用的是两键。** 找文件、格式化、跳定义。少用的才允许长一点。
- **前缀的用途保持稳定。** `,` 操作当前文件或视图，`;` 搜索目的地。
  通用操作在不同文件类型里保持含义；buffer 局部功能可以复用键位：例如 `,v`
  在 Python 中选择环境，在 LaTeX 中预览 PDF，菜单会显示对应的分区标题。

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

光标不必先进到对象里：光标在括号前面时，`ci(` 改的就是**后面那对**括号里的内容。
中间插一个 `l`（last）则往回找：`cil(` 改前一对括号里的内容。Visual 模式的 `an`、`in`
是 Neovim 自带的语法节点选择：每按一次 `an` 选区扩大到外层节点，`in` 再缩回去。

**which-key：** 按 `di`（或 `da`、`vi`）停半秒，弹窗列出所有对象。

### 4. 连按两次 = 整行；大写 = 更大或更强

动词连按两次就作用于当前行：`dd` `yy` `cc` `>>` `gcc`。

大写字母和对应的小写键是**同一个动作**，方向不变、走得更远：范围更大，或者力度更强。
Vim 自己的键就是这样：

| 小写 | 大写 |
|---|---|
| `d` `c` 到某处 | `D` `C` 到行尾（= `d$` `c$`） |
| `i` `a` 光标前 / 后插入 | `I` `A` 行首 / 行尾插入 |
| `w` `b` `e` 按词 | `W` `B` `E` 按字串（空白分隔，更大） |

本配置自己的成对键也照此理解，小写是窄的或普通的，大写是宽的或强的：

| 小写 | 大写 |
|---|---|
| `;s` 本文件的符号 | `;S` 整个工作区的符号 |
| `<Space>gl` blame 这一行 · `<Space>gr` 丢弃这个 hunk | `<Space>gL` blame 整个文件 · `<Space>gR` 丢弃整个文件的改动 |
| `<Space>gc` / `<Space>gh` 当前文件的 commit / 历史 | `<Space>gC` / `<Space>gH` 整个仓库的 |
| `<Space>uf` 当前文件的自动格式化 | `<Space>uF` 所有文件的自动格式化 |
| `<Space>tm` / `<Space>tf` 运行最近的测试 / 本文件的测试 | `<Space>tM` / `<Space>tF` 同样的运行，放在调试器里 |
| `<Space>bd` 删除 buffer | `<Space>bD` 删除 buffer 连同它的窗口 |
| `<Space>qq` 全部退出 | `<Space>qQ` 强制全部退出 |

不同的对象，或者并不比小写键更宽的范围，用另一个有名字的字母，而不是大小写：
`<Space>xx` 已经列出全部诊断，所以当前文件的诊断是 `<Space>xb`（**b**uffer），不是
`xX`。例外是"从这里"：`;F` 和 `;D` 从当前文件所在目录开始找文件、搜文本，而 `;f`
和 `;/` 从工作目录开始。Vim 的方向对（`o`/`O`、`n`/`N`、`f`/`F`、`t`/`T`、`p`/`P`）
是它自己对大小写的用法，保持 Vim 原样。

在 `[` / `]` 抽屉里（[第 6 条](#6-单字母命名空间)），大写走到同一列表的尽头：对列表是
第一个 / 最后一个（`[Q` / `]Q` quickfix、`[D` / `]D` 诊断、`[B` / `]B` buffer），
对文本对象是对象的结尾（`]m` 下一个函数开头，`]M` 它的结尾）。

顶部 buffer 栏、buffer 切换（`<S-h>`/`<S-l>`、`[b`/`]b`，以及跳到第一个 / 最后一个的
`[B`/`]B`）和 buffer 选择器会跳过终端 buffer。用 `<Space>af` 聚焦 AI 面板，`<C-/>` 打开 shell 终端，
避免文件导航把编辑窗口变成终端面板。
点击文件标签会聚焦当前 tabpage 的编辑区域，chat 和终端面板保持可见。
如果只剩面板，会新建一个编辑分屏来显示文件。buffer 键在 chat 或其他面板里也一样：
在那里按 `]B`、`]b` 或 `;B`，会先回到编辑区域，再按它的 buffer 列表执行；取消的
`;B` 留在原处。Oil（`-`、`;o`）、Harpoon（`;1`–`;9`、`;h`）、文件路径上的 `gx`，以及
文件和搜索选择器也一样：这套配置从面板里打开的东西都进编辑区域，不会进面板自己的
窗口。GitHub 选择器在 tab 里有编辑窗口时也这样；它们不会为此新开分屏，因为大多数
操作并不打开 buffer。

几个单键只是缩写：`D` = `d$`，`C` = `c$`，`x` 也近似 `dl`，只差一点：这里的
`x` 删进黑洞寄存器，既不会覆盖系统剪贴板，也不会往 yank 历史（`[y` / `]y`）里
添一条。所以经典的 `xp`（交换两个字符）在这里要写成 `dlp`；`"ax` 仍会删进寄存器
`a`。`s` 本来是 `cl`，这里把它让给了窗口前缀，改一个字符请用 `cl`。

### 5. 数字 = 次数

放在动词前或目标前都行：`3dd`、`d3w`、`5j`、`3>>`、`10<C-a>`。

### 6. 单字母命名空间

有几个键本身不做事，只是打开一个抽屉，后面再跟一个字母：

| 抽屉 | 含义 | 例子 |
|---|---|---|
| `[` `]` | 上一个 / 下一个 X | `]d` 诊断 · `]e` 错误 · `]h` git hunk · `]q` quickfix · `]r` 引用 · `]m` 函数 · `]c` 类 · `]x` 冲突 · `]y` yank 历史。大写 = 第一个 / 最后一个：`[D` `]Q` `[B` `]B` |
| `g` | 去某处 / 关于光标下的东西 | `gd` 定义 · `gr` 引用 · `gb` 实现 · `gy` 类型 · `gC` 调用方 · `gs` JS 源码（JS/TS） · `K` 文档 · `gx` 打开 URL / 文件 · `gS` 拆 / 合行 · `gv` 重选 |
| `z` | 折叠与拼写 | `zR` 全展开 · `zM` 全折叠 · `za` 切换 · `z=` 拼写建议 · `zg` 加进词典 |
| `Ctrl` | 立即执行，不问问题，任何模式都一样 | `<C-h/j/k/l>` 窗口 · `<C-/>` 终端 · `<C-o>` 原路返回 · `<C-a>` `<C-x>` 加减 · `<C-r>` 重做 |

列表视图和面板（picker、oil、大纲、右侧和底部的面板）共用几个没有弹窗会列出的键。
视图有这个动作时，就在这个键上：

| 键 | 在列表视图或面板里 |
|---|---|
| `q` | 关闭 |
| `<C-c>` | 停止进行中的请求（Chat 的回复、`<Space>ae` 的修改） |
| `<C-s>` / `<C-v>` / `<C-t>` | 在下方 / 旁边 / 新 tab 打开条目 |
| `<M-p>` · `<M-.>` | 开关预览 · 隐藏文件（oil 里是 `g.`） |
| `dd` · `<C-x>` | 删除条目（已打开的 buffer、已保存的 Chat）· 在 picker 输入时同样作用 |
| `R` | 刷新（oil 里是 `gR`，因为它的列表是你要编辑的文本） |
| `g?` | 列出视图自己的键（原本就有 `?` 的地方 `?` 也保留） |

**which-key：** 按 `[`、`]`、`g`、`z` 停半秒，弹窗列出抽屉里的东西，并按
类别加标题分块（`── diagnostics`、`── git` ……），每块一个颜色，长列表因此读起来
是几个区块而不是一串字母。分组在 `lua/config/whichkey_spec.lua` 里声明；启用分组的
菜单中，未显式归类的键（包括新增插件键和内置命令）统一放在最后的 `── others`
下，避免混入上一个分组。没有剩余条目时不显示 `others`；`z` 等未声明分组的
菜单保留默认布局。

有些 buffer 给这些键另有含义，弹窗在那里显示的就是那个含义。`]]` / `[[`（以及
`][` / `[]`）在哪里都是 buffer 的章节跳转：要么是 Vim 自带的，要么是 Python、Go、
Rust、Vim script、TeX、Markdown、help 和 checkhealth buffer 里文件类型插件的——
Python 是顶层 class 或 def，Go 是 type 或 func，Vim script 是函数。下一个 / 上一个
引用是 `]r` / `[r`，只有 TeX buffer 例外：那里 `]r` / `[r` 在所有模式下都是 VimTeX
的 frame 跳转。Python 的 `]m` / `]M` 是它的 class/def 跳转，VimTeX 的是环境；VimTeX
另外加了 `]n` / `]N` 数学区、`]R` frame 结尾和 `]/` / `]*` 注释（开头 / 结尾）。在
diff 窗口里 `]c` / `[c` 是下一个 / 上一个 hunk（弹窗写作 *Next class start (diff:
next hunk)*）；在 CodeDiff 视图的窗格里，`]c` / `[c` 和 `]h` / `[h` 都走视图显示的
hunk，用的是 CodeDiff 自己的 *Next hunk*。`gO` 在代码里是
*[LSP] Document symbols (Nvim default)*；在 markdown、help、checkhealth 和 man
buffer 里是 *Show outline*——标题列表，不需要语言服务器——放在单独的 `outline`
分区下。

`gx` 打开当前行离光标最近的 HTTP(S) 链接或已存在的本地文件：URL 交给系统
浏览器，引用的文件在 Nvim 内打开。从终端触发时，文件打开在当前 tab 的编辑窗口，
原终端保持可见。支持绝对路径、`~/…` 和相对路径；相对路径以源文件所在目录，
或 Snacks 终端记录的工作目录为基准。含空格的路径用引号或反引号包裹。
没有找到目标时，普通文件 buffer 仍用系统默认应用打开自身；终端不执行打开操作。

在终端 Normal 模式下，表格同一列中被换行拆开的 `(...)` 或 `<...>` 目标也会
完整打开，包括报告路径显示成 `(/tmp/`、下一行 `report.md)` 的情况。引号包裹的
文件路径也支持换行。比面板还宽、由终端自己折行（后半段从下一行第 0 列开始）的
链接，不论带不带括号，也会完整打开。光标放在任一段都可以。先按 `Ctrl-\` 或 `jk`
退出终端输入模式。

在终端 buffer 里复制时，被终端折行的文本按程序打印的那一整行复制：对这类链接用
`yi(` 或 `V` 加 `y`，剪贴板里就是完整 URL，不会在面板边缘多出一个换行。
`yiW`、`y$` 这类只在一行内移动的动作，仍然停在该行末尾。

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

剩下的键都挂在四个前缀下面，每个前缀回答一个问题——这就是[核心思路](#核心思路)，
下一节逐个展开。

### 为什么这件事重要

你不需要"学会 `dif`"。你学的是 `d`，和 `if`，这个组合自然就成立了——
连带 `cif`、`yif`、`>if`、`gcif`、`vif` 也一起会了。
**6 个操作符 × 20 个目标 = 120 个你从没背过的命令。**

想做一件新事情时，只问两个问题：*什么操作？* 和 *作用在什么上？*
然后按这个顺序打出来。打到一半忘了，停半秒，菜单会告诉你。

---

## 四个前缀

```
;  去某处              ,  当前文件 / 视图操作
s  窗口                <Space>  其余一切
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
| `;f` | 在 cwd 下按文件名找 |
| `;i` | 遵守 `.gitignore` 找文件，包含隐藏文件 |
| `;F` | 在当前文件所在目录找 |
| `;r` | 最近打开过的（cwd 下） |
| `;b` | 已打开的 buffer |
| `;B` | 按标签字母选一个 buffer |
| `;g` | git 跟踪的文件 |
| `;p` | 切换项目 |
| `;a` | **上次使用的 buffer（alternate）**——回到当前窗口上一个 buffer。 |
| `;;` | 重开上次的搜索，结果列表原样保留 |

通过文件启动（如 `vi /work/project/src/main.lua`）时，cwd 会设为最近的 Git
根目录（`/work/project`）；非 Git 文件则使用文件所在目录。支持 worktree 和
子模块，符号链接按目标文件的仓库识别。新文件的父目录尚不存在时，从最近的已存在
祖先目录开始查找。多个参数以第一个文件为准；目录参数使用指定目录，无参数或
stdin 启动保留 shell 的 cwd。只在启动时设置一次，之后切换文件不会自动改变 cwd。
启动命令或恢复的 session 已改变 cwd 时，以它们为准。用 `:pwd` 查看，
`:cd /path/to/project` 手动切换；`;f` 和 `;/` 从 cwd 开始搜索。

Nvim 把这个上一个 buffer 称为 **alternate buffer（交替缓冲区）**。在同一窗口
先打开 A，再打开 B，按 `;a` 回到 A，再按一次回到 B。它对应原生 `Ctrl-^`，
适合在实现文件和测试文件之间来回编辑。

`;<Space>` 是最该养成习惯的一个：它会学习你常碰哪些文件并排到最前。

### 文本与符号

| 键 | 作用 |
|---|---|
| `;/` | 在 cwd 下搜文本 |
| `;?` | 遵守 `.gitignore` 搜文本，包含隐藏文件 |
| `;w` | 搜光标下的词 |
| `;l` | 在当前文件里按行找 |
| `;D` | 从这里搜：当前文件所在目录 |
| `;s` | 当前文件的符号（函数、类） |
| `;S` | 整个 workspace 的符号 |

`;f` 和 `;/` 包含被 Git 忽略的文件，但排除常见构建/依赖目录。`;i` 和 `;?`
按 `.gitignore` 过滤，不做额外目录排除，因此 `build/` 等目录内被跟踪的源码也能搜到。

在 picker 里，`<C-s>` / `<C-v>` / `<C-t>` 在下方 / 旁边 / 新 tab 打开条目，`<M-p>`
开关预览，`<M-.>` 开关隐藏文件（原来是 `<M-h>`，被 tmux 拿去切换 pane 了）；Normal
模式下 `g?` 或 `?` 列出 picker 的键。在 `;p` 里，Insert 模式的 `<C-w>` 删除查询里的
一个词，Normal 模式的 `<C-w>` 把该项目设为当前 tab 的目录（`:tcd`）。

### 浏览

没有文件树侧栏：目录一律用 oil 浏览和编辑，文件一律用上面的 picker 到达。

| 键 | 作用 |
|---|---|
| `;o` | **oil**——把目录当文本编辑（见下） |
| `-` | 用 oil 打开当前文件所在目录 |

`;F`、`;D` 使用当前文件所在目录或 Oil 正在显示的目录；
在终端等面板中则使用当前窗口/标签页的工作目录。

在终端（含 Codex）中，先用 `Ctrl-\` 或 `jk` 离开终端输入模式，
再按 `-` 或 `;o`。Oil 会在当前标签页的编辑区域打开并获得焦点；没有编辑窗口时
会新建一个空白分屏。`q` 关闭 Oil 并返回编辑区域，终端保持打开。

Oil 列表没有待保存的改动时，`;f` 会在同一窗口打开选中的文件，取消则保留原来的
列表和布局。如果还有未保存的目录编辑，选择器会使用其他编辑窗口，必要时新建分屏。

在 Oil 中，`h/j/k/l` 保留原生光标移动，方便编辑文件名。
用 `-` 返回上一级目录，回车打开选中的文件或进入目录；`g?` 查看 Oil 快捷键，`q` 关闭。
`<C-s>` 在下方打开条目，`<C-v>` 在旁边，`<C-t>` 在新 tab，与 picker 和大纲是同一组
组合键；`<M-p>` 开关预览，`gR` 重新读取列表，`g.` 显示隐藏文件。`<C-r>` 是重做，
`v<C-v>` 进入列块 Visual，与任何 buffer 一样。
修改文件名或增删行后，用 `:w` 检查并确认文件操作。

### Harpoon 文件

| 键 | 作用 |
|---|---|
| `;H` | 把当前文件加进 Harpoon |
| `;h` | 打开 Harpoon 菜单 |
| `;1` … `;9` | 直达第 1-9 个 Harpoon 文件 |

把正在改的三四个文件加进去，之后 `;2` 不用看屏幕就能过去。换任务时换一批。
Harpoon 的列表不是 bufferline 的固定（`<Space>bp`），后者只是让一个标签停在
tabline 左端。

### 位置

`;j` 跳转表 · `;m` 标记 · `;c` git hunk · `;t` TODO · `;T` TODO/FIX/FIXME

`;c` 列出整个仓库里所有改动过的 hunk（已暂存和未暂存的都有），预览窗口显示
diff，回车跳过去。`]h` / `[h` 则是从光标处逐个前后跳。在这个 picker 里，`<Tab>`
暂存或取消暂存这个 hunk，`<C-x>` 则是**还原**：确认 Yes/No 之后，未暂存的 hunk
会从工作区里丢弃，已暂存的则从暂存区撤下。它是这里唯一有破坏性的键，用的是 picker
里"移除一项"的组合键；输入框里的 `<C-r>` 和 Insert 模式下一样，用来插入寄存器。
`<leader>gs` 里也是如此。

---

## 当前文件与视图操作

按 `,` 查看当前文件或视图上的操作。通用编辑与语言专用功能共用这个菜单，
分区标题标明每类操作属于哪个上下文。

| 键 | 作用 |
|---|---|
| `,a` | **Code action**——修复菜单（补 import、快速修复） |
| `,f` | 格式化 |
| `,r` | 重命名符号，全项目生效，带实时预览 |
| `,c` | 运行 codelens（gopls 提供 generate、test、tidy、govulncheck） |
| `,n` | 生成文档注释 |
| `,x` | 在下方的终端分屏里运行当前文件 |
| `,O` | 显示 / 隐藏当前文件大纲 |

`,a`、`,r` 和 `,c` 只在有语言服务器的地方存在——纯文本文件里它们根本不出现。

在大纲里，`j` / `k` 移动，`p` 把源码滚动到该符号，回车跳过去，`<C-s>` / `<C-v>` 在
下方 / 旁边打开；`<C-j>` / `<C-k>` 在那里也是窗口移动，与别处一致。

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
| `,ef` / `,eF` | 提取成函数 / 提取成另一个文件里的函数 |
| `,ex` | 把表达式提取成变量，buffer 里相同的表达式一并替换 |
| `,i` | 把光标下的变量内联到所有引用处 |
| `,R` | 重构菜单：提取/内联变量、提取/内联函数 |
| `,w` | 替换光标下的词 |
| `,F` | 完整的搜索替换面板 |

`,ef`/`,eF`/`,ex` 在 Visual 模式下作用于选区；在 Normal 模式下是操作符，和 `d`
一样后接移动或文本对象：`,ef_` 提取当前行，`,efj` 提取当前行和下一行，`,exi(` 提取
括号内的内容。每个操作都会询问名称，`,eF` 会先询问目标文件。`,ex` 会替换 buffer 中
所有相同的表达式，其他函数里的也一样，执行后请检查结果。`,i` 通过语言服务器查找引用，
所以 buffer 需要已连接 LSP。`:Refactor extract_var total` 对上一次的 Visual 选区执行
同样的操作，名称直接作为参数给出。


### 文件类型与视图操作

`<localleader>` 也设为逗号。文件类型专用键只注册在对应 buffer：Python 显示导入/环境，
TeX 显示编译/预览，普通文本不会出现这些分区。分区标题不增加按键层级。
`[LSP]` 标明需要语言服务器的操作，`[AI]` 标明出现在 `<Space>a` 以外菜单里的 AI 键（目前是 Git 视图里的 `,C` 审阅反馈），以 "…" 结尾的条目会先询问（输入或选择）再执行：`,a`、`,r`、`,e…`、`,R`、Python 的 `,v`。Java 测试调试键在 jdtls 与调试适配器初始化后出现。
Dart 热重载/重启需要兼容且正在运行的 DAP 会话。菜单列出的是操作入口，
不代表所需依赖或运行会话一定已经就绪。

| 上下文 | 操作类别 | 键 |
|---|---|---|
| Go | 导入 / 语言服务 | `,o` 整理导入 · `,G` 重建 gopls 索引 |
| Python | 导入 / 环境 | `,o` 整理导入 · `,v` 选择虚拟环境 |
| C/C++ | 关联文件 | `,H` 切换源文件/头文件 |
| Dart / Flutter | 运行控制 | `,dr` 热重载 · `,dR` Flutter 热重启 |
| Markdown | 预览 | `,p` 浏览器预览 · `,m` 编辑器内渲染 |
| CodeCompanion Chat | 对话 / 渲染 | `,s` 保存 · `,X` 清空消息 · `,q` 结束 Chat · `,z` 折叠代码块 · `,m` 切换 Markdown 渲染 |
| 搜索替换面板 | 替换 / 同步 / 结果 / 历史 | `,S…` 面板操作；`g?` 帮助 |
| LaTeX | 编译 | `,b` 连续编译开关 · `,s` 停止 · `,K` 清理辅助文件 · `,E` 错误 |
| LaTeX | 预览 / 工具 | `,v` 看 PDF · `,t` 目录开关 · `,L…` VimTeX 完整命令集 |
| CodeDiff | 面板 / 布局 | `,P` 聚焦 explorer（文件面板） · `,B` 显示 / 隐藏它 · `,z` compact 模式（折叠未改动的行） · `,I` diff 布局：行内 / 并排 |
| CodeDiff | 冲突处理 | `,go` 接受 current（我方） · `,gt` incoming（对方） · `,gb` 保留基础版本（两边都丢弃） · `,ga` 两边都要；末字母大写（`,gO`、`,gT`、`,gB`、`,gA`）作用于整个文件 |
| CodeDiff | 审阅 | `,C` 对 hunk / 选区 / 文件写反馈 · `,S` / `,U` 暂存 / 取消暂存这个 hunk · `,X` 把这个 hunk 丢弃回基线 |
| 终端 | 会话 | Normal 模式下 `,1`–`,9` 选择终端 1–9（先按 `jk`） |

CodeDiff 是叠加在文件类型之上的视图：Markdown 差异文件保留 `,p`/`,m`，同时加上
它自己的分区。`,z` 和 `,I` 在每个视图的每个窗口里都可用，文件面板和历史面板也一样；
`,P` 和 `,B` 只出现在有文件面板的视图里（状态视图和 revision 对比），历史视图里没有。
Git 仓库的视图里，`,C` 在每个窗口都可用。`,S`、`,U` 和 `,X` 暂存、取消暂存和丢弃
一个 hunk——就是状态视图文件面板的 `S` / `U` / `X`，只作用于一个 hunk——只出现在视图
能安全执行它们的地方，见 [Git](#git) 一节的表格。在 CodeDiff 窗格里 `,S` 就是这个
暂存键，不是搜索替换面板的 `,S…`，后者只在那个面板里存在。关闭视图后所有键原样还回，语言键保持
不变。终端数字键不会出现在普通文件中，也不会拦截 shell 输入。

通用编辑键保持原样：`,h`/`,l` 减少/增加缩进，`,k` 上移，`,r` 重命名，`,c` 运行 codelens，
`,e…` 提取重构。文件类型的大写键、`,L…` 与 `,S…` 避免给这些短键增加前缀等待。
按 `,` 等一下即可查看当前操作分区。

### 搜索替换面板：`,S`

用 `,F` 打开 grug-far，或用 `,w` 预填光标下的词。输入搜索与替换文本，
用 `Tab` / `Shift-Tab` 切换输入字段，确认结果后再应用修改。
Normal 模式下按 `,S` 可按操作类别查看面板功能，`g?` 打开完整帮助。
这些键只在搜索面板出现，其可编辑结果区仍保留通用逗号编辑键。

| 键 | 操作 |
|---|---|
| `,Sr` | 执行替换，支持多行替换 |
| `,Ss` / `,Sl` / `,Sv` | 将编辑后的结果写回所有文件 / 当前行 / 当前文件 |
| `,Sj` / `,Sk` | 应用当前修改、移除该结果，并打开下一个 / 上一个修改 |
| `,Sn` / `,Sp` | 同步当前修改并移到下一个 / 上一个匹配 |
| `,So` / `,Si` | 打开 / 预览结果位置 |
| `,Sq` | 将结果发送到 quickfix |
| `,St` / `,Sa` | 打开搜索历史 / 将当前搜索加入历史 |
| `,Sf` / `,Sb` | 刷新搜索 / 中止正在执行的操作 |
| `,Se` / `,Sx` | 切换搜索引擎 / 替换解释器 |
| `,Sw` | 开关搜索命令显示 |
| `,Sc` | 关闭面板 |

### VimTeX 完整命令：`,L`

在 `.tex` buffer 中按 `,L` 可查看完整的 VimTeX 命令组。以下 22 个按键组合与上面的
LaTeX 直接操作键并存，均可在 Normal 模式使用；`,LL` 还支持 Visual 模式。
BibTeX buffer 也会提供其中一部分命令。

| 键 | 操作 |
|---|---|
| `,Ll` | 连续编译开关 |
| `,LS` | 编译一次 |
| `,LL` | 编译选中行；Normal 模式下接动作或文本对象 |
| `,Lk` / `,LK` | 停止当前项目 / 所有已打开项目的编译 |
| `,Lo` | 打开编译器输出 |
| `,Le` | 显示错误与警告 |
| `,Lg` / `,LG` | 当前项目 / 所有已打开项目的编译状态 |
| `,Lc` / `,LC` | 清理辅助文件 / 同时删除输出文件 |
| `,Lv` | 查看 PDF，并正向定位到源文件位置 |
| `,Lt` / `,LT` | 打开 / 切换目录 |
| `,Li` / `,LI` | 当前项目 / 所有已打开项目的 VimTeX 信息 |
| `,Lq` | VimTeX 消息日志 |
| `,Lm` | 列出 VimTeX 的 Insert 模式快捷键 |
| `,Lx` / `,LX` | 重载 VimTeX 脚本 / 当前 buffer 状态 |
| `,Ls` | 在主项目与当前子文件之间切换 |
| `,La` | 光标所在项的上下文菜单 |

### 颜色预览

颜色预览支持十六进制、`rgb()`、`hsl()` 和 CSS `var(--name)` 引用；CSS 变量定义
在当前 buffer 内解析。前端文件还会预览 Tailwind 类名；Tailwind LSP 连接后可提供
项目自定义颜色。`:ColorizerToggle` 切换当前 buffer 的颜色预览。

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

`ss` 和 `sv` 就是 Vim 自带的 `:split`、`:vsplit`。`splitbelow` 和 `splitright`
让所有普通分屏都开在当前窗口的下方或右侧，`:new`、`:help` 和 `,x` 的终端也一样。
面板（agent、quickfix、调试视图）仍停靠在 edgy 分给它们的边上。

在面板里，`q` 关闭它，`<C-w>` 的调整大小键照常可用。edgy 自己的 `Q` 和 `<C-q>`
（会让面板一去不回）以及它在 `]w` / `[w` 上的窗口轮换都已关闭：`]w` / `[w` 仍是跳到
警告，`<C-q>` 仍是列块 Visual，面板之间用 `Ctrl-h/j/k/l` 移动。

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


## 其余：`<leader>`

`<leader>` 就是 **空格键**。按下稍等，每个字母是一个分组。

| 键 | 分组 | 内容 |
|---|---|---|
| `<Space>g` | Git | 状态、blame、hunk、行内 diff（`gD`）、lazygit（`gg`）、diff 与历史视图（`gv`、`gm`、`gk`、`gh` / `gH`）、保存的基线（`gK`） |
| `<Space>G` | GitHub | PR、issue、review |
| `<Space>d` | 调试 | 断点、单步、查看变量 |
| `<Space>t` | 测试 | 运行 / 调试最近的测试（`tm` / `tM`）和本文件（`tf` / `tF`）、汇总、输出、诊断 |
| `<Space>x` | 诊断 | 错误列表、当前文件的（`xb`）、quickfix、location list |
| `<Space>a` | AI | 右侧的 Chat——Codex 面板和 CodeCompanion Chat（`an` 新建、`al` 切换、`ac` / `af`）、prompt、transcript、审阅轮次（`av` / `aV`）、API key（`ax`） |
| `<Space>b` | Buffer | 删除、固定、移动（`b<` / `b>`）、删除其他、删除隐藏的（`bh`） |
| `<Space>m` | 管理 | 配置、插件源码、help、man、键位、消息、Lazy、Mason、LSP 状态 |
| `<Space>s` | 会话 | 保存 / 恢复工作布局 |
| `<Space>y` | 复制 | 复制文件路径、`path:line`（`yl`）、git permalink（`yg`）、yank 历史、寄存器 |
| `<Space>u` | 开关 | 换行、拼写、诊断、inlay hint、配色 |
| `<Space><Tab>` | Tab | tab page：新建（`<Tab>n`）、关闭、下一个 / 上一个、第一个 / 最后一个 |
| `<Space>q` | 退出 | 全部退出 |

### 配置和插件文件

| 键 | 作用 |
|---|---|
| `<Space>mf` | 在这份 Neovim 配置中找文件 |
| `<Space>mF` | 在 lazy.nvim 安装目录中找插件源码 |

这两个入口用于维护编辑器本身，放在管理组中。

### 消息与通知

按 `:` 时，命令行出现在屏幕上方的弹窗里，补全菜单紧跟在它下面；`/` 和 `?`
搜索仍在最底下一行。不会停下来等你按 **Enter**：Vim 自己的消息和报错跟插件
发出的通知一样，在右上角弹出，过几秒自动消失。`:w` 的 "written"、撤销、`]q` 的
"(2 of 9)" 这类"刚刚发生了什么"的确认，改为在右下角以小字显示两秒。弹窗放不下
的长行会在边缘截断。20 行以上的消息改为在底部的分屏里显示；在分屏里按 `q` 关闭，
`<Space>un` 会连同弹窗一起关掉。按了一半的命令（`2d`、`"a`）和 Visual 选区的大小
显示在状态栏里。

| 键 | 作用 |
|---|---|
| `g<` / `<Space>mnl` | 在分屏里重看上一条命令的输出 |
| `:messages` / `<Space>mna` | 在分屏里看消息历史：`:echomsg`、`print()` 输出和错误（普通 `:echo` 不记录） |
| `<Space>mnh` | 通知历史：插件发出的通知、Vim 的报错和警告，以及最近一条普通消息 |
| `<Space>mnt` | 在 picker 里搜索通知 |
| `<Space>un` | 关掉屏幕上的通知 |

插件发出的通知只在通知历史里；Vim 的报错和警告两边都有。Vim 的普通消息共用一个
弹窗，下一条会把它替换掉，所以要找更早的一条，去 `:messages` 里看。两份历史都在
`<Space>mn` 组下，组名是 *Messages/notifications*。

---

## 工作流

### 读陌生代码

```
;/  搜一个你认得的词
gd  跳到定义
gd  再跳，再跳——顺着往下追
Ctrl-o  原路返回
gC  谁调用了它？
]r  当前文件里这个符号的下一处
```

在 TeX buffer 里 `]r` 是 VimTeX 的 frame 跳转；`]]` 在哪里都是章节跳转（见[单字母
命名空间](#6-单字母命名空间)）。

`K` 显示光标下内容的文档，`Ctrl-f` / `Ctrl-b` 在光标不离开代码的情况下滚动
这个弹窗，`KK` 进入弹窗。`gr` 列出所有引用。输入函数调用时，参数列表会自动显示在
上方。

在 JavaScript 和 TypeScript 里，对从某个包导入的东西按 `gd`，只会停在这个包的
类型声明（`.d.ts`）里。`gs` 会继续跳到实际运行的 JavaScript，方便读实现；和 `gd`
一样用 Ctrl-o 跳回。同时发布多份构建（CommonJS 和 ES module）的包可能有多个结果，
这时会放进 quickfix 列表。`<Space>uh` 打开 inlay hint，把参数名和推断出的类型直接画在代码行里；只要
语言服务器提供就能用，默认关闭。

### 编辑循环

```
;<Space>   打开文件
,a         让语言服务器修掉能修的
,f         格式化
<Space>tf  跑这个文件的测试
```

语言服务器和 linter 把问题标在 gutter 上，图标与状态栏计数用的相同：`` 错误、
`` 警告、`` 信息、`` 提示。每行只放得下一个标记，同一行有多个问题时显示最严重
的那个。`]d` / `[d` 跳到下一个 / 上一个并显示消息；`<Space>xd` 显示当前行的。

在两个文件之间来回用 `;a`；三四个文件就用 `;H` 加进 Harpoon，然后 `;1`-`;4`。

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
`<Space>gf` 打开当前文件的历史。两者都会聚焦浮动终端并进入输入状态：`j`/`k`
直接交给 lazygit，快速连按也不会退出，`q` 退出 lazygit。lazygit 本身没有 Vim 式的
Normal/Insert 模式；`Ctrl-]` 可以主动退出 Neovim 的终端输入状态，`i` 恢复输入。
`;c` 跳到仓库里任意一处改动的 hunk（见[位置](#位置)）。

Diff 视图由 CodeDiff 提供。每个视图开在自己的 tabpage 里，左边是文件面板，旁边是
所选文件的两侧（历史视图 `gh` / `gH` 则在底部的面板里列出 commit）：

| 键 | 显示 |
|---|---|
| `<Space>gv` | **Diff 视图**——状态视图：Staged、Changes、Conflicts 三组，包括未跟踪的文件。index 对比 HEAD，工作区对比 index |
| `<Space>gm` | 工作区对比 `main`（没有就用 `master`，再没有就用 `HEAD`）——对比的是分支本身，不是它的 merge base |
| `<Space>gM` | 工作区对比你选的分支、tag、最近的 commit 或基线 |
| `<Space>gk` | **任选两端对比**：工作区、index、基线、分支 / tag / commit，或你输入的 revision |
| `<Space>gK` | 把当前代码存为一个有名字的基线，供以后 `gk` 和 `gM` 对比 |
| `<Space>gh` / `<Space>gH` | 当前文件 / 整个仓库的历史：最新的 100 个非 merge commit（和 `gc` / `gC` 列 commit 一样） |
| `<Space>gq` | 关闭本 tab 的 diff 视图，或 `<Space>gd` 的分屏（见下文） |

工作区干净时，`<Space>gv` 直接提示，不打开空视图；在视图里按它会提示改用
`<Space>gq`——在那里它只会把视图关掉。名字先解析成 commit，只有标签里保留名字，
所以叫 `docs` 或 `history` 的分支也能和别的分支一样对比；不是 commit 的名字会被
拒绝。超过 100 个 commit 的历史用范围来看：`:CodeDiff history origin/main..HEAD`
（或者设置 `history_limit`，见[设置](#设置vimgai_review)）。

`<Space>gk` 会问两次：先 *Compare from*，再 *Compare … with*。CodeDiff 总把"活"的
一端——工作区，其次是 index——放在右边，所以先选了它会对调两边，并提示一声；
index 对比工作区就是状态视图，看它的 Changes 组即可。两端相同会被拒绝。
*Type a revision…* 接受任意 revision，作为第一端时也接受一个自成一体的范围：
`main...feature` 是 `feature` 对比它与 `main` 的 merge base，`main...` 是工作区对比
`main` 与 `HEAD` 的 merge base。两端内容相同时提示 "no differences"，什么也不打开
——除非工作区里有大到无法对比的未跟踪文件（见下文），它们可能有看不到的差别：
这时视图照常打开，并列出这些文件。

视图里，`]h` / `[h`（和别处一样）以及 `]c` / `[c` 在视图显示的 hunk 之间跳，`]f` / `[f` 在文件之间跳，`do` / `dp` 像 vimdiff
一样取来或推过去一处改动，`gf` 在上一个 tab 里打开这个文件，`g?` 列出 CodeDiff
的键。其余的都在 `,` 菜单里（[文件类型与视图操作](#文件类型与视图操作)）。状态栏写明
视图在对比什么（`main → working tree`）。某一侧缺少的行用 `╱` 斜线填充。鼠标滚轮
放在任一对比窗口上，上下滚动都会让两侧保持同步，包括填充区域和折叠区域；键盘焦点
保持原处，文件面板独立滚动。视图跟着磁盘上的文件变化，所以 agent 写下的内容会在
你看的时候出现；光标保持行号不变，而不是跟着原来那段文字走。

文件面板，以及历史面板里每个 commit 下的文件，都按目录树显示。在面板里按 `i` 切换成
平铺列表（只对当前视图有效），`zo` / `zc` 展开或折叠光标所在的目录，`zR` / `zM` 展开或
折叠全部。在目录行上按 `,C` 会提示你把光标放到文件上。

视图的每个窗口里，`;`、`s`、切换 buffer 的 `H` / `L`、`[b` / `]b`、`[B` / `]B`（第一个 / 最后一个 buffer）和 `<C-^>`，以及
`-`（状态视图的文件面板除外，在那里它是暂存）都被禁用，并给出提示。`;` 的 picker
会把文件开在工作区那一侧的窗格里，视图就跟丢了它，把别的 buffer 换进窗格或面板也是
一样；大多数 `s` 键会关闭或改变一个窗格，而关掉一个窗格整个视图就散了。`<C-w>` 仍可在窗口之间移动，`gf` 在别处打开文件，`<Space>` 键照常
可用。`q` 只在文件面板或历史面板里关闭视图；在对比窗格里它照常录制宏。状态视图的
文件面板里，`-` 暂存或取消暂存一个文件，`S` / `U` 暂存 / 取消暂存全部，`X` 丢弃一个
文件的改动（会先确认）；其他视图都没有这四个键。

一个视图有哪些 `,` 审阅键，取决于它在对比什么：

| 视图 | `,S` | `,U` | `,X` |
|---|---|---|---|
| 状态视图，Changes 组（index → 工作区） | 暂存 | — | — |
| 状态视图，Staged 组（HEAD → index） | — | 取消暂存，整个 hunk | — |
| 基线 → 工作区（`<Space>av`，或在 `gk` / `gM` 里选的基线） | 暂存 | 取消暂存 | 把这个 hunk 丢弃回基线 |
| 同上，但文件是基线之后新增或删除的 | — | — | 告诉你怎么撤销 |
| 其他 revision → 工作区（`gm`、`gM`、`gk`） | 暂存 | 取消暂存 | — |
| revision → revision、→ index、历史、冲突 | — | — | — |

`,C`（反馈）在所有这些视图里都有，见[审阅一轮 agent 修改](#审阅一轮-agent-修改)。

`,S` 和 `,U` 通过 gitsigns 修改真正的 index，暂存的正好是屏幕上的那处改动。如果在
这几行附近，index（对 `,U` 来说是 HEAD）和视图左侧不一样——agent 的 hunk 旁边有一处
未暂存的修改、hunk 里有一行已经暂存过、`gm` 的 hunk 里夹着分支自己的 commit——
"只暂存这个 hunk"就会带上视图之外的内容，所以它们拒绝执行，并提示去 `<Space>gv`，
那里直接和 index 对比。Visual 模式下它们作用于右侧窗格里选中的行。

`,X` 把工作区文件里的一个 hunk 丢弃回基线，恢复成基线里的样子，并写入这个文件。它跳过格式化和
其他所有写入前的 hook，所以只有这个 hunk 会变；index 不受影响，`u` 再 `:w` 即可撤销。
Visual 模式下它作用于选区碰到的每个 hunk，其中有 hunk 只被选中一部分时拒绝执行。它
只处理 hunk：对基线之后被删除的文件，它打印一条可以粘贴执行的 `git restore` 命令；
新文件请自己删除。

三个键都宁可拒绝，也不去操作屏幕上看到的以外的东西：右侧窗格有未保存的修改（先 `:w`
或 `:e!`）、文件画出来之后又在磁盘上变了、hunk 重新计算后对不上了、符号链接、子模块、
有冲突的文件，或带 `filter` 属性的文件（如 Git LFS）。提示会说明原因，什么都不改。

对比 revision 的视图只列出真正不同的东西：revision 跟踪而你的 index 没有跟踪的文件
显示为修改，用普通 `mv` 移动的文件显示为重命名，非 ASCII 文件名也能正确显示。被忽略
的文件永远不会出现，仍在磁盘上的路径也不会被列为删除；这些路径，以及超过 10 MiB 的
未跟踪文件，每个视图会用一条 "Not compared" 提示列出一次。buffer 有未保存的修改、
而它的文件在磁盘上又被改了时，视图会提示一次——`:e!` 采用磁盘上的版本，`:w` 保留你的。

GitHub issue/PR buffer 是阅读视图，隐藏行号和折叠栏。视图没有待保存的改动时，
`;f` 会在同一窗口打开选中的文件；取消选择则保留原来的视图和布局。从
`<Space>Gi`/`<Space>Gp` 打开的 issue 或 PR 也同样落在编辑区，即使 picker 是从
chat 或 agent 面板里打开的，右侧面板保持原样。

`<Space>gD` 在当前窗口里直接显示这个文件的改动：相对 index 删掉的每一行都以只读
形式画回原来的位置，所以改过的行上方紧挨着它的旧内容。`]h` / `[h` 在改动之间跳；
再按一次 `<Space>gD` 回到普通视图。`<Space>gd` 则是在分屏里显示同样的对比，左边是 index
（有冲突的文件则是左边 ours、右边 theirs，`<Space>gD` 也会打开这个分屏）；再按一次同一个键，
或按 `<Space>gq`，关闭分屏。在别的窗口按 `<Space>gd` 会把分屏移到那里：Vim 会把一个
tabpage 里所有 diff 窗口两两对比，两个文件的分屏并排时，两个文件之间也会被对比；在 Git
不跟踪的 buffer 里按，只会提示一声，分屏留在原处。
index 那一侧有未保存的修改时不会关闭：在那里 `:w` 会暂存这些修改，`:e!` 会丢弃。状态栏
在分支名旁边显示当前 buffer 相对 index 的改动行数，例如 `+3 ~1 -2` 分别是新增、
修改、删除的行。

`<Space>yg` 复制当前行（Visual 模式下是选中的几行）在远端仓库（GitHub、GitLab
等）上的 permalink。链接指向最后一次修改这个文件的 commit，所以分支继续往前走之后
它仍然指向同一段代码；但行号也是那个 commit 里的：光标上方有未提交的改动时行号会
对不上，而且要等这个 commit 推送之后链接才能打开。

`<Space>bh` 删除所有 tabpage 里都没有窗口在显示的文件 buffer，不动任何窗口；终端等
特殊 buffer 会保留。`<Space>bo` 则只留下当前 buffer，其他分屏里显示的内容也会被换掉。

### 终端与 AI

`<C-/>` 打开普通编号终端，`<Space>an` 新建 AI chat。终端 Normal 模式下的
`,1`–`,9` 选择编号，再按不会关闭。`al` 切 chat，`ac` 隐藏/恢复上次 chat，
`af` 聚焦，`ai` 编辑 prompt。

本期原生后端是 Codex；CodeCompanion 提供 Codex ACP 和 OpenAI HTTP chat。
`an` 列出传输方式、计费和可用性；运行中的原生入口复用同一会话。显示一个目标只隐藏
本 tab 的其他 AI 窗口，保留 buffer 和进程。目标在其他 tab 可见时跳转并提示。
本 tab 显示的终端副本仍是此处的投递目标。唯一普通窗口不能隐藏，浮窗不算额外窗口。

`as` 在 picker 前捕获 Visual 内容，不自动按 Enter。已保存选区使用文件/行范围引用，
未保存文本精确粘贴并提示。`ab` 加入文件；native/ACP 从磁盘读取，未保存会提示。
HTTP chat 接收 buffer 文本。目录列表明确拒绝，本期没有 Claude 专属 Oil 操作。
从 CodeDiff 使用 chat 键时，作用于来源 tab。

`ai` 通过 Codex 的 `ctrl+g` 和 `$EDITOR` 把真实输入草稿交给本 Nvim。
`<C-d>` 返回，取消保留原输入。`<C-v>` 暂存图片，在 editor 关闭后交给 Codex 自身
的附件通道。其他程序的 editor 请求没有 agent owner，不接受 seed 或图片。
`ar` 恢复，`aR` 继续，`am` 选模型；会话运行时只聚焦，不向可能含草稿或审批的输入框
写入命令。`at`/`aT` 阅读 JSONL transcript，独立于终端滚动历史。

`config/ai.lua` 声明 provider、HTTP profile、面板、原生 argv、本地插件目录和 terminal。
`terminal.provider` 可为 `native`、`snacks` 或自定义内嵌 adapter。tmux 渲染独立选择，
`CODEX_WRAP_TMUX=0` 关闭。runner/watchdog/teardown 保留启动错误、CJK、滚动历史，
清理所属后代进程；不写 CLI 配置。

`ae` 消耗 HTTP API credits；`ax` / `:AI key` 只切当前进程的 HTTP profile，
不动终端和已有 chat。默认 OpenAI key 为 `NVIM_OPENAI_API_KEY`；CLI 自己的
`OPENAI_API_KEY` 可能改变计费并会提示。ACP 使用 `chat-gpt` 登录，不静默借用 CLI key。
详见 [AI 快捷键](../README_CN.md#ai-快捷键)。

### 原生终端的本地插件

`config/ai.lua` 的 `plugin_dirs` 声明目录，`NVIM_AI_PLUGIN_DIR` 覆盖。
入口可为插件目录或带 `codex/<plugin>` 的分发根目录。只在原生启动时解析，
不在 Nvim 启动或 CodeCompanion 启动时安装。Codex 使用临时 `CODEX_HOME` 运行
`plugin add` 刷新快照，仅共享真实 plugin cache；marketplace/enabled 覆盖只属于本次调用，
不改变用户配置和全局启用状态。

### 三种问 AI 的方式

| 工作流 | 传输 / 计费 | 用途 |
| --- | --- | --- |
| 原生 Codex | 原生 CLI / ChatGPT 登录 | 完整 TUI 和 prompt editor |
| Codex ACP chat | CodeCompanion + codex-acp / ChatGPT 登录 | 带 CLI 工具的 chat UI |
| OpenAI API chat / inline | HTTP / API credits | 对话或 `ae` 行内编辑 |

Picker 标明区别和可用性。HTTP key 读取 `NVIM_*`；chat 创建后 adapter 固定。
本地 transcript history 与 `/resume` 恢复 ACP agent 有状态会话是两回事。

幽灵文本是独立的第四条路径：本地 llama-server，只在附着 UI 且文件符合条件时启动。
`<C-l>` 接受，不理它就继续打字。`config/completion.lua` 管模型和服务偏好，
`config/keymaps.lua` 管接受键。Markdown/text/commit 默认排除；
`:Minuet virtualtext toggle` 切换当前 buffer。

## 审阅一轮 agent 修改

轮次是绑定到对话的不可变 worktree 基线。它只证明修改发生在基线之后，不判断修改者；
同仓库的用户操作或其他 agent 修改也会出现。审阅是修改后的 Git 比较，不是未来写入的审批。

### 轮次从哪里来

Codex `UserPromptSubmit` hook 在 prompt 执行前取快照；CodeCompanion 的
`on_before_submit` 为 ACP/HTTP chat 做同一件事。`aV` 手动开轮次；`gK` 保存另外的、
无对话 owner 的基线。Codex 相同 turn id 的 steer 不开新轮次；重复事件去重，树未变化
复用上一轮；带 `agent_id` 的子线程属于父轮次。有变化的新 turn 才新开一轮。

原生 root 固定为启动 cwd 的 Git 根目录，chat 在创建时固定。之后 agent 改目录仍记录
原 root，并提示一次。hook 最多等 `hook_wait_ms`（2500 ms）；迟到的基线标为 Late，
因为最早修改可能已进入快照。Nvim 来不及处理整个事件时，不在事后补拍基线。
集成错误不会阻止用户 prompt。

hook 通过本次进程的 `-c hooks=...` 和对应 trust record 注入，保留用户配置和其他 hook。
Codex 在提交 prompt 时才报告当前 session；resume/new/fork 后、下一次 prompt 前，
Nvim 无法证明输入框属于谁，投递可能询问确认。普通 shell 启动的 CLI 没有注入 hook。

### `<Space>av`：审阅视图

对话 buffer 优先其最新轮次；其他位置优先本 tab 右侧 chat（CodeDiff 使用来源 tab），
再选本进程在该 root 最新的轮次，最后是存储里的最新轮次。没有可见 chat 时不会拿第一个
provider 当 owner。每个 root 保留一个 review tab，不重排其他 root 的视图。

CodeDiff 使用不可变基线 SHA 比较工作区。标题说明来源、时间、对话、root 和 Late。
保留策略之后删除 ref 也不会改变已打开的比较。视图内保持布局敏感前缀的保护；逗号动作、
文件/LSP 键按 Git 工作流的原有作用域应用。

### `,C`：反馈

Git 视图内以 `,C` 为所选行/hunk 加评论。上下文和正文先进入持久草稿，不直接发 chat。
编辑草稿、删改条目后以 `<C-d>` 投递。草稿原子存储于
`state/ai-review/<root hash>/`，关视图和重启仍保留。并发非重叠修改合并；冲突另存
conflict 文件并提示，不覆盖另一份内容。

草稿头记录 root/owner；丢失头会拒绝投递。`<id>.last-sent.md` 留存最后一次已确认投递，
只有文字确实到达才清空待发送草稿。含非空反馈草稿的轮次不受 retention 删除。

### `<C-d>`：投递

原生反馈为确切 Codex prompt editor 暂存 seed，editor 消费才确认成功。
取消、超时、被替换或失败都保留草稿。TUI 自己的 editor handoff 处理真实输入内容。
ACP/HTTP 反馈加入确切的本进程 chat，成功才确认。Chat 忙碌时拒绝；工具循环中即使两次
请求之间没有 HTTP 请求，也算忙碌。

### 谁会收到

按顺序检查：

1. 视图 root、草稿 root、目标 root 的 realpath 必须一致，没有确认可以绕过 root 检查。
2. 原生 terminal 必须运行所属 session；chat 必须仍在本 Nvim 打开。未报告或报告后输入过
   的原生 session 先确认；`unknown_session = "refuse"` 则拒绝。
3. Chat 处于 turn/工具循环中时拒绝。
4. Owner 已消失时拒绝。除非 `redirect = false`，可以选择同 root 的当前 session/chat，
   再确认一次改投。取消保留草稿。

不按 provider 顺序或隐藏 chat 猜目标。原生 conversation id 包含 session id，
chat id 包含本进程 nonce，因此另一个 Nvim 同编号 chat 不是同 owner。
历史 Claude owner 可以读取；没有该后端时只能按同样的显式同 root 规则改投。

### 各 agent 的局限

| | 原生 Codex | ACP / HTTP chat |
| --- | --- | --- |
| 基线 | prompt 前、有上限等待 | submit callback 前、有上限等待 |
| 何时认识 session | UserPromptSubmit | 创建 chat |
| 确认 | 首次 prompt 前、输入之后，或 always_confirm | 不询问原生 session |
| 重启后 | resume 后确认，或先发 prompt | 原进程 chat owner 已消失 |
| 写前审批 | CLI 自己配置的策略 | Chat 工具审批 |

原生 argv 保留 `--no-alt-screen --yolo`。Git review 不等于 IDE 提案接受/拒绝。
Claude IDE protocol/openDiff 及对应键位留待后续扩展。

### 手动轮次、保存的基线与任选两端

`aV` 手动开轮次：对话 buffer 属于该 owner；文件属于右侧同 root 可见 chat，否则无 owner。
`gK` 保存命名、无 owner 的基线；`gk` 列出已保存基线；`gM` 比较任选两端。
标签可读取原生 session 的名称和时间，包括历史 Claude JSONL。重命名/隐藏会话不改变
已打开比较的不可变 SHA。

快照使用唯一临时 index，不改 HEAD、真实 index、分支、stash 或 reflog。
长期写入是 objects 和 `refs/nvim-review/<wtid>/...`。忽略规则每次重新读取；过大未跟踪
文件在哈希前排除。Retention 删除 refs，objects 交给 Git gc。如何从图和 mirror 排除
这些 refs，见 [诊断](DIAGNOSTICS.md#what-review-baselines-leave-in-a-repository)。

### 每个动作改变什么

| 动作 | 作用 |
| --- | --- |
| `aV` | 现在取快照，能确定时绑定轮次 owner |
| `av` | 工作区与轮次基线比较 |
| `gK` | 保存独立基线 |
| `,C` | 持久捕获反馈 |
| 草稿 `<C-d>` | 检查目标后投递，确认到达才清空 |
| 支持的基线文件 `,X` | 在视图保护下把 hunk 丢弃回基线 |

### 设置：`vim.g.ai_review`

可编辑默认值放 `config/review.lua`，共享 Git 值放 `config/git.lua`，setup 时复制。
运行中给 `vim.g.ai_review` 整表赋值才能覆盖，改嵌套副本无效。
未知/错误 leaf 警告一次，合法同级项继续生效。`:checkhealth config` 显示有效值。

| 键 | 默认值 | 含义 |
| --- | --- | --- |
| `retention.rounds` | 20 | 每 worktree 保留的轮次数；待发草稿豁免 |
| `sources.codex` | true | 注入/接收原生 submit hook |
| `sources.codecompanion_acp` / `codecompanion_http` | true | Chat 提交时开轮次 |
| `hook_wait_ms` | 2500 | 等基线上限；0 立即继续提交 |
| `unknown_session` | `"confirm"` | `"refuse"` 拒绝无法证明的原生 owner |
| `always_confirm` | `{}` | `{ "codex" }` 每次原生投递均确认 |
| `redirect` | true | Owner 消失时提供显式同 root 改投 |
| `seed_ttl_ms` | 10000 | Prompt editor 消费时限 |

Git 默认值为 `max_file_size = 10485760`、`retention.saved = 10`、
`history_limit = 100`（或 false）。这些字段在 `vim.g.ai_review` 的旧运行时覆盖继续保留。
`sources.claude`、`claude_cwd` 已移除。原生命令/hook 修改下次启动生效，关闭来源立即
丢弃事件。来源关闭时创建的 chat 不会事后自动补装 hook。setup 声明修改需重启；HTTP
key 切换仅属于当前进程。

## 忘了键位怎么办

1. **按下前缀然后等。** `;`、`,`、`s`、`<Space>` 停顿一下都会弹菜单。最快。
2. **`<Space>?`** —— 一页列出所有前缀和常用键。
3. **`<Space>mk`** —— 按描述搜索所有键位。
4. **`;;`** —— 搜索结果列表丢了，用它原样找回来。

那些菜单是**从配置本身生成的**，不会像文档一样过期。

## 调试

打开源码，用 `<Space>db` 设置断点，再按 `<Space>dc` 选择启动或附加配置。
会话开始时自动打开面板。`<Space>di` 进入函数、`dO` 单步跳过、`do` 跳出函数。

调试视图开在自己的 tabpage 里，和 diff 一样——会话不会打乱你正在编辑的窗口，
结束时原样奉还。视图内部：Scopes、Breakpoints、Stacks、Watches 停靠在左侧，
REPL 和程序控制台与终端、quickfix 一起排在底部。位置由 edgy 决定，和这里其他
面板一视同仁，所以 `so` 和窗口键对待它们的方式与 AI 面板相同，而不是另起一套
布局。一个适配器驱动多个目标时，视图只打开一次，不会每个目标打开一次。

步进停留在你所在的 tabpage。会话进行中切回编辑 tab，调试键照常可用，在那个
tab 内跳转，面板在看不见的地方继续更新；`<Space>du` 把视图叫回来。调试视图
永远不会主动把你在 tab 之间搬来搬去。

| 键 | 作用 |
|---|---|
| `<Space>dB` | 设置条件断点（会询问条件） |
| `<Space>dA` / `:DapAttach` | 选择 attach 配置，附加已有进程 |
| `<Space>dL` | 日志断点，例如 `value={value}`，输出日志但不停下 |
| `<Space>de` | 从当前适配器提供的选项中选择异常断点 |
| `<Space>dR` | 从会话树的根重启会话 |
| `<Space>dD` | 断开会话及其子会话，并请求保留目标进程运行 |
| `<Space>dt` | 终止目标，连同它所属的整棵会话树 |
| `<Space>du` | 关闭或重新打开调试视图 |
| `<Space>dw` | 对光标处表达式或当前 Visual 选区求值 |
| `<Space>dW` | 输入或编辑表达式后添加到 Watches |
| `<Space>ds` | 列出会话，选择主进程、渲染进程或子会话 |
| `<Space>dq` / `<Space>dx` | 列出 / 清除所有断点 |

gutter 和面板控制条都支持鼠标。点击行号切换断点，`Ctrl` 加点击则先询问条件；
控制台上方那排图标是八个按钮，依次为继续/暂停、三种单步、step back、重跑上次、
终止、断开。`mouse` 设为 `nv`，所以要先离开 Insert 或终端模式。

gutter 的形状不依赖颜色也能分辨：`●` 断点、`◉` 条件断点、`◆` 日志断点、
`○` 适配器尚未确认绑定、`󰁕` 当前停驻行（该行同时会高亮）。

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
| `<Space>tM` | 调试光标所在用例（Go/Python/Java 也会寻找前面的最近用例） |
| `<Space>tF` | 调试当前文件里的测试 |
| `<Space>tm` / `<Space>tf` | 普通运行最近用例 / 测试文件（neotest：Go/Python） |

大写是同一次运行放进调试器：`tm` / `tM` 是最近的用例，`tf` / `tF` 是整个文件。
`<Space>ts` 开关 neotest 的汇总面板（在那里 `g?`，或 `?`，列出它的键），`<Space>to`
显示测试输出，`<Space>tx` 开关 neotest 以诊断形式显示的失败信息。

先用 `<Space>db` 打断点，把光标放进测试用例，再按 `<Space>tM`。
这些直接入口会先保存当前文件；未命名 buffer 或保存失败时中止。
各语言使用同一套键位，目标选择逻辑分别放在 `lua/plugin/lang/*.lua`。

| 语言 | `df` | `tM` / `tF` |
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
在 `dc` 中选择 **Debug Package**。`tM`/`tF` 通过 neotest-golang 和 Delve
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

安装 Python 和 Mason 的 `debugpy`，按需用 `,v` 选择项目环境。
`df` 调试脚本，`tM`/`tF` 使用 neotest-python。pytest 测试需要在选中的环境安装
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

安装 JDK 25+（jdtls 运行在它上面；项目本身仍可以面向更早的版本），并在 Mason 中安装
`jdtls`、`java-debug-adapter`、`java-test`。
打开项目，等待 jdtls 导入完成。`dc` 动态发现主类，`df` 选择当前文件对应的
主类；发现前没有静态主类列表是正常的。每个项目使用独立的 jdtls workspace。
`tM`/`tF` 调试最近的方法或第一个发现的测试类。

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
`tM`/`tF` 按前述规则筛选标准 libtest 测试。

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
C/C++ 尚未注册 `df`/`tM`/`tF`，因为本配置不替项目选择构建系统和测试框架。

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
loader 需要项目 launch 配置。`tM`/`tF` 使用最近安装的 Vitest，最近测试需 v3+。

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
安装和排错见 [DIAGNOSTICS.md](DIAGNOSTICS.md)。

### Dart CLI

安装 Dart SDK，或使用 Flutter 自带的 Dart。适配器优先使用最近的
`.fvm/flutter_sdk/bin`，其次查找 PATH。先运行 `dart pub get`；直接调用
SDK 的 `dart debug_adapter`，不需 Mason 适配器。`df` 启动当前入口，
`tM`/`tF` 通过 SDK 测试适配器调试用例。

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
`,dr` 请求支持的热重载，`<Space>dR` 重启通过 launch 启动的 CLI 会话。
VM 服务启动方式见 [Dart 调试工具文档](https://dart.dev/tools/dart-devtools)。

### Flutter

安装 Flutter 或使用 FVM，执行 `flutter pub get`，启动模拟器或连接设备，
用 `flutter devices` 查看。`dc` 提供 **flutter: launch app**（默认
`lib/main.dart`）、**flutter: attach to running app** 和当前测试文件。
`df` 使用当前文件作为入口；pubspec 声明 `sdk: flutter` 时，`tM`/`tF`
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
保存后 `,dr` 热重载，`,dR` 执行 Flutter 热重启。
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

本配置尚未支持 React Native/Hermes DAP 工作流，请使用 React Native DevTools。
连接失败、断点未绑定、SDK 路径和系统权限
问题见 [DIAGNOSTICS.md](DIAGNOSTICS.md)。
