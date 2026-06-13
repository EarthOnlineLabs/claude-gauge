#!/bin/bash
# Claude Code 用量刷新器（LaunchAgent 每 30 秒触发，脚本自适应决定是否真的 poll）
# ① token<20分钟过期 → 从 /tmp headless `claude -p` 续命(省 context 成本)
# ② 自适应节流：紧急45s / 需关注·活跃60s / 够用且静止240s（防 429）
# ③ 跨阈值(75%/90%)主动推送通知，每窗口每轮只通知一次
# ④ 原子写 cache.json，防插件读到半截
[ "$1" = "force" ] && export CQ_FORCE=1
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
/usr/bin/python3 <<'PY'
import json, subprocess, time, os, tempfile, urllib.request, datetime
CACHE=os.path.expanduser("~/.cache/claude-gauge/cache.json")
STATE=os.path.expanduser("~/.cache/claude-gauge/refresh-state.json")
def load(p,d):
    try: return json.load(open(p))
    except Exception: return d
def awrite(path,obj):
    dd=os.path.dirname(path); os.makedirs(dd,exist_ok=True)
    fd,tmp=tempfile.mkstemp(dir=dd)
    with os.fdopen(fd,"w") as f: json.dump(obj,f)
    os.replace(tmp,path)
def token():
    try:
        raw=subprocess.run(["/usr/bin/security","find-generic-password","-s","Claude Code-credentials","-w"],capture_output=True,text=True,timeout=5).stdout
        return json.loads(raw)["claudeAiOauth"]
    except Exception: return None
def lvl(u):
    if u is None: return 0
    if u>=90: return 2
    if u>=75: return 1
    return 0
def cd(v, weekly):
    try:
        if isinstance(v,(int,float)) or (isinstance(v,str) and str(v).replace('.','',1).isdigit()): s=float(v)-time.time()
        else:
            t=datetime.datetime.fromisoformat(str(v).replace("Z","+00:00"))
            if t.tzinfo is None: t=t.replace(tzinfo=datetime.timezone.utc)
            s=(t-datetime.datetime.now(datetime.timezone.utc)).total_seconds()
    except Exception: return ""
    if s<=0: return "马上"
    if weekly:
        tm=int(round(s/60)); d,r=divmod(tm,1440); h=r//60
        return (f"{d}天{h}时" if (d<3 and h) else f"{d}天") if d>=1 else (f"{r//60}小时" if r>=60 else f"{r}分钟")
    m=int(round(s/60))
    return (f"{m//60}小时{m%60}分" if m>=60 else f"{m}分钟")

st=load(STATE,{}); now=time.time()
# ① 续命（仅 token 快过期时；从 /tmp 跑省成本）
tk=token()
if tk and tk.get("expiresAt") and tk["expiresAt"]/1000 < now+1200:
    try:
        subprocess.run(["claude","-p","ok"],stdin=subprocess.DEVNULL,capture_output=True,timeout=75,cwd="/tmp")
        tk=token()
    except Exception: pass
# ② 节流：到点才 poll
lm=st.get("last_max_util"); chg=st.get("changed",False)
iv = 45 if (lm is not None and lm>=90) else (60 if (lm is not None and lm>=75) else (60 if chg else 240))
if os.environ.get("CQ_FORCE")!="1" and now-st.get("last_poll_ts",0) < iv: raise SystemExit(0)
if not tk or (tk.get("expiresAt") and tk["expiresAt"]/1000 < now): raise SystemExit(0)
# ③ poll
try:
    req=urllib.request.Request("https://api.anthropic.com/api/oauth/usage",headers={"Authorization":f"Bearer {tk['accessToken']}","anthropic-beta":"oauth-2025-04-20"})
    j=json.load(urllib.request.urlopen(req,timeout=10))
except Exception: raise SystemExit(0)
# ④ 原子写 cache
data={}
for k in ("five_hour","seven_day","seven_day_sonnet","seven_day_opus"):
    b=j.get(k)
    if b and b.get("utilization") is not None: data[k]={"utilization":float(b["utilization"]),"resets_at":b.get("resets_at")}
if j.get("extra_usage"): data["extra_usage"]=j["extra_usage"]
awrite(CACHE,{"ts":now,"data":data})
# ⑤ 变化检测 + 通知
u5=(j.get("five_hour") or {}).get("utilization"); u7=(j.get("seven_day") or {}).get("utilization")
p5,p7=st.get("last_5h"),st.get("last_7d")
chg_now = (u5 is not None and p5 is not None and abs(u5-p5)>=1) or (u7 is not None and p7 is not None and abs(u7-p7)>=1)
def notify(u,resets,key,label,weekly):
    cur=lvl(u); prev=st.get(key,0)
    if cur>prev and cur>=1:
        tag="⚠️ 紧急" if cur==2 else "需关注"; c=cd(resets,weekly)
        msg=f"{label}已用 {u:.0f}%" + (f"，约 {c}后重置" if c else "")
        try: subprocess.run(["osascript","-e",f'display notification "{msg}" with title "Claude Code 额度 · {tag}"'],capture_output=True,timeout=5)
        except Exception: pass
    st[key]=cur
notify(u5,(j.get("five_hour") or {}).get("resets_at"),"notified_5h","当前5小时额度",False)
notify(u7,(j.get("seven_day") or {}).get("resets_at"),"notified_7d","本周额度",True)
st.update({"last_poll_ts":now,"last_max_util":max([x for x in (u5,u7) if x is not None],default=None),"last_5h":u5,"last_7d":u7,"changed":chg_now})
awrite(STATE,st)
PY
