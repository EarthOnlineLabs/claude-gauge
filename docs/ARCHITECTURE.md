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

核心三层 + 一个可选层（statusLine 桥接）+ 默认开的提醒层（完成提醒），彻底解耦：**写数据的不管渲染，渲染的不管拉取**。

| 层 | 文件 | 触发方式 | 职责 | 是否碰网络/token |
|---|---|---|---|---|
| 渲染层 | `plugin/claude-gauge.15s.sh` | SwiftBar 每 15 秒 | 只读缓存、渲染菜单栏标题与下拉菜单 | 默认否（仅在后台彻底失效时兜底拉一次） |
| 数据层 | `refresher/claude-gauge-refresh.sh` | LaunchAgent 每 30 秒 | 自适应节流拉取用量、自愈 token、原子写 `cache.json` | 是 |
| 桥接层（可选） | `bridge/claude-gauge-statusline.py` | Claude Code 的 statusLine 命令 | 从 CC 状态栏 JSON 取额度、写 `live.json`、回显一行用量 | 否（零成本） |
| 提醒层（默认开） | `alert/claude-gauge-alert.py` | Claude Code 的 `Stop` / `Notification(permission_prompt)` / `PermissionRequest` hook + 菜单栏左键点击 | 事件触发时记一个时间戳写 `attention.json`、点击拉起 Claude 写 `ack.json`，让菜单栏表盘亮「有新发现」彩虹态 | 否（仅本机 hooks，**绝不读对话/代码/transcript**） |
| 安装/卸载 | `install.sh` / `uninstall.sh` | 手动 | 装组件、配 LaunchAgent、合并提醒层 hook、提示 statusLine；卸载对称删自己（含提醒层 hook） | 否 |

> **提醒层（第 4 层）默认随 `install.sh` 自动启用**：主 `install.sh` 的「step 6」复用 `alert/install-alerts.sh` 把提醒层 hook 合并进 `~/.claude/settings.json`（非致命，失败不影响菜单栏主功能），`uninstall.sh` 对称移除；`alert/install-alerts.sh`（及其 `--uninstall`）仍可单独跑来开关本层。下文 §2、§3、§4、§5、§6 描述的是核心三层 + 桥接层；提醒层的完整契约与渲染逻辑见 **§8.5**。

设计要点：

- **渲染层是纯函数式渲染器**。它读的是磁盘上较新的那份缓存，几乎不主动联网。这样 SwiftBar 每 15 秒的高频刷新成本极低，且永远不会因为网络慢而卡住菜单栏。
- **数据层是唯一的"真相来源写入者"**。LaunchAgent 每 30 秒被唤醒，但脚本内部用节流逻辑决定**这一次到底要不要真的发请求**（见第 5 节）。
- **桥接层是可选的"零成本实时通道"**。你用 Claude Code 的时候，CC 已经把额度信息塞进 statusLine 的 JSON 里了，桥接层顺手把它写到 `live.json`——不需要 API、不需要 token、不花一分钱配额。
- **提醒层是默认开的"离场提醒"**。默认随 `install.sh` 启用（也可用 `alert/install-alerts.sh` 单独开关）之后，Claude Code 自己的「一个回合完成 / 停下来等授权」hook 事件会触发它往 `attention.json` 写一个**时间戳**；若事件发生时你不在 Claude 桌面 App 前台，渲染层就把表盘点成彩虹叫你回来，左键点一下拉起 Claude、彩虹熄灭。它**只对 CC 推送的事件作反应，绝不读对话或代码**，不联网、不弹系统通知、零遥测；无 `attention.json` 时（旧装/异常/已关）相关分支全程短路，菜单栏输出与今天逐字节一致（详见 §8.5）。

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

关键约定：**`live.json` 与 `cache.json` 结构完全一致**——都是 `{"ts": <epoch 秒>, "data": {...}}`。渲染层只比较两者的 `ts`，谁新用谁（`plugin/claude-gauge.15s.sh:215-216`）。这就是"plugin 读较新者"的全部含义：你用 CC 时桥接层写得更勤，菜单栏跟着 CC 实时刷新；你不用 CC 时数据层每分钟级别更新。

`data` 字段里每个窗口的结构：`{"utilization": <float, 已用%>, "resets_at": <ISO 字符串>}`。可能出现的 key：`five_hour`、`seven_day`、`seven_day_sonnet`、`seven_day_opus`、`extra_usage`。

