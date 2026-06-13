#!/usr/bin/env bash
# ClaudeGauge installer —— 把菜单栏用量工具装好并跑起来
set -euo pipefail
say(){ printf "\033[1;36m▸\033[0m %s\n" "$1"; }
ok(){  printf "\033[1;32m✓\033[0m %s\n" "$1"; }
warn(){ printf "\033[1;33m!\033[0m %s\n" "$1"; }

REPO="$(cd "$(dirname "$0")" && pwd)"
[ "$(uname)" = "Darwin" ] || { echo "ClaudeGauge 仅支持 macOS"; exit 1; }

# 1. SwiftBar（菜单栏渲染宿主）
if [ ! -d "/Applications/SwiftBar.app" ]; then
  say "未检测到 SwiftBar，准备用 Homebrew 安装"
  command -v brew >/dev/null || { echo "需要 Homebrew：https://brew.sh"; exit 1; }
  read -r -p "  安装 SwiftBar？[Y/n] " a; [ "${a:-Y}" = "n" ] && { echo "已取消"; exit 1; }
  brew install --cask swiftbar
fi
ok "SwiftBar 就绪"

# 2. SwiftBar 插件目录
PLUGIN_DIR="$(defaults read com.ameba.SwiftBar PluginDirectory 2>/dev/null || true)"
if [ -z "$PLUGIN_DIR" ]; then PLUGIN_DIR="$HOME/.swiftbar"; defaults write com.ameba.SwiftBar PluginDirectory "$PLUGIN_DIR"; fi
mkdir -p "$PLUGIN_DIR" "$HOME/.claude" "$HOME/.cache/claude-gauge"

# 3. 装组件
install -m 0755 "$REPO/plugin/claude-gauge.15s.sh"      "$PLUGIN_DIR/claude-gauge.15s.sh"
install -m 0755 "$REPO/refresher/claude-gauge-refresh.sh" "$HOME/.claude/claude-gauge-refresh.sh"
install -m 0755 "$REPO/bridge/claude-gauge-statusline.py" "$HOME/.claude/claude-gauge-statusline.py"
ok "插件 → $PLUGIN_DIR ；刷新器/桥接 → ~/.claude"

# 4. LaunchAgent（后台每 30s 自适应刷新）
PLIST="$HOME/Library/LaunchAgents/dev.earthonline.claude-gauge.plist"
cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>dev.earthonline.claude-gauge</string>
  <key>ProgramArguments</key><array>
    <string>/bin/bash</string><string>$HOME/.claude/claude-gauge-refresh.sh</string>
  </array>
  <key>StartInterval</key><integer>30</integer>
  <key>RunAtLoad</key><true/>
</dict></plist>
PL
launchctl bootout "gui/$(id -u)/dev.earthonline.claude-gauge" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
ok "后台刷新器已加载"

# 5. 先拉一次数据 + 刷新菜单栏
bash "$HOME/.claude/claude-gauge-refresh.sh" force || true
# 重启 SwiftBar 以加载新插件（仅 refreshallplugins 不认新文件）
osascript -e 'tell application "SwiftBar" to quit' 2>/dev/null || true
sleep 1; open -a SwiftBar 2>/dev/null || true
ok "已拉取首次数据并加载插件"

echo
ok "安装完成！菜单栏右上角应出现用量百分比。"
echo
say "可选（实时增强）：让 Claude Code 把实时额度喂给本工具"
echo "  在 ~/.claude/settings.json 里加（若已有 statusLine 需自行合并）："
echo '    "statusLine": { "type": "command", "command": "'"$HOME"'/.claude/claude-gauge-statusline.py" }'
echo "  这样你用 Claude Code 时菜单栏即时刷新；不加也能每分钟自动更新。"
