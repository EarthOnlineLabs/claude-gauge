#!/bin/bash
# Claude Code 用量 — SwiftBar 插件。每 15 秒读 cache.json/live.json 渲染。
# 数据由后台刷新器(LaunchAgent)写入；本插件只渲染+兜底。不碰对话文件。
# 配色：够用=默认(黑/自适应)，需关注=橙，紧急=红，无绿色。进度条为主，倒计时为辅。
# SwiftBar 元数据：隐藏宿主自动追加的页脚项（上次更新/命令行运行/停用插件/关于/SwiftBar 子菜单），
# 让下拉干净收尾在「立即刷新」，与落地页样图一致。这些只是宿主噪音，不影响任何渲染逻辑。
# <swiftbar.hideLastUpdated>true</swiftbar.hideLastUpdated>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideSwiftBar>true</swiftbar.hideSwiftBar>
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
/usr/bin/python3 <<'PY'
import os, json, urllib.request, datetime, time, sys, subprocess, tempfile
CACHE=os.path.expanduser("~/.cache/claude-gauge/cache.json")
LIVE =os.path.expanduser("~/.cache/claude-gauge/live.json")
ATTN =os.path.expanduser("~/.cache/claude-gauge/attention.json")   # 完成提醒层：未读事件（默认开；旧装/异常时可能没有→分支短路）
ACK  =os.path.expanduser("~/.cache/claude-gauge/ack.json")          # 完成提醒层：已读标记
os.makedirs(os.path.dirname(CACHE), exist_ok=True)
STALE_SEC=900
CLAUDE_BUNDLE="com.anthropic.claudefordesktop"                      # 点击拉起 / 自动熄灭判定的目标 App
ALERT=os.path.expanduser("~/.claude/claude-gauge-alert.py")         # 左键点击动作脚本
SEEN =os.path.expanduser("~/.cache/claude-gauge/seen.json")        # ① Claude 最近在用时间戳（随 Claude 显隐 + linger 余韵）
LINGER=120                                                          # ① Claude 退出后仍显示的秒数；抹平连续一次性命令的闪烁；设 0 = 退出即隐
def _atomic(path,obj):
    try:
        d=os.path.dirname(path); os.makedirs(d,exist_ok=True)
        fd,tmp=tempfile.mkstemp(dir=d)
        with os.fdopen(fd,"w") as f: json.dump(obj,f)
        os.replace(tmp,path)
    except Exception: pass
def _claude_running():
    """桌面端在跑 或 有 claude 命令行会话存活。仅查进程/App，绝不读对话/代码/凭证。"""
    for cmd in (["/usr/bin/lsappinfo","find","bundleID="+CLAUDE_BUNDLE],["/usr/bin/pgrep","-x","claude"]):
        try:
            if subprocess.run(cmd,capture_output=True,text=True,timeout=2).stdout.strip(): return True
        except Exception: pass
    return False
def _active():
    """Claude 在用：此刻在跑（刷新 last_seen），或仍在 linger 窗口内。"""
    now=time.time()
    if _claude_running(): _atomic(SEEN,{"ts":now}); return True
    try: return (now-float((json.load(open(SEEN)) or {}).get("ts",0))) < LINGER
    except Exception: return False
# ① Claude 没在用 → 输出空 → SwiftBar 隐藏菜单栏项（正常路径不碰网络）
if not _active(): raise SystemExit(0)
# 菜单栏图标 = 新品牌 logo 的分段光谱仪表盘（与落地页/favicon 同形）。实测当前 macOS+SwiftBar：
# templateImage 与 image= 均【无容器框】——常态(OK)用 templateImage 单色蒙版、自动随真实菜单栏深浅变黑/白；
# 橙/红/灰/彩虹用 image= 全彩位图（这些颜色本就恒显、不需随栏自适应）。全部 base64 内嵌，运行期零依赖。
# 重新生成：bash alert/build-menubar-icons.sh（从 docs/logo.svg 渲染，把下面 5 个 base64 粘回）。
ICON_SZ="width=21 height=17"
ICON_OK="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"
ICON_WARN="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"
ICON_CRIT="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"
ICON_STALE="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"
ICON_RAINBOW="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"
WARN_TH,CRIT_TH=25.0,10.0
# 配色取 DesignOnline token 实测值：warning=amber-700 / danger=red-700 / 过期=text-subtle(ink-500)。
COL_WARN,COL_CRIT,COL_STALE="#C2902E","#C0492B","#9CA0A2"
def _is_dark():
    try: return subprocess.run(["defaults","read","-g","AppleInterfaceStyle"],capture_output=True,text=True,timeout=2).stdout.strip()=="Dark"
    except Exception: return False
# 浅色取 DS token（text-default=ink-900 / text-subtle=ink-500）；深色保留菜单栏自适应近白/灰。
NORMAL = "#ededef" if _is_dark() else "#1B1B1B"
MUTE   = "#9a9aa0" if _is_dark() else "#9CA0A2"
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

