# ClaudeGauge — 产品使用数据在哪看（METRICS）

> 推广期「回收数据」的唯一权威清单：每一处能看到真实使用/采纳数据的地方、怎么看、看到的是什么、有什么坑。
> 最近更新：2026-06-15。

## 0. 红线（先记牢）

- **埋点只在落地页，工具永不被埋点。** 三层菜单栏工具（`plugin/` · `refresher/` · `bridge/`）**绝不**发任何遥测，不向任何第三方/自有服务器上报。工具采纳量只能靠 **GitHub 侧间接信号**推断（见 §2），这是产品立身之本，不可侵蚀。
- 因此「产品使用数据」分两类：**① 落地页流量漏斗**（Vercel Web Analytics，§1）；**② 工具采纳间接信号**（GitHub，§2）。社媒平台自身的互动数据不在本文档范围。

---

## 1. 落地页流量 — Vercel Web Analytics（主漏斗）

- **看什么**：页面浏览量（PV）、独立访客、来源 referrer、UTM 渠道、粗粒度地理、OS/浏览器/设备、时间趋势。配合 §3 的 UTM 方案，这是区分 **Twitter vs 小红书 引流量**、看落在哪个页面、哪个地区的主视图。
- **在哪看**：Vercel Dashboard → 项目 `claude-gauge` → **Analytics** 标签页。
  - 项目：`claude-gauge`（team `earthonlinedevs-projects`，projectId `prj_w3NFiONdFHqx9W61PQN1IcCW1A1i`）。
  - ⚠️ **没有公开数据 API**：Vercel 至今未提供拉取 WA 数据的 REST 端点（社区 FR 仍 open）。**只能在 Dashboard 看/截图**，无法编程导出。
- **当前状态（2026-06-15，已上线 ✅）**：WA **已启用（Hobby 免费档）并部署上线**。`site/index.html` 首屏 pageview 探针已落地，`claude-gauge.earthonline.site/_vercel/insights/script.js` + `/view` 信标已在浏览器**实测同源触发、零第三方请求、无 Set-Cookie**，pageview 开始出数（Dashboard → Analytics 可见）。启用是 Dashboard 一次性「Enable」按钮（无 CLI/API），本会话经 Chrome 完成。
- **首屏探针（已落地，零第三方）**：同源 `/_vercel/insights/script.js` + `/_vercel/insights/view` 信标，**无 cookie、无 localStorage、无第三方域名、无 PII、无需 consent banner**（Vercel 隐私文档：访客=请求哈希、24h 丢弃）。这是对「零第三方」品牌最干净的可观测方案——DevTools 里看到的是**指向我们自己域名的第一方请求**，不是外部 tracker。
- **关键限制 — 点击漏斗要 Pro**：**自定义事件（custom events）是 Pro/Enterprise 专属**（官方文档 + 启用弹窗双重确认）。本项目是 **Hobby 免费档**，`va('event',…)` 会**静默失效**。
  - **Hobby 免费档实测额度**（启用弹窗所示）：**50,000 events/月**、**30 天可见历史**、**无自定义事件**、ingestion 有上限。
  - **免费能拿到**：pageview、referrer/UTM、地理、设备。
  - **要升级 Pro（$20/mo）才能拿到**：`install_copied`（点了复制安装命令）、`github_click`、`lang_toggle`、`cta_click` —— 即「点击级意图漏斗」。
  - 故意**没有**预埋 `va('event')` 调用：在 Hobby 上它们只会制造「假装在测」的错觉。升级 Pro 后再接（接入点见文末）。

---

## 2. GitHub 采纳信号（工具被多少人用，间接推断）

> 安装方式只有 `git clone`（无 release 资产、无 cask、无 curl|bash），所以**没有 release 下载数**可看；采纳量靠下面这些信号。全部用 `gh`（已以 `EarthOnlineDev` 身份认证、有 push 权限，traffic 端点需要 push 权限）。

