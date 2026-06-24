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
import json, subprocess, time, os, tempfile, urllib.request, urllib.error
CACHE=os.path.expanduser("~/.cache/claude-gauge/cache.json")
STATE=os.path.expanduser("~/.cache/claude-gauge/refresh-state.json")
ORG_CACHE=os.path.expanduser("~/.cache/claude-gauge/org.json")
CLIENT_ID="9d1c250a-e61b-44d9-88ed-5944d1962f5e"
TOKEN_URL="https://platform.claude.com/v1/oauth/token"
UA="claude-cli/1.0.119 (external, cli)"
SEC="/usr/bin/security"; SERVICE="Claude Code-credentials"
# ① Claude 没在用（非强制）→ 不轮询、不续命、直接退出（菜单栏侧自行隐藏）。仅查进程/App，不读内容。
def _claude_running():
    for cmd in (["/usr/bin/lsappinfo","find","bundleID=com.anthropic.claudefordesktop"],["/usr/bin/pgrep","-x","claude"]):
        try:
            if subprocess.run(cmd,capture_output=True,text=True,timeout=2).stdout.strip(): return True
        except Exception: pass
    return False
if os.environ.get("CQ_FORCE")!="1" and os.environ.get("CQ_REFRESH")!="1" and not _claude_running():
    raise SystemExit(0)

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
    """零额度续命：refresh_token 换新 access_token，原地写回钥匙串（只改3字段，保留其余）。
    返回 (新 claudeAiOauth 或 None, 是否 invalid_grant)。invalid_grant=钥匙串里的 RT 已被服务端作废，
    续命无解、唯有用户在 CC 里 /login 重新登录能救 —— 用于点亮诚实失败态，区别于网络抖动（后者不算 dead）。"""
    try:
        rt=blob["claudeAiOauth"]["refreshToken"]
        body=json.dumps({"grant_type":"refresh_token","refresh_token":rt,"client_id":CLIENT_ID}).encode()
        req=urllib.request.Request(TOKEN_URL,data=body,headers={"Content-Type":"application/json","User-Agent":UA,"Accept":"application/json"},method="POST")
        r=json.load(urllib.request.urlopen(req,timeout=20))
        at=r.get("access_token")
        if not at: return None,False
        nb=json.loads(json.dumps(blob))
        nb["claudeAiOauth"]["accessToken"]=at
        if r.get("refresh_token"): nb["claudeAiOauth"]["refreshToken"]=r["refresh_token"]
        nb["claudeAiOauth"]["expiresAt"]=int(time.time()*1000)+(r.get("expires_in") or 28800)*1000
        w=subprocess.run([SEC,"add-generic-password","-U","-s",SERVICE,"-a",kc_account(),"-w",json.dumps(nb,separators=(',',':'))],capture_output=True,text=True,timeout=10)
        if w.returncode!=0: return None,False
        return nb["claudeAiOauth"],False
    except urllib.error.HTTPError as e:
        try: dead = (e.code==400 and "invalid_grant" in e.read().decode("utf-8","replace"))
        except Exception: dead=False
        return None,dead
    except Exception: return None,False

st=load(STATE,{}); now=time.time()
blob=kc_read()
tk=blob.get("claudeAiOauth") if blob else None
auth_dead=bool(st.get("auth_dead"))
# ① 续命：仅临近过期(≤60s)或被强制时（纯鉴权，零额度，不与活跃 CC 抢轮换）
if blob and tk and tk.get("expiresAt") and (os.environ.get("CQ_REFRESH")=="1" or tk["expiresAt"]/1000 < now+60):
    new,dead=refresh_oauth(blob)
    if new: tk=new; auth_dead=False
    elif dead: auth_dead=True
# 续命被服务端拒（RT 失效）→ 立刻持久化诚实失败态供菜单栏提示 /login（早于节流/退出；恢复时由成功 poll 收尾清零）
if auth_dead != bool(st.get("auth_dead")):
    st["auth_dead"]=auth_dead; st["auth_dead_ts"]=now; awrite(STATE,st)
