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
ATTN =os.path.expanduser("~/.cache/claude-gauge/attention.json")   # 完成提醒层：未读事件（装了可选层才有）
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
ICON_STALE="iVBORw0KGgoAAAANSUhEUgAAADEAAAAoCAYAAABXRRJPAAAABmJLR0QA/wD/AP+gvaeTAAAFb0lEQVRYhe1ZbYhUVRh+3uNc2tUtZw0xZv2hRBjq9kVIYCAWglSEGS3Vxlrj3HtlhaEgYasfXkjSpLY/zua5s7uSWxkbVuYaIVSSmKFpUYZFYkQhlZK2rrLj7py3H84O556Z2Zm5O5sFPv/O+3We55xzz8cMcBX/DVCtCnV3dy/MZrP3CCGamXkegBiABgAWM58jorMAfgLwvVLqcyI66LruSC36npAI3/eXAGgFcB+ApirThwB8LIQYWL16dR8RqbA8QonIjXofEd0WtmMdzPw3EbU5jvNhmPyqREgppxLRBgBJAFPCdFgGe4UQTiKR+KWapIpFSCmbiWgngJvGCTtORPuY+ZhS6mQkEjkPYEQpdR2A2QBuBrAYwF0AIiVqDAGwHcd5p1JuFYmQUq4goj5c/lBNjDLz+5ZldcTj8ZOV1Nu2bVs0m80mlVLrStRkAJts236BiLhcvbIipJSPENHbKBy5IWZ+sb6+PtXW1nahEvIFTJmpu7v7IWbeDODGIiFbbNtOlhMyroitW7cuF0LsRqGAfUKIJ6tdu6UgpZwqhNjIzMkCgkSbbNt+brz8kiJ6enrmZbPZLwFEDdeWU6dOPeN53mg4yqXh+34rgB4A12hmJqJW27Z3lMorKsLzvEgsFjsMwNxCNzqO8/yE2Y4DKeX9uQ1EF3KBiJpt2/65WI4oZozFYutQKKBnsgUAgOu6e5g5bpinMbPPzEUHvcCYTqdnMfNJAFM18+FoNHp3S0vLpRryBQBs3759WiaT8Zl5GYDNjuO8AgBSyteI6OkAWaIVtm3vMmsUzIRSqgNBAZeEEPHJENDb2ztzeHj4U2Z+HMBMAC/19/dPAYBMJtMB4LjBbYPneQWcA4ZUKtUghLCNmNcTicSx2tIH0un03NHR0QMAFmnmIy0tLVkASCaTGQAdeg4RLWxqarrXrBUQYVnWemaeppmGR0ZGNtWO+mVIKZuZeT+Cp/+hSCTyoB5n2/ZuAEd0m1Kq06xnTk2b0T66du3a3yfAtwBSyqVEtB/BW+8AMy+Nx+On9djcIddn2BZ2dnbW67a8iJxjhu5k5g9qRR4A0un0SiL6CMB0jdQbzLzSdd2LxXKY+S3T1tDQsFhvC82xCMGTeRRAaqLExyClTDLzuwDqNPPLiUTiqfEeR67rnmHmrw3zEr2RJ83M84kCO+6hUqNTCdLp9Cyl1HIhRAMzzwfQrrmzAJKO43Q5jlO2FhHtBnC7zlX3R7TAeUbucYSE7/tLmPk9IprBXHB3ywBocxynv9J6RPSDXsfkqs/E9fpMMPNvVXIHAEgpLQBvwvi+cjUHhRAP2La9v5qaSqlfjVUSqJ3/JojoWiP3fDUdjSE31bOL+YQQ6WoF5GqaXAJc9S028FAXQhS9V1WAkt9R7jpTNYjIfAoHuWqBg0bgdISA67onYBxQOQwJIfaEqVluleRFMPMfuoOZ54TskIUQjwL4RjOfAfDYBB5Rcw1uf+ptfcn8aAQGtrFqkEgkTkSj0TuJ6FYAi+vq6uY4jjMQth6ABXpDCBHYOfXD7TvdQUS3dHV1Nba3t58N02vuIvdtmNwiCBxuSqkA1/xMRKPRowDOab4plmUtrxGJ0EilUjcAuMMwf6Y38iJyI/eJ7mTmVZPGrkJYlvUEgj/U/dXY2PiVHmNuo+Zla5nv+wtwhZA7OPXrCph5x9ibYwzCCBgAoO9SgojWTxrL8lgFY2cC0GsGBUS4rjtCRK/qNmZead7f/y0QUath2uu67lEzrtgbO0VE+YcQEZ0eHBzMTALHsjDub6yU8orFFYhwXfeiUmoFgAMAvmDmhz3PC/3fwUQghHgWwE5mPgbAXbNmzcErweMqruL/hn8AioAFs/0YXAoAAAAASUVORK5CYII="
ICON_RAINBOW="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"
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

# ---- 完成提醒层（可选）：未装时 attention.json 不存在 → _armed 恒 False、渲染与今天逐字节一致 ----
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
def _armed():
    """有未读完成/需关注事件，且事件发生时你不在 Claude 前台 → 点亮彩虹。"""
    att=_loadj(ATTN)
    if not att or "ts" not in att: return False
    if att.get("front")==(att.get("host") or CLAUDE_BUNDLE): return False   # 触发时你已在会话载体(终端/桌面)前台 → 不点亮
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
