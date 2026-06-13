# ClaudeGauge 交接文档

> 给接手开发者：本文档让你不读完全部代码也能快速建立心智模型、跑起来、改下去。
> 所有行为描述均与当前脚本实现一致（已逐行核对），改动代码后请同步更新本文件。

---

## 1. 这是什么

ClaudeGauge 是一个 **macOS 菜单栏小工具**，实时、状态感知地显示 Claude Code（Pro/Max 订阅）的额度用量。

核心设计承诺：

- **口径与 Claude Code `/usage` 一致**：显示「已用 %」，越大越满（同源端点 `api.anthropic.com/api/oauth/usage`）。
- **够用就静默，不够才报警**：默认近黑、只显当前 5 小时窗口；只有窗口紧张时才上色、显倒计时、显周窗口。
- **绝不显示骗人的旧数据**：数据超过 15 分钟没更新就变灰加 `~` 并在下拉里警告。
- **自愈 token**：Claude Code 闲置导致钥匙串 token 过期时，刷新器会自动让 CC 续命，无需人工干预。

协议 MIT。组织 EarthOnline（GitHub org `earthonline` / `EarthOnlineDev`）。

菜单栏效果见 `docs/screenshots/menubar.png`（显示形如 "49%"）。

---

## 2. 三层架构（务必先建立这张图）

```
                    ┌─────────────────────────────────────────────┐
                    │   ~/.cache/claude-gauge/                     │
   写 ──────────────►   cache.json   (后台 API 拉取，权威数据)      │
   写 ──────────────►   live.json    (CC statusLine 桥接，即时)     │◄──── 读
                    │   refresh-state.json (刷新器节流状态)         │
                    └─────────────────────────────────────────────┘
        ▲                          ▲                              │
        │                          │                              ▼
  ┌───────────┐            ┌──────────────┐              ┌─────────────────┐
  │ 桥接层(可选)│            │   数据层      │              │   渲染层         │
  │ statusline │            │  refresher    │              │  SwiftBar plugin │
  │  .py       │            │  .sh          │              │  .15s.sh         │
  │ CC 状态栏触发│           │ LaunchAgent   │              │ SwiftBar 每 15s  │
  │ 零成本     │            │ 每 30s 触发    │              │ 只读+渲染        │
  └───────────┘            └──────────────┘              └─────────────────┘
```

数据流：**写入方**（数据层 / 桥接层）各自往缓存目录写 JSON；**渲染层**只读取 `live.json` 和 `cache.json` 中 `ts` 较新的一份来画菜单栏。三层通过文件系统解耦，互不直接调用。

### 2.1 渲染层 `plugin/claude-gauge.15s.sh`

- SwiftBar 每 15 秒执行一次（文件名 `.15s.` 即刷新周期）。
- 读 `live.json` 与 `cache.json`，取 `ts` 较新的一份渲染（`plugin/claude-gauge.15s.sh:124-126`）。
- **兜底自拉**：若两份缓存都缺失或最新一份超过 150 秒，插件自己从钥匙串读 token 直接调一次 API 写回 `cache.json`（`plugin/claude-gauge.15s.sh:127-134`）。后台刷新器正常工作时这条几乎不触发。
- **显示逻辑（状态感知的单一信号灯）**：
  - 显示已用 %，带 `%`；5 小时窗口无前缀，一周窗口加 `W` 前缀（`title_line`，`:61-80`）。
  - 够用（两个窗口都 OK）→ 只显当前 5h 已用 %、近黑自适应色、藏掉周。
  - 不够 → 只显「正在咬人」的那个窗口 + 橙/红 + 重置倒计时；两个都报警显更严重的；周一旦紧急（≥90%）优先（7 天是硬墙）。
- **阈值**（注意脚本内部用的是「剩余 %」，与对外的「已用 %」互补）：
  - 已用 `<75%` 够用 / `75–89%` 需关注（橙 `#e08a2b`）/ `≥90%` 紧急（红 `#e0483d`）。
  - 代码里以剩余值表达：`WARN_TH=25.0` `CRIT_TH=10.0`（`plugin/claude-gauge.15s.sh:12`，即剩余 ≤25% 警告、≤10% 紧急）。
  - 配色去绿；够用 = 近黑，按系统深浅色自适应（`NORMAL` 在 `:14-17` 由 `AppleInterfaceStyle` 决定）。
- **宽度受限**：带刘海的 Mac，菜单栏标题须 ≤ 约 11 字符（`MAXW=11`，`:19`），否则会被刘海吞掉整条消失。`extra_usage`（超额消费）的 `+$` 标记只在不超宽时才加（`:77`）。
- **诚实陈旧**：`STALE_SEC=900`（15 分钟，`:11`）。超过则菜单栏变灰加 `~`，下拉里显示「数据已 N 分钟未更新」（`render`，`:88-98`）。
- **下拉每行显式上色**：SwiftBar 会把「无动作 + 无颜色」的行渲染成禁用灰，因此每行都显式设了 `color=`（见 `section` 与 `render`）。进度条放大为主信息（`size=15`），倒计时为辅（小灰字 `size=11`）。
- 下拉底部有「立即刷新」按钮，调 `~/.claude/claude-gauge-refresh.sh force`（`:109`）。

