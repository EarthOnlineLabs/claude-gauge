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
import os, json, urllib.request, urllib.error, datetime, time, sys, subprocess, tempfile
CACHE=os.path.expanduser("~/.cache/claude-gauge/cache.json")
LIVE =os.path.expanduser("~/.cache/claude-gauge/live.json")
ATTN =os.path.expanduser("~/.cache/claude-gauge/attention.json")   # 完成提醒层：未读事件（默认开；旧装/异常时可能没有→分支短路）
ACK  =os.path.expanduser("~/.cache/claude-gauge/ack.json")          # 完成提醒层：已读标记
STATE=os.path.expanduser("~/.cache/claude-gauge/refresh-state.json")# 数据层状态：含 auth_dead（续命被服务端 invalid_grant 拒 → 钥匙串令牌失效，需 /login）
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
# 重新生成：bash alert/build-menubar-icons.sh（从落地页 GaugeMark 半圆表盘形状渲染，把下面 5 个 base64 粘回）。
ICON_SZ="width=18 height=18"
ICON_OK="iVBORw0KGgoAAAANSUhEUgAAACQAAAAkCAYAAADhAJiYAAAABmJLR0QA/wD/AP+gvaeTAAAC9UlEQVRYhe2WT0hUURTGv3OdcUZTk2mmx7w7KlFtGgppFwVGuAn7h1QILWrjom1ERNQmKGpju6RdhiAEhdBGCaGgCAKDwmljaMqb55+GcbJF42vmnhaNcp3GmadltHgfvMX5ON+5v/PgPh7gyZMnT57+b9FGg83NzXGl1EGlVJSITABgZlsIMZPL5V7Nzs5+3HQg0zTDRHQJwBkAuyq0jwN4TEQ9lmWl/ypQPB6vzmQylwFcAbDV7fCCMkR0xzCMntHR0R9/DGQYxnafz/cEwKHfwkSLAMaZ2S7UJoDdzNxQYtRLZj5t23Zqw0BNTU07lVIjAFo0WzHzAIC+aDT6onjreDxevbCw0AbgAhF1ARDaApNCiPbp6emJdQOFQqGG2traN8y8R7PfElG3ZVkfyi0CAOFwuD4YDL5n5h26z8wJx3EOpFKpb6VyopQJADU1Nf06DBEN+P3+NjcwACgQCDwshinMiQeDwUdrBkuZUspjAJ4t18w8bNt2B4C8CxhIKa8BuKVZIwCyADo0sKOWZQ0VZ0u9oSoAt7X6czabPesWxjTNdgA3NWuKmbsCgcA5ANPLJjPfLXX+b4ZpmkcA7F2uieh6Op1edAMTjUZbiGgAv5YCgO/M3GnbdmpiYuIrgBta+77CWeWBiOiUVn6yLGvADUwsFqsRQjwFENbsi7Ztv1sukslkP4CVGyaEOFkRCMBxDW4QgHIDxMy9APZr1r1kMtlX1KYADGqZE2WBDMPYAqBpJa3U80ogsVisW0o5D+C8Zr9ubGy8WqqfiPSZzaZp1q4J5Pf7zaL8VAWYNmZ+ACCi2V9yuVxnIpFwSmXy+fyqmVVVVdE1gZh5m15ns9mZckBKqcMo+nQw8+Dc3Nz8WpmlpaVk0Qx9mdVAjuOMEdFkYfBQpdtFRIliTwgxXC6TTqcXmXmokJ90HGesXD8ikUidlLIVgK9sY4FJStkrpcwXnvtw9wfhk1K2RiKROhe961coFGoIh8P1mzLckydPnv6xfgI5/hQcGqnB1wAAAABJRU5ErkJggg=="
ICON_WARN="iVBORw0KGgoAAAANSUhEUgAAACQAAAAkCAYAAADhAJiYAAAABmJLR0QA/wD/AP+gvaeTAAADNUlEQVRYhe2UXYiUVRjHf8/7OjM7mauoSS6kRMlC08yyKZi5H40YdJElS4I3Ul1IhOAXWxkUzGVirO4SmHcZwsKCsjfBLiGVO1sWbeKrU4jh6kW74RfjZtk4c87TRdP6zvdoRl3M/+75n+f/nN857wc01FBDDTX0/5bcazDZ1xZR164FWWqttAA4jk6BTqvMSXZtP/XDvw70+QcrF7uB7G5UNoE+XqP9vApDAWP6ntmdun5fgVKJSPDaArcX4S2U+fUOzyst6PvhcLBv1esT2X8MNL4vtsQEOAp0lK7qDMh5FaYARGkBXQHSXNrKl8YEXo73Tly9Z6DxgScfM8Y5jrDcZ1tEBq2aww+GQ18UnzqViASvLJBuF+dVhc2A41ueFNX1nbvOXLhroJMDq5tv29+/BnnC1/0tard27TzrVTsIQHJv6zwbCp0GHi1aSjmZzJqOt8/9Wi7nlDMBMnrrSAEMDJrmme56YFQRDYU+LgMDELGhpk8qZcsCjR1oe0GUDT5r9JeW1i3x1y7+UQsGYKw/9o5Cj886riKf+pA3jvXHni+XLXlkQ0Ob3Ienz51Cieati0En3Pb09m9m6oLZH12vIiOA+9feXDImsCqXIxtqynrAsnyr15n22iWB9edLbmjJ1I/rfDCo6rv1wox/2L5cRQZnYeAW0BPvnbj63J6JGwLv+dpjyfnRdcUzSoAEZ6Ov+qnrxpnBemC+6lsTNjlzDFg8exjhja5d3vd/1x1p7whw4c6681IdQL53R3W4+EorKSe/HQSe8k3a373DO1wwO4FFdPiOoy9WBRrdF5sLPDLb7spntUBOHIhuPdEfu4zwis8eX5TO7SnXLxTMXPbdoZUPVARqCjot/tq1eqkqzEC0G+QQykM++4qbpSeSSN0ul7HWFszMZDJLKwK5Yhf56zlOeLoakKg8S9GXKjC89k3vcqVMyJ37s79WHP9hCoGyrjkLTObLkVpfl1pSJR6MVsvkZ47ky8n8nuWB4ttSN03AxFx12k16of/HWFadO72jwEeABSzCwc4d3rFaOZNeuMFVp90ETCy+LXWzVv9d6+TA6ubk3tZ5931wQw011NB/oD8BXJokXpB1fZAAAAAASUVORK5CYII="
ICON_CRIT="iVBORw0KGgoAAAANSUhEUgAAACQAAAAkCAYAAADhAJiYAAAABmJLR0QA/wD/AP+gvaeTAAADL0lEQVRYhe2TT2xUVRTGf+e+aadSWxYyTWgixFgl7ZQxVZKC4AxDEJzGqaRxEjZGNyzcGmMkwYSlK1yiOzEkTTCQRoKdUUuHpAgxVmPtKxEaCwsgtsRInbZTZuYdFw70dXjzB8ToYr7kLc53z3fu7933LtRVV1111fX/ljxs8OzerqBlZDuq61WkHUBUbyByU2AsPGxP/etAo/Fn10mu8R1EE0BHlfYrCif8DkdeTNm/P1IgOxFsnMvIu6DvAWtrHV7UHwIfNs82HdkyPp77x0Dn94TaclbhJLDDY3le/j6JG8Vh7QrPAK0eG51zfLnXo6cv33pooJFY99MWOgJsdNmOIoMiHHv8N3+69K3tRLBxbkEiqL4F7AeMa7cZS8zul878/OsDA12MdbRm8V8Aulzd3xlHDoSTkxOVXgRgrH9TS/6O7yeEp0qWbF9DftuOL3750ytnvEyALP7jJTCDurgQqQVGQfJ536ceMADBfK7hs3JZT6DRvu5XgfgKC6nZ5q43oumr2WowAOdi3QdRBlz5EVU540LeN9oXfMUre98nO5FIWG2ZqR+BzUXrahPLz20dnp6vBWZ0b+duMSYJWEXrmvpyW/JLLbmGhuwEsKHoT0R67R45jOPO33dCbQuXdrlgEPRQrTAjfZ0bxZhBF8yScZyB6OnLt17+Zvy2wAeu9lD6Queu0hken0z3uYrpcO/UYC0w3ya2PWapdQpYd9cT5e1w6tIPd+twr30cuHfDjDGvVQdS97+jQ6VHWk7LmfmjoM/fM4SPIkn7mLtHDuOgDK1sRX9FoNSeUDPwpGv562og6VjwQDrWPSvw5goL5wPNvO/Vrwb3zA3fx19YUxaoqTHX7q4Laq5Vgjkb2xwBPgENuOw5X8EaCH5u3/HKGJFVM2/nl9eXBXIKPOGu18jizUpAlhZ2UnJTDQxt/2pitlzG72Svr+4vBFbXbi2ZSYQZAJRktdvliNilXl5IVcpsHZ6eR0kCIMywZCbLAkXTdkYXCanQo9lAnCraOWyfFPRjwCk+R6Nf2qeq5TQbiKvQo4uEomk7U63/gXUx1tE61r+p5ZEPrquuuur6D/QXNgIWglVNBboAAAAASUVORK5CYII="
ICON_STALE="iVBORw0KGgoAAAANSUhEUgAAACQAAAAkCAYAAADhAJiYAAAABmJLR0QA/wD/AP+gvaeTAAADIklEQVRYhe2TTUhUURiG3+/eGX9GtEU/kKAi1abIMNpEgSEuWmSJ1BA2OjmODNIuIgoKZtmqljbi2MztlnBBcRMoIRQUQYsiyTblT2QKJpGaNjPOPV+LbtOdcf60ohb3hbv4vvO973nOuRzAkiVLliz936LNGntCoX0E+YhE2Anm8h9pNCsYc7KgJx6P681fBwrcv79NjsUvAjgDYHf2aX4LkIZ47KbX6/38R4E0TStY/ha9xMyXAWzJN9zQFxDd0COrN30+39pvA3Uryg67wACAo2mWlwB6C/CsEVcO8B4AZamDzHgsCm2nfS0tC5sGCoRCu2SSRsGoMrUFA/1gCovY6qPUU2uaVrC4Eq0jic8T4ywDkml5ShJyg8dzbnLDQKqqlkXi4hmAvab2cybu7HS7x7IdBACCwWApy/ZXAKpTlsZJXzvc0dGxnM4npWsCQCQuVDMMgftl1uvygWFmYps9lAYGAPaxbFcyedMC9YTDJwA0JmAYI6WO4tb29vZILhgA6FPUq2A0mwBHCfTANNLUe+fu8XTedb9M0zR5cTXykoD9Rmu6yCYdcLlcS3nBhMMNgmkYgGzs8F632w5h2bYmF0bGAFQao2Mz05O1fr9fmP3rbmhxJVpvggGBruUL09t7r0ow9f+EYeCbpFOzr6VlwedzLhLoumm8prK6uj41Yx0QAU2m8t2H6Yn+fGA0TStmmz4IYFsii7jL42l98bP+MD2hAki8MME4lRMIxI2/Ch5KvdJMWlqJdhNw0NS65XW7w+YZv98vwDRk2uxkViBFUUoAVCTGwQ9zgQTvKJ29IWUexG7TRk/LHEVXMljMmZWBQMCREUjX5fIkqy6/zwbTpyh1TAgA2J5oMn9ak7jZ6XTG0nlY5uTMwsKdGYHi4K3JszSXDYiZjiHlpZJEQ11tbfOZPMWS9DEJgG3bk2pzESspeA1gyiiHc70uATG+npJGsnmMzGGjnDL2TA90wen8GnUU1QjWa2eqKhqRQ962tgEGbgMQxtftcbsGc/lmqioaBeu1UUdRzQWn82uu+Q1LVdWyYDBY+seDLVmyZOkf6Du6My0LYLcsdgAAAABJRU5ErkJggg=="
ICON_RAINBOW="iVBORw0KGgoAAAANSUhEUgAAACQAAAAkCAYAAADhAJiYAAAABmJLR0QA/wD/AP+gvaeTAAADgklEQVRYhe2UW2hUVxSG/7XnJGnsJDEdEzDEDFNjgpeGWp8kDxGREtBRSZkQrEV9EBWairakprVwFFotBYX6YIVGvOQCCUpASmMlEGhFK2ipGPGSmlqoSWNmEjOpc+Zc9uqDmeEkmVuLUh/OD8PhX3v9a3+bc/YAjhw5cuTo5Rb912B1e89Sk4PVUYTmGwiW6HIcUTH6yGdEh0q1yZ/adn5/+4UD+dsn5hn0eK+J0UCUx8p1hKBzEM+eIegIwWtEYr/7XvNp5wIrfKR2b38o0z1EJk0BlbPrW0KfkDAHAG5mUHkGsUXM+JQs5bc7hyo/5hMrsp4L0E51uDincKyXQZ8DKJixPAHQdQAXwHwBwPVntWmaC+bDfw+NXpr4sGJeuv2UVIuN+/9a+DRL6QXgtZUlGB0CdNoMh/t+2fG+Yc+4OwPZZU+4BoytABoQPzTXQNGvje+pWDP36L0HyfZM+g01NgbzpVte0dxiSdRNiLoJ2hxcM3hse8+m12+mO2lTS3Veedj61WtEfF4jglJdg9QEOCL69XDWyqKTd8OJcklfmQKrlYElMc+gjrA2XpMJDBiUreWcAuCbvYSlLsU6kyyaEKh52/A6AP74EMJFyit4r2+bT0sLA2Dzt2ubAdTZKHpB+M7WsjG4dWFtRkCBALsY9IWt9DvA9V31ZGUCs+rkO2uIcTDmCXhIOWjQc5R3Cfgj3ijFl6zO3n9WYTFGVgN4I+aZaX/bB56ZNyehfG2bvFJQBwDXVCkimesqP7o3+tq+B08k02e29qrg7YrVaYGIsNFmB8rMwo5MYEo79+RKdp0HI361mbCrtunmjZjPzx1sBTh+wyRjQ3ogZr/NdqsqyUyAcnU+DuAtW+nojt1XT0+brUISU3fcg9anBPrq7eFXGVgQL7C4lA7kzdavty9rOzAC8JZ4DLisFHn2JU6QfWbZI/+KOUmBtGxRYvesyIepYFa2t9cQ0QkGimzlx2QZdWp9l54oI4Q5babLjM5PCkSW9Ni9ooihVEAW0SrM+HMloPvsrh9GkmV0K+tPu2fFsh9mOpAZEbcIGJyyPcfU1LeLgP6ZNUl8MVXGc2xgAkDPlB0Ur4hbSYHUvuJJQFQJpuUFniL7x51QPzc0nAPwDQAJQILp+I9bzp1PlyssKfULgeUMpaq4q38yXf+/Vnmrml/Z0pT33Ac7cuTI0f+gfwBkik/cVgNqmQAAAABJRU5ErkJggg=="
WARN_TH,CRIT_TH=25.0,10.0
# 配色取 DesignOnline token 实测值：warning=amber-700 / danger=red-700 / 过期=text-subtle(ink-500)。
COL_WARN,COL_CRIT,COL_STALE="#C2902E","#C0492B","#9CA0A2"
def _is_dark():
    try: return subprocess.run(["defaults","read","-g","AppleInterfaceStyle"],capture_output=True,text=True,timeout=2).stdout.strip()=="Dark"
    except Exception: return False