---

## 4. 渲染层显示规则详表

### 4.0 随 Claude 显隐（菜单栏项的存在性门控）

渲染层在跑任何渲染逻辑前，先判断「Claude 此刻是否在用」——**没在用就输出空 → SwiftBar 隐藏整个菜单栏项**，省得它在你根本不用 Claude 时常驻吃眼睛。机制在脚本顶部 `:23-46`：

- **常量**：`SEEN`（`:23`，`~/.cache/claude-gauge/seen.json`，「最近在用」时间戳）、`LINGER=120`（`:24`，Claude 退出后仍显示的秒数；设 0 = 退出即隐）。
- **`_claude_running()`（`:32-38`）**：桌面端在跑（`lsappinfo find bundleID=com.anthropic.claudefordesktop`）**或**有命令行会话存活（`pgrep -x claude`）→ `True`。**仅查进程/App 是否存在，绝不读对话/代码/凭证。**
- **`_active()`（`:39-44`）**：在跑 → 原子写 `seen.json` 时间戳并返回 `True`；没跑 → 看 `seen.json` 是否在 `LINGER` 秒内（余韵窗口）。
- **门控**：`if not _active(): raise SystemExit(0)`（`:46`）——输出空，SwiftBar 隐藏该项；正常路径不碰网络。
- **为何要 linger**：连续一次性的 `claude -p` 命令（每条命令是独立短命进程）会让图标在命令间隙闪烁，2 分钟 linger 把这些缝隙抹平；交互式会话整段进程都在、不受影响。完成提醒层 `event` 时也会顺手写 `seen.json`（喂 linger），让刚完成时彩虹不被本机制隐藏。
- **延迟**：藏/显 ≤15s（SwiftBar 周期），数据恢复 ≤30s（数据层 LaunchAgent 周期）。数据层 `:26-27` 有对称的早退守卫——Claude 没在用且非 force/refresh 时不轮询、不续命（后台轮询随 Claude 关闭而暂停），见 §5。

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

阈值常量在 `plugin/claude-gauge.15s.sh:57`：`WARN_TH, CRIT_TH = 25.0, 10.0`（剩余值口径）。分级函数 `_lvl(p)` 在 `:93-97`：`p<=10 → 2`、`p<=25 → 1`、否则 `0`。**配色刻意去绿**——够用时不是绿色而是近黑/近白，把颜色这个强信号留给真正需要注意的时刻。

### 4.3 菜单栏标题状态机（`title_line`，`plugin/claude-gauge.15s.sh:138-162`）

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

- **5 小时窗口无前缀**（即"当前"），**周窗口加 `W` 前缀**——`s5()` 与 `s7()` 函数，`:145-146`。
- **额外用量提示**：若 `extra_usage.is_enabled` 且 `used_credits > 0`，且当前是够用状态、加上后宽度仍 ≤ `MAXW`，标题追加 `+$`（`:154`）。
- 倒计时格式：5h 用 `_cd5`（分钟/`{h}h{mm}m`，≥10 小时封顶显 `9h+`，`:77-84`）；周用 `_cd7`（`{d}天{h}时` / `{d}天` / 小时 / 分钟，`:85-92`）。

### 4.4 宽度硬约束（刘海）

带刘海的 Mac，菜单栏标题一旦超过约 90px（≈ 11 字符）就会被刘海吞掉**整个消失**。所以：

- `MAXW = 11`（`plugin/claude-gauge.15s.sh:64`）是字符宽度上限。
- 宽度用 `_w(s)` 计算（`:98`），中文字符（`ord(c) > 0x2E80`）按 2 宽度算，其余按 1。
- `+$` 提示只在加上后仍不超宽时才追加（`:154`）。
- 倒计时封顶常量 `CD_CAP = "9h+"`（`:64`），避免长倒计时撑爆宽度。

### 4.5 陈旧检测（诚实陈旧）

- `STALE_SEC = 900`（15 分钟，`:20`）。
- `render()` 里 `age = time.time() - ts; stale = age > STALE_SEC`（`:171`）。
- 陈旧时：菜单栏标题变灰加 `~`（`title_line` 的 stale 分支，`:157`/`:160`），且下拉菜单插入警告块：`⚠️ 数据已 N 分钟未更新` + `闲置/限流；用一下 Claude Code 即刷新`（`:181-184`）。
- 这样陈旧数据一眼可辨，菜单栏不会停在过时的数字上。