| 信号 | 命令 | 看什么 | 坑 |
|---|---|---|---|
| Star / Fork / Watcher | `gh api repos/EarthOnlineDev/claude-gauge --jq '{stars:.stargazers_count,forks:.forks_count,watchers:.subscribers_count}'` | 社会证明的头号指标，推广落地后重点盯 star 增长 | 累计值无时间序列（要 star 时间线用 stargazers + `Accept: application/vnd.github.star+json`） |
| 仓库流量·浏览 | `gh api repos/EarthOnlineDev/claude-gauge/traffic/views` | 仓库页 PV/UV，确认「落地页→仓库」漏斗 | **14 天滚动窗口，GitHub 不留存**；含自己访问 |
| 仓库流量·clone | `gh api repos/EarthOnlineDev/claude-gauge/traffic/clones` | 最接近「有人拉代码去装」的代理指标 | 同 14 天窗口；**clone 数被 CI/镜像/依赖 bot 严重灌水，是上界不是真人数**；clone ≠ install |
| 来源 referrer | `gh api repos/EarthOnlineDev/claude-gauge/traffic/popular/referrers` | 谁把流量带到仓库（含落地页、各平台） | 仅 Top 10；14 天 |
| 热门路径 | `gh api repos/EarthOnlineDev/claude-gauge/traffic/popular/paths` | 哪个 README（en/zh）更受关注 | 仅 Top 10；14 天 |
| Release 下载数 | `gh api repos/EarthOnlineDev/claude-gauge/releases` | 每个 release 资产的 `download_count` | **当前为空**：0 release、0 tag。除非开始打 tagged release 并附资产，否则永远空 |
| Insights·Traffic（UI） | 仓库 → Insights → Traffic | 上述 clone/views/referrers 的图形界面 | 同样 14 天窗口、需 push 权限 |

### 当前基线快照（2026-06-15，推广前）

```
stars 0 · forks 0 · watchers 0        ← 仓库 2026-06-13 建，基本零外部传播
views  16 / uniques 1                  ← 几乎只有 owner 自己；referrer = 落地页 & github.com 各 1
clones 201 / uniques 88                ← 几乎全部集中在 launch 当天，bot 灌水为主，勿当 88 真人
top path = README.zh-CN.md (10 views)  ← 早期受众偏中文 → 利好小红书
```

> ⏰ **14 天窗口会丢数据**：上面 clone/views/referrers 是滚动 14 天、GitHub 不留存。**推广 push 期正是最值得留存的窗口**。建议在开推前加一个每日 `gh api` 快照（GitHub Action 或本地 launchd，把四个 traffic JSON 追加存档），否则 launch-spike 历史永久丢失。（默认未加——见待定决策。）

---

## 3. UTM / ref 渠道方案（区分 Twitter vs 小红书）

每一条对外分享的链接都打标签，否则无法归因来源。

- **落地页（Twitter）**：`https://claude-gauge.earthonline.site/?utm_source=twitter&utm_medium=social&utm_campaign=launch`
- **落地页（小红书）**：`https://claude-gauge.earthonline.site/?utm_source=xiaohongshu&utm_medium=social&utm_campaign=launch`
- **直链仓库**：`https://github.com/EarthOnlineDev/claude-gauge?ref=twitter` / `?ref=xiaohongshu`（让来源出现在 GitHub traffic referrers 里）
- **坑**：UTM 只能归因「点了你打标签的链接」；自然传播/裸域名复制会丢归因。**小红书尤其会剥离 referrer、且站内不让点外链** → 优先给小红书一个**好记的独立短链/路径**，别指望 referrer 头。Hobby 计划下点击后是 pageview-only，所以 **UTM source 是渠道级的主要信号**。

---

## 4. Vercel 部署 / 访问日志（完整性旁证，非行为分析）

- `vercel logs <deployment-url> --scope earthonlinedevs-projects`；`vercel ls claude-gauge --scope ...`。UI：Dashboard → Logs。
- 静态站无 serverless 函数，"日志"主要是 edge/访问条目，**没有点击/语言/CTA 等行为数据**。仅用于「页面确实在被请求/被正常 serve」的旁证，不替代 WA。

---

## 5. 决策状态（2026-06-15）

1. **启用 Vercel WA** — ✅ **已完成**。Hobby 免费档，经 Chrome 点 Enable + 重新部署（启用后的新部署才带 `/_vercel/insights/*` 路由）+ `vercel alias set` 指回 `claude-gauge.earthonline.site` + 浏览器实测信标同源触发。
2. **是否升级 Pro（$20/mo）** — 决策：**先只要免费 pageview + UTM（$0）**。日后想要点击级漏斗（install_copied 等）再升 Pro。
3. **落地页隐私披露文案** — 🔄 **进行中**：已定「加一行双语披露」，草稿待产品方过目后上线（属对外文案）。
4. **GitHub traffic 每日快照** — ⏳ **待定**：建议开推前加每日快照（Action/launchd）保留 14 天窗口；默认未加，等指示。

> **Pro 升级后的事件接入点**（届时再接）：`copyInstall()`（`site/index.html` 复制安装命令）→ `install_copied`；`toggleLang()` → `lang_toggle`；GitHub 链接（nav/hero/footer）→ `github_click`；`#install` CTA → `cta_click`。调用形如 `va('event',{name:'install_copied'})`。
