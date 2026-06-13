# ClaudeGauge 架构文档

> 给接手开发者的深度技术文档。读完你应该能独立改阈值、改配色、改轮询策略、加模型分项，并能本地调试每一层。
>
> 本文所有路径、函数名、参数均直接取自仓库脚本，未经推断。引用处给出 `文件:行号`。

---

## 1. 一句话定位

ClaudeGauge 是一个 macOS 菜单栏小工具，**实时、状态感知地**显示 Claude Code（Pro/Max 订阅）的额度用量。它会自愈过期的 OAuth token；数据陈旧时菜单栏会变灰提示，不会停在旧数字上。

显示口径与 Claude Code 内置的 `/usage` 完全一致：**显示"已用百分比"，越大越满**。

---

## 2. 组件清单与职责

三层 + 一个可选桥接层，彻底解耦：**写数据的不管渲染，渲染的不管拉取**。

| 层 | 文件 | 触发方式 | 职责 | 是否碰网络/token |
|---|---|---|---|---|
| 渲染层 | `plugin/claude-gauge.15s.sh` | SwiftBar 每 15 秒 | 只读缓存、渲染菜单栏标题与下拉菜单 | 默认否（仅在后台彻底失效时兜底拉一次） |
| 数据层 | `refresher/claude-gauge-refresh.sh` | LaunchAgent 每 30 秒 | 自适应节流拉取用量、自愈 token、原子写 `cache.json` | 是 |
| 桥接层（可选） | `bridge/claude-gauge-statusline.py` | Claude Code 的 statusLine 命令 | 从 CC 状态栏 JSON 取额度、写 `live.json`、回显一行用量 | 否（零成本） |
| 安装/卸载 | `install.sh` / `uninstall.sh` | 手动 | 装组件、配 LaunchAgent、提示 statusLine；卸载只删自己 | 否 |

设计要点：

- **渲染层是纯函数式渲染器**。它读的是磁盘上较新的那份缓存，几乎不主动联网。这样 SwiftBar 每 15 秒的高频刷新成本极低，且永远不会因为网络慢而卡住菜单栏。
- **数据层是唯一的"真相来源写入者"**。LaunchAgent 每 30 秒被唤醒，但脚本内部用节流逻辑决定**这一次到底要不要真的发请求**（见第 5 节）。
- **桥接层是可选的"零成本实时通道"**。你用 Claude Code 的时候，CC 已经把额度信息塞进 statusLine 的 JSON 里了，桥接层顺手把它写到 `live.json`——不需要 API、不需要 token、不花一分钱配额。

---

## 3. 数据流图

```
                        ┌───────────────────────────────────────────────┐
                        │                 数据来源                        │
                        └───────────────────────────────────────────────┘

  Anthropic 用量端点                                  Claude Code 进程
  api.anthropic.com/api/oauth/usage                  （statusLine JSON: rate_limits）
            │                                                   │
            │ OAuth Bearer token                                │ stdin JSON
            │ (钥匙串 "Claude Code-credentials")                 │ (five_hour / seven_day:
            │                                                   │  used_percentage + resets_at)
            ▼                                                   ▼
  ┌──────────────────────────┐                    ┌──────────────────────────────┐
  │ 数据层（LaunchAgent 30s） │                    │ 桥接层（CC statusLine 命令）  │
  │ claude-gauge-refresh.sh  │                    │ claude-gauge-statusline.py    │
  │  · 自适应节流决定是否 poll │                    │  · 解析 rate_limits           │
  │  · token 零额度自愈续命     │                    │  · Unix 秒 → ISO 时间          │
  │  · 原子写                 │                    │  · 回显一行 "◔ 5h x% · 周 y%" │
  │                          │                    │  · 原子级 json.dump 写        │
  └────────────┬─────────────┘                    └───────────────┬──────────────┘
               │ awrite()                                          │ json.dump
               ▼                                                   ▼
   ~/.cache/claude-gauge/cache.json              ~/.cache/claude-gauge/live.json
   {"ts": <写入时刻>, "data": {...}}              {"ts": <写入时刻>, "data": {...}}
               │                                                   │
               └─────────────────────┬─────────────────────────────┘
                                     │  两份缓存格式完全相同
                                     ▼
                        ┌──────────────────────────────┐
                        │  渲染层（SwiftBar 15s）       │
                        │  claude-gauge.15s.sh          │
                        │   · load(LIVE), load(CACHE)   │
                        │   · 取 ts 较新的一份 (best)   │
                        │   · 兜底：best 失效才自己拉   │
                        │   · render()                  │
                        └───────────────┬──────────────┘
                                        ▼
                               macOS 菜单栏标题 + 下拉菜单
                               （如 "49%"）
```

