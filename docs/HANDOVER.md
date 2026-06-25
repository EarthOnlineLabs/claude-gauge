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
- **自愈 token（零额度）**：Claude Code 闲置导致钥匙串 token 过期时，刷新器用 refresh token 直接走 OAuth 刷新续命，零额度消耗、无需人工干预。若 refresh token 已被服务端作废（无法自愈），菜单栏不再误导，而是诚实提示去 `/login` 重新登录（`auth_dead`，见 §2.2）。

协议 MIT。组织 EarthOnline Labs（GitHub org `EarthOnlineLabs`）。

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
- 读 `live.json` 与 `cache.json`，取 `ts` 较新的一份渲染（`plugin/claude-gauge.15s.sh:223-225`）。
- **随 Claude 显隐（①）**：渲染前先 `_active()` 门控——Claude（桌面端或命令行）没在用时输出空 → SwiftBar 隐藏整个菜单栏项（`plugin/claude-gauge.15s.sh:33-47`，仅查进程/App、不读内容，带 120s linger 抹平 `claude -p` 闪烁）。详见 `docs/ARCHITECTURE.md` §4.0。
- **兜底自拉**：若两份缓存都缺失或最新一份超过 150 秒，插件自己从钥匙串读 token 直接调一次 API 写回 `cache.json`（`plugin/claude-gauge.15s.sh:226-233`）。后台刷新器正常工作时这条几乎不触发。
- **显示逻辑（状态感知的单一信号灯）**：
  - 显示已用 %，带 `%`；5 小时窗口无前缀，一周窗口加 `W` 前缀（`title_line`，`:143-167`）。
  - 够用（两个窗口都 OK）→ 只显当前 5h 已用 %、近黑自适应色、藏掉周。
  - 不够 → 只显「正在咬人」的那个窗口 + 橙/红 + 重置倒计时；两个都报警显更严重的；周一旦紧急（≥90%）优先（7 天是硬墙）。
- **阈值**（注意脚本内部用的是「剩余 %」，与对外的「已用 %」互补）：
  - 已用 `<75%` 够用 / `75–89%` 需关注（橙 `#e08a2b`）/ `≥90%` 紧急（红 `#e0483d`）。
  - 代码里以剩余值表达：`WARN_TH=25.0` `CRIT_TH=10.0`（`plugin/claude-gauge.15s.sh:58`，即剩余 ≤25% 警告、≤10% 紧急）。
  - 配色去绿；够用 = 近黑，按系统深浅色自适应（`NORMAL` 在 `:61-65` 由 `AppleInterfaceStyle` 决定）。
- **宽度受限**：带刘海的 Mac，菜单栏标题须 ≤ 约 11 字符（`MAXW=11`，`:67`），否则会被刘海吞掉整条消失。`extra_usage`（超额消费）的 `+$` 标记只在不超宽时才加（`:159`）。
- **诚实陈旧**：`STALE_SEC=900`（15 分钟，`:21`）。超过则菜单栏变灰加 `~`，下拉里显示「数据已 N 分钟未更新」；若续命被服务端 `invalid_grant` 拒（`auth_dead`）则改显「登录已失效 · 去 `/login`」（`render`，`:175-208`，见 §2.2 与 `docs/ARCHITECTURE.md` §6.4）。
- **下拉每行显式上色**：SwiftBar 会把「无动作 + 无颜色」的行渲染成禁用灰，因此每行都显式设了 `color=`（见 `section` 与 `render`）。进度条放大为主信息（`size=15`），倒计时为辅（小灰字 `size=11`）。
- 下拉底部有「立即刷新」按钮，调 `~/.claude/claude-gauge-refresh.sh force`（`:204`）；其后（仅当装了稳定卸载脚本 `~/.claude/claude-gauge-uninstall.sh` 时）有 `管理 ▸ 卸载 ClaudeGauge…` 子菜单，`terminal=true` 在 Terminal 里跑卸载（②，`:205-208`，见 `docs/ARCHITECTURE.md` §8.6）。

### 2.2 数据层 `refresher/claude-gauge-refresh.sh`

- 由 LaunchAgent 触发，label `dev.earthonline.claude-gauge`，`StartInterval=30`（每 30 秒唤醒）。
- **随 Claude 暂停轮询（①）**：脚本最前面有 `_claude_running()` + 早退守卫（`refresher/claude-gauge-refresh.sh:20-27`，同渲染层、只查进程/App）——非 force/refresh 且 Claude 没在用时直接退出、不轮询不续命，后台轮询随 Claude 关闭而暂停。
- **自适应节流**（`refresher/claude-gauge-refresh.sh:88-90`）：唤醒后先看上轮状态决定是否真的 poll。间隔 `iv`：
  - 紧急（max 已用 ≥90%）→ 45s
  - 需关注（≥75%）或刚变化过 → 60s
  - 够用且静止 → 240s（防 429）
  - 未到间隔直接 `raise SystemExit(0)`；`force` 参数跳过节流。