### 4.6 下拉菜单结构（`render` + `section`，`:164-199`）

SwiftBar 的坑：一行若**既无点击动作又无颜色**，会被渲染成"禁用灰"。所以**每一行都显式上色**。

每个窗口由 `section(label, icon, u, cd_str, col)` 渲染三/四行（`:164-168`）：

| 行 | 内容 | 样式 | 角色 |
|---|---|---|---|
| 标签 | `当前 5 小时 · session` / `本周 · 7 天` | `sfimage` 图标 + `NORMAL` 色 | 分组标题 |
| 数字 | `已用 X% · 还剩 Y%` | `size=14` + 状态色 | 精确数值 |
| 进度条 | `bar(u)`（10 格 `█`/`░`） | `font=Menlo size=15` + 状态色 | **主信息（放大）** |
| 倒计时 | `{cd} 后重置` | `size=11` + `MUTE` 灰 | 辅信息（小灰字） |

进度条函数 `bar(used)`（`:67-68`）：`f = round(used/10)`，输出 `"█"*f + "░"*(10-f)`。

下拉还包含：标题行 `Claude Code 用量`；按模型分项（若有 `seven_day_sonnet` / `seven_day_opus`，`:189-191`）；更新时间 `更新于 HH:MM（N分钟前/刚刚）`（`:193-194`）；一个可点击的 **`立即刷新（强制拉最新）`** 项——它 `shell` 调用 `~/.claude/claude-gauge-refresh.sh` 并传 `param0=force`，强制数据层立刻 poll（`:195`）；以及（仅当稳定卸载脚本 `~/.claude/claude-gauge-uninstall.sh` 存在时）一个 **`管理 ▸ 卸载 ClaudeGauge…`** 子菜单——`terminal=true` 在 Terminal 里可见地跑卸载脚本，收进子菜单不污染主下拉（`:196-199`，机制见 §8.6）。

**收尾整洁（脚本顶部 `:7-11` 的 SwiftBar 元数据）**：用 `swiftbar.hideLastUpdated` / `hideRunInTerminal` / `hideDisablePlugin` / `hideAbout` / `hideSwiftBar` 五个元数据，关掉 SwiftBar 宿主**默认给每个插件追加**的页脚（上次更新 / 从命令行运行 / 停用插件 / 关于 / SwiftBar 子菜单）。这些是宿主噪音、与渲染逻辑无关；关掉后下拉干净收尾在「立即刷新」，与落地页样图一致。元数据是 bash 注释，不进渲染输出。

---

## 5. 自适应节流参数表（数据层）

LaunchAgent 每 30 秒唤醒脚本，但**真正发请求的频率由脚本内部决定**，目的是在"够实时"和"防 429（限流）"之间取平衡。

节流间隔 `iv` 的计算在 `refresher/claude-gauge-refresh.sh:77-78`：

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

- **随 Claude 暂停轮询（①）**：脚本最前面有 `_claude_running()`（`:20-25`，同渲染层，只查 `lsappinfo`/`pgrep`、绝不读内容）+ 早退守卫（`:26-27`）——非 force/refresh 且 Claude（桌面端或命令行）没在用时直接 `raise SystemExit(0)`，**不轮询、不续命**。后台轮询随 Claude 关闭而暂停，跟着渲染层一起隐藏，省网络与电；下次起会话 / 开桌面端自动恢复。
- **强制绕过节流**：菜单栏点"立即刷新"或安装时传 `force` → `CQ_FORCE=1`，跳过节流判断直接 poll（`:8`、`:79`；`refresh` 测试钩子的 `CQ_REFRESH=1` 同样绕过，`:9`、`:79`）。
- **变化检测**：`chg_now` = 5h 或周用量相比上轮变化 ≥ 1%（`:96`），写回 `state` 供下一轮判断（`:97`）。
- **节流未到点就退出**：`now - last_poll_ts < iv` 时 `raise SystemExit(0)`，本次不发请求（`:79`）。

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

续命之后，正常的节流 + poll 流程接着走（`:76` 起）。如果 token 已彻底过期且续命也失败（例如 refresh token 本身失效、需要用户重新登录 CC），脚本直接退出不发请求（`:80`），菜单栏走"诚实陈旧"变灰，等用户下次用 CC 重新登录后自动恢复。

### 6.3 渲染层的独立兜底