关键约定：**`live.json` 与 `cache.json` 结构完全一致**——都是 `{"ts": <epoch 秒>, "data": {...}}`。渲染层只比较两者的 `ts`，谁新用谁（`plugin/claude-gauge.15s.sh:124-126`）。这就是"plugin 读较新者"的全部含义：你用 CC 时桥接层写得更勤，菜单栏跟着 CC 实时刷新；你不用 CC 时数据层每分钟级别更新。

`data` 字段里每个窗口的结构：`{"utilization": <float, 已用%>, "resets_at": <ISO 字符串>}`。可能出现的 key：`five_hour`、`seven_day`、`seven_day_sonnet`、`seven_day_opus`、`extra_usage`。

---

## 4. 渲染层显示规则详表

### 4.1 设计哲学：状态感知的"单一信号灯"

渲染层不是简单地把所有数字都堆到菜单栏上，而是按"够用就静默，不够才报警"的原则压缩信息：

- **够用就静默**：只显示当前 5 小时窗口的已用%，用自适应黑/白字（深色模式白、浅色模式黑），藏掉周窗口。
- **不够才报警**：只显示"正在咬人"（接近耗尽）的那个窗口，配橙/红色 + 重置倒计时。
- **两个窗口都报警**：显示更严重的那个；周窗口一旦进入紧急（≥90%）优先显示，因为周是 7 天硬墙，撞上了一周都难受。

### 4.2 阈值与配色

注意：脚本内部用的是**剩余百分比**（`remain` / `rem`），阈值表也是按剩余值写的；对外展示和本文其余部分用**已用百分比**。两者互补（已用 = 100 − 剩余）。

| 状态 | 已用% | 剩余% | 内部 level | 颜色 | 常量 |
|---|---|---|---|---|---|
| 够用 | < 75% | > 25% | 0 | 近黑/近白（自适应） | `NORMAL`（深色 `#ededef` / 浅色 `#1d1d1f`） |
| 需关注 | 75–89% | 11–25% | 1 | 橙 | `COL_WARN = #e08a2b` |
| 紧急 | ≥ 90% | ≤ 10% | 2 | 红 | `COL_CRIT = #e0483d` |
| 陈旧 | — | — | — | 灰 | `COL_STALE = #9a9a9a` |

阈值常量在 `plugin/claude-gauge.15s.sh:12`：`WARN_TH, CRIT_TH = 25.0, 10.0`（剩余值口径）。分级函数 `_lvl(p)` 在 `:48-52`：`p<=10 → 2`、`p<=25 → 1`、否则 `0`。**配色刻意去绿**——够用时不是绿色而是近黑/近白，把颜色这个强信号留给真正需要注意的时刻。

### 4.3 菜单栏标题状态机（`title_line`，`plugin/claude-gauge.15s.sh:61-80`）

`fh` = 5 小时窗口剩余%，`wk` = 周窗口剩余%，`fl`/`wl` = 各自的 level。