- **自愈 token（关键创新，零额度）**：token 在 60 秒内到期时（`now+60`），用钥匙串里的 refresh token 向 `https://platform.claude.com/v1/oauth/token` 发一次 OAuth 刷新（`refresh_oauth()`），换回新 token 并**原地写回钥匙串**——纯鉴权调用，零额度消耗。只改 `claudeAiOauth` 三字段、保留 `mcpOAuth` 等其余内容；refresh token 会轮换故必须写回。卡 60 秒是为了避开与活跃 CC（提前 5 分钟自刷新）抢轮换。
- **续命彻底失败的诚实失败态（auth_dead → /login）**：当钥匙串里的 refresh token 已被服务端作废（CC 活跃使用时自己轮换了 token、但新 token 只留在内存没回写钥匙串），续命会收到 `400 invalid_grant`、**无法自愈**（有效 token 只在 CC 内存里、外部读不到）。此时 `refresh_oauth()` 返回 `dead=True`，刷新器把 `auth_dead` 写进 `refresh-state.json`；渲染层据此把陈旧文案从「闲置/限流；用一下 Claude Code 即刷新」换成「⚠️ 登录已失效 · 在 Claude Code 里运行 `/login`」——避免误导（用户正在用 CC 也好不了）。用户 `/login` 后下一次成功 poll 自动清 `auth_dead` 复原。**失败路径绝不写 keychain**。完整机制见 `docs/ARCHITECTURE.md` §6.4。
- 从 macOS 钥匙串 `Claude Code-credentials` 读出完整凭证 blob 做鉴权（`kc_read()`，`:37-42`）；调用时带 `Authorization: Bearer <accessToken>`（`:94`）。
- 调 `https://api.anthropic.com/api/oauth/usage`，header 带 `anthropic-beta: oauth-2025-04-20`（`:94`）。
- **原子写** `cache.json`：先写临时文件再 `os.replace`（`awrite`，`:32-36`），防止插件读到半截 JSON。
- 状态持久化在 `refresh-state.json`：`last_poll_ts` / `last_max_util` / `last_5h` / `last_7d` / `changed` / `auth_dead`（`:108`）。`auth_dead` 在续命收到 `400 invalid_grant` 时置真、成功 poll 时清零，供渲染层把陈旧文案切成「登录已失效 · 去 /login」（见下「续命彻底失败的诚实失败态」）。

### 2.3 桥接层（可选）`bridge/claude-gauge-statusline.py`

- 作为 Claude Code 的 `statusLine` 命令注册。CC 每次刷新状态栏时通过 stdin 传入 JSON。
- 从 `rate_limits.five_hour` / `seven_day` 读 `used_percentage` + `resets_at`（Unix 秒，转成 ISO 写出，`iso()`，`:8-10`）。
- 写 `~/.cache/claude-gauge/live.json`（`:16-21`），并向 stdout 输出一行状态栏文本（形如 `◔ 5h 12%  ·  周 34%`）。
- 价值：**用 CC 时菜单栏即时刷新，不需 API / token，零成本**。
- **默认接通**：`install.sh`（step 6b）现在会**幂等**把 statusLine 合并进 `~/.claude/settings.json`（已有别的 statusLine 则**不覆盖**、只提示；非致命）；`uninstall.sh` 对称移除（仅删指向本桥接的那条）。无需手动加。
- 限制：仅对配置 `statusLine` **之后新开的会话**生效；**且只在终端 CLI 会话执行——桌面版 Claude.app 的会话不跑命令型 `statusLine`，故桥接对桌面端用户无效**（桌面端遇到令牌失效只能靠 §2.2 的 `/login` 提示）。

### 2.4 提醒层（默认开 · 随 install.sh 自动启用）`alert/claude-gauge-alert.py`

- **「有新发现」彩虹态（面向会话载体 ⑤）**：装了它之后，你离开本次会话的**载体 App**（运行 CC 的终端 App，或 Claude 桌面 App）时若有 CC 会话**完成**（`Stop` hook）或**停下来等你授权**（桌面端经 `PermissionRequest` hook 触发——实测桌面端**结构性不发** `Notification`/`permission_prompt`，故授权提醒在桌面端靠 PermissionRequest；终端模式两者皆可。PermissionRequest 仅真请求授权时触发、自动放行的工具不触发，无噪音），菜单栏表盘点成**彩虹**叫你回来；**左键点图标 = 拉回会话所在载体（终端会话→终端 App、桌面会话→桌面端）+ 熄灭彩虹**，右键照常开下拉。**数字仍保留额度三色**（橙/红不被遮蔽），只把图标染彩虹——两个信号共存。
- **绝不读内容**：被 hook 调用时**整条忽略 stdin**（CC 灌进来的 `transcript_path` 一律不读），只原子写 `attention.json = {ts, event, front, host, idle}`：`front` = 触发那刻前台 App bundle id（`front_bundle()`，`lsappinfo`）；`host` = 本次会话宿主 App bundle，由 `session_host()` 走**进程祖先链**（`ps -o ppid=`/`comm=`）认出（终端会话→终端 App，桌面会话→桌面端），跳过 claude CLI 自身与 shell/解释器；`idle` = 触发那刻系统空闲秒数（自上次键鼠输入以来），由 `idle_secs()` 读 IOKit `HIDIdleTime`（`ioreg -c IOHIDSystem`）得到——**只读「距上次输入多久」这一个时长，不读任何内容、不弹授权**，取不到则 0.0（视作你在用）。全程只读进程/输入元数据（`ps`/`defaults`/`lsappinfo`/`ioreg`），不弹授权框、绝不读对话/代码。渲染层据 `attention.ts > ack.ts` 且 `attention.front != (attention.host or 桌面端 bundle)`（触发时你不在会话载体前台）**且** `attention.idle >= AWAY_SEC`（触发时你确实已空闲离开，`AWAY_SEC=90.0`）三者皆成立才决定点亮——这样**只是短暂切到别的 App、人还在用电脑（空闲≈0）不会点亮，真正离开座位（空闲 ≥ 90s）才点亮**；旧版 `attention.json` 无 `idle` 字段读作 0 → 不点亮（fail-quiet）。回到会话载体前台时渲染层自动写 `ack.json` → 彩虹熄灭。**关键修复**：旧版点击写死拉桌面端，终端会话点了会跳错 App（甚至没装桌面端时点了没反应）；现在 `open -b <host>`（回退链 host→front→桌面端）回到正确载体。
- **默认开 · 随 install.sh 自动启用**：主 `install.sh` 的 step 6 会调 `alert/install-alerts.sh` 把 hook 合并进 `~/.claude/settings.json`（非致命：settings.json 异常时安全跳过、不拖垮菜单栏主功能）；`alert/install-alerts.sh` 仍是可复用机制 + 独立开关（见 §4 组件表）。**无 `attention.json` 时（旧装/异常/已关）→ 插件相关分支全程短路，菜单栏输出与今天逐字节一致**。不联网、不弹系统通知、零遥测。
- 完整缓存契约、点亮判定、armed 渲染与彩虹位图生成见 `docs/ARCHITECTURE.md` §8.5。