渲染层也能读 token 自己拉一次（`read_token`，`plugin/claude-gauge.15s.sh:205-212`），但**仅在后台缓存彻底失效时**才触发——`best is None` 或 `best.ts` 比当前早超过 150 秒（`:217`）。它读 token 前会检查 `expiresAt` 是否还有 30 秒余量（`:219`），过期就不拉。注意渲染层**不做 token 续命**，续命是数据层的专责。

---

## 7. 文件与路径布局

### 7.1 仓库内（源文件）

| 路径 | 说明 |
|---|---|
| `plugin/claude-gauge.15s.sh` | 渲染层（SwiftBar 插件，文件名中 `15s` 是 SwiftBar 的刷新间隔约定） |
| `refresher/claude-gauge-refresh.sh` | 数据层 |
| `bridge/claude-gauge-statusline.py` | 桥接层（可选） |
| `alert/claude-gauge-alert.py` | 提醒层（默认开）事件入口：被 CC 的 `Stop`/`Notification`/`PermissionRequest` hook 与菜单栏左键点击调用，写 `attention.json`/`ack.json`（详见 §8.5） |
| `alert/install-alerts.sh` | 提醒层装/卸机制（默认由主 `install.sh` 调用，也可单独跑开关）：把 Stop + Notification(permission_prompt) + PermissionRequest 三条 hook **幂等**合并进 `~/.claude/settings.json`（先备份、回解析校验、原子写、只删自己）；`--uninstall` 反向移除 |
| `alert/build-menubar-icons.sh` | 构建期管线：`rsvg-convert`（`brew install librsvg`）从品牌 logo `docs/logo.svg` 渲 5 张菜单栏图标（OK 单色模板蒙版 / WARN 橙 / CRIT 红 / STALE 灰 / RAINBOW 彩虹），描边比品牌 logo 减细（弧 1.8 / 针 1.44 / 轴 r1.48 / 白芯 r0.66）以和 SF 符号同栏和谐，输出 base64 粘回插件里的 `ICON_OK`/`WARN`/`CRIT`/`STALE`/`RAINBOW` 五个常量。仅本机重生成图标时用（运行期插件只读内嵌 base64，零依赖） |
| `install.sh` / `uninstall.sh` | 安装 / 卸载（核心三层 + 默认开的提醒层 hook：install.sh 经 step 6 合并、uninstall.sh 对称移除） |
| `site/` | 落地页（`index.html` + 自托管 `fonts/` + `vercel.json`）——与三层工具独立，形态与发布见 `docs/HANDOVER.md` §9 |
| `docs/ARCHITECTURE.md` | 本文 |
| `docs/screenshots/menubar.png` | 菜单栏截图（显示 "49%"） |

### 7.2 安装后（运行时）

| 路径 | 内容 | 谁写 | 谁读 |
|---|---|---|---|
| `$PLUGIN_DIR/claude-gauge.15s.sh` | 渲染层副本（`PLUGIN_DIR` 由 SwiftBar 配置，默认 `~/.swiftbar`） | install.sh | SwiftBar |
| `~/.claude/claude-gauge-refresh.sh` | 数据层副本 | install.sh | LaunchAgent、下拉菜单刷新项 |
| `~/.claude/claude-gauge-statusline.py` | 桥接层副本 | install.sh | Claude Code |
| `~/.claude/claude-gauge-alert.py` | 提醒层副本（默认开） | install.sh（经 step 6 调 alert/install-alerts.sh）；也可单独跑 alert/install-alerts.sh | CC 的 `Stop`/`Notification`/`PermissionRequest` hook、菜单栏左键点击 |
| `~/.claude/claude-gauge-uninstall.sh` | 稳定卸载脚本副本（与 clone 解绑，菜单「管理▸卸载」+ 命令行都指它；②） | install.sh（自删于 uninstall.sh） | 渲染层下拉「管理▸卸载」、用户命令行 |
| `~/Library/LaunchAgents/dev.earthonline.claude-gauge.plist` | LaunchAgent 定义（`StartInterval 30` + `RunAtLoad`） | install.sh | launchd |
| `~/.cache/claude-gauge/cache.json` | 数据层写的用量缓存 | 数据层 | 渲染层 |
| `~/.cache/claude-gauge/live.json` | 桥接层写的实时用量 | 桥接层 | 渲染层 |
| `~/.cache/claude-gauge/refresh-state.json` | 数据层节流状态 | 数据层 | 数据层 |
| `~/.cache/claude-gauge/seen.json` | ①「最近在用」时间戳 `{ts}`（喂随 Claude 显隐 + linger） | 渲染层 / 数据层（Claude 在跑时）＋提醒层（`event` 时） | 渲染层 |
| `~/.cache/claude-gauge/attention.json` | 提醒层未读事件 `{ts, event, front, host}`（默认开；无此文件时＝旧装/异常/已关） | 提醒层（hook 触发 `event` 时） | 渲染层 |
| `~/.cache/claude-gauge/ack.json` | 提醒层已读标记 `{ts}`（默认开；无此文件时＝旧装/异常/已关） | 提醒层（左键点击）＋渲染层（检测到会话载体回前台时） | 渲染层 |

