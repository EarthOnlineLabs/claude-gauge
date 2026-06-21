#!/usr/bin/env bash
set -euo pipefail
PLUGIN_DIR="$(defaults read com.ameba.SwiftBar PluginDirectory 2>/dev/null || echo "$HOME/.swiftbar")"
launchctl bootout "gui/$(id -u)/dev.earthonline.claude-gauge" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/dev.earthonline.claude-gauge.plist"
rm -f "$PLUGIN_DIR/claude-gauge.15s.sh"
rm -f "$HOME/.claude/claude-gauge-refresh.sh" "$HOME/.claude/claude-gauge-statusline.py"

# 完成提醒层（默认随安装启用）：对称移除——只删我们加的 hook（command 含 claude-gauge-alert.py），
# 先备份、回解析校验、原子写；你已有的任何 hook 原封不动。自包含（不依赖 repo）；非致命（异常只提示、不阻断卸载）。
/usr/bin/python3 - <<'PY' || true
import json, os, shutil, time
P=os.path.expanduser("~/.claude/settings.json")
MARK="claude-gauge-alert.py"
if not os.path.exists(P): raise SystemExit(0)
raw=open(P).read()
try: cfg=json.loads(raw) if raw.strip() else {}
except Exception:
    print("  · settings.json 非合法 JSON，跳过自动移除——请手动删掉含 claude-gauge-alert.py 的 hook。"); raise SystemExit(0)
hooks=cfg.get("hooks")
if not isinstance(hooks, dict): raise SystemExit(0)
changed=False
for event in ("Stop","Notification","PermissionRequest"):
    arr=hooks.get(event)
    if not isinstance(arr, list): continue
    new=[]
    for grp in arr:
        if not isinstance(grp, dict): new.append(grp); continue
        inner=grp.get("hooks")
        if isinstance(inner, list):
            kept=[h for h in inner if MARK not in ((h or {}).get("command") or "")]
            if len(kept)!=len(inner): changed=True
            if kept: g=dict(grp); g["hooks"]=kept; new.append(g)   # 该组还有别的 hook → 保留，仅剥掉我们的
            # else: 该组只为我们而设 → 整组丢弃
        else: new.append(grp)
    if new: hooks[event]=new
    else:
        if event in hooks: changed=True
        hooks.pop(event, None)                                     # 不留空数组
if not changed: raise SystemExit(0)
bak=f"{P}.claude-gauge.bak.{int(time.time())}"; shutil.copy2(P, bak)
out=json.dumps(cfg, indent=2, ensure_ascii=False); json.loads(out)  # 回解析校验
tmp=P+".tmp"; open(tmp,"w").write(out+"\n"); os.replace(tmp, P)
print(f"  · 已移除「完成提醒」hook（已备份 → {bak}；你已有的 hook 原封不动）。")
PY
rm -f "$HOME/.claude/claude-gauge-alert.py"

# statusLine 桥接：对称移除——仅当 settings.json 的 statusLine 指向本桥接时才删（你自定义的 statusLine 不碰）。
# 自包含、非致命；先备份、回解析校验、原子写。
/usr/bin/python3 - <<'PY' || true
import json, os, shutil, time
P=os.path.expanduser("~/.claude/settings.json"); MARK="claude-gauge-statusline.py"
if not os.path.exists(P): raise SystemExit(0)
raw=open(P).read()
try: cfg=json.loads(raw) if raw.strip() else {}
except Exception:
    print("  · settings.json 非合法 JSON，跳过 statusLine 自动移除——如加过指向 claude-gauge-statusline.py 的 statusLine 请手动删。"); raise SystemExit(0)
sl=cfg.get("statusLine")
if not (isinstance(sl,dict) and MARK in ((sl.get("command")) or "")): raise SystemExit(0)
cfg.pop("statusLine",None)
bak=f"{P}.claude-gauge.bak.{int(time.time())}"; shutil.copy2(P,bak)
out=json.dumps(cfg, indent=2, ensure_ascii=False); json.loads(out)  # 回解析校验
tmp=P+".tmp"; open(tmp,"w").write(out+"\n"); os.replace(tmp,P)
print(f"  · 已移除指向本桥接的 statusLine（已备份 → {bak}；你自定义的配置原封不动）。")
PY

rm -rf "$HOME/.cache/claude-gauge"

# SwiftBar 宿主清理：ClaudeGauge 是唯一插件时彻底清干净（退进程 + 删开机自启登录项 + 卸掉安装时 brew 装的 SwiftBar.app）。
# 唯一例外——你还有别的 SwiftBar 插件：删了 SwiftBar/登录项会害那些插件起不来，故保留并明示（见 tasks/lessons.md L12）。
if [ -d "$PLUGIN_DIR" ]; then
  OTHER_PLUGINS=$(find "$PLUGIN_DIR" -maxdepth 1 -type f ! -name '.*' 2>/dev/null | wc -l | tr -d ' ')
else
  OTHER_PLUGINS=0   # 插件目录不存在（自定义目录失效/已删）→ 视作无其它插件，避免 find 非零退出被 set -e 中断卸载
fi
if [ "${OTHER_PLUGINS:-0}" = "0" ]; then
  osascript -e 'tell application "SwiftBar" to quit' 2>/dev/null || true
  pkill -x SwiftBar 2>/dev/null || true
  osascript -e 'tell application "System Events" to if exists login item "SwiftBar" then delete login item "SwiftBar"' 2>/dev/null || true
  SB_MSG="SwiftBar 已退出、开机自启（登录项）已移除"
  if command -v brew >/dev/null 2>&1 && brew list --cask swiftbar >/dev/null 2>&1; then
    if brew uninstall --cask swiftbar >/dev/null 2>&1; then SB_MSG="$SB_MSG、SwiftBar.app 已卸载"
    else SB_MSG="$SB_MSG（SwiftBar.app 自动卸载失败，可手动跑 brew uninstall --cask swiftbar）"; fi
  else
    SB_MSG="$SB_MSG（SwiftBar.app 非 brew 安装，未自动删除——如需可手动从 /Applications 移除）"
  fi
else
  open "swiftbar://refreshallplugins" 2>/dev/null || true
  SB_MSG="检测到你还有其它 SwiftBar 插件（$OTHER_PLUGINS 个）→ 保留 SwiftBar 与开机自启给它们用，仅移除本插件"
fi

echo "✓ ClaudeGauge 已卸载（菜单栏 / 后台刷新器 / 桥接 / 完成提醒 hook / 缓存 / 开机自启）。未触碰 Claude Code 的凭证与任何对话数据。"
echo "  · $SB_MSG。"
rm -f "$HOME/.claude/claude-gauge-uninstall.sh" 2>/dev/null || true   # ② 自删装好的副本，卸得干净