---

## 3. 隐私 / 安全模型

- 只读钥匙串 OAuth token + 只调 Anthropic 用量端点。
- **从不读** `~/.claude/projects` 下的对话 / 代码文件。
- **随 Claude 显隐（①）只查进程/App 是否存在**（`lsappinfo`/`pgrep`）判断 Claude 在不在用，**绝不读对话/代码/凭证**。
- 默认开的**提醒层**（§2.4）只对 CC 自己推送的 `Stop`/`Notification`/`PermissionRequest` hook 事件作反应、只记时间戳 + 事件名 + 前台/会话宿主 App 的 bundle id + 系统空闲秒数（面向会话载体 ⑤ 只读进程元数据 `ps`/`defaults`/`lsappinfo`；空闲时长读 IOKit `HIDIdleTime` 经 `ioreg`，只是「距上次键鼠输入多久」、不弹授权、不读任何内容），**绝不读 stdin/transcript/对话/代码**；纯本机 hooks，不联网、不弹系统通知。
- 无遥测；token 只发往 Anthropic。
- 全部是可读的 bash / python，无混淆，可逐行审计。

---

## 4. 当前状态（已完成 / 已上线 / 可交接）

**产品已完成、已开源、已部署，可直接交接。**

- **线上落地页**：https://claude-gauge.earthonline.site （HTTP 200）。已按 **EarthOnline / AISelf v0.6 设计语言换皮**（宋体/Fraunces 衬线 + 光谱点缀），字体**自托管、零第三方请求**。形态与**发布流程见 §9**（注意：部署必须带上 `site/fonts/` + `site/favicon.*`）。
  - **品牌 logo（新增，2026-06）**：分段光谱**仪表盘** logo（内联 SVG `#logo`，∞ 标记的「仪表」同胞），上导航品牌 + 页脚品牌 + favicon 均已用；README（双语）顶部加 `<picture>` logo（明暗主题切 PNG）。**菜单栏 mock 仍单色 `#dial`**（演示变色卖点，未动）。资产见 §8、细节见 §9.1。✅ **已发布**（commit `97e9201` 推 origin/main；落地页已 deploy 上线，`/favicon.svg`·`/favicon.png` 同源 200）。
- **开源仓库**：https://github.com/EarthOnlineLabs/claude-gauge （PUBLIC，`HEAD == origin/main`，工作区干净已推送）
- **运行时**：launchd 任务 `dev.earthonline.claude-gauge` 已加载运行；`~/.cache/claude-gauge/cache.json` 数据新鲜；SwiftBar 插件已装。
- **安装一致性**：三个已安装文件与 repo **字节级一致**（经审计 `diff` 零差异）。

功能勾选：

- [x] 渲染层：状态感知信号灯、深浅色自适应、刘海宽度保护、陈旧检测、下拉详情、立即刷新按钮、插件自拉兜底。
- [x] **① 随 Claude 显隐**：Claude（桌面端或命令行）没在用时菜单栏项隐藏（输出空 → SwiftBar 隐藏），重开/起会话自动重现；带 120s linger 抹平 `claude -p` 闪烁；渲染层 + 数据层对称门控，只查进程/App、不读内容（`docs/ARCHITECTURE.md` §4.0）。
- [x] 数据层：LaunchAgent 自适应节流、原子写、**token 零额度自愈续命**、随 Claude 暂停轮询（①）。
- [x] 桥接层：CC statusLine 即时写 `live.json`（**默认由 install.sh 接通**；纯本地、零网络、零额度；**仅终端 CLI 生效，桌面 App 会话不执行 statusLine**）。
- [x] **诚实失败态（auth_dead）**：续命被服务端 `invalid_grant` 拒（钥匙串令牌失效）时，菜单栏显示「登录已失效 · 去 `/login`」而非误导的「闲置/限流」；用户重登后自动恢复（`docs/ARCHITECTURE.md` §6.4）。
- [x] 安装 / 卸载脚本：`install.sh` 装 SwiftBar（如缺）、铺组件、写并加载 LaunchAgent、首拉数据、**装稳定卸载脚本到 `~/.claude/`（②）**、**step 6 默认启用完成提醒层、step 6b 幂等接通 statusLine 桥接（均合并进 `settings.json`，非致命、已有别的不覆盖）**；`uninstall.sh` 反向清理（含对称移除我们的 hook + statusLine + 删 alert 脚本）且不碰 CC 凭证与数据、不动用户其它 hook / statusLine。
- [x] **② 菜单卸载入口**：下拉 `管理 ▸ 卸载 ClaudeGauge…` 子菜单（装了稳定卸载脚本才显示），在 Terminal 里可见地跑卸载；卸载脚本与 clone 解绑、自删干净（`docs/ARCHITECTURE.md` §8.6）。
- [x] 提醒层（默认开 · 随 install.sh 自动启用，commit `52db7f9`）：CC `Stop`/`Notification(permission_prompt)`/`PermissionRequest` hook 触发「有新发现」彩虹态；左键拉回会话载体 + 熄灭；主 `install.sh` step 6 默认启用，`alert/install-alerts.sh` 为可复用机制 + 独立开关（`bash alert/install-alerts.sh` / `--uninstall`），主 `uninstall.sh` 对称移除。**绝不读对话/代码**（详见 §2.4 / `docs/ARCHITECTURE.md` §8.5）。
- [x] **⑤ 提醒层面向会话载体**：`session_host()` 走进程祖先链认出会话宿主（终端 App / 桌面端），点击回到正确载体（修复终端会话点彩虹跳错 App 的旧 bug）；只读进程元数据（`docs/ARCHITECTURE.md` §8.5）。