### 2.2 数据层 `refresher/claude-gauge-refresh.sh`

- 由 LaunchAgent 触发，label `dev.earthonline.claude-gauge`，`StartInterval=30`（每 30 秒唤醒）。
- **自适应节流**（`refresher/claude-gauge-refresh.sh:34-36`）：唤醒后先看上轮状态决定是否真的 poll。间隔 `iv`：
  - 紧急（max 已用 ≥90%）→ 45s
  - 需关注（≥75%）或刚变化过 → 60s
  - 够用且静止 → 240s（防 429）
  - 未到间隔直接 `raise SystemExit(0)`；`force` 参数跳过节流。
- **自愈 token（关键创新，零额度）**：token 在 60 秒内到期时（`now+60`），用钥匙串里的 refresh token 向 `https://platform.claude.com/v1/oauth/token` 发一次 OAuth 刷新（`refresh_oauth()`），换回新 token 并**原地写回钥匙串**——纯鉴权调用，零额度消耗。只改 `claudeAiOauth` 三字段、保留 `mcpOAuth` 等其余内容；refresh token 会轮换故必须写回。卡 60 秒是为了避开与活跃 CC（提前 5 分钟自刷新）抢轮换。
- 用从 macOS 钥匙串 `Claude Code-credentials` 读到的 OAuth token 鉴权（`token()`，`:20-24`）。
- 调 `https://api.anthropic.com/api/oauth/usage`，header 带 `anthropic-beta: oauth-2025-04-20`（`:40`）。
- **原子写** `cache.json`：先写临时文件再 `os.replace`（`awrite`，`:15-19`），防止插件读到半截 JSON。
- 状态持久化在 `refresh-state.json`：`last_poll_ts` / `last_max_util` / `last_5h` / `last_7d` / `changed`（`:54-55`）。

### 2.3 桥接层（可选）`bridge/claude-gauge-statusline.py`

- 作为 Claude Code 的 `statusLine` 命令注册。CC 每次刷新状态栏时通过 stdin 传入 JSON。
- 从 `rate_limits.five_hour` / `seven_day` 读 `used_percentage` + `resets_at`（Unix 秒，转成 ISO 写出，`iso()`，`:8-10`）。
- 写 `~/.cache/claude-gauge/live.json`（`:16-21`），并向 stdout 输出一行状态栏文本（形如 `◔ 5h 12%  ·  周 34%`）。
- 价值：**用 CC 时菜单栏即时刷新，不需 API / token，零成本**。
- 限制：仅对配置 `statusLine` **之后新开的会话**生效；若用户已有 `statusLine` 需手动合并。

---

## 3. 隐私 / 安全模型

- 只读钥匙串 OAuth token + 只调 Anthropic 用量端点。
- **从不读** `~/.claude/projects` 下的对话 / 代码文件。
- 无遥测；token 只发往 Anthropic。
- 全部是可读的 bash / python，无混淆，可逐行审计。

---

## 4. 当前状态（已完成 / 可用）

- [x] 渲染层：状态感知信号灯、深浅色自适应、刘海宽度保护、陈旧检测、下拉详情、立即刷新按钮、插件自拉兜底。
- [x] 数据层：LaunchAgent 自适应节流、原子写、token 自愈续命。
- [x] 桥接层：CC statusLine 即时写 `live.json`（可选增强）。
- [x] 安装 / 卸载脚本：`install.sh` 装 SwiftBar（如缺）、铺组件、写并加载 LaunchAgent、首拉数据；`uninstall.sh` 反向清理且不碰 CC 凭证与数据。

**结论：三层均可用，安装即出菜单栏百分比。**

---

## 5. 已知局限

1. **桥接仅对新会话生效**：注册 `statusLine` 后，只有之后新开的 Claude Code 会话才会写 `live.json`；已开会话不受影响。
2. **续命依赖 OAuth 端点与凭证格式**：自愈走 `platform.claude.com/v1/oauth/token` + 固定 `client_id`，并按 CC 的钥匙串 JSON 结构写回。若 Anthropic 改了端点 / client_id / 凭证格式，续命会失效——届时降级为"诚实陈旧"变灰，不会报错，用户重新登录 CC 后自动恢复。**已无早期 `claude -p` 的额度成本，续命零消耗。**
3. **usage 端点非高频设计**：`api/oauth/usage` 不是为高频轮询设计的，官方 `/usage` 页面自身缓存约 4 分钟。我们的自适应节流（够用时 240s）即为避免 429。改间隔时务必保守。
4. **平台**：仅 macOS（依赖 SwiftBar、`security` 钥匙串、`launchctl`、`defaults`）。
5. **订阅前提**：需已登录的 Claude Code（提供钥匙串 token 与 refresh token）+ Pro/Max 订阅；系统自带 `python3`。

