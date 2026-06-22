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
ICON_SZ="width=25 height=16"
ICON_OK="iVBORw0KGgoAAAANSUhEUgAAADMAAAAgCAYAAAC/40AfAAAABmJLR0QA/wD/AP+gvaeTAAAE1ElEQVRYhe1YXWgcVRT+zp2dnaLNjzZJ3ZkpWyTYSqiKYNWCVYh9qBWh+F/RWBB8KFRBtPVF6IPFB6EPLf4g1gdrRaq1FBFBYpE+VENjrW2gatpusjOziaus6bax2c3M8SG7y2Zz7+xMkgeRfk97z893zsfcO/fMAtfw3wQtNmE6nU6Vy+U1QohVQRBYQojrmTkJ4DKAKwDOE9E5AL84jvPPYtZeFDGmaa4TQmxh5gcBrIqYdhXADwC+SiQSB0dGRnIL7WPeYnp6epKFQuFZInoV0QWo4DPzUU3Tdmez2ZPzJZmXGNu2NzPzHgDp+RZWgYiO+L7/ci6XG4mdGyfYNM0OIvoQwCNxC8XEJDPv8DxvX5ykyGIsy7oHwCEAdtzOFoAvpqen+8bHx69ECY4kxrbth5j5EIDrIoSfAnCMiE4x83lmLiQSiVIQBEuDIFgOYJUQYh0z9wLoisD3IzM/7Hnen80Cm4qpCDkCQA8JmwDwDhHtdxxnOEKDAKDZtr2BmbcB2NSklzO6rq/PZDJ/hxGGiqlsrX6on8g0gL2GYey6cOHCRBhXGEzTPExEm8NiiOj4kiVLNgwPD0+pYrSQAh1E1A9gmSIkQ0QbXdfdXygUlAWawbbtFwC8FiE07fv+DZcuXfpaFaAU09ra+imAuxTuAQD3u64bdUtJYdv23ZWzmIiYsralpeV0sVg8J3NKt1nlHjmsIBwolUq9+Xz+csQGpOjq6lqu6/pJyN+OjJktLDunTqlUulVWXzQaenp6kpULUYYMM29aqBAACV3XP4PiNU9EbwN4RpFrJ5PJnTLHnG2m6/rzRPScJHa6ckZ+j9qxCqZp7iGiJxXu71zX3VosFs+2tbV1AljbGEBEd7S3t78/MTFxtd7e+GSoMmvJsNdxnIH4rc+GbdtbiGi7wj3q+/5TmNlimJqa2gnAaQxi5tYgCF5stM8SY5rmvZAPjROGYeyK3XkDLMu6nZk/ULivCiEeHRsby1cN+Xz+MjO/IQtm5r5G2ywxQogtisR3F3KPAIBt2zcCOAzFncXM22QTcyqVOgAgK0lZbZrmnfWGWWKYeYOsEBF9FLVpBQQzHwBws4J/n+d5+2W+wcHBMoCPpaRCzOq3JiadTqcA3CLJOeW67m9Ru5bBNM3dADYq3Cfa2tpeCctn5s9l9iAIHqhf18SUy+U1Cq5jYYXCYFlWr2ma3xPRDkWTY0KIx4aGhkphPJ7nnQbwV6OdiG6rX9fECCFWK7h+bt72XFiW9SaAb4lovSKkzMxPZLNZLwJdAOC0xJ7q6OhoqS5qYpj5JgVR7JHFsqxeAK8jfJDdnsvljseglfVBhmGkqouaGCJqkQSDmQsxClZztiJECDN/47rue3E4iUg6/jPz0urv+reZtHgymQz9hlBANWlXGzsYlzAIgjlnBgA0TatNMfVi+iWxZzKZzHjcwkQ0FObXNO2nuJzM3I+ZAbQefzDz2eqiJsZxnC+Z+S0A5YrpV03TnpYQNIXv+/sAFBXuo6Ojo6FiZcjlcoNE9BKAyYrJFUI8Xv9H4pyttXLlynbf95dls9mLmHmLzAsrVqxYHwTBJ5g9GR/Vdb2v2edvGDo7O5cahpFyHOciKjNcFYv+92w9uru7jcnJyfsAdCQSiTPzeSLX8H/Av9l3yZvjA+tKAAAAAElFTkSuQmCC"
ICON_WARN="iVBORw0KGgoAAAANSUhEUgAAADMAAAAgCAYAAAC/40AfAAAABmJLR0QA/wD/AP+gvaeTAAAE40lEQVRYhe1YbWxTVRh+3nPvKggzlS1iI4mJMQ4z2hlHok5at8zFCMa4KKIYspiYkDjYRpGI/iDlh0QTsOv40MSIP0QSQYEsxpgo1rVEdGGObjQRAwEVxQ/YRxhjrPee1z9rbddzb2+7/TCG51fP+/k8veee+94L3MB/EzTbBWPhWg9rhpcYVcy4g4B5zHCRkGOQuMqCzgrGj5qcN1AXPH5tNnvPipieyJI6AW01Mz8KoMph2gTA3zHEZ8T6/sCGvosz5VGymGSo2nXJra0hYBOcC7CCyeBuTfK2ZcFTJ0otUpKYeKSmmSWHQbiz1MbWoCOaLjoeXtf/c9GZxQRHt9dWanrqfQBPFtuoSIwD/GqgY3BXMUmOxRzr8j0oJQ4CWFQ0tdLx6bUUWh7bNHDVSbAjMT0R73JiOgjgZgfh/SCOgkW/ZHmWdQzrBiaZeL4EFgpQFUB1ABoB3Oag3vemUfZEwyt9lwoFFhQzJeQIgDKbKqMA9pimubchmDzjgCAOHFipeS6ebmJGK4AVtlwIg6YUgYYNJ0fsatqKmdpaR2F9RQyAdl6f0Lc2be4bLcDfEj2dNYcI3GxLlBC/QuNNy9vOXLeK0a0c0e21lVKm7LbWeUhaFQgmep1RViMW9r2EAkIAgBn+cszbAWCdVYywckydWuqbndA7qU8unamQeKfvARAcn1jM3BoLe5+y8iu3WTxS08zMhywyek3dbGxoTY45JaHCV51LFrogTkD9hzEYBkh5n14wy8x7Vf3zrkwyVO1iyWELDufNVNmKmQqJhup1F4uPYX3MbyfiFyx8i4ShbVY58sRccmtrLJ7sBiStcnJEFoJwD+0A4REL99fmyILX/R2DB4lotyqAmNfH93hvzaubvWAGTc1aqhI7Z3qPAEBPxLuagDYL9y8Q2nMNoW8MADB0YzOACwout8iUWDvdmiMm1rXkIaiGRsLo9Ql9a/HUcxHvqq4hpvcs3BNCyqcDbf1/pw0NrckxIt6iChbMLXm23IW2WpVIzO/M5DkCAN++Xb2ApXYIFkc9MbWqJua5c1z7APw63c7A4ljYd3+2LXebgZuUTEzxQRG888AhiJTQ9gG4Sx1Bu/wbEntVnqVr+1IAPlRmUS7fjJhYuNYDxj2KnH7/xsRPDnkrEXPXbCPgcQv38YoRY6NdPgv6RGkH1WevMxMAa4aXpCKDOFqAqyViEV8jGFuYOWAxOP0hNO2Z6tDApF2dwFAiEXf7LgOomObyZS8yV0ZIXqwqRBAnHTGfhlin7w0wvgQQILWQlJR4dtn6/t8L1aIQJICEwuU59lZVeXqREcOE21WFTCkdTcHZiEV8jQBeg+0kTG31wYG405rMpOJBrM/xpBf/HgBM5YpgsI5hpw2zerwI+4n8i0B74t2iKgLK8Z8Fz0//zoghsmgupO07hBLM0/d2LjGi/UXXFPKyyixJaJmQLPvR/K4YrH85+WexfQlI2vpN/FBCzaMAeJr5L5eceyq9yIjxtycOE/hNAKkp02lh0vNEeQUKwmCxC8AVC3f3smDCVqwK/vbBPhC1AxgHAAZ+Y/DK7A+JeVsrGr7P7dKMirqhU+emTpGS0NPpDRDoI+ROxt0mi5ZCr792iO6uni+MMo8cdp9Lz3BpzPrn2Wx83nX3TeXmXD8LqhQmDZZyRW7g/4B/ACfVwGNudZN6AAAAAElFTkSuQmCC"
ICON_CRIT="iVBORw0KGgoAAAANSUhEUgAAADMAAAAgCAYAAAC/40AfAAAABmJLR0QA/wD/AP+gvaeTAAAE0ElEQVRYhe1YXUxbZRh+3q8tP1uZP2MicYmJMWOlRY1ZghLpWpCUgpItilPMQkxMvECniTGbXpjtwsULFy+GP4lxXjiXKIoEJz9u0ALGOTJkGy37yZZNnT+bmEn4GdD2e71Y6Qr9zuk5hQtj9lz1vD/P+z79zved9xzgJv6boOUm7Pc5CllYShiyiEF3CWAlA1lgTIIwRYzzMcGnc1becrKs5ci15ay9LGL6al1lMsYNRHgUQJHBtBkAPxL4IEk+4O4+9cdS+8hYTLjemTU2QVuZ+DUYF6CFGIB2Jtrt7Qgdy5QkIzHBatdmEL8L4O5MC2uD2mIUe6Wy49TPpjPNBAceX5dPUdvHAOrMFjKJaQa2ezvDzWaSDIsJ+B0PEUQLgLWmW8sQBHw1E7M0+r47OWUwPj36qh01TKIFwAoD4cNgBBg0TKDzLHHVasMcx9guBQqYuYgIZWBUArjDQINHpTXymPebs2MGYg0JaQNg0wkbB9P7zLzP2x0+l44TAL6or7esmRqtIkYTgNo0vYxwts3tbTv+jx6nrpj4rdUD7RWJgrA3Mpezq+rw0Lhu9zoI+l2tAG/WDSIMTPNsVU3nuVmtEKuW4/pm1721LgqJLe7u8KChjrXq1DifB6cRAgCM8lzO3gPgRa0QoeWIn1rqzU4YjM7FNixVSG9NcSkxDJ9YRGgK+B2bNP0qY/w50qqRMcjTqPQGw5NGm1DhcJ2rwBrhY1D/YQwgCvU+vcTX4FDVT1mZcL0zK/5AVOEiWyK1SxUS8Histgh/Du2VfwfMz2qkr0UudqgcKWLGJmgr1E/2qJDYYuSITAdacWUPAxs13L08veYNT9doCzPeU+YDLw3Ulty22L5ADAMUn7VUDHuXukcAoK/G2QCmbRruXwSynvYGg1EAwAx2ALikiFsVjckXFhsXiOmvdT0M9dA4HpnL2WWu7VT0+pz3M+MjDfcMEz3h7hz+a97gDYYnQfymKpgEGhfbFoiRMW5QJhI+WMpzBAB+8DlvFwKt0DjqCdSkmpjtl3P3A/g1JYGxvt/neDDZtEAMEapUhQRin5joO7XuTog5gf0A7lH5CWje2Bnap/JtGBqKAPypkleIBf0mxPT7HIUA1ilyhss7Tp813LkCwaPO3QD8Gu4j+Xa8qpdPwJcqOzM8ydcJMSwsJUomRkCvkB56q4sre/2uPgK2a4T8aY1Gn3S2hOf0eNyloycA/J3iINyXfHlDDGO9kknQ8XRNqxD0F78liA4JsFsjJALJTz1y6Mzv6bhoJySAEwpX4fd1RXmJVpMcdyqZJBmagpPRW11cCdDr0BlkmWibp3t0wAStqg/iKBXOXyTEEHGeIhgscdVEwTiXeA56Ezlzl7cj9KFJWuX4zzGyz/9OiJGsUdwqdd8hVCDm1boBLA6Y5YRqzwCQJCzzv2+sDKhHETvi6QhfNluVicJ6fgn5k1lOKUQPrg+gybiSlbcqNH+REOPpCn1NhLcBROKmM1LyM5RKkB4cbQYwoeFtr+ge1RWrQsW3I0MAvwxgOm76jUjWJ39ITLm1ApseuFXORldXlIYuxE+RjNBX43Azi8+wcDJu52xbY7rXXz0EPE67sMtCOVlwITHDxbHsn2eT0eG/NztX2spBIp+ZRzJZkZv4P+BffLK5x/4XbfwAAAAASUVORK5CYII="
ICON_STALE="iVBORw0KGgoAAAANSUhEUgAAADMAAAAgCAYAAAC/40AfAAAABmJLR0QA/wD/AP+gvaeTAAAE80lEQVRYhe1YXWxTZRh+3nO6ro7xoxJwcQgSw9AETYyJSgJKJhcKMRK1yEj/1kIvptPEEMELUi4kXkhIANHZdqXraGKnSIgXJgaXyIVKUMRpokZkyPCf8DNW1+2c7/WCbXTt952e0+1CE56rft/7fs/7PD3f+b43B7iB/yZougk7MpkGl2kuA1MTA7eDMINAbma6ShqGGOK0RvR9vcfzjdfr/Wc6a0+LmXc6M8t1jVuY8BgYTTaXDQP4nIEPhU7ZqM/321R1VG0ml8u5B/PDPiZscWBABZNBRzSNd4b9/hPVklRlJplOr2PQbjAWVlvYAodh6C9FIhvPOl3oyExHNjtXHxlNAvSk00IOkQfRK5GAb5+TRbbNxFPdDxGJHgCNjqVVj/fdGgJ+v3/ITrItM/FU1xNE6AFQZyP9JJh6WRMnNeC0IcTFGnaPmLpRD6HNJw1NxGI5QM0MzKvIxvjCrHWtjba0/F0ptaKZMSOHAdRYpF0GsB86dUZ8vp8qCgSQy+X0K0OF1UTcxsAaKy0M9LnYXBkKhS5ZcVqaGdtaR6F+IgaAvWbBsyMa9V6uZECF5IH0IQatq5B2LH/l0ur29vaCKsGlCnRks3NpxLDaWv0gXh8JBI7b0KtEIp2JMHMlIwCwYsasObsAPK9K0FSBa6eW8mU/XkP8wFSNdHZ1PQhm2ycWA22JVOYpVVy6zZLp9DpmOqRYc7xQ52lu83qv2hUhQzyenU81xgnI/zBmsEEg2Xs6UKjz3C2rX/Zkcrmcm0G7FRr6TbdrzVSNxHp7XXAZ70Lx5JnoDWLaqFjeWJsf3ioLlJkZzA/7FDe7AeL1do7ISlhw9twuIjwiixHhk/N3NL4aCfl7CHhTQfHC/oMHby6dnGSGmYkJWxQEe6f6jgBAItXVwkC7IvwLmcZzsVWrDAAYrvNsBTAgyZtVM2JGSycnmYmnuh9WNI2XzYJnh1PhpUgmM/eBEFeEh0nD062trX+NT7R5vVcZtF2WrBECZXPFA13jFtlCIrw1lXsEABKJxC2s8yGojnrmNlnHLAr5bgDnytKBpZ2dmfuL57SShNWyOiY45UB3GWKxmAZXbTeAxfIM3hcJBTplkWg0OsrMGVlM6JP1TpjpyGQaACyRrDm5ORD40aZuKRoX3rkT4McV4c9m1d30stV60vCeNMD8aPFwogNwmeYylt2hTL0VtCqRONDdzDC3A1ipSPmdzJpnvF7viBXPwJkzpxoXLb4A4NYScfcWjybUC2hL5VT8dUXVEsRT6dcA8TGBViru5lFm8obDG36txBWLxQQRTpVHqCGZTM4cH02YIeA2GRFpbKsLLkbiQHczEW2DRSNLjPZNId8x26QMmQ4yXa6G8UFRo8kzZbUNIS7aLjhRV4TIqiPX8FHY73/bGSek7b/L1Oqv046BQNLibgWJFahsb5fARNYpJ4ALskmDSB//ff2NJz5amshAXzAY/MNpVQK+s4oLEl855WSIo9ckTarz55wZ7m/HxxNmwoHAB0R4HcDoWOYPDLGBiCYR2IHG5j4AgwpZRzYHg5ZmZdgUDH5JzC8CyAMAA+cZ4tniD4mTzuJwwL9NZ3OeCXHXwJmf76mmKACEQqF+QKxFWV/FR3QWZW2IXYRDgb2FOs98nfUl5xcuWBQJBj8tjk/759li7Nmzp7Z+9uwVQtBcQaKv2j/nBv7v+Be418OSDGZV+wAAAABJRU5ErkJggg=="
ICON_RAINBOW="iVBORw0KGgoAAAANSUhEUgAAADMAAAAgCAYAAAC/40AfAAAABmJLR0QA/wD/AP+gvaeTAAAFjElEQVRYhe1YfUxVdRh+3nPggqik3AtIUmYZ2Ae1OVvm0miklTonKSiU05zTLdKG5kKXdm3pbMl0gZKatimTBYrlmKuZ6fKPTDMysg8nDc1MQD4u3Itwzu/83v7g63I5h/shW7X5/HXP733f53kfOOc9773AHfw3QYNNOOXA4QQt/FaKJt3Jkj2jBTxDdbhtAh63gVbPXUKvthvab45m5aeyVWW3BlN7UMxML6marKM1W7LnOR3uZAEPBNww2IPuz4I9MOBGtNEBh6HDbmjtDkM7Yzc6KuyacTA39/Tf/5qZjFK2tRu1CwV71gjqNGDAA8FuBGgGDkOD3dBgN3TDIbSjMbq+eeZbld+H2pMSkpG9Tem6cF1iwscgJIcq7gUVQDopfO7clkeP/PHe2DGhkARlJmtriyOrqPFzEMoBhCToDwyewxT2i+vdMa8HWxuwmaXvN0wKV0UlgNnBioSAKAYKWtePOXTjzfihgRaFBZK03Fk3Q5coAxAVQHolQCcBVCqkVCuQTcyKJhU5jAyKZ3AygMkA0gDE+eGaG6UOSWxZnTQrOv/STX/CfgdAztq6GXqE8pmIoHARSdAjARFB0CMJQmnvesjdLgHPTlZb9p3KfOFyAIaRUZqhxja2TIuReo5daDMdQqPOoaB3DQUNqg6wRpA6VbHkqSO31zSHbGbFqoZJ0iZP6JEUJSIIJmaEZE+BpjZt/CpzoisQE2bYXvB0uV3X0q3MsE6ARqejSZlGBZc7rHgsb7PVy647BMsyaX1r1UDh+ccyHzgbqgkAWF+YupSlSPeXx8CUZk3mA7AcDJYDQFHVvQASTYOEs6QrEysyE27LSM6u6U8yUWHgFZRzc3HSHKuoqZm8JbXpDLKYWnQWbXrakUXRDYE30R9Ze2bHG0yHAESYhBmAbqpOXFCX8cgws1g/M86MizYA2yx6qIGizizLiXMH2LMpUp2pYQL8KVn85wnYCuaXLcoTlUiRZxboZ0aE2xfC/IUowHJ+yfJovyPSH9R77fkAnrEIf31FH71uxDtXy0DYYZrBvKI5O2Wk73EfMwwmgNaY1RNQsH+V47aeEQBI2b8gm4GVFuGrYdK24FnnKQEAt5S2PICvmeRFC6Njue9hHzMb59U9hc6Xmi9cKtHGoDv3wdgDSx4nxh6LcDtLmjthXWV990Gcs94Npg1myQxa5HvWxwwxsi2EinbnxYT8HgGAxNLcGCajHBajnohyzDbm4c32YgB/mpSMr3/poQneBz7PjJxmJsTgTwLs2RxOpxKhdRQDuN+cnwpfyf1un1mMdp/XiXHAtI7Rp98eM5uer08AKKm/ECr3OGMvBdW8D5IfbNsM0IvmUf62pbFx9UD1BslDFrWp3lc9G4Bi01PMXjvEOOmvWSs8VpyfJqltg86tUy1SboTJ8HlO50VtIJ4R0VcuuG6ObQDI7ivhfdHTvWEo402ZFPoxgL77YUJJ0SYiHGfwVIsNUIdEpnPF8ev+uMgJCdAFk1BC/ezk4T2t9hRAjrKgCmgL9sYTJcVpYFqLARZZYl5Z9NqXpwNnZbM+CIISui96zRANN0kGgZsCF+yqYX4VAxv5onRZxUdBspqv/yr1rDY9ZpjMxaWQA36HsBD2vbf7gBX1YAicpruggKJ2f+41Az5hQlC184PY2qBlgYsDxZnkD8FyQsEJdC6g3qgTka6fe1O68HbF3UcY2ILebfV3BZQFkC+BXxCphQBaLcJHTy4+PKBZM4z4sPo8gDcAtHUd/QWijHvKrvX8kNhnFjsPj1obZouIMwyMGxYf+/C2bfagRQHgTFZWDTNmAeS7Vx1VZGS/NSRQjNxVXWAMscVLqSY5ahPuiyv/9Rvv+KD/POuNccc+jAhvck0x4HZIclddzt4R0h/nDv7v+AefpUyZefK20QAAAABJRU5ErkJggg=="
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