### 已安装组件清单

| 组件 | 安装位置 | repo 源 |
|---|---|---|
| 续命/刷新脚本 | `~/.claude/claude-gauge-refresh.sh` | `refresher/claude-gauge-refresh.sh` |
| SwiftBar 插件 | `~/.swiftbar/claude-gauge.15s.sh` | `plugin/claude-gauge.15s.sh` |
| statusline 桥接 | `~/.claude/claude-gauge-statusline.py` | `bridge/claude-gauge-statusline.py` |
| 提醒脚本（默认开 · 随 install.sh 启用） | `~/.claude/claude-gauge-alert.py` | `alert/claude-gauge-alert.py` |
| 稳定卸载脚本（②） | `~/.claude/claude-gauge-uninstall.sh` | `uninstall.sh`（由 `install.sh:29` 拷入，与 clone 解绑） |
| LaunchAgent plist | `~/Library/LaunchAgents/dev.earthonline.claude-gauge.plist` | `install.sh` 内联生成 |

运行时依赖仅：系统自带 `python3` + `security`（已无 `claude` CLI 依赖）。

> **提醒层默认随主 `install.sh` 启用**：主 `install.sh` 的 step 6 调 `alert/install-alerts.sh` 装 `~/.claude/claude-gauge-alert.py` 并合并 hook 进 `~/.claude/settings.json`（`|| warn` 非致命：settings.json 异常时安全跳过、菜单栏主功能照常装成）；主 `uninstall.sh` 对称移除。`alert/install-alerts.sh` 仍是可复用机制 + 独立开关：`bash alert/install-alerts.sh` 单独安装、`bash alert/install-alerts.sh --uninstall` 单独卸载——把 `Stop` + `Notification(permission_prompt)` + `PermissionRequest` 三条 hook **幂等**合并进 `~/.claude/settings.json`（改前先备份、回解析校验、原子写）；卸载只删 command 含 `claude-gauge-alert.py` 的条目，用户已有的其它 hook 原封不动。

### 最近一次关键变更：`claude -p` → 零额度 OAuth 续命

旧版自愈靠从 `/tmp` 跑 headless `claude -p ok`（消耗极小额度）。现已换成**直接 OAuth refresh**：token 将在 ≤60s 内过期时，用钥匙串里的 refresh token POST `https://platform.claude.com/v1/oauth/token`，拿回新 token 后**深拷贝整个 blob、只改 `claudeAiOauth` 三个 token 字段写回**，完整保留 `mcpOAuth` 与其余字段。纯鉴权调用、**零额度消耗**；refresh token 会轮换故必须写回；卡 60s 是避免与活跃 CC（提前 5 分钟自刷新）抢轮换。详见 §2.2 与 `docs/ARCHITECTURE.md` §6。

### 最近一次关键变更：429 限流重试 + 失败退让（修测试用户数据不更新）

**根因**：刷新器 poll 阶段 `except Exception: raise SystemExit(0)` 把所有 API 错误（含 429 限流）无声吞掉，导致缓存永不更新。外部测试用户安装时缓存 3%，之后 API 持续被 429，缓存卡在 3% 而实际用量已涨到 89%。**验证**：通过浏览器拦截对比，`api.anthropic.com/api/oauth/usage` 返回的数据与官方 `claude.ai` Usage 页面一致——端点本身无误，问题纯在客户端错误处理。**修复**：① 429 时 sleep 15s 重试一次；② 失败递增 `poll_fail_streak` 写入 state，连续失败自动拉长节流间隔（1 次→300s、3 次→600s）；③ 成功 poll 清零 streak；④ 加 User-Agent header（与 CC CLI 一致）。渲染层兜底同步加了 429 重试。

### 最近一次关键变更（续）：auth_dead 诚实失败态 + 桥接默认接通