LaunchAgent label：**`dev.earthonline.claude-gauge`**（`install.sh:38`），用 `launchctl bootstrap gui/$(id -u)` 加载（`:47`）。

缓存目录统一在 `~/.cache/claude-gauge/`，由各脚本 `os.makedirs(..., exist_ok=True)` 兜底创建。

---

## 8. 扩展点

### 8.1 改阈值

- **渲染层显示分级**：`plugin/claude-gauge.15s.sh:57` 的 `WARN_TH, CRIT_TH = 25.0, 10.0`（剩余值口径，对应已用 75% / 90%）。改这里会改菜单栏的橙/红切换点。
- **数据层节流分级**：`refresher/claude-gauge-refresh.sh:78` 的 `iv` 计算，直接用 `last_max_util` 配合内联判断（已用值口径，`>=90` 紧急 45s、`>=75` 需关注 60s）。**两处口径相反**（一个用剩余、一个用已用），改阈值时务必两边都改、并注意换算（已用 = 100 − 剩余），否则菜单栏颜色和节流频率会不同步。

### 8.2 改配色

`plugin/claude-gauge.15s.sh:58`：`COL_WARN="#e08a2b"`（橙）、`COL_CRIT="#e0483d"`（红）、`COL_STALE="#9a9a9a"`（灰）。够用色在 `:62` 的 `NORMAL`（深色 `#ededef` / 浅色 `#1d1d1f`，由 `_is_dark()` 判定）。辅助灰 `MUTE` 在 `:63`。配色"去绿"是刻意设计，改时建议保持够用态为低饱和度中性色。

### 8.3 改轮询策略

- **后台唤醒频率**：`install.sh:42` 的 `<key>StartInterval</key><integer>30</integer>`。这是 launchd 唤醒脚本的间隔，不是实际 poll 间隔。
- **自适应节流间隔**：`refresher/claude-gauge-refresh.sh:78` 的 `iv` 计算（45 / 60 / 60 / 240）。想更激进或更保守改这里。注意 240s 这个上限是**防 429** 的关键，不要随意调小。
- **渲染层兜底阈值**：`plugin/claude-gauge.15s.sh:217` 的 `150` 秒（best 多久没更新才让渲染层自己拉）。

### 8.4 加模型分项

数据层已经在抓 `seven_day_sonnet` / `seven_day_opus`（`refresher/claude-gauge-refresh.sh:88` 的循环 key 列表），渲染层也已展示（`plugin/claude-gauge.15s.sh:173`、`:189-191`）。要加新模型分项：

1. 在数据层 `:88` 的 key 元组里加上新窗口名（前提是 API 返回该 key）。
2. 在渲染层 `render()` 里仿照 `son`/`opus` 取 `remain(...)` 并加进 `extras` 列表（`:173`、`:189-191`）。

桥接层目前只透传 `five_hour` / `seven_day`（`bridge/claude-gauge-statusline.py:7`、`:12-15`），若想让 CC 实时通道也带模型分项，需在此补充对应 key。

### 8.5 完成提醒 / 彩虹层（默认开）

「有新发现」是一个**默认开的第 4 层**：你离开本次会话的**载体 App**（运行 CC 的终端 App，或 Claude 桌面 App）后，若有 Claude Code 会话**完成**（`Stop`）或停下来**等你授权**（`Notification` 的 `permission_prompt` / 桌面端的 `PermissionRequest`），菜单栏表盘点成**彩虹**叫你回来；**左键点图标 = 拉回该会话所在的载体（终端会话→终端 App，桌面会话→桌面端）+ 熄灭彩虹**。它**只对 CC 自己推送的 hook 事件作反应——绝不读对话、代码、transcript**；只读进程元数据（`lsappinfo`/`ps`/`defaults`）认载体，不弹辅助功能/自动化授权框；不联网、不弹系统通知、零遥测。默认随 `install.sh` 启用；**无 `attention.json` 时（旧装/异常/已关）→ 下面整套逻辑全程短路，菜单栏输出与今天逐字节一致**。

