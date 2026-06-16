# 功能简报 ·「有新发现」完成提醒（Completion Alert）

> **用途**：给**落地页（`site/index.html`）+ GitHub README 讲述**用的功能简报。功能代码已完成并实测；落地页是反复雕琢的精工件，建议在干净 session 里专注撰写——本文做到零上下文也能动手。
> **写于** 2026-06-14。

---

## 0. 一句话

> 你把任务丢给 Claude Code 后去忙别的，当某个会话**完成**、或停下来**等你授权**时，菜单栏的表盘亮起**彩虹**叫你回来；**点一下**就把 Claude 桌面 App 拉回前台、彩虹随即熄灭。

解决的痛点：长任务跑着你走开了，回来才发现 Claude 早就完成了 / 卡在等授权干等半天。原本菜单栏只告诉你"额度"，现在还告诉你"该回去看看了"。

---

## 1. 锁定的产品决策（用户已拍板，文案据此）

- **目标 = Claude 桌面 App**（`com.anthropic.claudefordesktop`）；点击拉起 `open -b com.anthropic.claudefordesktop`。
- **彩虹只染图标**（gauge 表盘），**百分比数字仍保留额度三色**（黑/橙/红）——两个信号共存，不遮蔽额度告急。
- **触发源**：Claude Code 的 `Stop`（一个回合完成）+ `Notification`/`permission_prompt`（卡住等你授权）。**不含 idle**（与"完成"重复）。
- **只关注「有/无」未读**，不关注是哪个会话、几个会话。
- **交互**：有新发现时**左键点图标 = 拉起 Claude + 熄灭彩虹**（恢复常态）；**右键 = 照常打开下拉**（额度详情/刷新/退出）。没有新发现时左键 = 照常开下拉。
- **形态**：第 4 层，**默认开**（随 `install.sh` 自动启用）；**无 `attention.json` 时（旧装/异常/已关），菜单栏与现在逐字节一致**。（2026-06-16 更新：产品方改为默认开——这是核心价值，没有理由让用户多跑一条命令；落地实现见 `install.sh` 第 6 步 + `uninstall.sh` 对称移除。`alert/install-alerts.sh` 仍是可复用机制 + 独立开关。）

---

## 2. 菜单栏视觉（落地页样张照此画）

| 态 | 图标 | 数字 |
|---|---|---|
| 够用 / 需关注 / 紧急 / 陈旧 | 原版 gauge（sfimage，自适应/三色），落地页已有 warn/crit 两幕 | 黑(自适应)/橙/红/灰 |
| **有新发现** | gauge **变彩虹**（红→橙→黄→绿→蓝→紫） | 保持其额度色 |

**落地页画法（全是现成积木）**：复用 `.scene` / `.mini-bar` / `.mbg` / `#dial`，把仪表字形的描边设成 `stroke="url(#eoSpectrum)"` 就是彩虹表盘——`#eoSpectrum` 彩虹渐变已在 `site/index.html` 约 `:280` 定义（EarthOnline 光谱：purple→blue→green→orange→red）。

> ⚠️ 注意：真机里彩虹图标受 SwiftBar/macOS 限制（彩色位图带淡框、尺寸需手调，最终取"彩虹+同尺寸+留淡框"）。**这些是实现细节，与落地页无关**——落地页是 SVG/CSS，可做到完美彩虹无框。**别把"边框/尺寸取舍"写进对外文案。**

---

## 3. 红线（文案必须守 —— 宁可不说，不可夸大）