| 条件 | 标题显示 | 颜色 |
|---|---|---|
| `fh` 和 `wk` 都为 None（无数据） | `额度⚠` | 橙 `COL_WARN` |
| 两窗口都够用（level 0/None） | `{u5}%`（仅 5h 已用%，无前缀），周有数据而 5h 无则显 `W{u7}%` | 默认 `sfimage` logo |
| 仅 5h 在报警（周够用） | `{u5}% {5h倒计时}` | 红（5h 紧急）否则橙 |
| 仅周在报警（5h 够用） | `W{u7}% {周倒计时}` | 红（周紧急）否则橙 |
| 两个都报警，周紧急或周更严重 | `W{u7}% {周倒计时}` | 红（周紧急）否则橙 |
| 两个都报警，5h 更严重 | `{u5}% {5h倒计时}` | 红（5h 紧急）否则橙 |
| 数据陈旧（age > 900s） | 上述文本 + `~` 后缀 | 灰 `COL_STALE` |

补充规则：

- **5 小时窗口无前缀**（即"当前"），**周窗口加 `W` 前缀**——`s5()` 与 `s7()` 函数，`:68-69`。
- **额外用量提示**：若 `extra_usage.is_enabled` 且 `used_credits > 0`，且当前是够用状态、加上后宽度仍 ≤ `MAXW`，标题追加 `+$`（`:77`）。
- 倒计时格式：5h 用 `_cd5`（分钟/`{h}h{mm}m`，≥10 小时封顶显 `9h+`，`:32-39`）；周用 `_cd7`（`{d}天{h}时` / `{d}天` / 小时 / 分钟，`:40-47`）。

### 4.4 宽度硬约束（刘海）

带刘海的 Mac，菜单栏标题一旦超过约 90px（≈ 11 字符）就会被刘海吞掉**整个消失**。所以：

- `MAXW = 11`（`plugin/claude-gauge.15s.sh:19`）是字符宽度上限。
- 宽度用 `_w(s)` 计算（`:53`），中文字符（`ord(c) > 0x2E80`）按 2 宽度算，其余按 1。
- `+$` 提示只在加上后仍不超宽时才追加（`:77`）。
- 倒计时封顶常量 `CD_CAP = "9h+"`（`:19`），避免长倒计时撑爆宽度。

### 4.5 陈旧检测（诚实陈旧）

- `STALE_SEC = 900`（15 分钟，`:11`）。
- `render()` 里 `age = time.time() - ts; stale = age > STALE_SEC`（`:89`）。
- 陈旧时：菜单栏标题变灰加 `~`（`:78`），且下拉菜单插入警告块：`⚠️ 数据已 N 分钟未更新` + `闲置/限流；用一下 Claude Code 即刷新`（`:95-98`）。
- 这样陈旧数据一眼可辨，菜单栏不会停在过时的数字上。

### 4.6 下拉菜单结构（`render` + `section`，`:82-109`）

SwiftBar 的坑：一行若**既无点击动作又无颜色**，会被渲染成"禁用灰"。所以**每一行都显式上色**。

每个窗口由 `section(label, icon, u, cd_str, col)` 渲染三/四行（`:82-86`）：

| 行 | 内容 | 样式 | 角色 |
|---|---|---|---|
| 标签 | `当前 5 小时 · session` / `本周 · 7 天` | `sfimage` 图标 + `NORMAL` 色 | 分组标题 |
| 数字 | `已用 X% · 还剩 Y%` | `size=14` + 状态色 | 精确数值 |
| 进度条 | `bar(u)`（10 格 `█`/`░`） | `font=Menlo size=15` + 状态色 | **主信息（放大）** |
| 倒计时 | `{cd} 后重置` | `size=11` + `MUTE` 灰 | 辅信息（小灰字） |

进度条函数 `bar(used)`（`:22-23`）：`f = round(used/10)`，输出 `"█"*f + "░"*(10-f)`。

下拉还包含：标题行 `Claude Code 用量`；按模型分项（若有 `seven_day_sonnet` / `seven_day_opus`，`:102-105`）；更新时间 `更新于 HH:MM（N分钟前/刚刚）`（`:107-108`）；以及一个可点击的 **`立即刷新（强制拉最新）`** 项——它 `shell` 调用 `~/.claude/claude-gauge-refresh.sh` 并传 `param0=force`，强制数据层立刻 poll（`:109`）。

---

## 5. 自适应节流参数表（数据层）

