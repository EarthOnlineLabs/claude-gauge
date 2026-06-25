#!/usr/bin/env bash
# Build a macOS .pkg installer for ClaudeGauge.
# Usage: ./build-pkg.sh [version]   (default: parsed from CHANGELOG.md)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"

# --- version ---
if [ -n "${1:-}" ]; then
  VERSION="$1"
else
  VERSION=$(grep -m1 -oE '## \[[0-9]+\.[0-9]+\.[0-9]+\]' "$ROOT/CHANGELOG.md" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "0.1.0")
fi
IDENTIFIER="dev.earthonline.claude-gauge"
OUTPUT="$ROOT/dist/ClaudeGauge-${VERSION}.pkg"

echo "→ Building ClaudeGauge ${VERSION} …"

# --- staging ---
STAGING="$(mktemp -d)/claude-gauge-pkg"
SCRIPTS="$STAGING/scripts"
PAYLOAD="$SCRIPTS/payload"
mkdir -p "$PAYLOAD/plugin" "$PAYLOAD/refresher" "$PAYLOAD/bridge" "$PAYLOAD/alert" "$ROOT/dist"

cp "$ROOT/plugin/claude-gauge.15s.sh"        "$PAYLOAD/plugin/"
cp "$ROOT/refresher/claude-gauge-refresh.sh"  "$PAYLOAD/refresher/"
cp "$ROOT/bridge/claude-gauge-statusline.py"  "$PAYLOAD/bridge/"
cp "$ROOT/alert/claude-gauge-alert.py"        "$PAYLOAD/alert/"
cp "$ROOT/alert/install-alerts.sh"            "$PAYLOAD/alert/"
cp "$ROOT/uninstall.sh"                       "$PAYLOAD/"

# --- postinstall script ---
cat > "$SCRIPTS/postinstall" <<'POSTINSTALL'
#!/bin/bash
# ClaudeGauge pkg postinstall — runs as root; all user-space ops via sudo -u.
set -euo pipefail

log(){ echo "[ClaudeGauge] $1"; }
ok(){  echo "[ClaudeGauge] ✓ $1"; }
warn(){ echo "[ClaudeGauge] ! $1"; }

# The macOS Installer sets $USER to the GUI-login user even when running as root,
# but $HOME points to /var/root. Derive the real home from dscl.
REAL_USER="$USER"
REAL_HOME=$( dscl . -read /Users/"$REAL_USER" NFSHomeDirectory | awk '{print $2}' )
REAL_UID=$( id -u "$REAL_USER" )

run_as_user() { sudo -u "$REAL_USER" -- "$@"; }

PAYLOAD="$(dirname "$0")/payload"

# 1. SwiftBar
if [ ! -d "/Applications/SwiftBar.app" ]; then
  BREW="$(run_as_user bash -lc 'command -v brew' 2>/dev/null || true)"
  if [ -n "$BREW" ]; then
    log "Installing SwiftBar via Homebrew …"
    run_as_user env NONINTERACTIVE=1 HOMEBREW_NO_AUTO_UPDATE=1 "$BREW" install --cask swiftbar 2>&1 || true
  fi
  if [ ! -d "/Applications/SwiftBar.app" ]; then
    warn "SwiftBar not found. Please run: brew install --cask swiftbar"
  fi
fi

# 2. SwiftBar plugin directory
PLUGIN_DIR="$(run_as_user defaults read com.ameba.SwiftBar PluginDirectory 2>/dev/null || true)"
if [ -z "$PLUGIN_DIR" ]; then
  PLUGIN_DIR="$REAL_HOME/.swiftbar"
  run_as_user defaults write com.ameba.SwiftBar PluginDirectory "$PLUGIN_DIR"
fi
run_as_user mkdir -p "$PLUGIN_DIR" "$REAL_HOME/.claude" "$REAL_HOME/.cache/claude-gauge"