- **绝不读对话 / 代码**：它只对 **Claude Code 自己推送的「完成 / 需授权」事件**（CC hooks）作反应，**从不读你的对话、代码、会话内容**。这是与竞品的核心差异、也是本功能的隐私基石——**务必讲清是"对事件作反应"而非"读取内容"**。
- **不是系统弹窗**：靠菜单栏**变彩虹**传达，**不弹 macOS 通知**（与产品一贯"靠变色不弹窗"的立场一致）。
- **零遥测、零第三方、零自有服务器**。
- **默认开**：随 `install.sh` 自动启用（第 6 步调 `alert/install-alerts.sh`，非致命：settings.json 异常时安全跳过、不拖垮菜单栏主功能）。它会把 Stop/Notification/PermissionRequest 三条 hook 合并进你的 `~/.claude/settings.json`，**已做：先备份 → 幂等 → 校验 → 外科式移除（`uninstall.sh` 对称卸载），绝不动你已有的 hooks**。（2026-06-16 更新：从 opt-in 改为默认开。）
- **别说"纯本地 / 完全离线"**：这层需要 Claude Code 触发 hooks（本机进程间），但**仍不联网、不读内容**。措辞要准。

---

## 4. 草拟文案（EN / 中 —— 起稿，可改）

**小节（建议放在「一个数·三种色」场景区之后）**
- eyebrow：`When you step away` / `当你离开时`
- h2：`It waves you back when there's something new` / `有新发现，它把你叫回来`
- 正文：`Kick off a task and go do something else. When a Claude Code session finishes — or pauses to ask your permission — the menu-bar gauge lights up in rainbow. One click brings Claude to the front, and the rainbow clears.` / `把任务丢给它，自己去忙别的。当某个 Claude Code 会话完成、或停下来等你授权时，菜单栏的表盘亮起彩虹。点一下就把 Claude 拉回前台，彩虹随即熄灭。`
- 诚实小字：`On by default. It reacts only to Claude Code's own "finished / needs-permission" signals — never your conversations or code. No pop-ups, no telemetry.` / `默认开启。只对 Claude Code 自己的「完成 / 等授权」信号作反应——绝不读你的对话或代码。无弹窗、无遥测。`
- 样张 caption：`<b>Something's waiting</b> — a session wrapped up (or needs you) while you were away. Click to jump back in.` / `<b>有新发现</b>——你离开时有会话完成了（或在等你）。点一下跳回去。`

**FEATURES 区功能卡（可选附加；该区主题是"只在要紧时出声"，与本功能天然契合）**
- h3：`Come back at the right moment` / `恰好在该回来时叫你`
- p：`Walk away during a long run. When it's done — or stuck waiting for your OK — the gauge goes rainbow so you don't sit there wondering. One click and you're back.` / `长任务跑着你尽管走开。完成了、或卡在等你点头时，表盘变彩虹，省得你干等或反复去瞄。点一下就回到现场。`

**HOW IT WORKS 区第 4 层（可选附加，与三层架构对齐）**
- 标号 `04 · ALERT / 提醒`，`on by default/默认开` 徽章
- h3：`The nudge` / `提醒`，tag：`alert/claude-gauge-alert.py`
- p：`A built-in layer that hooks Claude Code's own "finished" and "needs-permission" events, records just a timestamp (never the transcript), and flips the gauge to rainbow when you're away. Click to raise Claude and clear it.` / `一个内置层，挂上 Claude Code 自己的「完成」「等授权」事件，只记一个时间戳（绝不读 transcript），在你离开时把表盘翻成彩虹。点一下拉起 Claude 并熄灭。`

---

## 5. 落地页放置建议

- **主体**：`site/index.html` 的 states 场景区（约 `:368-439`，warn/crit 两幕）**之后**，加一幕彩虹样张 + 上面那段说明（或单独一个小节，带 eyebrow+h2）。
- **可选**：FEATURES 区（约 `:525`）加一张 `.feat` 卡；HOW IT WORKS 区（约 `:557`）加「第 4 层」`.layer` 卡。
- **页面套路**：每 section = `.sec-head`(eyebrow + h2 + p)；scene = `.mini-bar`(`.mbg` 含 `#dial`+百分比 + `.popover .dropdown`) + `.scene-cap`；i18n 一律 `<span class="en">…</span><span class="zh">…</span>`，靠 `html[data-lang]` 切换。
- 改完用本地预览/截图核对深浅、EN/中、移动端，再上线（部署步骤见 `docs/HANDOVER.md` §9，记得带 `site/fonts/`）。

---

## 6. GitHub README 讲述（README.md + README.zh-CN.md 双语都要）