LaunchAgent 每 30 秒唤醒脚本，但**真正发请求的频率由脚本内部决定**，目的是在"够实时"和"防 429（限流）"之间取平衡。

节流间隔 `iv` 的计算在 `refresher/claude-gauge-refresh.sh:68-69`：

```
lm = st["last_max_util"]   # 上轮两窗口已用%的最大值
chg = st["changed"]        # 上轮用量是否有变化（≥1%）

iv = 45  if lm >= 90              # 紧急
   = 60  if lm >= 75              # 需关注
   = 60  if chg                   # 够用但仍在活跃变化
   = 240 otherwise                # 够用且静止
```

| 场景 | 判定条件 | 拉取间隔 | 理由 |
|---|---|---|---|
| 紧急 | `last_max_util >= 90` | 45s | 快耗尽，需高频盯紧倒计时 |
| 需关注 | `last_max_util >= 75` | 60s | 接近阈值，适度提频 |
| 够用·活跃 | 上轮用量有变化（`changed`） | 60s | 用户正在干活，值得跟 |
| 够用·静止 | 以上都不满足 | 240s | 没人用，拉慢点防 429 |

补充逻辑：

- **强制绕过节流**：菜单栏点"立即刷新"或安装时传 `force` → `CQ_FORCE=1`，跳过节流判断直接 poll（`:8`、`:70`；`refresh` 测试钩子的 `CQ_REFRESH=1` 同样绕过，`:9`、`:70`）。
- **变化检测**：`chg_now` = 5h 或周用量相比上轮变化 ≥ 1%（`:87`），写回 `state` 供下一轮判断（`:88-89`）。
- **节流未到点就退出**：`now - last_poll_ts < iv` 时 `raise SystemExit(0)`，本次不发请求（`:70`）。

状态文件：`~/.cache/claude-gauge/refresh-state.json`（`STATE`，`:14`），存 `last_poll_ts` / `last_max_util` / `last_5h` / `last_7d` / `changed`。

---

## 6. 自愈 token 机制详解

### 6.1 为什么需要

Claude Code 的 OAuth token 存在 macOS 钥匙串里（服务名 `Claude Code-credentials`）。问题在于：**Claude Code 闲置时不会主动刷新这个 token**。token 过期后，直接拿它调用 `api.anthropic.com/api/oauth/usage` 会返回 **401**，菜单栏就再也拿不到新数据了——而这恰恰是"诚实陈旧"机制会触发灰色报警的场景。

我们需要的是：在 token 还没过期前，让某个进程替 Claude Code 走一次正常的刷新流程，把新 token 写回钥匙串。

### 6.2 怎么做

在数据层每次运行的最前面（`refresher/claude-gauge-refresh.sh`）：

```
blob = kc_read()                               # 从钥匙串读完整凭证 blob（含 mcpOAuth）
tk = blob["claudeAiOauth"]
if tk.expiresAt/1000 < now + 60:               # 距过期 ≤ 60 秒
    new = refresh_oauth(blob)                  # OAuth refresh_token 换新 + 写回钥匙串
    if new: tk = new                           # 续命成功就用新 token
```

机制拆解：

- **触发条件**：token 距过期 **≤ 60 秒**才续命。为什么卡这么晚？因为活跃使用时 Claude Code 会**提前 5 分钟**自己刷新 token，永远轮不到我们这个 60 秒窗口——这样就不会和 CC **抢着轮换** refresh token。只有 CC 闲置（没在跑、不会自刷新）时 token 才会逼近过期，由我们接手；此时没有活跃的 CC 进程，零竞态。
- **续命动作**：用钥匙串里的 `refreshToken` 向 `https://platform.claude.com/v1/oauth/token` 发一次 POST（body `grant_type=refresh_token` + `refresh_token` + `client_id`，`Content-Type: application/json`），拿回新的 `access_token` / `refresh_token` / `expires_in`。这是一次**纯鉴权调用，不是模型推理，零额度消耗**——比早期版本用 `claude -p ok`（会消耗极小额度）干净。
- **refresh_token 会轮换**：每次刷新服务端都会发一个新的 refresh token 并让旧的失效，所以**必须把新 token 写回钥匙串**，否则 CC 下次刷新拿着失效的旧 token 会被登出。
- **写回只改 3 字段**：读出完整 blob，只更新 `claudeAiOauth` 的 `accessToken` / `refreshToken` / `expiresAt`，**完整保留 `mcpOAuth`（其它 MCP 服务器的 OAuth token）等其余内容**，用 `security add-generic-password -U` 原地更新（保留 ACL，CC 照样能读）。
- **端点细节**：必须是 `platform.claude.com`，`console.anthropic.com/v1/oauth/token` 会返回 404；请求需带 `User-Agent`（缺了会被 Cloudflare 403）。