# ---- 完成提醒层（默认开）：无 attention.json 时（旧装/异常/已关）_armed 恒 False、渲染与无此层逐字节一致 ----
def _loadj(p):
    try: return json.load(open(p))
    except Exception: return None
def _front_bundle():
    """当前前台 App 的 bundle id；仅用 lsappinfo（不弹辅助功能/自动化授权框）。取不到→None。"""
    try:
        asn=subprocess.run(["/usr/bin/lsappinfo","front"],capture_output=True,text=True,timeout=2).stdout.strip()
        if not asn: return None
        out=subprocess.run(["/usr/bin/lsappinfo","info","-only","bundleID",asn],capture_output=True,text=True,timeout=2).stdout
        if "=" in out:
            v=out.split("=",1)[1].strip().strip('"').strip()   # 形如 "CFBundleIdentifier"="com.…"
            if v and v!="NULL" and "." in v: return v
        return None
    except Exception: return None
def _awrite_ack(ts):
    try:
        dd=os.path.dirname(ACK); os.makedirs(dd,exist_ok=True)
        fd,tmp=tempfile.mkstemp(dir=dd)
        with os.fdopen(fd,"w") as f: json.dump({"ts":ts},f)
        os.replace(tmp,ACK)
    except Exception: pass
def _ts(x):
    try: return float(x or 0)
    except Exception: return 0.0
AWAY_SEC=90.0   # 完成那刻「已空闲 ≥ 此秒数」才算你真的离开了；只是切了下窗口/还在用电脑(空闲≈0)→ 不点亮
def _armed():
    """有未读完成/需关注事件，且事件发生时你确实离开了（不在载体前台 且 已空闲）→ 点亮彩虹。"""
    att=_loadj(ATTN)
    if not att or "ts" not in att: return False
    if att.get("front")==(att.get("host") or CLAUDE_BUNDLE): return False   # 触发时你已在会话载体(终端/桌面)前台 → 不点亮
    if _ts(att.get("idle")) < AWAY_SEC: return False                        # 触发时你还在用电脑(没空闲) → 你没离开，只是切了下窗 → 不点亮
    return _ts(att.get("ts")) > _ts((_loadj(ACK) or {}).get("ts"))

def title_line(fh,wk,d,stale=False,armed=False):
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
    if armed:
        act=f"image={ICON_RAINBOW} {ICON_SZ} bash=/usr/bin/python3 param0={ALERT} param1=open terminal=false"
        if stale:       return f"{text}~ | color={COL_STALE} {act}"
        if col is None: return f"{text} | {act}"                   # 够用态：不写 color，用菜单栏自适应色（深色壁纸下自动白字，别强制成黑）
        return f"{text} | color={col} {act}"                       # 数字额度色（橙/红，本就该恒定显色），图标彩虹
    if stale: return f"{text}~ | color={COL_STALE} image={ICON_STALE} {ICON_SZ}"
    if col is None: return f"{text} | templateImage={ICON_OK} {ICON_SZ}"   # 够用态：单色蒙版，自动随真实菜单栏深浅变黑/白（无框）
    return f"{text} | color={col} image={ICON_CRIT if col==COL_CRIT else ICON_WARN} {ICON_SZ}"

def section(label, icon, u, cd_str, col):
    print(f"{label} | sfimage={icon} size=12 color={NORMAL}")                       # 标签：默认色(清晰)
    print(f"已用 {u}%　·　还剩 {100-u}% | size=14{col}")              # 数字：默认/橙/红
    print(f"{bar(u)} | font=Menlo size=15{col}")                     # 进度条：放大(主信息)
    if cd_str: print(f"{cd_str} 后重置 | size=11 color={MUTE}")      # 倒计时：小灰(辅信息)

def render(d,ts):
    age=time.time()-ts; stale=age>STALE_SEC
    fh,wk=remain(d.get("five_hour")),remain(d.get("seven_day"))
    son=remain(d.get("seven_day_sonnet")); opus=remain(d.get("seven_day_opus"))
    # 完成提醒层：仅当装了该层(有 attention.json)才做前台检测；未装则零开销、输出同今天。
    att=_loadj(ATTN)
    if att and _front_bundle()==(att.get("host") or CLAUDE_BUNDLE):          # 回到会话载体(终端/桌面)前台 → 标记已读（≤15s 自动熄灭）
        if _ts(att.get("ts")) > _ts((_loadj(ACK) or {}).get("ts")): _awrite_ack(time.time())
    print(title_line(fh,wk,d,stale,_armed() if att else False))
    print("---")
    print(f"Claude Code 用量 | color={NORMAL}")                                     # 标题（gauge 图标按用户要求移除，下拉头不再重复）
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
    un=f"{home}/.claude/claude-gauge-uninstall.sh"                    # ② 菜单卸载入口（装了稳定卸载脚本才显示，子菜单收纳、不污染主下拉）
    if os.path.exists(un):
        print("---"); print(f"管理 | size=11 color={MUTE}")
        print(f"--卸载 ClaudeGauge… | shell=/bin/bash | param0={un} | terminal=true | sfimage=trash")

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