修一类**反复发生的卡死**：CC 活跃使用时自己轮换 OAuth token、新 token 只留内存没回写钥匙串，钥匙串遂停在「access 过期 + refresh 失效」死态，续命收 `400 invalid_grant` 无法自愈——旧版菜单栏一律显示误导文案「闲置/限流；用一下 Claude Code 即刷新」（用户正在用 CC 也好不了）。两层修复：① **诚实失败态**——刷新器检测 `invalid_grant` 写 `auth_dead`，渲染层据此改显「⚠️ 登录已失效 · 去 `/login`」（覆盖所有用户，含桌面端；`refresher`/`plugin` 改动，失败路径绝不碰 keychain）；② **桥接默认接通**——`install.sh` step 6b 幂等把 statusLine 合并进 `settings.json`（`uninstall.sh` 对称移除），让**终端 CLI** 用户走零 token 通路、对此 bug 免疫。诚实标注：**桌面版 Claude.app 会话不执行 statusLine，桥接救不了桌面端**，桌面端遇此态只能靠 `/login` 提示。详见 `docs/ARCHITECTURE.md` §6.4。

**对外卖点定调**：首屏主打「只读官方用量、绝不读你的对话/代码（多数竞品在翻 `~/.claude/projects` 算用量）」+「免费、开源、零额度消耗」。**不主打"纯本地"**（默认要联网调 Anthropic 用量端点，仅桥接模式纯本地）、**不写"完全零消耗"以外的夸大**。

---

## 5. 已知局限

1. **桥接仅对新会话生效、且只覆盖终端 CLI**：注册 `statusLine` 后只有之后新开的 CC 会话才写 `live.json`；**桌面版 Claude.app 的会话不执行命令型 `statusLine`，桥接对桌面端用户无效**。`install.sh`（step 6b）现会自动幂等合并 statusLine（不覆盖你已有的）。
2. **续命依赖 OAuth 端点与凭证格式**：自愈走 `platform.claude.com/v1/oauth/token` + 固定 `client_id`，并按 CC 的钥匙串 JSON 结构写回。若 Anthropic 改了端点 / client_id / 凭证格式，续命会失效——届时降级为"诚实陈旧"变灰，不会报错，用户重新登录 CC 后自动恢复。**已无早期 `claude -p` 的额度成本，续命零消耗。**
3. **usage 端点非高频设计**：`api/oauth/usage` 不是为高频轮询设计的，429 限流窗口约 5 分钟。我们的自适应节流（够用时 240s）即为避免 429。改间隔时务必保守。**刷新器已有 429 重试（15s 后）+ 连续失败自动退让（1 次→300s、3 次→600s）+ `poll_fail_streak` 追踪**，避免缓存因限流而永久卡死。
4. **平台**：仅 macOS（依赖 SwiftBar、`security` 钥匙串、`launchctl`、`defaults`）。
5. **订阅前提**：需已登录的 Claude Code（提供钥匙串 token 与 refresh token）+ Pro/Max 订阅；系统自带 `python3`。
6. **令牌失效需手动重登（钥匙串路径无法自动恢复）**：CC 活跃使用时会自己轮换 OAuth token 且未必回写钥匙串，钥匙串可能停在「access 过期 + refresh 失效」死态，续命收 `invalid_grant`、自愈无解。此时菜单栏不再误导，而是变灰提示「⚠️ 登录已失效 · 去 `/login`」（`auth_dead`，见 §2.2 / `docs/ARCHITECTURE.md` §6.4）；用户在 CC 里 `/login` 重登后下一次成功 poll 自动恢复。**终端 CLI** 用户装了桥接（零 token）可规避此路径；**桌面端**用户不走桥接，只能靠该提示重登。

---

## 6. Roadmap / TODO