#### 事件入口 `alert/claude-gauge-alert.py`

装到 `~/.claude/claude-gauge-alert.py`。极小、纯副作用、任何异常都安全降级、永远 `exit 0`（不阻塞 CC、不破坏任何东西）。两种调用模式：

- `event <stop|permission>`（被 CC 的 hook 调用，`main` `:104-110`）：**绝不读 stdin**——CC 会把含 `transcript_path` 的 JSON 灌进 stdin，本脚本整条忽略；事件类型由 hook 的 matcher 在 CC 层就分好了。原子写 `attention.json = {ts, event, front, host}`（`:108`）：`front` 是 `front_bundle()`（`:72-90`，用 `lsappinfo`、不弹授权框）取的**触发那刻前台 App 的 bundle id**，取不到记 `"unknown"`（宁可多提醒、不漏）；`host` 是 `session_host()`（`:29-57`）走**进程祖先链**（`ps -o ppid=`/`comm=`）认出的**本次会话宿主 App bundle**——终端会话→终端 App（Terminal/iTerm/VSCode 等），桌面会话→`com.anthropic.claudefordesktop`（经 `/Applications/Claude.app/.../disclaimer` 解析），跳过 claude CLI 自身（路径含 `/claude-code/`）与 shell/解释器，认不出记 `None`。同时顺带原子写 `seen.json`（`:109`）喂 ① 的 linger，让刚完成时彩虹在 linger 窗口内不被 ① 隐藏。写完 `open -g swiftbar://refreshplugin?name=claude-gauge.15s.sh` 让菜单栏即时重画。
- `open`（被菜单栏左键点击调用，`:111-126`）：从 `attention.json` 读 `host`，`open -b <host>`（回退链 host→front→桌面端；`host`/`front` 缺失或 `"unknown"` 时回落桌面端 `com.anthropic.claudefordesktop`），把你拉回会话所在载体——**终端会话点击回终端、桌面会话回桌面端**（关键修复：旧版写死拉桌面端，终端会话点了会跳错 App 甚至无反应）。再原子写 `ack.json = {ts}` 确认已读 → 彩虹熄灭。

#### 缓存契约（均在 `~/.cache/claude-gauge/`，原子写）

- `attention.json = {"ts": <epoch 秒>, "event": "stop"|"permission", "front": <bundle id 或 "unknown">, "host": <会话宿主 bundle id 或 null>}` —— 提醒层（hook `event`）写，渲染层读。`host` 是判定点亮/熄灭/点击目标的会话载体；缺失（旧数据 / 认不出）则各处回退老行为（与 `CLAUDE_BUNDLE` 比较、拉桌面端）。
- `ack.json = {"ts": <epoch 秒>}` —— 提醒层（左键点击 `open`）写、渲染层（检测到会话载体回到前台时）也写；渲染层读。
- `seen.json = {"ts": <epoch 秒>}` —— ① 随 Claude 显隐用的「最近在用」时间戳；提醒层 `event` 时顺带写一份（让刚完成的彩虹在 linger 窗口内不被 ① 隐藏），渲染层 / 数据层各自也写读（见渲染层 §4 顶部 `_active`、`:39-46`）。

#### 渲染层点亮判定（`plugin/claude-gauge.15s.sh`）

无 `attention.json` 时（旧装/异常/已关），`_armed()` 恒 `False`、`render()` 里相关分支不进，零额外开销。