# 3. Install components
install -o "$REAL_USER" -m 0755 "$PAYLOAD/plugin/claude-gauge.15s.sh"        "$PLUGIN_DIR/claude-gauge.15s.sh"
install -o "$REAL_USER" -m 0755 "$PAYLOAD/refresher/claude-gauge-refresh.sh"  "$REAL_HOME/.claude/claude-gauge-refresh.sh"
install -o "$REAL_USER" -m 0755 "$PAYLOAD/bridge/claude-gauge-statusline.py"  "$REAL_HOME/.claude/claude-gauge-statusline.py"
install -o "$REAL_USER" -m 0755 "$PAYLOAD/uninstall.sh"                       "$REAL_HOME/.claude/claude-gauge-uninstall.sh"
install -o "$REAL_USER" -m 0755 "$PAYLOAD/alert/claude-gauge-alert.py"        "$REAL_HOME/.claude/claude-gauge-alert.py"
ok "Components installed"

# 4. LaunchAgent
PLIST="$REAL_HOME/Library/LaunchAgents/dev.earthonline.claude-gauge.plist"
run_as_user mkdir -p "$REAL_HOME/Library/LaunchAgents"
cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>dev.earthonline.claude-gauge</string>
  <key>ProgramArguments</key><array>
    <string>/bin/bash</string><string>${REAL_HOME}/.claude/claude-gauge-refresh.sh</string>
  </array>
  <key>StartInterval</key><integer>30</integer>
  <key>RunAtLoad</key><true/>
</dict></plist>
PL
chown "$REAL_USER" "$PLIST"
run_as_user launchctl bootout "gui/$REAL_UID/dev.earthonline.claude-gauge" 2>/dev/null || true
run_as_user launchctl bootstrap "gui/$REAL_UID" "$PLIST"
ok "Background refresher loaded"

# 5. First data pull + restart SwiftBar
run_as_user bash "$REAL_HOME/.claude/claude-gauge-refresh.sh" force 2>/dev/null || true
if [ -d "/Applications/SwiftBar.app" ]; then
  run_as_user osascript -e 'tell application "SwiftBar" to quit' 2>/dev/null || true
  pkill -x SwiftBar 2>/dev/null || true
  sleep 2
  run_as_user open -a SwiftBar 2>/dev/null || true
  ok "SwiftBar restarted"
fi

# 5b. SwiftBar login item
run_as_user osascript -e '
tell application "System Events"
  if not (exists login item "SwiftBar") then
    make login item at end with properties {path:"/Applications/SwiftBar.app", hidden:false}
  end if
end tell' 2>/dev/null || warn "Could not set SwiftBar as login item — add it manually in System Settings > Login Items"

# 6. Alert hooks (non-fatal)
if [ -f "$PAYLOAD/alert/install-alerts.sh" ]; then
  run_as_user bash "$PAYLOAD/alert/install-alerts.sh" 2>&1 \
    || warn "Alert hooks not installed (non-fatal)"
fi

# 6b. statusLine bridge (non-fatal)
BRIDGE="$REAL_HOME/.claude/claude-gauge-statusline.py"
run_as_user /usr/bin/python3 - "$BRIDGE" <<'PY' || warn "statusLine bridge not connected (non-fatal)"
import json, os, sys, shutil, time
P=os.path.expanduser("~/.claude/settings.json"); bridge=sys.argv[1]
raw=open(P).read() if os.path.exists(P) else ""
try: cfg=json.loads(raw) if raw.strip() else {}
except Exception: raise SystemExit(0)
cur=cfg.get("statusLine")
if isinstance(cur,dict) and (cur.get("command") or "")==bridge: raise SystemExit(0)
if cur: raise SystemExit(0)
cfg["statusLine"]={"type":"command","command":bridge}
if os.path.exists(P):
    bak=f"{P}.claude-gauge.bak.{int(time.time())}"; shutil.copy2(P,bak)
else:
    os.makedirs(os.path.dirname(P),exist_ok=True)
out=json.dumps(cfg, indent=2, ensure_ascii=False); json.loads(out)
tmp=P+".tmp"; open(tmp,"w").write(out+"\n"); os.replace(tmp,P)
PY

ok "Installation complete!"
exit 0
POSTINSTALL
chmod +x "$SCRIPTS/postinstall"

# --- build pkg ---
COMPONENT="$STAGING/claude-gauge-component.pkg"
pkgbuild \
  --nopayload \
  --scripts "$SCRIPTS" \
  --identifier "$IDENTIFIER" \
  --version "$VERSION" \
  "$COMPONENT"

productbuild \
  --package "$COMPONENT" \
  --identifier "$IDENTIFIER" \
  --version "$VERSION" \
  "$OUTPUT"

rm -rf "$STAGING"
echo "✓ Built $OUTPUT"
