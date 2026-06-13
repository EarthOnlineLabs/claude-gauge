#!/bin/bash
# Claude Code 用量 — SwiftBar 插件。每 15 秒读 cache.json/live.json 渲染。
# 数据由后台刷新器(LaunchAgent)写入；本插件只渲染+兜底。不碰对话文件。
# 配色：够用=默认(黑/自适应)，需关注=橙，紧急=红，无绿色。进度条为主，倒计时为辅。
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
/usr/bin/python3 <<'PY'
import os, json, urllib.request, datetime, time, sys, subprocess
CACHE=os.path.expanduser("~/.cache/claude-gauge/cache.json")
LIVE =os.path.expanduser("~/.cache/claude-gauge/live.json")
os.makedirs(os.path.dirname(CACHE), exist_ok=True)
LOGO="gauge.with.needle"; STALE_SEC=900
WARN_TH,CRIT_TH=25.0,10.0
COL_WARN,COL_CRIT,COL_STALE="#e08a2b","#e0483d","#9a9a9a"
def _is_dark():
    try: return subprocess.run(["defaults","read","-g","AppleInterfaceStyle"],capture_output=True,text=True,timeout=2).stdout.strip()=="Dark"
    except Exception: return False
NORMAL = "#ededef" if _is_dark() else "#1d1d1f"
MUTE   = "#9a9aa0" if _is_dark() else "#8a8a8a"
MAXW,CD_CAP=11,"9h+"

def remain(b): return None if not b or b.get("utilization") is None else 100-float(b["utilization"])
def bar(used):
    f=max(0,min(10,round(used/10.0))); return "█"*f+"░"*(10-f)
def _secs_until(v):
    if v is None or v=="": return None
    try:
        if isinstance(v,(int,float)) or (isinstance(v,str) and v.replace('.','',1).isdigit()): return float(v)-time.time()
        s=str(v).strip().replace("Z","+00:00"); t=datetime.datetime.fromisoformat(s)
        if t.tzinfo is None: t=t.replace(tzinfo=datetime.timezone.utc)
        return (t-datetime.datetime.now(datetime.timezone.utc)).total_seconds()
    except Exception: return None
def _cd5(v):
    s=_secs_until(v)
    if s is None: return ""
    if s<=0: return "0m"
    if s>=36000: return CD_CAP
    m=int(round(s/60.0))
    if m>=60: h,mm=divmod(m,60); return f"{h}h{mm:02d}m"
    return f"{m}m"
def _cd7(v):
    s=_secs_until(v)
    if s is None: return ""
    if s<=0: return "0m"
    tm=int(round(s/60.0)); days,rem=divmod(tm,1440); hrs=rem//60
    if days>=1: return f"{days}d{hrs}h" if (days<3 and hrs>0) else f"{days}d"
    if rem>=60: return f"{rem//60}h"
    return f"{rem}m"
def _lvl(p):
    if p is None: return None
    if p<=CRIT_TH: return 2
    if p<=WARN_TH: return 1
    return 0
def _w(s): return sum(2 if ord(c)>0x2E80 else 1 for c in s)
def _used(rem): return None if rem is None else min(100,max(0,int(round(100-rem))))
def scol(rem):
    l=_lvl(rem)
    if l==2: return f" color={COL_CRIT}"
    if l==1: return f" color={COL_WARN}"
    return f" color={NORMAL}"

def title_line(fh,wk,d,stale=False):
    d=d if isinstance(d,dict) else {}
    if fh is None and wk is None: return f"额度⚠ | color={COL_WARN}"
    u5,u7=_used(fh),_used(wk); fl,wl=_lvl(fh),_lvl(wk)
    fr=(d.get("five_hour") or {}).get("resets_at"); wr=(d.get("seven_day") or {}).get("resets_at")
    ex=d.get("extra_usage") or {}
    spending=bool(ex.get("is_enabled")) and float(ex.get("used_credits") or 0)>0
    def s5(a): return f"{u5}% {_cd5(fr)}".rstrip() if a else f"{u5}%"
    def s7(a): return f"W{u7}% {_cd7(wr)}".rstrip() if a else f"W{u7}%"
    if fl in (0,None) and wl in (0,None):
        text,col=(f"W{u7}%" if fl is None and wl is not None else f"{u5}%"),None
    elif wl in (0,None): text,col=s5(True),(COL_CRIT if fl==2 else COL_WARN)
    elif fl in (0,None): text,col=s7(True),(COL_CRIT if wl==2 else COL_WARN)
    else:
        if wl==2 or wl>fl: text,col=s7(True),(COL_CRIT if wl==2 else COL_WARN)
        else:              text,col=s5(True),(COL_CRIT if fl==2 else COL_WARN)
    if spending and col is None and _w(f"{text}+$")<=MAXW: text=f"{text}+$"
    if stale: return f"{text}~ | color={COL_STALE}"
    if col is None: return f"{text} | sfimage={LOGO}"
    return f"{text} | color={col}"