续命之后，正常的节流 + poll 流程接着走（`:73` 起）。如果 token 已彻底过期且续命也失败（例如 refresh token 本身失效、需要用户重新登录 CC），脚本直接退出不发请求（`:71`），菜单栏走"诚实陈旧"变灰，等用户下次用 CC 重新登录后自动恢复。

### 6.3 渲染层的独立兜底

渲染层也能读 token 自己拉一次（`read_token`，`plugin/claude-gauge.15s.sh:115-122`），但**仅在后台缓存彻底失效时**才触发——`best is None` 或 `best.ts` 比当前早超过 150 秒（`:127`）。它读 token 前会检查 `expiresAt` 是否还有 30 秒余量（`:129`），过期就不拉。注意渲染层**不做 token 续命**，续命是数据层的专责。

---

## 7. 文件与路径布局

### 7.1 仓库内（源文件）

| 路径 | 说明 |
|---|---|
| `plugin/claude-gauge.15s.sh` | 渲染层（SwiftBar 插件，文件名中 `15s` 是 SwiftBar 的刷新间隔约定） |
| `refresher/claude-gauge-refresh.sh` | 数据层 |
| `bridge/claude-gauge-statusline.py` | 桥接层（可选） |
| `install.sh` / `uninstall.sh` | 安装 / 卸载 |
| `docs/ARCHITECTURE.md` | 本文 |
| `docs/screenshots/menubar.png` | 菜单栏截图（显示 "49%"） |

### 7.2 安装后（运行时）

| 路径 | 内容 | 谁写 | 谁读 |
|---|---|---|---|
| `$PLUGIN_DIR/claude-gauge.15s.sh` | 渲染层副本（`PLUGIN_DIR` 由 SwiftBar 配置，默认 `~/.swiftbar`） | install.sh | SwiftBar |
| `~/.claude/claude-gauge-refresh.sh` | 数据层副本 | install.sh | LaunchAgent、下拉菜单刷新项 |
| `~/.claude/claude-gauge-statusline.py` | 桥接层副本 | install.sh | Claude Code |
| `~/Library/LaunchAgents/dev.earthonline.claude-gauge.plist` | LaunchAgent 定义（`StartInterval 30` + `RunAtLoad`） | install.sh | launchd |
| `~/.cache/claude-gauge/cache.json` | 数据层写的用量缓存 | 数据层 | 渲染层 |
| `~/.cache/claude-gauge/live.json` | 桥接层写的实时用量 | 桥接层 | 渲染层 |
| `~/.cache/claude-gauge/refresh-state.json` | 数据层节流状态 | 数据层 | 数据层 |

LaunchAgent label：**`dev.earthonline.claude-gauge`**（`install.sh:37`），用 `launchctl bootstrap gui/$(id -u)` 加载（`:46`）。

缓存目录统一在 `~/.cache/claude-gauge/`，由各脚本 `os.makedirs(..., exist_ok=True)` 兜底创建。

---

## 8. 扩展点

### 8.1 改阈值