# 浅色取 DS token（text-default=ink-900 / text-subtle=ink-500）；深色保留菜单栏自适应近白/灰。
NORMAL = "#ededef" if _is_dark() else "#1B1B1B"
MUTE   = "#9a9aa0" if _is_dark() else "#9CA0A2"
# 数据行挂"点击=刷新"动作 → 启用态=墨色清晰(会 hover)，留意橙/告急红在下拉里也恒亮、不被压淡。
# 点任意数据行 = 强制拉最新（与"立即刷新"同效，hover 名正言顺）。
ACT = f"shell={os.path.expanduser('~')}/.claude/claude-gauge-refresh.sh param0=force terminal=false refresh=true"
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
    return ""   # 充裕态不强制色：用原生菜单默认 label 色（vibrancy 自适应、清晰，不发灰失真）

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
    print(f'{label} | sfimage={icon} size=12 font="PingFang SC" {ACT}')              # 标签：苹方常规；可点(刷新)→墨色+hover
    print(f"{u}% 已用　·　{100-u}% 还剩 | size=14 font=Menlo{col} {ACT}")             # 数字：等宽常规；可点→墨色(OK)/橙红(警示)恒亮
    print(f"{bar(u)} | font=Menlo size=15{col} {ACT}")               # 进度条：可点→显色不发灰
    if cd_str: print(f"{cd_str} 后重置 | size=11 color={MUTE} font=Menlo")  # 倒计时：等宽小灰(DS --font-mono)

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
    print(f'Claude Code 用量 | size=15 font="Songti SC" {ACT} image={ICON_RAINBOW} {ICON_SZ}')  # 标题宋体 + 彩虹表盘；可点(刷新)→墨色
    if stale:
        print("---")
        if (_loadj(STATE) or {}).get("auth_dead"):                  # 续命被服务端拒：钥匙串令牌失效，唯有重新登录能救（别误导成"用一下就刷新"）
            print(f"⚠️ 登录已失效 | color={COL_WARN}")
            print(f"在 Claude Code 里运行 /login 重新登录 | size=11 color={MUTE}")
        else:
            print(f"⚠️ 数据已 {int(age//60)} 分钟未更新 | color={COL_WARN}")
            print(f"闲置/限流；用一下 Claude Code 即刷新 | size=11 color={MUTE}")
    print("---")
    if fh is not None: section("当前 5 小时 · 会话","clock",_used(fh),_cd5((d.get('five_hour') or {}).get('resets_at')),scol(fh))
    if wk is not None: section("本周 · 7 天","calendar",_used(wk),_cd7((d.get('seven_day') or {}).get('resets_at')),scol(wk))
    extras=[]
    if son is not None: extras.append(f"Sonnet {_used(son)}%")
    if opus is not None: extras.append(f"Opus {_used(opus)}%")
    if extras: print("---"); print("按模型（本周）　"+" · ".join(extras)+f" | size=11 color={MUTE} font=Menlo")
    print("---")
    # 显示当前读取的组织名（排查多 org 用户数据不匹配）
    try:
        _oj=json.load(open(os.path.expanduser("~/.cache/claude-gauge/org.json")))
        _on=_oj.get("name") or _oj.get("uuid","")
        if _on: print(f"{_on} | size=10 color={MUTE} font=Menlo")
    except Exception: pass
    upd=datetime.datetime.fromtimestamp(ts).strftime("%H:%M")
    print((f"更新于 {upd}（{int(age//60)}分钟前）" if age>=60 else f"更新于 {upd}（刚刚）")+f" | size=11 color={MUTE} font=Menlo")
    home=os.path.expanduser("~"); print(f"立即刷新（强制拉最新） ›| shell={home}/.claude/claude-gauge-refresh.sh | param0=force | terminal=false | refresh=true | sfimage=arrow.clockwise")
    un=f"{home}/.claude/claude-gauge-uninstall.sh"                    # ② 菜单卸载入口（装了稳定卸载脚本才显示，子菜单收纳、不污染主下拉）
    if os.path.exists(un):
        print("---"); print("管理 | sfimage=gearshape")   # 真按钮：墨色 + 齿轮图标 + 子菜单 ›（与"立即刷新"同级）
        print(f"--卸载 ClaudeGauge… | shell={un} | terminal=true | sfimage=trash")

