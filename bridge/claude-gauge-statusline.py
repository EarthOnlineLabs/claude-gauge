#!/usr/bin/python3
# Claude Code statusLine 桥接：把 CC 实时额度写到 live.json 供菜单栏读取；并显示一行用量。
import sys, json, os, time, datetime, subprocess, hashlib, tempfile
CDIR = os.path.expanduser("~/.cache/claude-gauge")
FPCACHE = os.path.join(CDIR, "fp.json")   # fp 边车缓存：避免每次 statusline 渲染都同步读钥匙串(热路径提速)
def _awrite(path, obj):
    """原子写：临时文件 + os.replace，防半截文件被并发读到（与 refresher/plugin 一致）。"""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path))
    with os.fdopen(fd, "w") as f: json.dump(obj, f)
    os.replace(tmp, path)
def _read_keychain_fp():
    """现读钥匙串算 token 指纹（纯本地，无网络/无额度）。与 refresher/plugin 的 cred_fp 必须一致。"""
    try: acct = subprocess.run(["/usr/bin/id","-un"], capture_output=True, text=True, timeout=2).stdout.strip()
    except Exception: acct = os.environ.get("USER","")
    for args in ((["-a", acct] if acct else []), []):   # 先锁本机用户，取不到再退 service-only
        try:
            raw = subprocess.run(["/usr/bin/security","find-generic-password","-s","Claude Code-credentials"]+args+["-w"], capture_output=True, text=True, timeout=2).stdout
            if raw.strip():
                at = json.loads(raw)["claudeAiOauth"]["accessToken"]
                return hashlib.sha256(("cg1:"+at).encode()).hexdigest()[:16]
        except Exception: pass
    return None
def _cur_fp():
    """给 live.json 盖归属戳，供插件核对这份实时数据属于当前登录账号——防换号后菜单栏显示上个账号的实时额度。
    fp 边车缓存 90s，避免每次渲染都同步读钥匙串阻塞 CC statusline；轮换后最迟 90s 内自动重算。"""
    try:
        s = json.load(open(FPCACHE))
        if time.time() - s.get("ts", 0) < 90 and s.get("fp"): return s.get("fp")
    except Exception: pass
    fp = _read_keychain_fp()
    if fp:
        try: _awrite(FPCACHE, {"fp": fp, "ts": time.time()})
        except Exception: pass
    return fp
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
    p = os.path.join(CDIR, "live.json")
    try:
        obj = {"ts": time.time(), "data": data}
        _fp = _cur_fp()
        if _fp: obj["fp"] = _fp   # 盖归属戳；读不到 token 就不盖 → 插件会忽略这份 live 退回 cache(宁可少实时也不串号)
        _awrite(p, obj)           # 原子写(修 L3)
    except Exception: pass
parts = []
if "five_hour" in data: parts.append(f"5h {int(round(data['five_hour']['utilization']))}%")
if "seven_day" in data: parts.append(f"周 {int(round(data['seven_day']['utilization']))}%")
sys.stdout.write(("◔ " + "  ·  ".join(parts)) if parts else "")
