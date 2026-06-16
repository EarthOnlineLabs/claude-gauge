#!/usr/bin/env bash
# ClaudeGauge 完成提醒层安装器（默认随主 install.sh 启用；也可单独跑来重新开启）。
# 它做两件事：① 装 alert 脚本到 ~/.claude；② 把 Stop + PermissionRequest + Notification 三条 hook
# 幂等合并进 ~/.claude/settings.json（改前必先备份、改后校验、原子写、绝不动你已有的 hooks）。
# 触发点：Stop=回合完成；PermissionRequest=需要你授权(桌面端真实触发点)；Notification=终端模式的授权/idle 通知(桌面端不发)。
#
# 这是唯一会改 settings.json 的入口：主 install.sh 默认调用它启用，主 uninstall.sh 对称移除我们的 hook。
# 单独关闭：alert/install-alerts.sh --uninstall
set -euo pipefail
say(){ printf "\033[1;36m▸\033[0m %s\n" "$1"; }
ok(){  printf "\033[1;32m✓\033[0m %s\n" "$1"; }

REPO="$(cd "$(dirname "$0")/.." && pwd)"
[ "$(uname)" = "Darwin" ] || { echo "ClaudeGauge 仅支持 macOS"; exit 1; }

if [ "${1:-}" = "--uninstall" ]; then
  say "从 settings.json 移除 alert 层 hook（先备份，只删我们的条目）"
  /usr/bin/python3 - <<'PY'
import json, os, shutil, sys, time
P=os.path.expanduser("~/.claude/settings.json")
MARK="claude-gauge-alert.py"
if not os.path.exists(P):
    print("  无 settings.json，无需处理。"); sys.exit(0)
raw=open(P).read()
try: cfg=json.loads(raw) if raw.strip() else {}
except Exception:
    print("  settings.json 非合法 JSON，跳过自动移除。请手动删掉含 claude-gauge-alert.py 的 hook。"); sys.exit(1)
hooks=cfg.get("hooks")
if not isinstance(hooks,dict):
    print("  无 hooks 段，无需处理。"); sys.exit(0)
changed=False
for event in ("Stop","Notification","PermissionRequest"):
    arr=hooks.get(event)
    if not isinstance(arr,list): continue
    new=[]
    for grp in arr:
        if not isinstance(grp,dict): new.append(grp); continue
        inner=grp.get("hooks")
        if isinstance(inner,list):
            kept=[h for h in inner if MARK not in ((h or {}).get("command") or "")]
            if len(kept)!=len(inner): changed=True
            if kept:
                g=dict(grp); g["hooks"]=kept; new.append(g)   # 该组还有别的 hook → 保留，仅剥掉我们的
            # else: 该组只为我们而设 → 整组丢弃
        else:
            new.append(grp)
    if new: hooks[event]=new
    else:
        if event in hooks: changed=True
        hooks.pop(event,None)                                  # 不留空数组
if not changed:
    print("  settings.json 里没有我们的 hook，未改动。"); sys.exit(0)
bak=f"{P}.claude-gauge.bak.{int(time.time())}"; shutil.copy2(P,bak); print(f"  已备份 → {bak}")
out=json.dumps(cfg, indent=2, ensure_ascii=False); json.loads(out)   # 回解析校验
tmp=P+".tmp"; open(tmp,"w").write(out+"\n"); os.replace(tmp,P)
print("  ✓ 已移除 alert 层 hook，其余 hook 原封不动。")
PY
  rm -f "$HOME/.claude/claude-gauge-alert.py"
  ok "alert 脚本已删除（attention.json/ack.json 在 ~/.cache/claude-gauge/，随主卸载或手动清理）。"
  exit 0
fi

# ---- 安装 ----
mkdir -p "$HOME/.claude" "$HOME/.cache/claude-gauge"
install -m 0755 "$REPO/alert/claude-gauge-alert.py" "$HOME/.claude/claude-gauge-alert.py"
ok "alert 脚本 → ~/.claude/claude-gauge-alert.py"

say "把 Stop + PermissionRequest + Notification hook 幂等合并进 settings.json（先备份）"
/usr/bin/python3 - <<'PY'
import json, os, shutil, sys, time
HOME=os.path.expanduser("~")
P=os.path.join(HOME,".claude","settings.json")
ALERT=os.path.join(HOME,".claude","claude-gauge-alert.py")
PY3="/usr/bin/python3"; MARK="claude-gauge-alert.py"
STOP_CMD =f"{PY3} {ALERT} event stop"
NOTIF_CMD=f"{PY3} {ALERT} event permission"

cfg={}
if os.path.exists(P):
    raw=open(P).read()
    if raw.strip():
        try: cfg=json.loads(raw)
        except Exception:
            print("  settings.json 非合法 JSON，拒绝自动修改。请修复后重试，或手动加 hook。"); sys.exit(1)
    bak=f"{P}.claude-gauge.bak.{int(time.time())}"; shutil.copy2(P,bak); print(f"  已备份 → {bak}")
if not isinstance(cfg,dict):
    print("  settings.json 顶层不是对象，拒绝修改。"); sys.exit(1)
hooks=cfg.setdefault("hooks",{})
if not isinstance(hooks,dict):
    print("  hooks 不是对象，拒绝修改。"); sys.exit(1)

def installed(event):
    for grp in (hooks.get(event) or []):
        if not isinstance(grp,dict): continue
        for h in (grp.get("hooks") or []):
            if MARK in ((h or {}).get("command") or ""): return True
    return False

def add(event, entry):
    arr=hooks.setdefault(event,[])
    if not isinstance(arr,list):
        print(f"  hooks.{event} 不是数组，拒绝修改。"); sys.exit(1)
    if installed(event):
        print(f"  {event}: 已安装，跳过（幂等）"); return
    arr.append(entry); print(f"  {event}: 已追加")

add("Stop", {"hooks":[{"type":"command","command":STOP_CMD}]})
add("Notification", {"matcher":"permission_prompt","hooks":[{"type":"command","command":NOTIF_CMD}]})  # 终端模式的授权/idle 通知；桌面端结构性不发，无害保留(给终端用户)
add("PermissionRequest", {"hooks":[{"type":"command","command":NOTIF_CMD}]})                            # 桌面端授权弹窗的真实触发点：实测可触发，且仅真请求授权时触发、自动放行的工具不触发(已验证无噪音)

out=json.dumps(cfg, indent=2, ensure_ascii=False); json.loads(out)   # 回解析校验
tmp=P+".tmp"; open(tmp,"w").write(out+"\n"); os.replace(tmp,P)
print("  ✓ 已写入 settings.json（其余 hook 未动）。")
PY

echo
ok "完成提醒层已启用。"
say "之后：Claude Code 回合结束 / 卡住等授权，且你不在 Claude 前台时，菜单栏图标变彩虹；左键点一下回到 Claude 即熄灭。"
say "关闭：随 ./uninstall.sh 一起移除，或单独跑 bash alert/install-alerts.sh --uninstall"
