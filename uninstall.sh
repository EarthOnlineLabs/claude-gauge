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

rm -rf "$HOME/.cache/claude-gauge"
open "swiftbar://refreshallplugins" 2>/dev/null || true
echo "✓ ClaudeGauge 已卸载（菜单栏 / 后台刷新器 / 桥接 / 完成提醒 hook / 缓存）。未触碰 Claude Code 的凭证与任何对话数据。"
echo "  · 如加过 statusLine：请自行从 ~/.claude/settings.json 移除那一行（这一行是你手动加的，本卸载不替你删）。"
rm -f "$HOME/.claude/claude-gauge-uninstall.sh" 2>/dev/null || true   # ② 自删装好的副本，卸得干净