- **`_armed()`（`:131-136`）**：`attention.json` 存在且有 `ts`，且 `attention.front != (attention.host or CLAUDE_BUNDLE)`（事件发生时你不在**会话载体**前台；`host` 缺失则回退比桌面端 bundle），且 `attention.ts > ack.ts` → 返回 `True`（点亮彩虹）。
- **回到会话载体自动熄灭**：`render()`（自动熄灭判定在 `:175-177`）每次重画时若检测到当前前台 == `attention.host or CLAUDE_BUNDLE`（`_front_bundle()`，`:110-120`，同样只用 `lsappinfo`）且有未读，就写一份新的 `ack.json` → 下次重画 `_armed` 转 `False`、彩虹熄灭（≤15s 内自动恢复常态）。即终端会话回终端、桌面会话回桌面端都能自动熄灭。
- **armed 渲染**（`title_line` 的 armed 分支，`:155-159`）：菜单栏标题用 `image={ICON_RAINBOW} {ICON_SZ}` 全彩位图 **+ 左键动作** `bash=/usr/bin/python3 param0=<alert.py> param1=open terminal=false`；**数字仍保留额度三色**（橙/红恒显，够用态不写 `color=` 走菜单栏自适应），只把图标染彩虹——两个信号共存，不遮蔽额度告急。普通（未 armed）态走原版图标常量（够用态 `templateImage={ICON_OK}`、橙/红/灰 `image={ICON_WARN/CRIT/STALE}`，`:160-162`），与 `ICON_RAINBOW` 同源同形（均由 `build-menubar-icons.sh` 从 `docs/logo.svg` 渲），故彩虹态与普通态**形状 100% 一致**。
- **彩虹位图来源**：`ICON_RAINBOW`（`:56`，内嵌 base64）由 `alert/build-menubar-icons.sh` 构建期一次性生成——从品牌 logo `docs/logo.svg`（分段光谱仪表盘，与落地页/favicon 同形）用 `rsvg-convert` 渲出彩虹弧 + 深针 + 白芯，描边按菜单栏重量减细（弧 1.8 / 针 1.44，与 SF 符号同栏和谐）。它和 OK/WARN/CRIT/STALE 四态由**同一脚本同一形状**渲出，只是着色不同，故彩虹态与普通态形状 100% 一致。**为何用 `image=` 全彩位图而非 SF 符号 sfconfig**：SF 符号的 Palette 多色在实测 SwiftBar 上糊成单橙，故彩虹/橙/红/灰态都用 `image=` 全彩位图，够用态用 `templateImage` 单色蒙版随栏自适应（见 `:47-50` 注释）。**运行期零依赖**——插件只读内嵌 base64，`build-menubar-icons.sh` 仅在重生成图标时本机用一次（仅构建期需 `librsvg`）。

#### 触发源 / 装卸

- **触发源**：`Stop`（一个回合完成）+ `Notification`/`permission_prompt`（终端模式卡住等授权）+ `PermissionRequest`（桌面端授权弹窗的真实触发点），**不含 idle**（与"完成"重复）。只关注「有/无」未读，不区分是哪个 / 几个会话。
- **默认装/卸**：默认随 `install.sh` 的「step 6」启用——主 `install.sh` 跑 `bash alert/install-alerts.sh`（以 `|| warn` 包裹，**非致命**：settings.json 异常/缺失时安全跳过，菜单栏主功能照样装成）。`alert/install-alerts.sh` 装 alert 脚本并把三条 hook **幂等**合并进 `~/.claude/settings.json`（`Stop` → `event stop`；`Notification` matcher `permission_prompt` → `event permission`；`PermissionRequest` → `event permission`）——改前先备份、回解析校验、原子写、**绝不动用户已有的 hooks**。`bash alert/install-alerts.sh --uninstall`（或直接 `uninstall.sh`，见 §8.6）只删 command 含 `claude-gauge-alert.py` 的条目（空组 / 空事件不留空壳），其余 hook 原封不动。`alert/install-alerts.sh` 仍可单独跑来单独开关本层。

### 8.6 菜单卸载入口 + 稳定卸载脚本

为了让用户不必回到 clone 目录就能卸载，`install.sh` 把卸载脚本装到一个**与 clone 解绑的稳定位置**，并在下拉里挂一个收纳子菜单：