- **渲染层显示分级**：`plugin/claude-gauge.15s.sh:12` 的 `WARN_TH, CRIT_TH = 25.0, 10.0`（剩余值口径，对应已用 75% / 90%）。改这里会改菜单栏的橙/红切换点。
- **数据层节流分级**：`refresher/claude-gauge-refresh.sh:69` 的 `iv` 计算，直接用 `last_max_util` 配合内联判断（已用值口径，`>=90` 紧急 45s、`>=75` 需关注 60s）。**两处口径相反**（一个用剩余、一个用已用），改阈值时务必两边都改、并注意换算（已用 = 100 − 剩余），否则菜单栏颜色和节流频率会不同步。

### 8.2 改配色

`plugin/claude-gauge.15s.sh:13`：`COL_WARN="#e08a2b"`（橙）、`COL_CRIT="#e0483d"`（红）、`COL_STALE="#9a9a9a"`（灰）。够用色在 `:17` 的 `NORMAL`（深色 `#ededef` / 浅色 `#1d1d1f`，由 `_is_dark()` 判定）。辅助灰 `MUTE` 在 `:18`。配色"去绿"是刻意设计，改时建议保持够用态为低饱和度中性色。

### 8.3 改轮询策略

- **后台唤醒频率**：`install.sh:41` 的 `<key>StartInterval</key><integer>30</integer>`。这是 launchd 唤醒脚本的间隔，不是实际 poll 间隔。
- **自适应节流间隔**：`refresher/claude-gauge-refresh.sh:69` 的 `iv` 计算（45 / 60 / 60 / 240）。想更激进或更保守改这里。注意 240s 这个上限是**防 429** 的关键，不要随意调小。
- **渲染层兜底阈值**：`plugin/claude-gauge.15s.sh:127` 的 `150` 秒（best 多久没更新才让渲染层自己拉）。

### 8.4 加模型分项

数据层已经在抓 `seven_day_sonnet` / `seven_day_opus`（`refresher/claude-gauge-refresh.sh:79` 的循环 key 列表），渲染层也已展示（`plugin/claude-gauge.15s.sh:91`、`:102-105`）。要加新模型分项：

1. 在数据层 `:79` 的 key 元组里加上新窗口名（前提是 API 返回该 key）。
2. 在渲染层 `render()` 里仿照 `son`/`opus` 取 `remain(...)` 并加进 `extras` 列表（`:102-105`）。

桥接层目前只透传 `five_hour` / `seven_day`（`bridge/claude-gauge-statusline.py:7`、`:12-15`），若想让 CC 实时通道也带模型分项，需在此补充对应 key。

---

## 9. 本地开发与调试

### 9.1 手动跑各脚本看输出

**渲染层**（直接看 SwiftBar 会渲染成什么）：

```bash
bash ~/.swiftbar/claude-gauge.15s.sh
# 或仓库内：
bash plugin/claude-gauge.15s.sh
```

输出是 SwiftBar 格式的纯文本：第一行是菜单栏标题，`---` 分隔下拉项。每行 `| ` 后是样式参数（`color=` / `size=` / `sfimage=` 等）。

**数据层**（强制拉一次，绕过节流）：

```bash
bash ~/.claude/claude-gauge-refresh.sh force
# 看它写了什么：
cat ~/.cache/claude-gauge/cache.json | python3 -m json.tool
```

不带 `force` 直接跑会受节流约束，可能立刻 `SystemExit(0)` 什么都不做——调试时记得带 `force`。

**桥接层**（喂一个模拟的 CC statusLine JSON）：

```bash
echo '{"rate_limits":{"five_hour":{"used_percentage":49,"resets_at":1760000000},"seven_day":{"used_percentage":30,"resets_at":1760400000}}}' \
  | python3 bridge/claude-gauge-statusline.py
# 它会回显一行 "◔ 5h 49% · 周 30%" 并写 live.json
cat ~/.cache/claude-gauge/live.json | python3 -m json.tool
```

### 9.2 看缓存

```bash
ls -la ~/.cache/claude-gauge/
# cache.json      ← 数据层写的
# live.json       ← 桥接层写的（用过 CC 才有）
# refresh-state.json ← 数据层节流状态
for f in ~/.cache/claude-gauge/*.json; do echo "== $f =="; python3 -m json.tool "$f"; done
```