> **非目标 · 阈值通知（刻意不做）**：落地页曾出现过"跨过 75% / 90% 弹原生 macOS 通知"的对外文案，但这**从来不是需求、代码也从未实现**——本次已把该虚假声明从站点撤除。产品方明确不要这个功能：信号靠菜单栏变色（够用近黑 / 75% 橙 / 90% 红）+ 诚实陈旧变灰来传达，不弹系统通知。**请勿再加回该声明，也不要实现它。**
>
> **完成提醒 / 彩虹层（默认开 · 随 install.sh 自动启用，已上线）**：「有新发现」提醒层已实现并提交（commit `52db7f9`）——插件标题栏的 attention / 彩虹逻辑（`~/.cache/claude-gauge/attention.json` + `ack.json`）+ `alert/` 目录（`claude-gauge-alert.py` / `install-alerts.sh` / `build-menubar-icons.sh`）+ 运行时 `~/.claude/claude-gauge-alert.py`。它**只对 CC 自己的 `Stop`/`Notification(permission_prompt)`/`PermissionRequest` hook 事件作反应、绝不读对话/代码**，默认随主 `install.sh` step 6 启用（`alert/install-alerts.sh` 为可复用机制 + 独立开关，主 `uninstall.sh` 对称移除）。心智模型见 §2.4、验收见 §7.3、完整契约见 `docs/ARCHITECTURE.md` §8.5。落地页是否讲述本功能由另一独立任务负责，与本文档无关。
- [ ] **`kc_account()` 解析健壮性**（`refresher/claude-gauge-refresh.sh:43-50`）：当前在标准 CC 安装上正确（解析出的 acct == `$USER`）。残余风险：若某机器 keychain 的 acct ≠ `$USER` 且文本解析失败，回退用 `$USER` 写回可能在错误 account 下**新建第二个钥匙串项**。改进：解析失败时**宁可不写也不猜 `$USER`**，或直接复用 `kc_read()` 成功时的 acct。低概率、不紧急。
- [ ] **文档补充**：`refresh` 测试钩子即使 token 还新鲜也会强制 rotate（烧掉一次轮换，但 CC 内存里的 access_token 仍有效到真实过期、不会登出）——在 §7.3 或脚本注释里点明。
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
- **登录失效诚实提示（auth_dead）**：模拟令牌彻底失效——往 `~/.cache/claude-gauge/refresh-state.json` 写 `"auth_dead": true` 并让 cache 陈旧（停 LaunchAgent 等 >15min，或手动把 cache 的 `ts` 调早）→ 跑 `bash ~/.swiftbar/claude-gauge.15s.sh`，下拉应显示「⚠️ 登录已失效 / 在 Claude Code 里运行 /login」而非「闲置/限流」；把 `auth_dead` 改回 `false` → 回到「闲置/限流」文案。真实触发：refresh token 被服务端作废时，`bash ~/.claude/claude-gauge-refresh.sh refresh` 续命收 `400 invalid_grant`，刷新器自动把 `auth_dead` 置真（失败路径不碰 keychain）。
- **① 随 Claude 显隐**：关掉 Claude 桌面端**且**无任何 `claude` 命令行会话在跑 → 等 ≤15-30s（SwiftBar 周期 + linger 120s 过后），菜单栏图标**消失**；重开桌面端或起一个 `claude` 会话 → ≤15s 图标**重现**，数据 ≤30s 恢复新鲜。手动核对：Claude 没在用时跑 `bash ~/.swiftbar/claude-gauge.15s.sh` 应**输出为空**（被 `_active()` 早退）。只查进程/App，不读内容。
- **① 续 · SwiftBar 开机自启（重启后 gauge 仍随 Claude 显隐）**：`./install.sh`（step 5b）应把 SwiftBar 设为登录项——核对 `osascript -e 'tell application "System Events" to exists login item "SwiftBar"'` 返回 `true`，或 `系统设置▸通用▸登录项` 里有 SwiftBar。**关机/重启/重新登录后 SwiftBar 自动起来**，gauge 照常随 Claude 显隐；否则「随 Claude 显隐」逻辑在插件里、没宿主进程执行就永不出现（**实测断电后踩过，见 `tasks/lessons.md`**）。
- **② 菜单卸载**：装好后下拉底部应有 `管理 ▸ 卸载 ClaudeGauge…`（前提 `~/.claude/claude-gauge-uninstall.sh` 存在）。点击它应**在 Terminal 里可见地**跑卸载脚本（`terminal=true`），即使原 clone 目录已删也能卸载（脚本已拷到 `~/.claude/`，与 clone 解绑）。
- **完成提醒层（默认开 · 随 `./install.sh` 自动启用；也可单独 `bash alert/install-alerts.sh` 装）**：
  - **install.sh 默认启用**：跑 `./install.sh` 后，`~/.claude/settings.json` 的 `hooks` 里应出现 command 含 `claude-gauge-alert.py` 的 `Stop` / `Notification(permission_prompt)` / `PermissionRequest` 三条；用户原有的任何 hook **原封不动**（装前后 `diff` settings.json 只多我们这三条 + 备份文件）。若 settings.json 缺失/损坏，install.sh 会打印一条 `warn` 跳过、菜单栏主功能仍装成（非致命）。
  - **离场点亮（仅真离开才亮，空闲门控）**：**离开座位**（系统空闲 ≥ `AWAY_SEC=90s`、且不在会话载体前台），让某个 CC 会话跑到一个回合结束（`Stop`）或触发一次需授权（`permission_prompt`）——菜单栏表盘几秒内变**彩虹**（数字仍是额度色）。反向验收：完成那刻你**人在用电脑**（哪怕只是临时切到 Chrome 看一眼、空闲≈0）→ **不应**点亮（旧 bug：以前只要那一刻 Claude 窗口不在最前就点，切个窗就误亮，现已被空闲门控挡掉）。也可手动模拟：`/usr/bin/python3 ~/.claude/claude-gauge-alert.py event stop` 后跑 `bash ~/.swiftbar/claude-gauge.15s.sh`，首行应含 `image=…`（彩虹位图）——注意手动 `event` 写入的 `idle` 是你此刻真实空闲秒数，若你正盯着屏幕（空闲 <90s）则不会点亮，符合预期。
  - **⑤ 点击回到会话载体**：**终端会话**完成后点彩虹 → 应回到运行 CC 的那个**终端 App**（Terminal/iTerm/VSCode 等），不是桌面端；**桌面会话**完成后点彩虹 → 回到桌面端。点击后彩虹随即熄灭（写了 `ack.json`）。也可回到对应载体前台等下一次 15s 重画自动熄灭。手动核对：`cat ~/.cache/claude-gauge/attention.json` 应有 `host` 字段为对应载体 bundle id，以及 `idle` 字段（触发那刻系统空闲秒数）。
  - **无 attention.json 时零影响**（旧装/异常/已关）：`~/.cache/claude-gauge/attention.json` 不存在时，`bash ~/.swiftbar/claude-gauge.15s.sh` 的输出应与无提醒层时**逐字节一致**（彩虹分支全程短路）。
  - **uninstall.sh 对称移除**：跑 `./uninstall.sh` 后，`~/.claude/settings.json` 里仅 command 含 `claude-gauge-alert.py` 的 hook 条目被移除、用户其它 hook 原封不动（卸载前后 `diff` settings.json 只差我们那三条 + 备份文件），`~/.claude/claude-gauge-alert.py` 删除。单独 `bash alert/install-alerts.sh --uninstall` 亦达成同样效果。

