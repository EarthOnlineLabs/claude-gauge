# Contributing to ClaudeGauge

Thanks for your interest in improving ClaudeGauge! This is a small,
single-purpose macOS tool, so contributing is intentionally simple.
[English](#english) · [中文](#中文)

---

## English

### Project layout

| Path | Layer | Role |
|---|---|---|
| `plugin/claude-gauge.15s.sh` | Render | SwiftBar plugin, reads cache and draws the menu bar |
| `refresher/claude-gauge-refresh.sh` | Data | LaunchAgent that polls the usage API and self-heals the token |
| `bridge/claude-gauge-statusline.py` | Bridge (optional) | Claude Code `statusLine` that writes `live.json` |
| `install.sh` / `uninstall.sh` | — | Setup / teardown |

Runtime cache lives in `~/.cache/claude-gauge/` (`cache.json`,
`live.json`, `refresh-state.json`).

### Local development

Requirements: macOS, [SwiftBar](https://swiftbar.app)
(`brew install --cask swiftbar`), a logged-in Claude Code with a Pro/Max
subscription (provides the OAuth token and the `claude` CLI), and the
system `python3`.

1. Clone and run `./install.sh`. It installs SwiftBar if missing, copies
   the components into place, loads the LaunchAgent
   (`dev.earthonline.claude-gauge`), and pulls a first data point.
2. Edit a script in the repo, then reinstall (`./install.sh`) or copy the
   changed file to its installed location to test:
   - plugin → your SwiftBar plugin directory
   - refresher / bridge → `~/.claude/`
3. Test each layer in isolation:
   - Refresher: `bash ~/.claude/claude-gauge-refresh.sh force` (forces an
     immediate poll, bypassing throttling).
   - Plugin: run it directly to see the rendered SwiftBar output, or click
     "refresh now" in the dropdown.
   - Bridge: `echo '{"rate_limits":{...}}' | ~/.claude/claude-gauge-statusline.py`.
4. `./uninstall.sh` removes everything cleanly. It never touches Claude
   Code credentials or data.

### Code style

- **Single-file, readable scripts, no obfuscation.** Each component is one
  self-contained bash/Python file you can read top to bottom. Keep it that
  way — no build step, no bundler, no minification.
- Match the existing concise style and inline comments.
- Privacy is a hard rule: read only the keychain OAuth token, call only the
  Anthropic usage endpoint, never read `~/.claude/projects` files, and add
  no telemetry.

### Pull requests

1. Fork and branch from `main`.
2. Keep the change focused; describe what you changed and why.
3. Confirm install → use → uninstall still work end to end on your machine.
4. Open the PR against `earthonline/claude-gauge`.

### Reporting bugs

Open an issue and include:

- **SwiftBar version** (SwiftBar → About)
- **macOS version** (e.g. 14.5)
- **Subscription tier** — Pro or Max
- What you saw vs. what you expected (a menu-bar screenshot helps)

---

## 中文

### 项目结构

| 路径 | 层 | 职责 |
|---|---|---|
| `plugin/claude-gauge.15s.sh` | 渲染层 | SwiftBar 插件，读缓存并绘制菜单栏 |
| `refresher/claude-gauge-refresh.sh` | 数据层 | LaunchAgent，轮询用量 API 并自愈 token |
| `bridge/claude-gauge-statusline.py` | 桥接层（可选） | Claude Code `statusLine`，写 `live.json` |
| `install.sh` / `uninstall.sh` | — | 安装 / 卸载 |

运行时缓存在 `~/.cache/claude-gauge/`（`cache.json`、`live.json`、
`refresh-state.json`）。

### 本地开发

依赖：macOS、[SwiftBar](https://swiftbar.app)
（`brew install --cask swiftbar`）、已登录且为 Pro/Max 订阅的 Claude Code
（提供 OAuth token 和 `claude` CLI）、系统自带 `python3`。

1. clone 后运行 `./install.sh`。它会在缺失时装好 SwiftBar、把各组件安装到
   位、加载 LaunchAgent（`dev.earthonline.claude-gauge`）并拉取首次数据。
2. 在仓库里改脚本，然后重装（`./install.sh`）或把改动的文件复制到安装位置
   来测试：
   - 插件 → 你的 SwiftBar 插件目录
   - 刷新器 / 桥接 → `~/.claude/`
3. 各层单独测试：
   - 刷新器：`bash ~/.claude/claude-gauge-refresh.sh force`（强制立即
     poll，绕过节流）。
   - 插件：直接运行看 SwiftBar 渲染输出，或点下拉菜单里的"立即刷新"。
   - 桥接：`echo '{"rate_limits":{...}}' | ~/.claude/claude-gauge-statusline.py`。
4. `./uninstall.sh` 干净移除所有东西，绝不触碰 Claude Code 的凭证与数据。

### 代码风格

- **单文件、可读脚本、无混淆。** 每个组件都是一个能从头读到尾的自包含
  bash/Python 文件。保持这样——没有构建步骤、没有打包、没有压缩。
- 沿用现有的精简风格和行内注释。
- 隐私是硬规则：只读钥匙串里的 OAuth token、只调 Anthropic 用量端点、绝不
  读 `~/.claude/projects` 文件、不加任何遥测。

### 提 PR

1. 从 `main` fork 并开分支。
2. 改动聚焦；说明改了什么、为什么。
3. 确认在你机器上 安装 → 使用 → 卸载 仍能完整跑通。
4. 向 `earthonline/claude-gauge` 提交 PR。

### 报告 Bug

提 issue 并附上：

- **SwiftBar 版本**（SwiftBar → About）
- **macOS 版本**（如 14.5）
- **订阅类型**——Pro 还是 Max
- 你看到的 vs. 你预期的（附一张菜单栏截图最好）