渲染层取 `cache.json` 和 `live.json` 里 `ts` 较新的一份。想验证"读较新者"逻辑，可以手动改某个文件的 `ts` 再跑渲染层。

### 9.3 模拟各状态

**直接构造缓存**最省事——往 `cache.json` 写一份你想要的数据，再跑渲染层：

```bash
# 模拟"5h 紧急"（已用 95% → 剩余 5% → 红 + 倒计时）
python3 - <<'PY'
import json, time, os
p = os.path.expanduser("~/.cache/claude-gauge/cache.json")
json.dump({"ts": time.time(), "data": {
    "five_hour": {"utilization": 95.0, "resets_at": time.time()+1800},
    "seven_day": {"utilization": 30.0, "resets_at": time.time()+500000},
}}, open(p, "w"))
PY
bash plugin/claude-gauge.15s.sh
```

按此套路可模拟各状态：

| 想看的状态 | 怎么构造 |
|---|---|
| 够用（默认色） | `five_hour.utilization = 40`，预期标题 `40%` 无前缀、近黑/白 |
| 需关注（橙） | `utilization = 80`，预期橙 + 倒计时 |
| 紧急（红） | `utilization = 95` |
| 周优先 | 5h `utilization=80`、周 `utilization=92`，预期标题切到 `W92%` 红 |
| 陈旧（灰 + `~`） | `ts = time.time() - 1000`（> 900s），预期标题灰 + `~` + 下拉警告 |
| 无数据 | 删掉 `cache.json` 和 `live.json`，预期 `额度⚠` 橙（注意可能触发渲染层兜底联网） |
| 额外用量 `+$` | 在够用态 `data` 里加 `"extra_usage":{"is_enabled":true,"used_credits":5}` |
| 模型分项 | `data` 加 `seven_day_sonnet` / `seven_day_opus` |

### 9.4 看后台 LaunchAgent 状态

```bash
launchctl print "gui/$(id -u)/dev.earthonline.claude-gauge"   # 是否加载、上次退出码
# 重新加载（改了脚本/plist 后）：
launchctl bootout "gui/$(id -u)/dev.earthonline.claude-gauge" 2>/dev/null
launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/dev.earthonline.claude-gauge.plist
```

### 9.5 强制 SwiftBar 刷新

```bash
open "swiftbar://refreshallplugins"
```

改了渲染层脚本后用这个立即看效果，不用等 15 秒。

---

## 10. 隐私与安全

- **只读** macOS 钥匙串里的 OAuth token（`security find-generic-password -s "Claude Code-credentials"`），**只调** Anthropic 的用量端点 `api.anthropic.com/api/oauth/usage`。
- **从不读** `~/.claude/projects` 下的对话/代码文件。
- **无遥测**；token 只发往 Anthropic，不发往任何第三方。
- 全部是**可读的 bash / python**，无混淆、无编译产物，可逐行审计。
- 卸载（`uninstall.sh`）只删自己装的东西，**不碰** Claude Code 的凭证与数据，statusLine 配置需用户自行从 `~/.claude/settings.json` 移除（`uninstall.sh:10`）。

---

## 11. 依赖与安装

**依赖**：macOS；SwiftBar（`brew install --cask swiftbar`）；已登录的 Claude Code（提供钥匙串 token 与 refresh token）；Pro/Max 订阅；系统自带 `python3`。

**安装**：`git clone` 后 `./install.sh`。脚本会：检测/安装 SwiftBar → 解析 SwiftBar 插件目录 → 装三个组件 → 写并加载 LaunchAgent → `force` 拉一次首数据 → 提示可选的 statusLine 配置。

**桥接层启用（可选）**：在 `~/.claude/settings.json` 加：

```json
"statusLine": { "type": "command", "command": "~/.claude/claude-gauge-statusline.py" }
```

注意：仅对**配置之后新开**的 CC 会话生效；若已有 `statusLine` 需手动合并。

**卸载**：`./uninstall.sh`。

协议：MIT。组织：EarthOnline（GitHub org `earthonline` / `EarthOnlineDev`）。