- **稳定副本**：`install.sh:29` 用 `install -m 0755 "$REPO/uninstall.sh" "$HOME/.claude/claude-gauge-uninstall.sh"`——即使 clone 目录被删/移动，卸载脚本仍在。`uninstall.sh` 结尾 `rm -f "$HOME/.claude/claude-gauge-uninstall.sh"`（`uninstall.sh:72`）自删这份副本，卸得干净。
- **管理子菜单**：渲染层 `render()`（`:196-199`）在「立即刷新」之后，**仅当** `~/.claude/claude-gauge-uninstall.sh` 存在时，打印一个 `管理 ▸ 卸载 ClaudeGauge…` 子菜单（`shell=/bin/bash param0=<那份稳定副本> terminal=true`）。`terminal=true` 让卸载在 Terminal 里可见地跑（用户能看到输出与提示）；用子菜单收纳、不污染主下拉。
- **对称移除提醒层 hook**：主卸载脚本以一段**内联、自包含**（不依赖 repo 仍存在）的 python 块对称移除我们加的 hook——只剥掉 command 含 `claude-gauge-alert.py` 的 `Stop`/`Notification`/`PermissionRequest` 条目（先备份、回解析校验、原子写、空组/空事件不留空壳），**你已有的任何其它 hook 原封不动**（`uninstall.sh:9-45`，非致命：settings.json 异常只提示、不阻断卸载），随后 `rm -f "$HOME/.claude/claude-gauge-alert.py"`（`uninstall.sh:46`）。statusLine 是用户手动加的那一行，卸载不替你删、只在输出里提示用户自行从 `~/.claude/settings.json` 移除（`uninstall.sh:71`）。
- **SwiftBar 宿主清理**：卸载时若 ClaudeGauge 是 SwiftBar 唯一插件 → 退出 SwiftBar、移除其开机自启登录项、并 `brew uninstall --cask swiftbar`（仅当它确是 brew cask）卸掉 App，彻底清干净；若你还有别的 SwiftBar 插件，则保留 SwiftBar 与登录项给它们用、只移除本插件（删了会害你别的插件起不来——见 `tasks/lessons.md` L12）。

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
# seen.json       ← ①「最近在用」时间戳（随 Claude 显隐 + linger）
# attention.json / ack.json ← 提醒层未读/已读（默认开；无此文件＝旧装/异常/已关；attention 含 host=会话载体）
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
- **随 Claude 显隐（①，§4.0）只查进程/App 是否存在**（`lsappinfo`/`pgrep`），判断 Claude 在不在用，**绝不读对话/代码/凭证**。
- 默认开的**提醒层**（§8.5）只对 CC 自己推送的 `Stop`/`Notification`/`PermissionRequest` hook 事件作反应、只记一个时间戳 + 事件名 + 前台/会话宿主 App 的 bundle id（**面向会话载体 ⑤** 只读进程元数据 `lsappinfo`/`ps`/`defaults`，不弹辅助功能/自动化授权框），**绝不读 stdin/transcript/对话/代码**；纯本机 hooks，不联网、不弹系统通知、零遥测。
- **无遥测**；token 只发往 Anthropic，不发往任何第三方。
- 全部是**可读的 bash / python**，无混淆、无编译产物，可逐行审计。
- 卸载（`uninstall.sh`）只删自己装的东西（含对称移除 command 含 `claude-gauge-alert.py` 的提醒层 hook，先备份、回解析校验、原子写，**你已有的其它 hook 原封不动**，`uninstall.sh:9-45`），**不碰** Claude Code 的凭证与数据；卸载还会清掉 SwiftBar 开机自启登录项、并卸掉安装时 brew 装的 SwiftBar.app（仅当它是 SwiftBar 唯一插件，否则保留给其它插件用）。statusLine 是用户手动加的那一行，需用户自行从 `~/.claude/settings.json` 移除（`uninstall.sh:71`）。

---

## 11. 依赖与安装

**依赖**：macOS；SwiftBar（`brew install --cask swiftbar`）；已登录的 Claude Code（提供钥匙串 token 与 refresh token）；Pro/Max 订阅；系统自带 `python3`。

**安装**：`git clone` 后 `./install.sh`。脚本会：检测/安装 SwiftBar → 解析 SwiftBar 插件目录 → 装三个组件 → 写并加载 LaunchAgent → `force` 拉一次首数据 → 设 SwiftBar 开机自启（step 5b 加登录项，否则关机/重启后宿主不回来、「随 Claude 显隐」逻辑无进程执行；非致命） → 默认启用提醒层（step 6 复用 `alert/install-alerts.sh` 合并 hook，非致命） → 提示可选的 statusLine 配置。

**桥接层启用（可选）**：在 `~/.claude/settings.json` 加：

```json
"statusLine": { "type": "command", "command": "~/.claude/claude-gauge-statusline.py" }
```

注意：仅对**配置之后新开**的 CC 会话生效；若已有 `statusLine` 需手动合并。

**卸载**：`./uninstall.sh`。

协议：MIT。组织：EarthOnline Labs（GitHub org `EarthOnlineLabs`）。
