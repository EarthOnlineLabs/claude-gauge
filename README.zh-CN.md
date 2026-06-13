<div align="right">

[English](README.md) · **简体中文**

</div>

# ClaudeGauge

**一个 macOS 菜单栏小工具，实时、状态感知地显示你的 Claude Code（Pro / Max 订阅）额度用量。token 过期能自愈，绝不拿旧数据糊弄你。**

<p align="center">
  <img src="docs/screenshots/showcase.png" alt="ClaudeGauge：菜单栏药丸与展开的下拉，显示 5 小时和一周用量" width="760">
</p>

跑 Claude Code 的时候，你大概率会问自己一句：*这个 5 小时窗口还剩多少？这周会不会撞墙？* ClaudeGauge 把答案常驻在菜单栏右上角——和 Claude Code `/usage` 完全同一个数据源、同一个口径，但你不用打断手头的事去查。

够用的时候它安安静静；快不够了它才出来提醒你——而且只提醒那个真正在告急的窗口。

---

## 它解决什么

**随时随地看额度，不用再频繁打开 usage 页。** Claude Code 的限额是实打实的，但想知道还剩多少，每次都得停下手头的事去跑 `/usage`、或反复打开 [claude.ai 用量设置页](https://claude.ai/settings/usage)。ClaudeGauge 把这个数字**常驻**在菜单栏，一瞥就知道离撞墙还有多远，不打断心流。

**安全、隐私——靠设计保证，不靠嘴上承诺。** 一个用量工具必须读你的账号，所以"可信"比"功能多"更重要。ClaudeGauge 就是为了让你**放心使用**而生：

- **只读**你的用量数字，**绝不读**你的对话、提示词、文件或代码。
- 你的 token 只发给 **Anthropic 官方接口，别无他处**——没有第三方服务器、没有我们自己的服务器、零遥测。
- **完全开源、无混淆**——每一行都是你能读懂的 bash / python，装之前可以自己审一遍；`uninstall.sh` 卸得干干净净，绝不碰你的凭证。

**该聪明的地方也聪明**——几个让它好用的细节：

- 🩹 **自愈 token** —— 闲置几小时后也照常工作：它会悄悄帮你过期的 token 续命，你永远看不到一个"死掉"的表盘。
- 🚦 **防限流** —— 自适应轮询：宽裕时几乎不打扰接口，临近限额时才加快。
- 🤥 **绝不骗你** —— 数据一陈旧就变灰、明说"别信"，而不是拿一个让你安心的错数字糊弄。
- 🔔 **主动预警** —— 跨过 75% / 90% 时弹一条 macOS 通知，撞墙不会突然袭击你。
- 📐 **刘海无惧** —— 标题始终够窄，刘海吞不掉。

---

## 特性

- **状态感知的单一信号灯。** 一眼看懂，不用解读。
  - 显示**已用百分比**（和 Claude Code `/usage` 口径一致，数字越大越满，带 `%`）。当前 5 小时窗口无前缀，一周窗口用 `W` 前缀。
  - **够用就闭嘴**：只显示当前 5 小时窗口，黑/白字随系统深浅色自适应，一周窗口直接藏起来。
  - **不够才报警**：只显示正在"咬人"的那个窗口，配橙色或红色，外加重置倒计时。两个窗口同时告急时显示更严重的一个；一周窗口一旦进入紧急（7 天硬墙），优先显示它。
- **去绿配色，符合直觉。**
  - 已用 `< 75%` —— 够用，近黑色（随系统深浅色自适应）
  - 已用 `75% – 89%` —— 需关注，橙色 `#e08a2b`
  - 已用 `≥ 90%` —— 紧急，红色 `#e0483d`
- **诚实陈旧。** 数据超过 15 分钟没更新，菜单栏标题变灰、加上 `~`，下拉菜单弹出明确警告。绝不让旧数字假装是新的。
- **刘海友好。** 带刘海的 Mac 上，菜单栏标题恒定保持在 ~90px 以内（约 11 个字符以内），不会因为太长被刘海吞掉、整个消失。
- **自愈 token。** Claude Code 闲置时不会刷新钥匙串里的 token，过期后 API 返回 401。ClaudeGauge 会在 token 快过期时自动帮它续命（见下文），全程无感。
- **桌面通知。** 用量跨过 75% / 90% 阈值时，主动弹一条 macOS 通知——每个窗口每轮只通知一次，不打扰。
- **可读、可审计。** 全部是 bash 和 python，没有任何混淆，你可以自己读一遍再装。

---

## 工作原理

ClaudeGauge 是**三层架构**，各管一段，互不阻塞：

### 1. 渲染层 —— SwiftBar 插件

`plugin/claude-gauge.15s.sh`

SwiftBar 每 15 秒跑一次这个脚本。它**只负责渲染**：读取 `~/.cache/claude-gauge/` 下 `live.json` 与 `cache.json` 中更新的那一份，按上面说的"状态感知信号灯"逻辑画出菜单栏标题和下拉菜单。

下拉菜单里，**进度条是主信息**（放大显示），**重置倒计时是辅助信息**（小号灰字）；每一行都显式上色——因为 SwiftBar 会把"无动作且无颜色"的行渲染成禁用态的灰色，所以必须主动给每行设色才好看。

> 兜底：万一后台刷新器失效、缓存超过 150 秒没更新，这个插件会自己直接拉一次 API，保证菜单栏不至于一直停在旧数据上。

### 2. 数据层 —— 后台刷新器

`refresher/claude-gauge-refresh.sh`

一个 LaunchAgent（标识 `dev.earthonline.claude-gauge`）每 30 秒触发它，但它**自适应节流**，并不是每次都真去请求：

| 当前状态 | 实际请求间隔 |
|---|---|
| 紧急（已用 ≥ 90%） | 45 秒 |
| 需关注 / 活跃（已用 ≥ 75% 或数字在变） | 60 秒 |
| 够用且静止 | 240 秒（防 429 限流） |

它调用 `https://api.anthropic.com/api/oauth/usage`（和 Claude Code `/usage` 同源），用从 macOS 钥匙串 `Claude Code-credentials` 读到的 OAuth token 鉴权，然后**原子写入** `cache.json`（先写临时文件再替换，杜绝插件读到半截数据）。用量跨过 75% / 90% 阈值时发 macOS 通知。

**关键创新 —— 自愈 token：** Claude Code 闲置时不会主动刷新钥匙串里的 token，过期后 API 就会返回 401。刷新器检测到 token 在 20 分钟内即将过期时，会从 `/tmp` 跑一次 headless 的 `claude -p ok`——让 Claude Code 用它的 refresh token 续命、并把新 token 写回钥匙串。这次调用成本极低，之后 ClaudeGauge 就能正常拿 token 调 API 了。

### 3. 桥接层（可选）—— Claude Code statusLine

`bridge/claude-gauge-statusline.py`

把它配成 Claude Code 的 `statusLine` 命令后，每当 Claude Code 刷新状态栏，它就从状态栏 JSON 里读 `rate_limits`（`five_hour` / `seven_day` 的 `used_percentage` 和 `resets_at`），写进 `~/.cache/claude-gauge/live.json`。

这样你**正在用 Claude Code 时菜单栏会即时刷新**——纯本地读写，不调 API、不碰 token，零成本。

> 注意：statusLine 只对你**配置之后新开**的会话生效；如果你已经有 statusLine 命令，需要自己手动合并。

---

## 安装

**前置条件**

- macOS
- [SwiftBar](https://github.com/swiftbar/SwiftBar)（安装脚本会在缺失时用 Homebrew 帮你装）
- 已登录的 Claude Code（提供 OAuth token，以及用于续命的 `claude` CLI）
- Claude Pro 或 Max 订阅
- 系统自带 `python3`

**安装**

```bash
git clone https://github.com/EarthOnlineDev/claude-gauge.git
cd claude-gauge
./install.sh
```

安装脚本会：装好 SwiftBar、把三个组件分别放到 SwiftBar 插件目录和 `~/.claude/`、注册每 30 秒触发的 LaunchAgent、立即拉一次数据并刷新菜单栏。装完，菜单栏右上角就会出现用量百分比。

**可选：打开实时增强**

安装结束时脚本会提示你这一步。在 `~/.claude/settings.json` 里加上（若已有 `statusLine` 请自行合并）：

```json
"statusLine": { "type": "command", "command": "~/.claude/claude-gauge-statusline.py" }
```

加上之后，用 Claude Code 时菜单栏即时刷新；不加也能靠后台刷新器每分钟自动更新。

**卸载**

```bash
./uninstall.sh
```

干净移除插件、刷新器、桥接脚本、LaunchAgent 和缓存目录。**不会触碰** Claude Code 的凭证或任何数据。（如果你加过 statusLine，请自行从 `~/.claude/settings.json` 移除那一行。）

---

## 隐私与安全

ClaudeGauge 在权限上极其克制：

- ✅ **只读取**钥匙串里的 OAuth token，**只调用** Anthropic 的用量端点（`/api/oauth/usage`）。
- ✅ token **只发往 Anthropic**，不发给任何第三方。
- ✅ 缓存写在本地 `~/.cache/claude-gauge/`。
- ❌ **从不读取** `~/.claude/projects` 下的对话、代码或任何项目文件。
- ❌ **没有任何遥测**、不上报、不收集。
- ❌ 没有任何混淆——全部是可读的 bash / python，欢迎逐行审计。

---

## 许可证

[MIT](LICENSE) © [EarthOnline](https://github.com/earthonline)