# ② 节流：到点才 poll
lm=st.get("last_max_util"); chg=st.get("changed",False)
iv = 45 if (lm is not None and lm>=90) else (60 if (lm is not None and lm>=75) else (60 if chg else 240))
if os.environ.get("CQ_FORCE")!="1" and os.environ.get("CQ_REFRESH")!="1" and now-st.get("last_poll_ts",0) < iv: raise SystemExit(0)
if not tk or (tk.get("expiresAt") and tk["expiresAt"]/1000 < now): raise SystemExit(0)
# ②b 解析组织 UUID（多组织用户的用量 API 需要显式指定，否则可能返回错误组织的数据）
def get_org_uuid(access_token):
    cached=load(ORG_CACHE,{})
    if "ts" in cached and now - cached.get("ts",0) < 86400: return cached.get("uuid")
    try:
        req=urllib.request.Request("https://api.anthropic.com/api/claude_cli/bootstrap",headers={"Authorization":f"Bearer {access_token}","anthropic-beta":"oauth-2025-04-20"})
        bs=json.load(urllib.request.urlopen(req,timeout=10))
        uuid=(bs.get("oauth_account") or {}).get("organization_uuid") or None
        awrite(ORG_CACHE,{"uuid":uuid,"ts":now})
        return uuid
    except Exception: return cached.get("uuid")
org_uuid=get_org_uuid(tk["accessToken"])
# ③ poll
try:
    hdrs={"Authorization":f"Bearer {tk['accessToken']}","anthropic-beta":"oauth-2025-04-20"}
    if org_uuid: hdrs["x-organization-uuid"]=org_uuid
    req=urllib.request.Request("https://api.anthropic.com/api/oauth/usage",headers=hdrs)
    j=json.load(urllib.request.urlopen(req,timeout=10))
except Exception: raise SystemExit(0)
# ④ 原子写 cache（优先 limits 数组——官方页面数据源；fallback 旧字段兼容）
data={}
lim={e["kind"]:e for e in (j.get("limits") or []) if "kind" in e}
def _pick(lim_kind, legacy_key, scope_model=None):
    le=lim.get(lim_kind)
    if le and le.get("percent") is not None: return {"utilization":float(le["percent"]),"resets_at":le.get("resets_at")}
    b=j.get(legacy_key)
    if b and b.get("utilization") is not None: return {"utilization":float(b["utilization"]),"resets_at":b.get("resets_at")}
    return None
for lk,dk in [("session","five_hour"),("weekly_all","seven_day")]:
    v=_pick(lk,dk);
    if v: data[dk]=v
for e in (j.get("limits") or []):
    if e.get("kind")=="weekly_scoped" and e.get("percent") is not None:
        mn=((e.get("scope") or {}).get("model") or {}).get("display_name","").lower()
        if mn=="sonnet": data["seven_day_sonnet"]={"utilization":float(e["percent"]),"resets_at":e.get("resets_at")}
        elif mn=="opus": data["seven_day_opus"]={"utilization":float(e["percent"]),"resets_at":e.get("resets_at")}
if not data.get("seven_day_sonnet"):
    v=_pick(None,"seven_day_sonnet");
    if v: data["seven_day_sonnet"]=v
if not data.get("seven_day_opus"):
    v=_pick(None,"seven_day_opus");
    if v: data["seven_day_opus"]=v
if j.get("extra_usage"): data["extra_usage"]=j["extra_usage"]
awrite(CACHE,{"ts":now,"data":data})
# ⑤ 变化检测（喂给自适应节流，决定下次多快再 poll）
u5=(data.get("five_hour") or {}).get("utilization"); u7=(data.get("seven_day") or {}).get("utilization")
p5,p7=st.get("last_5h"),st.get("last_7d")
chg_now = (u5 is not None and p5 is not None and abs(u5-p5)>=1) or (u7 is not None and p7 is not None and abs(u7-p7)>=1)
st.update({"last_poll_ts":now,"last_max_util":max([x for x in (u5,u7) if x is not None],default=None),"last_5h":u5,"last_7d":u7,"changed":chg_now,"auth_dead":False})
awrite(STATE,st)
PY