---

## 6. Roadmap / TODO

- [ ] **用量趋势图**：现在只有当前快照。可在 `cache.json` 旁追加轻量时序日志（append-only），在下拉里画 5h / 7d 趋势 sparkline。
- [ ] **可配置项**：阈值（75/90）、节流间隔、是否显示周窗口，目前都硬编码在脚本里。抽到 `~/.cache/claude-gauge/config.json` 或环境变量。
- [ ] **打包成 `.app` / Homebrew tap**：当前靠 `install.sh` 手动铺文件。做一个 `earthonline/homebrew-tap`，`brew install --cask claude-gauge` 一键装（含 SwiftBar 依赖声明）。
- [ ] **CI 发布**：GitHub Actions 在打 tag 时校验脚本（shellcheck / python 语法）、生成 release、更新 tap formula。
- [ ] （可选）**多账号 / 多 profile** 支持：当前固定读单一钥匙串条目。

---

## 7. 如何测试与验收

### 7.1 安装冒烟测试

```bash
git clone <repo> && cd claude-gauge
./install.sh
```

验收点：

1. 脚本结束后菜单栏右上角出现用量百分比（形如 `49%`）。
2. 缓存目录已生成：`ls ~/.cache/claude-gauge/` 应见 `cache.json`（首拉成功）。
3. LaunchAgent 已加载：`launchctl list | grep dev.earthonline.claude-gauge`。

### 7.2 各层单独验证

**数据层**——手动强制拉一次并看缓存：

```bash
bash ~/.claude/claude-gauge-refresh.sh force
cat ~/.cache/claude-gauge/cache.json   # 应有 {"ts":..., "data":{"five_hour":...}}
```

**渲染层**——直接跑插件看输出（应是 SwiftBar 格式的多行文本，首行是菜单栏标题）：

```bash
bash ~/.swiftbar/claude-gauge.15s.sh    # 或实际 PluginDirectory
```

**桥接层**——喂一段模拟 CC statusLine JSON，看是否写 `live.json` 且输出状态行：

```bash
echo '{"rate_limits":{"five_hour":{"used_percentage":12,"resets_at":1999999999},"seven_day":{"used_percentage":34,"resets_at":1999999999}}}' \
  | ~/.claude/claude-gauge-statusline.py
cat ~/.cache/claude-gauge/live.json
```

### 7.3 关键行为人工验收

- **够用静默**：用量 <75% 时，菜单栏只显当前 5h 已用 %、近黑色、无周窗口。
- **报警上色**：构造（或等到）某窗口 ≥75%，确认变橙、显倒计时；≥90% 变红。
- **陈旧检测**：停掉 LaunchAgent（`launchctl bootout gui/$(id -u)/dev.earthonline.claude-gauge`），等 >15 分钟，确认菜单栏变灰加 `~` 且下拉有警告。
- **深浅色自适应**：切换系统外观（浅 ↔ 深），确认够用态文字颜色随之变化、保持可读。
- **刘海宽度**：在带刘海的 Mac 上确认标题不会被吞（开 `extra_usage` 时 `+$` 是否被正确省略）。
- **token 自愈**：跑 `bash ~/.claude/claude-gauge-refresh.sh refresh` 强制续命，确认钥匙串 token 轮换（尾位变）、`mcpOAuth` 等其余字段保留、cache 随即刷新；零额度（不触发任何模型推理）。

### 7.4 卸载验收

```bash
./uninstall.sh
```

确认：LaunchAgent 卸载、插件与 `~/.claude` 下两个脚本删除、`~/.cache/claude-gauge` 删除；**Claude Code 凭证与数据未被触碰**（`statusLine` 若手动加过需用户自行从 `settings.json` 移除）。

---

## 8. 文件地图

| 路径 | 角色 |
|---|---|
| `plugin/claude-gauge.15s.sh` | 渲染层，SwiftBar 插件（装到 PluginDirectory） |
| `refresher/claude-gauge-refresh.sh` | 数据层，LaunchAgent 刷新器（装到 `~/.claude/`） |
| `bridge/claude-gauge-statusline.py` | 桥接层，CC statusLine 命令（装到 `~/.claude/`） |
| `install.sh` / `uninstall.sh` | 安装 / 卸载 |
| `docs/screenshots/menubar.png` | 菜单栏截图 |
| `~/.cache/claude-gauge/cache.json` | 后台 API 数据（权威） |
| `~/.cache/claude-gauge/live.json` | CC 桥接即时数据 |
| `~/.cache/claude-gauge/refresh-state.json` | 刷新器节流状态 |
| `~/Library/LaunchAgents/dev.earthonline.claude-gauge.plist` | LaunchAgent 定义 |
