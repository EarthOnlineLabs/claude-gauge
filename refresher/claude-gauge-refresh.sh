#!/bin/bash
# Claude Code 用量刷新器（LaunchAgent 每 30 秒触发，脚本自适应决定是否真的 poll）
# ① 续命：token 临近过期(≤60s)时走 OAuth refresh_token 换新 —— 纯鉴权调用，零额度消耗。
#    只在临近过期才换：活跃使用时 CC 会提前 5 分钟自刷新，永远轮不到我们 → 不与 CC 抢轮换。
#    换新时只改 claudeAiOauth 三字段，完整保留 mcpOAuth 等其余内容，绝不把你登出。
# ② 自适应节流：紧急45s / 需关注·活跃60s / 够用且静止240s（防 429）
# ③ 原子写 cache.json，防插件读到半截
[ "$1" = "force" ] && export CQ_FORCE=1
[ "$1" = "refresh" ] && export CQ_REFRESH=1
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
/usr/bin/python3 <<'PY'
import json, subprocess, time, os, tempfile, urllib.request
CACHE=os.path.expanduser("~/.cache/claude-gauge/cache.json")
STATE=os.path.expanduser("~/.cache/claude-gauge/refresh-state.json")
CLIENT_ID="9d1c250a-e61b-44d9-88ed-5944d1962f5e"
TOKEN_URL="https://platform.claude.com/v1/oauth/token"
UA="claude-cli/1.0.119 (external, cli)"
SEC="/usr/bin/security"; SERVICE="Claude Code-credentials"

def load(p,d):
    try: return json.load(open(p))
    except Exception: return d
def awrite(path,obj):
    dd=os.path.dirname(path); os.makedirs(dd,exist_ok=True)
    fd,tmp=tempfile.mkstemp(dir=dd)
    with os.fdopen(fd,"w") as f: json.dump(obj,f)
    os.replace(tmp,path)
def kc_read():
    """钥匙串完整 blob（含 mcpOAuth），失败 None"""
    try:
        raw=subprocess.run([SEC,"find-generic-password","-s",SERVICE,"-w"],capture_output=True,text=True,timeout=5).stdout
        return json.loads(raw)
    except Exception: return None
def kc_account():
    try:
        out=subprocess.run([SEC,"find-generic-password","-s",SERVICE],capture_output=True,text=True,timeout=5).stdout
        for ln in out.splitlines():
            ln=ln.strip()
            if ln.startswith('"acct"'): return ln.split('=',1)[1].strip().strip('"')
    except Exception: pass
    return os.environ.get("USER","")
def refresh_oauth(blob):
    """零额度续命：refresh_token 换新 access_token，原地写回钥匙串（只改3字段，保留其余）。返回新 claudeAiOauth 或 None"""
    try:
        rt=blob["claudeAiOauth"]["refreshToken"]
        body=json.dumps({"grant_type":"refresh_token","refresh_token":rt,"client_id":CLIENT_ID}).encode()
        req=urllib.request.Request(TOKEN_URL,data=body,headers={"Content-Type":"application/json","User-Agent":UA,"Accept":"application/json"},method="POST")
        r=json.load(urllib.request.urlopen(req,timeout=20))
        at=r.get("access_token")
        if not at: return None
        nb=json.loads(json.dumps(blob))
        nb["claudeAiOauth"]["accessToken"]=at
        if r.get("refresh_token"): nb["claudeAiOauth"]["refreshToken"]=r["refresh_token"]
        nb["claudeAiOauth"]["expiresAt"]=int(time.time()*1000)+(r.get("expires_in") or 28800)*1000
        w=subprocess.run([SEC,"add-generic-password","-U","-s",SERVICE,"-a",kc_account(),"-w",json.dumps(nb,separators=(',',':'))],capture_output=True,text=True,timeout=10)
        if w.returncode!=0: return None
        return nb["claudeAiOauth"]
    except Exception: return None

st=load(STATE,{}); now=time.time()
blob=kc_read()
tk=blob.get("claudeAiOauth") if blob else None
# ① 续命：仅临近过期(≤60s)或被强制时（纯鉴权，零额度，不与活跃 CC 抢轮换）
if blob and tk and tk.get("expiresAt") and (os.environ.get("CQ_REFRESH")=="1" or tk["expiresAt"]/1000 < now+60):
    new=refresh_oauth(blob)
    if new: tk=new
# ② 节流：到点才 poll
lm=st.get("last_max_util"); chg=st.get("changed",False)
iv = 45 if (lm is not None and lm>=90) else (60 if (lm is not None and lm>=75) else (60 if chg else 240))
if os.environ.get("CQ_FORCE")!="1" and os.environ.get("CQ_REFRESH")!="1" and now-st.get("last_poll_ts",0) < iv: raise SystemExit(0)
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
# ⑤ 变化检测（喂给自适应节流，决定下次多快再 poll）
u5=(j.get("five_hour") or {}).get("utilization"); u7=(j.get("seven_day") or {}).get("utilization")
p5,p7=st.get("last_5h"),st.get("last_7d")
chg_now = (u5 is not None and p5 is not None and abs(u5-p5)>=1) or (u7 is not None and p7 is not None and abs(u7-p7)>=1)
st.update({"last_poll_ts":now,"last_max_util":max([x for x in (u5,u7) if x is not None],default=None),"last_5h":u5,"last_7d":u7,"changed":chg_now})
awrite(STATE,st)
PY
