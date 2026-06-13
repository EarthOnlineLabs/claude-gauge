#!/usr/bin/python3
# Claude Code statusLine 桥接：把 CC 实时额度写到 live.json 供菜单栏读取；并显示一行用量。
import sys, json, os, time, datetime
try: inp = json.loads(sys.stdin.read() or "{}")
except Exception: inp = {}
rl = inp.get("rate_limits") or {}
fh = rl.get("five_hour") or {}; wk = rl.get("seven_day") or {}
def iso(ep):
    try: return datetime.datetime.fromtimestamp(float(ep), datetime.timezone.utc).isoformat()
    except Exception: return None
data = {}
if fh.get("used_percentage") is not None:
    data["five_hour"] = {"utilization": float(fh["used_percentage"]), "resets_at": iso(fh.get("resets_at"))}
if wk.get("used_percentage") is not None:
    data["seven_day"] = {"utilization": float(wk["used_percentage"]), "resets_at": iso(wk.get("resets_at"))}
if data:
    p = os.path.expanduser("~/.cache/claude-gauge/live.json")
    try:
        os.makedirs(os.path.dirname(p), exist_ok=True)
        json.dump({"ts": time.time(), "data": data}, open(p, "w"))
    except Exception: pass
parts = []
if "five_hour" in data: parts.append(f"5h {int(round(data['five_hour']['utilization']))}%")
if "seven_day" in data: parts.append(f"周 {int(round(data['seven_day']['utilization']))}%")
sys.stdout.write(("◔ " + "  ·  ".join(parts)) if parts else "")
