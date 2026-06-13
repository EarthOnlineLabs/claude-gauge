#!/usr/bin/env bash
set -euo pipefail
PLUGIN_DIR="$(defaults read com.ameba.SwiftBar PluginDirectory 2>/dev/null || echo "$HOME/.swiftbar")"
launchctl bootout "gui/$(id -u)/dev.earthonline.claude-gauge" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/dev.earthonline.claude-gauge.plist"
rm -f "$PLUGIN_DIR/claude-gauge.15s.sh"
rm -f "$HOME/.claude/claude-gauge-refresh.sh" "$HOME/.claude/claude-gauge-statusline.py"
rm -rf "$HOME/.cache/claude-gauge"
open "swiftbar://refreshallplugins" 2>/dev/null || true
echo "✓ ClaudeGauge 已卸载。如加过 statusLine，请自行从 ~/.claude/settings.json 移除。"
echo "  （未触碰 Claude Code 的凭证与任何数据。）"