加一节「Completion alert ·『有新发现』」：
- 价值一句话（见 §0）。
- **默认随 `install.sh` 启用**；如需单独开关：`bash alert/install-alerts.sh`（关闭 `bash alert/install-alerts.sh --uninstall`），主 `uninstall.sh` 也会对称移除。
- 隐私一句话（react to Claude Code's own events, never reads your chats/code; no pop-ups; no telemetry）。
- 可放一张彩虹菜单栏样图（README 用静态图即可）。

---

## 7. 安装 / 技术事实（供 README & docs）

- **安装**：默认随主 `install.sh` 第 6 步自动执行 `alert/install-alerts.sh`（`|| warn` 非致命：settings.json 异常时安全跳过、不拖垮菜单栏主功能）。机制本体 `alert/install-alerts.sh` 装 `claude-gauge-alert.py` 到 `~/.claude/`，并把三条 hook 幂等合并进 `~/.claude/settings.json`：`Stop`（→ event stop）、`Notification` matcher `permission_prompt`（→ event permission）、`PermissionRequest`（→ event permission，桌面端授权弹窗真实触发点）。改前备份、回解析校验、原子写、**不碰用户已有 hooks**。也可独立运行 `alert/install-alerts.sh` 单独开启。
- **卸载**：主 `uninstall.sh` 对称移除——内联自包含 python 块（不依赖 repo 仍在）只删 command 含 `claude-gauge-alert.py` 的条目（从 Stop/Notification/PermissionRequest），先备份、回解析校验、原子写，其余 hook 原封不动；再 `rm -f ~/.claude/claude-gauge-alert.py`。也可独立运行 `alert/install-alerts.sh --uninstall`。
- **依赖**：Claude Code 的 hooks 机制；**已实测桌面 App 内嵌的 CC 会执行 settings.json 的 Stop hook 且会话中途热加载生效**。
- **待同步的内部文档**（不属于落地页，但别忘）：`docs/ARCHITECTURE.md`（加第 4 层 + §7 路径表 + 新 §8.5）、`docs/HANDOVER.md`（组件表 + §7.3 验收 + 行号同步——本项目反复踩行号漂移的坑，见 `tasks/lessons.md` L2）。

---

## 8. 已落地的组件（代码完成、已装、实测过）

| 文件 | 作用 |
|---|---|
| `alert/claude-gauge-alert.py` | 事件入口：被 hook 调用写 `attention.json`（只记 ts/event/前台App，**不读 stdin/transcript**）；被点击调用拉起 Claude + 写 `ack.json` |
| `alert/install-alerts.sh` | 装/卸机制 + settings.json 幂等安全合并（默认由主 `install.sh` 调，也可独立开关；卸载由主 `uninstall.sh` 对称完成） |
| `alert/build-menubar-icons.sh` | 构建期管线：用 `rsvg-convert`（`brew install librsvg`）从品牌 logo `docs/logo.svg` 渲 5 张菜单栏图标（OK 单色模板 / WARN 橙 / CRIT 红 / STALE 灰 / RAINBOW 彩虹），描边比品牌 logo 减细（弧 1.8/针 1.44）以和 SF 符号同栏和谐，输出 base64 粘回插件 `ICON_*` 常量（重生成图标用；运行期零依赖） |
| `plugin/claude-gauge.15s.sh` | armed 渲染：有新发现=`image=<ICON_RAINBOW> {ICON_SZ}` + 左键动作；普通=原版图标常量（OK 用 `templateImage`，其余 `image=`）；无 `attention.json` 时（旧装/异常/已关）行为不变 |
| 缓存契约 | `~/.cache/claude-gauge/attention.json`(hook 写) / `ack.json`(点击或回到 Claude 写)，原子写 |

> 关于真机图标渲染踩过的坑（SwiftBar 彩色位图必带淡框、image vs sfimage 尺寸/自适应差异、sfconfig 做不出渐变等），见 `tasks/lessons.md` L7/L8——**这些只影响菜单栏实现，与落地页/README 文案无关**。
</content>