def load(p):
    try:
        c=json.load(open(p)); return c if ("ts" in c and "data" in c) else None
    except Exception: return None
def read_token():
    SVC="Claude Code-credentials"
    try: acct=subprocess.run(["/usr/bin/id","-un"],capture_output=True,text=True,timeout=5).stdout.strip()
    except Exception: acct=os.environ.get("USER","")
    try:
        raw=""
        if acct:  # 先锁本机用户，绝不读 iCloud 同步/机器迁移带进来的他人同名凭证（否则会显示别人的额度）
            raw=subprocess.run(["/usr/bin/security","find-generic-password","-s",SVC,"-a",acct,"-w"],capture_output=True,text=True,timeout=5).stdout
        if not raw.strip():
            raw=subprocess.run(["/usr/bin/security","find-generic-password","-s",SVC,"-w"],capture_output=True,text=True,timeout=5).stdout
        if not raw.strip():
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
            org_uuid=None
            org_f=os.path.expanduser("~/.cache/claude-gauge/org.json")
            try: org_uuid=json.load(open(org_f)).get("uuid")
            except Exception: pass
            hdrs={"Authorization":f"Bearer {tk['accessToken']}","anthropic-beta":"oauth-2025-04-20","User-Agent":"claude-cli/1.0.119 (external, cli)"}
            if org_uuid: hdrs["x-organization-uuid"]=org_uuid
            j=None
            for _att in range(2):
                try:
                    req=urllib.request.Request("https://api.anthropic.com/api/oauth/usage",headers=hdrs)
                    with urllib.request.urlopen(req,timeout=8) as r: j=json.load(r); break
                except urllib.error.HTTPError as e:
                    if e.code==429 and _att==0: time.sleep(10); continue
                    break
                except Exception: break
            if j is None: raise Exception("api failed")
            lm={e["kind"]:e for e in (j.get("limits") or []) if "kind" in e}
            dd={}
            for lk,dk in [("session","five_hour"),("weekly_all","seven_day")]:
                le=lm.get(lk)
                if le and le.get("percent") is not None: dd[dk]={"utilization":float(le["percent"]),"resets_at":le.get("resets_at")}
                else:
                    b=j.get(dk)
                    if b and b.get("utilization") is not None: dd[dk]={"utilization":float(b["utilization"]),"resets_at":b.get("resets_at")}
            for e in (j.get("limits") or []):
                if e.get("kind")=="weekly_scoped" and e.get("percent") is not None:
                    mn=((e.get("scope") or {}).get("model") or {}).get("display_name","").lower()
                    if mn=="sonnet": dd["seven_day_sonnet"]={"utilization":float(e["percent"]),"resets_at":e.get("resets_at")}
                    elif mn=="opus": dd["seven_day_opus"]={"utilization":float(e["percent"]),"resets_at":e.get("resets_at")}
            if j.get("extra_usage"): dd["extra_usage"]=j["extra_usage"]
            obj={"ts":time.time(),"data":dd}; json.dump(obj,open(CACHE,"w")); best=obj
        except Exception: pass
if best is None:
    print(f"额度⚠ | color={COL_WARN}"); print("---"); print("新开一个 Claude Code 会话发条消息即恢复实时 | size=12")
    print("---"); print("立即刷新 | refresh=true")
else:
    render(best["data"],best["ts"])
PY
