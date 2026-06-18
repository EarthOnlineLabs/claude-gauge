#!/usr/bin/python3
# ClaudeGauge 完成提醒层（默认随安装启用）——「有新发现」彩虹态的事件入口。
# 被 Claude Code 的 Stop / Notification hook 调用，以及被菜单栏图标的左键点击调用。
#
# 隐私红线：本脚本【绝不读 stdin】。Claude Code 会把含 transcript_path 的 JSON
# 灌到 stdin，但我们整条忽略——事件类型由 hook 的 matcher 在 CC 层就分好了，
# 我们只记「时间戳 + 事件名 + 触发那刻的前台 App + 系统空闲时长」。从不碰对话/代码/会话路径。
#
# 形态：极小、纯副作用、任何异常都安全降级、永远 exit 0（不阻塞 CC，也不破坏任何东西）。
import sys, os, json, time, tempfile, subprocess

CACHE = os.path.expanduser("~/.cache/claude-gauge")
ATTN  = os.path.join(CACHE, "attention.json")
ACK   = os.path.join(CACHE, "ack.json")
CLAUDE_BUNDLE = "com.anthropic.claudefordesktop"
PLUGIN_NAME   = "claude-gauge.15s.sh"
SEEN  = os.path.join(CACHE, "seen.json")     # ① Claude 最近在用时间戳；event 时顺带 bump，让彩虹在 linger 窗口内不被 ① 隐藏
_SHELLS = ("zsh", "bash", "sh", "dash", "fish", "tcsh", "csh", "login", "launchd", "python", "python3", "node")


def _ps(pid, field):
    try:
        return subprocess.run(["/bin/ps", "-o", field + "=", "-p", str(pid)],
                              capture_output=True, text=True, timeout=2).stdout.strip()
    except Exception:
        return ""


def session_host():
    """走进程祖先链认出本次会话的宿主 App bundle：终端会话→终端 App，桌面会话→Claude.app。
    仅读进程元数据(ps/defaults)，不弹授权、绝不读对话/代码/会话路径。认不出 → None。"""
    pid = os.getpid()
    for _ in range(25):
        try:
            pid = int(_ps(pid, "ppid") or "0")
        except Exception:
            break
        if pid <= 1:
            break
        exe = _ps(pid, "comm")
        if not exe or "/claude-code/" in exe:                 # 跳过 claude CLI 自身的 .app 包装
            continue
        if os.path.basename(exe).lstrip("-") in _SHELLS:      # 跳过 shell / 解释器
            continue
        i = exe.rfind(".app/")
        app = exe[:i + 4] if i != -1 else (exe if exe.endswith(".app") else None)
        if not app:
            continue
        try:
            bid = subprocess.run(["/usr/bin/defaults", "read",
                                  os.path.join(app, "Contents", "Info"), "CFBundleIdentifier"],
                                 capture_output=True, text=True, timeout=2).stdout.strip()
        except Exception:
            bid = ""
        if bid:
            return bid
    return None


def awrite(path, obj):
    """原子写：先写临时文件再 os.replace，防菜单栏读到半截。失败静默降级。"""
    try:
        os.makedirs(CACHE, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=CACHE)
        with os.fdopen(fd, "w") as f:
            json.dump(obj, f)
        os.replace(tmp, path)
    except Exception:
        pass


def front_bundle():
    """触发那刻的前台 App bundle id。仅用 lsappinfo（不弹辅助功能/自动化授权框）。
    取不到/解析异常一律 'unknown'——后续 arming 会照亮（宁可多提醒，不漏）。"""
    try:
        asn = subprocess.run(["/usr/bin/lsappinfo", "front"],
                             capture_output=True, text=True, timeout=2).stdout.strip()
        if not asn:
            return "unknown"
        out = subprocess.run(["/usr/bin/lsappinfo", "info", "-only", "bundleID", asn],
                             capture_output=True, text=True, timeout=2).stdout
        # 形如  "CFBundleIdentifier"="com.anthropic.claudefordesktop"  ；NULL 进程则  ...=NULL
        # （按首个 '=' 切分取值，兼容 CFBundleIdentifier / LSBundleID 两种键名）
        if "=" in out:
            val = out.split("=", 1)[1].strip().strip('"').strip()
            if val and val != "NULL" and "." in val:
                return val
        return "unknown"
    except Exception:
        return "unknown"


def idle_secs():
    """系统自上次键鼠输入以来的空闲秒数（IOKit HIDIdleTime）。只读「距上次输入多久」这一个
    时长，不读任何内容、不弹授权。用来判断你是「真离开了」还是只是切了下窗口/还在用电脑。
    取不到 → 0.0（视作'你在用'，宁可不打扰也不误判你已离开）。"""
    try:
        out = subprocess.run(["/usr/sbin/ioreg", "-c", "IOHIDSystem"],
                             capture_output=True, text=True, timeout=2).stdout
        for line in out.splitlines():
            if "HIDIdleTime" in line:
                return int(line.rsplit("=", 1)[1].strip()) / 1_000_000_000
    except Exception:
        pass
    return 0.0


def ping_refresh():
    """让菜单栏即时重画（-g 不抢焦点）。失败静默。"""
    try:
        subprocess.run(["/usr/bin/open", "-g",
                        "swiftbar://refreshplugin?name=" + PLUGIN_NAME], timeout=3)
    except Exception:
        pass


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    if mode == "event":
        ev = sys.argv[2] if len(sys.argv) > 2 else "stop"   # stop | permission
        # 注意：不读 sys.stdin。点亮只依赖 (事件名 + 当前前台 + 会话宿主)。
        now = time.time()
        awrite(ATTN, {"ts": now, "event": ev, "front": front_bundle(), "host": session_host(), "idle": idle_secs()})
        awrite(SEEN, {"ts": now})    # ① 喂 linger：刚完成 → 菜单栏在 linger 窗口内必显示（含彩虹）
        ping_refresh()
    elif mode == "open":
        # 左键点击：回到会话所在的载体（终端会话→终端、桌面会话→桌面端），并写 ack 让彩虹熄灭。
        att = {}
        try:
            att = json.load(open(ATTN)) or {}
        except Exception:
            att = {}
        target = att.get("host") or att.get("front") or CLAUDE_BUNDLE
        if target == "unknown":
            target = CLAUDE_BUNDLE
        try:
            subprocess.run(["/usr/bin/open", "-b", target], timeout=5)
        except Exception:
            pass
        awrite(ACK, {"ts": time.time()})
        ping_refresh()
    # 未知 mode：no-op


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
