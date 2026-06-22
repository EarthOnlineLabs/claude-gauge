#!/usr/bin/env bash
# ClaudeGauge installer —— 把菜单栏用量工具装好并跑起来
set -euo pipefail
say(){ printf "\033[1;36m▸\033[0m %s\n" "$1"; }
ok(){  printf "\033[1;32m✓\033[0m %s\n" "$1"; }
warn(){ printf "\033[1;33m!\033[0m %s\n" "$1"; }

[ "$(uname)" = "Darwin" ] || { echo "ClaudeGauge 仅支持 macOS"; exit 1; }

# 定位源码：本地 clone 直接用；curl|bash 自动下载到临时目录（不依赖 git）
REPO="$(cd "$(dirname "$0")" && pwd)"
if [ ! -f "$REPO/plugin/claude-gauge.15s.sh" ]; then
  say "通过 curl 运行，正在下载最新源码…"
  REPO="$(mktemp -d)/claude-gauge"
  mkdir -p "$REPO"
  curl -fsSL https://github.com/EarthOnlineLabs/claude-gauge/archive/refs/heads/main.tar.gz \
    | tar xz --strip-components=1 -C "$REPO"
  _CLEANUP_REPO="$REPO"
  trap 'rm -rf "${_CLEANUP_REPO:-}"' EXIT
  ok "源码就绪"
fi

# 1. SwiftBar（菜单栏渲染宿主）
if [ ! -d "/Applications/SwiftBar.app" ]; then
  say "未检测到 SwiftBar，准备用 Homebrew 安装"
  command -v brew >/dev/null || { echo "需要 Homebrew：https://brew.sh"; exit 1; }
  read -r -p "  安装 SwiftBar？[Y/n] " a < /dev/tty; [ "${a:-Y}" = "n" ] && { echo "已取消"; exit 1; }
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
install -m 0755 "$REPO/uninstall.sh"                     "$HOME/.claude/claude-gauge-uninstall.sh"   # ② 稳定卸载脚本：与 clone 解绑，菜单「管理▸卸载」+ 命令行都指它
ok "插件 → $PLUGIN_DIR ；刷新器/桥接/卸载脚本 → ~/.claude"

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
# 重启 SwiftBar 以加载新插件（refreshallplugins 不认新文件；osascript 退出实测不可靠会留旧实例冻住，必须 pkill 确保真重启）
osascript -e 'tell application "SwiftBar" to quit' 2>/dev/null || true
pkill -x SwiftBar 2>/dev/null || true
sleep 2; open -a SwiftBar 2>/dev/null || true
ok "已拉取首次数据并加载插件"

# 5b. SwiftBar 开机自启 —— 「随 Claude 显隐」的逻辑在插件里，得有 SwiftBar 进程在跑才会被执行。
#     若不设登录项，关机/重启后 SwiftBar 不会自己回来，开了 Claude 也唤不出 gauge（实测断电后踩过）。
if osascript >/dev/null 2>&1 <<'OSA'
tell application "System Events"
  if not (exists login item "SwiftBar") then make login item at end with properties {path:"/Applications/SwiftBar.app", hidden:false}
end tell
OSA
then ok "SwiftBar 已设为开机自启（关机/重启后菜单栏自动回来）"
else warn "未能自动设置 SwiftBar 开机自启；可在 系统设置▸通用▸登录项 手动添加 SwiftBar"
fi

# 6. 完成提醒层（默认开）：复用 alert/install-alerts.sh 把 Stop/PermissionRequest/Notification
#    hook 幂等合并进 ~/.claude/settings.json（先备份、回解析校验、原子写、绝不动你已有的 hooks）。
#    非致命：settings.json 缺失/异常时这步安全跳过，绝不拖垮上面的菜单栏主功能；uninstall.sh 会对称移除。
echo
if [ -f "$REPO/alert/install-alerts.sh" ]; then
  bash "$REPO/alert/install-alerts.sh" \
    || warn "完成提醒层未启用（settings.json 异常已跳过，不影响菜单栏）；修好后可单独跑 bash alert/install-alerts.sh"
else
  warn "未找到 alert/install-alerts.sh，跳过完成提醒层"
fi

# 6b. 实时增强（默认接通）：把 statusLine 桥接幂等合并进 ~/.claude/settings.json。
#     你用 Claude Code(终端 CLI)时 CC 把实时 rate_limits 喂给桥接 → 菜单栏即时刷新，且零 token/零钥匙串，
#     对「钥匙串令牌过期/失效导致卡死」那类问题免疫。先备份、回解析校验、原子写；已有别的 statusLine 绝不覆盖。
#     非致命：settings.json 异常/已指向本桥接 → 安全跳过。⚠️ 桌面版 Claude.app 会话不执行 statusLine，此增强只对终端 CLI 生效。uninstall.sh 对称移除。
echo
BRIDGE="$HOME/.claude/claude-gauge-statusline.py"
/usr/bin/python3 - "$BRIDGE" <<'PY' || warn "实时增强未接通（settings.json 异常已跳过，不影响菜单栏每分钟级更新）"
import json, os, sys, shutil, time
P=os.path.expanduser("~/.claude/settings.json"); bridge=sys.argv[1]
raw=open(P).read() if os.path.exists(P) else ""
try: cfg=json.loads(raw) if raw.strip() else {}
except Exception:
    print("  · settings.json 非合法 JSON，跳过实时增强——修好后可手动把 statusLine 指向桥接。"); raise SystemExit(0)
cur=cfg.get("statusLine")
if isinstance(cur,dict) and (cur.get("command") or "")==bridge:
    print("  · 实时增强已接通（statusLine 已指向本桥接）。"); raise SystemExit(0)
if cur:
    print("  · 检测到你已有自定义 statusLine → 不覆盖。如需实时增强，把它的 command 改成指向：")
    print("    "+bridge); raise SystemExit(0)
cfg["statusLine"]={"type":"command","command":bridge}
if os.path.exists(P):
    bak=f"{P}.claude-gauge.bak.{int(time.time())}"; shutil.copy2(P,bak); tail=f"（已备份 → {bak}）"
else:
    os.makedirs(os.path.dirname(P),exist_ok=True); tail=""
out=json.dumps(cfg, indent=2, ensure_ascii=False); json.loads(out)  # 回解析校验
tmp=P+".tmp"; open(tmp,"w").write(out+"\n"); os.replace(tmp,P)
print(f"  · 实时增强已接通：statusLine → 桥接{tail}。")
PY

echo
ok "安装完成！菜单栏右上角应出现用量百分比。"
echo "  · 用 Claude Code（终端）时菜单栏即时刷新；任何时候后台都每分钟级自动更新。"
