# #43 / #44 验收说明

本次交付 Codex-first 自定义插件，以及 config / plugin / local-plugin / util
四类目录。Claude 原生接入、IDE 协议和 openDiff 后续由 [#45](https://github.com/huiyu/nvim/issues/45)
推进。claudecode.nvim 不再声明，旧 Claude transcript / baseline 标签继续可读。

## 改动入口

| 关注点 | 入口 |
| --- | --- |
| 用户配置 | `lua/config/options.lua`、`behaviors.lua`、`theme.lua`、`keymaps.lua` |
| AI / terminal / 原生 argv | `lua/config/ai.lua` |
| Review 与 Git 策略 | `lua/config/review.lua`、`git.lua` |
| 本地补全 / dashboard | `lua/config/completion.lua`、`dashboard.lua` |
| lazy 引用与适配 | `lua/plugin/`，保持 editor/coding/ai/ui/git/lang 合并顺序 |
| 自定义实现 | `local-plugin/{editor-core,agent-workbench,git-review,llama-service}.nvim` |
| 独立插件 API | [agent-workbench README](../local-plugin/agent-workbench.nvim/README.md) |

配置声明无启动副作用；运行时负责复制、校验、状态和应用。
基础 editor setup 与便宜的 AI facade 由高优先级 local spec 初始化。
真实 CLI、模型、terminal provider、review、CodeDiff 和 CodeCompanion 按实际使用加载。
共享打开键在 config/keymaps 声明，由 Oil / Snacks / Aerial 显式适配；which-key 仅展示。

## 自动化证据

- `make verify`：70 个 spec、超过 5600 项顶层断言全部通过，另含独立 host 的内部契约断言；
  同时覆盖工作区/暂存区空白检查和 headless startup。
- `package_layout_spec`：四个 package 在无 host config/util、无插件管理器、禁止进程启动的
  独立 Nvim 中完成 require/setup；检查声明隔离、false、空 argv 替换和不开会话。
- `plugin_contract_spec`：native / Snacks / custom 三种 provider 在独立 host 运行离线 PTY，
  覆盖 argv/CJK/cwd/env、会话复用、无隐式 Enter、hide/show/stop、跨 tab 副本、唯一普通窗口、
  浮窗与旧 generation 回调。
- `shared_keys_spec`：禁用 which-key 后，单个 `<C-y>` 覆盖作用于真实 Oil、Snacks picker、
  Aerial 及帮助；替换/禁用旧键，保留 Oil Visual 模式。子进程必须到达最终完成标记。
- 原有基线、CodeDiff、draft/feedback、round/delivery、CodeCompanion billing、prompt editor、
  transcript、tmux 清理、语言/LSP/DAP 等回归测试保持有效。删除的测试对应未交付的原生 Claude
  控制/IDE 路径；通用窗口路由和反馈闭环迁移为 Codex fixture。
- Hook 测试使用固定 trust hash 向量，并向本机已安装 Codex app-server 查询 hooks/list 验证
  信任状态；不创建 thread、不提交 prompt。

## 真实 UI smoke

Neovim 0.12.6、一个真实 TUI 附着：分别检查 Snacks direct provider 与 native provider +
tmux。两次均在 startup 无会话/模型进程、noice 和 notifier 正常启用的条件下开始。

检查了 CJK/重音/emoji 文本、statusline agent 身份、上下文不自动提交、hide/show 保持 PTY、
帮助浮窗、通知/消息路由、显式 stop。native + tmux 从 160×45 缩放到 120×35，无 v:errmsg；
stop/退出后，所属 tmux server 与离线 pane 进程均消失。原配置中的用户会话未被操作。

PTY 使用离线 Python 替身，没有启动真实 AI 对话、提交 CodeCompanion 消息或加载模型权重。
这证明编辑器/终端/进程集成，实际 CLI 的模型响应、登录和图片识别仍由用户验收。
既有 Codex cold prompt 时序问题 [#16](https://github.com/huiyu/nvim/issues/16) 仍单独跟踪；
本次不把离线 fixture 视为它的真实 CLI 解决证据。

## 手动验收

在此 PR 的独立 checkout 中执行 `nvim -u ./init.lua`；保留原来的配置工作区。

1. 查看 config 文件、`:Lazy`、`:checkhealth config`、`:AI info`。确认 provider 只有当前
   配置的 Codex 入口，存在四个本地 package，未出现 Claude 原生入口/命令/按键。
2. 用 `an` 打开 Codex，验证 `ac` 隐藏/恢复、`af` 聚焦；再选择运行中 Codex 应复用。
   在另一 tab 切换与显示 terminal copy，确认不无声投递、不移动别的 tab 的窗口。
3. 用 `ab` 和 Visual `as` 加入上下文，确认没有自动 Enter；未保存选区应发送精确文本。
   `ai` / TUI ctrl+g 编辑真实草稿，取消与 `<C-d>` 返回行为一致。需要时单独检查剪贴板图片。
4. 在临时 Git 仓库以 `aV` 建立基线，修改文件后 `av`、`,C` 编辑反馈；取消投递应保留草稿。
   真正提交 prompt 后再检查 hook round 与确认投递。Git 的真实 index/HEAD 不应被快照改动。
5. 将 config.ai 的 terminal.provider 改为 native，重启并重复终端操作；或使用已验证的
   独立 provider 契约测试。最后退出，检查没有所属 tmux/agent 后代进程遗留。

`<Space>` 是默认 leader。正式全量 gate 的命令与结果记录在 PR 描述。
原先未提交的责任归属改动作为独立前置 commit 保留；无关 spikes 删除和本地 research
文件没有纳入 PR。未合并、未替换原工作区，也未清理共享 lazy 安装目录。
