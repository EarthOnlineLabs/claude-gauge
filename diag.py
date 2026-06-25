#!/usr/bin/env python3
"""ClaudeGauge 诊断工具 v2 —— 排查数据不准的根因
用法: python3 diag.py
把输出截图发给开发者即可（含长等待——429限流需要耐心）
"""
import json, subprocess, urllib.request, urllib.error, time, os, sys

SEC = "/usr/bin/security"; SERVICE = "Claude Code-credentials"
CACHE = os.path.expanduser("~/.cache/claude-gauge/cache.json")
LIVE  = os.path.expanduser("~/.cache/claude-gauge/live.json")
STATE = os.path.expanduser("~/.cache/claude-gauge/refresh-state.json")
ORG_F = os.path.expanduser("~/.cache/claude-gauge/org.json")

def load(p):
    try: return json.load(open(p))
    except: return None

def fetch_usage(token, org_uuid=None):
    hdrs = {"Authorization": f"Bearer {token}", "anthropic-beta": "oauth-2025-04-20",
            "User-Agent": "claude-cli/1.0.119 (external, cli)"}
    if org_uuid:
        hdrs["x-organization-uuid"] = org_uuid
    for attempt in range(5):
        try:
            req = urllib.request.Request("https://api.anthropic.com/api/oauth/usage", headers=hdrs)
            return json.load(urllib.request.urlopen(req, timeout=10))
        except urllib.error.HTTPError as e:
            if e.code == 429:
                w = 30 * (attempt + 1)
                print(f"  ⏳ 限流，等 {w}s…（{attempt+1}/5）")
                time.sleep(w)
            else:
                print(f"  ❌ HTTP {e.code}")
                return None
        except Exception as e:
            print(f"  ❌ {e}")
            return None
    print("  ❌ 5次重试均失败（限流太严格）")
    return None

def show(r, label):
    if not r:
        print(f"\n【{label}】无数据")
        return
    fh = r.get("five_hour", {})
    sd = r.get("seven_day", {})
    print(f"\n【{label}】")
    print(f"  5h: {fh.get('utilization')}%  重置 {fh.get('resets_at','?')}")
    print(f"  7d: {sd.get('utilization')}%  重置 {sd.get('resets_at','?')}")
    for l in (r.get("limits") or []):
        print(f"  limit: kind={l.get('kind')} pct={l.get('percent')}% active={l.get('is_active')}")

print("=" * 60)
print("ClaudeGauge 诊断 v2")
print(f"时间: {time.strftime('%Y-%m-%d %H:%M:%S')}")
print("=" * 60)

# 1. 钥匙串
print("\n--- 1. 钥匙串 ---")
try:
    raw = subprocess.run([SEC, "find-generic-password", "-s", SERVICE, "-w"],
                         capture_output=True, text=True, timeout=5).stdout
    blob = json.loads(raw)
    tk = blob.get("claudeAiOauth", {})
    exp = tk.get("expiresAt")
    exp_str = time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(exp / 1000)) if exp else "?"
    print(f"  token 过期: {exp_str}  {'✅ 有效' if (exp and exp/1000 > time.time()) else '⚠️ 已过期'}")
    at = tk["accessToken"]
except Exception as e:
    print(f"  ❌ 读取失败: {e}")
    sys.exit(1)

# 2. Bootstrap
print("\n--- 2. 组织信息 ---")
org_cache = load(ORG_F)
org_uuid = (org_cache or {}).get("uuid")
print(f"  缓存 org UUID: {org_uuid or '(无)'}")
try:
    req = urllib.request.Request("https://api.anthropic.com/api/claude_cli/bootstrap",
        headers={"Authorization": f"Bearer {at}", "anthropic-beta": "oauth-2025-04-20"})
    bs = json.load(urllib.request.urlopen(req, timeout=10))
    oa = bs.get("oauth_account", {})
    print(f"  organization_type: {oa.get('organization_type')}")
    print(f"  rate_limit_tier:   {oa.get('organization_rate_limit_tier')}")
    live_org = oa.get("organization_uuid")
except Exception as e:
    print(f"  ⚠️ bootstrap 失败: {e}")
    live_org = org_uuid

# 3. 缓存状态
print("\n--- 3. 当前缓存 ---")
cache = load(CACHE)
if cache:
    age = time.time() - cache.get("ts", 0)
    cd = cache.get("data", {})
    print(f"  更新于 {int(age)}s 前 ({int(age/60)}分钟)")
    print(f"  5h: {cd.get('five_hour',{}).get('utilization')}%")
    print(f"  7d: {cd.get('seven_day',{}).get('utilization')}%")
else:
    print("  ❌ 无缓存文件")

st = load(STATE)
if st:
    lp = st.get("last_poll_ts", 0)
    fs = st.get("poll_fail_streak", 0)
    print(f"  上次 poll: {int(time.time()-lp)}s 前  auth_dead={st.get('auth_dead')}  连续失败={fs}")
    if fs > 0:
        print(f"  ⚠️ 刷新器连续 {fs} 次 API 调用失败——这就是数据不更新的原因！")

# 4. API 实测（只做一次，带 org UUID——和刷新器一致）
print("\n--- 4. API 实测（可能需要等待限流冷却）---")
r = fetch_usage(at, org_uuid=live_org or org_uuid)
show(r, "API 返回")

# 5. 对比
print("\n--- 5. 结论 ---")
if r:
    fh_api = (r.get("five_hour") or {}).get("utilization")
    sd_api = (r.get("seven_day") or {}).get("utilization")
    # 从 limits 数组取（和刷新器逻辑一致）
    for l in (r.get("limits") or []):
        if l.get("kind") == "session" and l.get("percent") is not None:
            fh_api = l["percent"]
        if l.get("kind") == "weekly_all" and l.get("percent") is not None:
            sd_api = l["percent"]
    print(f"  API 数据: 5h={fh_api}%  7d={sd_api}%")
    if cache:
        c5 = cd.get("five_hour", {}).get("utilization")
        c7 = cd.get("seven_day", {}).get("utilization")
        print(f"  缓存数据: 5h={c5}%  7d={c7}%")
        if c5 is not None and fh_api is not None and abs(c5 - fh_api) > 5:
            print(f"  ⚠️ 5h 差异 {abs(c5-fh_api)}% → 缓存严重过期")
    print(f"\n  请对比 Settings > Usage 页面的数字。")
    print(f"  如果 API 数据和页面一致 → 问题是缓存过期（已修复）")
    print(f"  如果 API 数据和页面不一致 → 请截图告知开发者")
else:
    print("  ❌ API 调用失败——可能仍在限流中")
    print("  请等 5 分钟后重试: python3 diag.py")

print("\n" + "=" * 60)
print("请把以上输出截图发给开发者，同时截一张 Settings > Usage 页面")
print("=" * 60)