### 7.4 卸载验收

```bash
./uninstall.sh
```

确认：LaunchAgent 卸载、插件与 `~/.claude` 下的刷新/桥接脚本删除、`~/.cache/claude-gauge` 删除、稳定卸载脚本 `~/.claude/claude-gauge-uninstall.sh` 自删（②，`uninstall.sh:94`）；**提醒层对称移除**——`settings.json` 里 command 含 `claude-gauge-alert.py` 的 hook 条目被删、`~/.claude/claude-gauge-alert.py` 删除（见下）；**SwiftBar 宿主清理**——若 ClaudeGauge 是唯一插件则退出 SwiftBar + 移除开机自启登录项 + `brew uninstall --cask swiftbar`（彻底清干净），若你还有别的 SwiftBar 插件则保留给它们用、只移除本插件；**Claude Code 凭证与数据未被触碰、用户其它 hook 原封不动**（**statusLine 桥接也对称自动移除**：仅当 `settings.json` 的 statusLine 指向本桥接 [command 含 `claude-gauge-statusline.py`] 时才删该键，你自定义的 statusLine 原封不动）。

> **提醒层卸载**：主 `uninstall.sh` 用一段**自包含、不依赖 repo 仍在**的内联 python 块（`uninstall.sh` 约 :9–:46）对称移除——只剥掉 `Stop`/`Notification`/`PermissionRequest` 里 command 含 `claude-gauge-alert.py` 的 hook 条目（先备份、回解析校验、原子写、绝不动用户其它 hook），再 `rm -f ~/.claude/claude-gauge-alert.py`（非致命：settings.json 异常时只提示不阻断）；`attention.json`/`ack.json` 随 `~/.cache/claude-gauge` 一并清理。也可单独 `bash alert/install-alerts.sh --uninstall` 达成同样效果。

---

## 8. 文件地图

| 路径 | 角色 |
|---|---|
| `plugin/claude-gauge.15s.sh` | 渲染层，SwiftBar 插件（装到 PluginDirectory） |
| `refresher/claude-gauge-refresh.sh` | 数据层，LaunchAgent 刷新器（装到 `~/.claude/`） |
| `bridge/claude-gauge-statusline.py` | 桥接层，CC statusLine 命令（装到 `~/.claude/`） |
| `alert/claude-gauge-alert.py` | 提醒层（默认开 · 随 install.sh 启用），CC `Stop`/`Notification`/`PermissionRequest` hook + 左键点击入口（装到 `~/.claude/`；详见 §2.4 / ARCHITECTURE §8.5） |
| `alert/install-alerts.sh` | 提醒层装/卸机制（主 install.sh step 6 调用，亦可独立运行）：合并/移除 `settings.json` 里的 Stop+Notification(permission_prompt)+PermissionRequest hook（`--uninstall` 反向） |
| `alert/build-menubar-icons.sh` | 构建期：用 `rsvg-convert`（`brew install librsvg`）从 `docs/logo.svg` 渲 5 张菜单栏图标（OK/WARN/CRIT/STALE/RAINBOW）并输出 base64（已内嵌进插件 `ICON_*` 常量，仅重生成图标时本机用；运行期零依赖） |
| `install.sh` / `uninstall.sh` | 安装 / 卸载（核心三层 + 默认启用/对称移除提醒层 hook，非致命） |
| `site/index.html` | 落地页（单文件静态站，EarthOnline 换皮；发布见 §9） |
| `site/fonts/*.woff2` | 落地页自托管字体（Fraunces / JetBrains Mono / Noto Serif SC 子集；零第三方） |
| `site/vercel.json` | 落地页 Vercel 配置（安全 headers / cleanUrls） |
| `site/favicon.svg` / `site/favicon.png` | 落地页 favicon：分段光谱仪表盘 logo 置于白色圆角芯片（SVG 主用，PNG 兜底/apple-touch；发布必带，见 §9.3） |
| `docs/logo.svg` / `docs/logo.png` / `docs/logo-dark.png` | **品牌 logo**：分段光谱仪表盘（EarthOnline ∞ 标记的「仪表」同胞）。SVG 为矢量源；README 用 `<picture>` 按明暗主题切 PNG（深色用 `logo-dark.png`，浅针变浅） |
| `docs/screenshots/menubar.png` | 菜单栏截图 |
| `~/.cache/claude-gauge/cache.json` | 后台 API 数据（权威） |
| `~/.cache/claude-gauge/live.json` | CC 桥接即时数据 |
| `~/.cache/claude-gauge/refresh-state.json` | 刷新器节流状态 |
| `~/.cache/claude-gauge/seen.json` | ①「最近在用」时间戳 `{ts}`（随 Claude 显隐 + linger；渲染层/数据层/提醒层写，渲染层读） |
| `~/.cache/claude-gauge/attention.json` | 提醒层未读事件 `{ts, event, front, host, idle}`（默认开 · 触发后才有；`host`=会话宿主载体 ⑤；`idle`=触发那刻系统空闲秒数，点亮需 `idle ≥ AWAY_SEC=90s`，旧装无此字段读作 0→不点亮） |
| `~/.cache/claude-gauge/ack.json` | 提醒层已读标记 `{ts}`（默认开 · 熄灭后才有） |
| `~/.claude/claude-gauge-alert.py` | 提醒层运行时脚本（默认开 · 随 install.sh 装入） |
| `~/.claude/claude-gauge-uninstall.sh` | 稳定卸载脚本（②，与 clone 解绑；菜单「管理▸卸载」+ 命令行都指它，`uninstall.sh` 末尾自删） |
| `~/Library/LaunchAgents/dev.earthonline.claude-gauge.plist` | LaunchAgent 定义 |