def section(label, icon, u, cd_str, col):
    print(f"{label} | sfimage={icon} size=12 color={NORMAL}")                       # 标签：默认色(清晰)
    print(f"已用 {u}%　·　还剩 {100-u}% | size=14{col}")              # 数字：默认/橙/红
    print(f"{bar(u)} | font=Menlo size=15{col}")                     # 进度条：放大(主信息)
    if cd_str: print(f"{cd_str} 后重置 | size=11 color={MUTE}")      # 倒计时：小灰(辅信息)

def render(d,ts):
    age=time.time()-ts; stale=age>STALE_SEC
    fh,wk=remain(d.get("five_hour")),remain(d.get("seven_day"))
    son=remain(d.get("seven_day_sonnet")); opus=remain(d.get("seven_day_opus"))
    print(title_line(fh,wk,d,stale))
    print("---")
    print(f"Claude Code 用量 | sfimage={LOGO} color={NORMAL}")                      # 标题：默认色(清晰)
    if stale:
        print("---")
        print(f"⚠️ 数据已 {int(age//60)} 分钟未更新 | color={COL_WARN}")
        print(f"闲置/限流；用一下 Claude Code 即刷新 | size=11 color={MUTE}")
    print("---")
    if fh is not None: section("当前 5 小时 · session","clock",_used(fh),_cd5((d.get('five_hour') or {}).get('resets_at')),scol(fh))
    if wk is not None: section("本周 · 7 天","calendar",_used(wk),_cd7((d.get('seven_day') or {}).get('resets_at')),scol(wk))
    extras=[]
    if son is not None: extras.append(f"Sonnet {_used(son)}%")
    if opus is not None: extras.append(f"Opus {_used(opus)}%")
    if extras: print("---"); print("按模型（本周）　"+" · ".join(extras)+f" | size=11 color={MUTE}")
    print("---")
    upd=datetime.datetime.fromtimestamp(ts).strftime("%H:%M")
    print((f"更新于 {upd}（{int(age//60)}分钟前）" if age>=60 else f"更新于 {upd}（刚刚）")+f" | size=11 color={MUTE}")
    home=os.path.expanduser("~"); print(f"立即刷新（强制拉最新）| shell={home}/.claude/claude-gauge-refresh.sh | param0=force | terminal=false | refresh=true | sfimage=arrow.clockwise")

def load(p):
    try:
        c=json.load(open(p)); return c if ("ts" in c and "data" in c) else None
    except Exception: return None
def read_token():
    try:
        raw=subprocess.run(["/usr/bin/security","find-generic-password","-s","Claude Code-credentials","-w"],capture_output=True,text=True,timeout=5).stdout
        if not raw:
            fp=os.path.expanduser("~/.claude/.credentials.json")
            if os.path.exists(fp): raw=open(fp).read()
        return json.loads(raw)["claudeAiOauth"]
    except Exception: return None

best=None
for c in (load(LIVE),load(CACHE)):
    if c and (best is None or c["ts"]>best["ts"]): best=c
if (best is None) or (time.time()-best["ts"]>150):   # 兜底：后台失效才自己拉
    tk=read_token()
    if tk and ((tk.get("expiresAt") is None) or (tk["expiresAt"]/1000>time.time()+30)):
        try:
            req=urllib.request.Request("https://api.anthropic.com/api/oauth/usage",headers={"Authorization":f"Bearer {tk['accessToken']}","anthropic-beta":"oauth-2025-04-20"})
            with urllib.request.urlopen(req,timeout=8) as r: d=json.load(r)
            obj={"ts":time.time(),"data":d}; json.dump(obj,open(CACHE,"w")); best=obj
        except Exception: pass
if best is None:
    print(f"额度⚠ | color={COL_WARN}"); print("---"); print("新开一个 Claude Code 会话发条消息即恢复实时 | size=12")
    print("---"); print("立即刷新 | refresh=true")
else:
    render(best["data"],best["ts"])
PY