---

## 9. 落地页（`site/`）与发布流程

落地页是与三层工具**完全独立**的单页静态站，自己部署、自己的视觉语言；改它不影响工具，反之亦然。

### 9.1 形态与设计
- `site/index.html` —— **单文件**，内联 CSS/JS。EN/中文 i18n：`<span class="en/zh">` + `html[data-lang]`，首屏前按 `navigator.language` 自动匹配（以 `zh` 开头→中文，其余→英文），手动切换记 `localStorage('cg-lang')`。
- **视觉语言 = EarthOnline / AISelf v0.6 设计系统**（源参考 `~/projects/AISelf/design-exploration`，`LOGO_SPEC.md` + `design-system.html`）：宋体（Songti SC）/ Fraunces 衬线、白底暖光晕、「墨为底色作点缀」的光谱色、隐私/功能卡用**光谱淡底图标芯片**、深色代码面板、页脚锁定 **v0.6 光谱无限符号 ∞**（EarthOnline 标记，内联 SVG `#eo-mark`）。
- 导航：品牌 + GitHub + 安装 + 语言切换（无版块跳转链接）。页脚：GitHub 与 MIT 同一行 + ∞ EarthOnline。
- **品牌 logo**（内联 SVG `#logo`）：分段光谱**仪表盘**（紫→蓝→绿→橙→红，与页脚 ∞ 同一光谱、同样圆头粗描边——是 ∞ 标记的「仪表」同胞），黑针 + 白芯轴。**只出现在身份位**：导航品牌、页脚品牌、favicon（白色圆角芯片，`site/favicon.*`）。⚠️ **菜单栏 mock/下拉仍用单色 `#dial`**——它靠变橙/变红演示「一个数字三种颜色」核心卖点，**绝不能换成彩虹**。logo 颜色写死、不吃 `currentColor`，所以只放浅底；深底（README 深色主题）用 `docs/logo-dark.png`。
- 移动端：交互式菜单栏 mock 在 ≤680px 隐藏，换成一张**内联 base64 静态兜底图**（`.demo-mobile` / `.dm-en` / `.dm-zh`）。

### 9.2 自托管字体（零第三方请求）
- `site/fonts/` 下自托管 8 个 woff2：**Fraunces**（normal+italic，拉丁子集）、**JetBrains Mono**（500/700）、**Noto Serif SC**（按页面用到的汉字裁的子集，400/600/700/900）。
- **不引用 Google Fonts CDN** —— 落地页**零第三方请求**，与产品「零第三方」立场一致（页内应有 0 个 `fonts.googleapis/gstatic` 引用）。
- 中文字体栈 `'Songti SC' → … → 'Noto Serif SC'`：**Mac 用系统宋体**（根本不下载 Noto），**仅非 Mac 才拉 Noto 子集**拿到中文衬线。
- ⚠️ **维护**：Noto 子集是按**当前**页面文字「按字裁」的。大改中文文案、引入新字后需**重跑子集**（否则非 Mac 上新字会退成系统衬线；Mac 不受影响）。生成方式见 commit `e8770b9`：用 `https://fonts.googleapis.com/css2?family=Noto+Serif+SC:wght@<w>&text=<页面汉字>`（Chrome UA）取子集 woff2。

### 9.3 部署（Vercel）—— 必须带上 `site/fonts/`
- **项目** `claude-gauge`（team `earthonlinedevs-projects`，projectId `prj_w3NFiONdFHqx9W61PQN1IcCW1A1i`、orgId `team_j6T3OmyTSNVbXlILIG4vqgn8`）。**域名** `claude-gauge.earthonline.site`，DNS 在**阿里云**（CNAME `claude-gauge` → `cname.vercel-dns.com`），不在 Vercel。
- ⚠️ **`site/.vercel` 若存在是失效旧链接**（指向另一团队的 `site` 项目）——**别从 `site/` 直接 `vercel --prod`**，会发错项目。
- 正确流程（拷到干净目录再发，确保 `index.html` + `vercel.json` + **`fonts/`** + **`favicon.svg` / `favicon.png`** 一起上）：
  ```bash
  D=$(mktemp -d)
  cp site/index.html site/vercel.json site/favicon.svg site/favicon.png "$D"/ && cp -r site/fonts "$D"/fonts
  mkdir -p "$D/.vercel"
  echo '{"projectId":"prj_w3NFiONdFHqx9W61PQN1IcCW1A1i","orgId":"team_j6T3OmyTSNVbXlILIG4vqgn8","projectName":"claude-gauge"}' > "$D/.vercel/project.json"
  URL=$(vercel deploy --prod --yes --cwd "$D")
  vercel alias set "$URL" claude-gauge.earthonline.site --scope earthonlinedevs-projects
  ```
- 发布后核对：`curl -sI https://claude-gauge.earthonline.site/` → 200；页面 0 个 `fonts.googleapis/gstatic` 引用；`/fonts/*.woff2` 同源 200、`content-type: font/woff2`；`/favicon.svg` 与 `/favicon.png` 同源 200（漏拷会 404、浏览器标签页没图标）。
