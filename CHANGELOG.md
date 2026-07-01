# Changelog

All notable changes to ClaudeGauge will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.1]

### Fixed
- **CG can no longer display another account's usage — defense in depth.** Two
  independent gaps could make the menu bar show data that wasn't the logged-in
  user's:
  1. *Credential read wasn't pinned to you.* All three readers (refresher,
     plugin, diagnostic) looked up the keychain by service name only
     (`Claude Code-credentials`), without an account. If another machine's item
     arrived via iCloud Keychain sync or a Migration-Assistant/clone transfer, a
     service-only lookup could return that *foreign* credential. Reads now pin to
     the local macOS user (`security … -a "$(id -un)"`) first, falling back to
     service-only only for older CCs that stored the account differently; the
     OAuth write-back targets the exact item it read (never creating a second
     entry).
  2. *Cached data carried no owner identity.* `cache.json`/`live.json` stored the
     numbers without binding them to a credential, so a stale or copied cache
     would be shown verbatim. Every cached datum is now stamped with `fp` — a
     one-way fingerprint (`sha256("cg1:"+accessToken)[:16]`, never the token
     itself) of the token that fetched it. The menu bar displays a datum only when
     its `fp` equals the fingerprint of the token currently in the keychain;
     anything else (a foreign/synced credential's data, a previous account's
     leftovers after switching, a copied cache) has a different `fp` and is
     refused — the plugin instead fetches fresh with the current token. The
     fingerprint needs no network (immune to the usage API's aggressive 429s) and
     is always computable, so there is no "no-org"/"bootstrap-failed" hole. The
     statusline bridge stamps `live.json` the same way (reading the pinned keychain
     token locally, no network; fingerprint cached ~90s to keep the CC statusline
     fast). Net effect: however another account's credential or cache reaches the
     machine, a logged-in user only ever sees their own data; the worst case on a
     token rotation is a brief, honest "stale/unavailable" — never someone else's
     numbers. `org.json` is now used only to supply the usage API's organization
     header, itself gated by the same fingerprint.
- The diagnostic lists every same-service keychain item and warns when more than
  one exists.

## [Unreleased]

### Fixed
- **The completion alert no longer turns rainbow while you're at your computer.**
  It used to flip to rainbow whenever the Claude window wasn't the frontmost app
  at the exact instant a turn finished — so briefly switching to another app
  (e.g. a browser) while you were sitting right there still triggered it. The
  alert now also checks how long you've actually been idle and only lights when
  the turn finishes after you've been away from the keyboard for ≥90s (genuinely
  stepped away), not when you're present and just app-switching. It reads only
  the system idle *duration* (via IOKit `HIDIdleTime`) — never any app content,
  no permission prompt. `attention.json` gains an `idle` field; the threshold is
  the tunable `AWAY_SEC` in the plugin.
- **The gauge now survives a reboot / power-off.** SwiftBar (the menu-bar host
  that runs the plugin) was never registered to launch at login, so after a full
  shutdown it didn't come back — and because the "show/hide with Claude" logic
  lives *inside* the plugin, opening Claude couldn't bring the gauge back either
  (nothing was running to detect Claude). `./install.sh` now registers SwiftBar
  as a login item (idempotent, non-fatal), so the host is always up and the
  gauge reappears with Claude as intended. `./uninstall.sh` removes that login
  item again — and, when ClaudeGauge is SwiftBar's only plugin, also quits
  SwiftBar and (if SwiftBar was installed via Homebrew) `brew uninstall`s it for
  a fully clean removal (all kept intact if you run other SwiftBar plugins).

### Changed
- **Completion alert is now on by default.** `./install.sh` merges the alert's
  `Stop` / `PermissionRequest` / `Notification` hooks into
  `~/.claude/settings.json` for you (backed up first, idempotent, re-parsed for
  validity, atomic write, and never touching hooks you already have), and
  `./uninstall.sh` symmetrically removes only those entries again (also backed
  up, leaving your other hooks untouched). Previously it was an opt-in layer you
  had to enable separately with `bash alert/install-alerts.sh`; that command
  still works for toggling it on its own. The hook merge is non-fatal — a
  missing or malformed `settings.json` is skipped with a warning and never
  blocks the menu-bar install.
- **Landing page** re-skinned in the EarthOnline/AISelf v0.6 design language
  (Songti/Fraunces serif, spectrum accents, dark code panel, spectrum-∞
  footer). Nav slimmed to GitHub / Install / language toggle; footer trimmed
  (GitHub merged into the MIT line). Browser-language auto-detect (zh →
  Chinese, otherwise English).
- **Landing fonts self-hosted** (Fraunces, JetBrains Mono, and a page-subset
  of Noto Serif SC) under `site/fonts/` — the marketing site now makes **zero
  third-party requests**; Chinese falls back to system Songti SC on macOS.
- **SwiftBar dropdown** trimmed via `swiftbar.hide*` plugin metadata: the
  host's auto-appended footer (last-updated / run-in-terminal / disable-plugin
  / about / SwiftBar submenu) is hidden, so the menu ends cleanly at the
  "refresh now" action.

## [0.1.0] - 2026-06-13

First public release. A macOS menu-bar gauge for Claude Code (Pro/Max)
usage — real-time, state-aware, zero-cost self-healing, and never shows
stale data pretending to be fresh.

### Added

#### Render layer (SwiftBar plugin)
- Menu-bar title as a single state-aware signal light. Shows **used %**
  (same direction as Claude Code `/usage` — higher means fuller), suffixed
  with `%`. The 5-hour window shows with no prefix (i.e. "now"); the
  weekly window uses a `W` prefix.
- "Silent when fine": when usage is comfortable it shows only the current
  5h window in adaptive near-black/white text and hides the weekly window.
  When a window starts to bite, it surfaces only that window with a color
  warning plus a reset countdown.
- When both windows are warning, it shows the more severe one; the weekly
  window takes priority once it goes critical (the 7-day hard wall).
- Thresholds: used **<75%** comfortable / **75–89%** needs attention
  (orange `#e08a2b`) / **≥90%** critical (red `#e0483d`). No green —
  comfortable renders as adaptive near-black/white.
- Width-aware for notched Macs: the title stays within ~11 characters so
  the notch never swallows it.
- Honest staleness: if data is older than 15 minutes the title turns gray,
  gets a `~` suffix, and the dropdown shows a warning. Stale data is never
  passed off as current.
- Dropdown detail: every row is explicitly colored (SwiftBar renders
  uncolored/action-less rows as disabled gray), with the progress bar as
  the primary (enlarged) signal and the countdown as small gray secondary
  text. Per-window sections for the 5h and 7-day windows, plus per-model
  (Sonnet/Opus) weekly breakdown when present, an "updated at" line, and a
  "refresh now" action that force-pulls the latest data.
- Fallback fetch: if the background data is missing or older than 150s, the
  plugin itself reads the keychain OAuth token and calls the usage endpoint
  directly so the menu bar can still render.

#### Data layer (LaunchAgent refresher)
- Background refresher (`launchctl` label `dev.earthonline.claude-gauge`),
  triggered every 30s, with adaptive throttling: 45s when critical / 60s
  when needs-attention or actively changing / 240s when comfortable and
  idle (to avoid 429s).
- Calls `https://api.anthropic.com/api/oauth/usage` (same source as
  Claude Code `/usage`), authenticated with the OAuth token read from the
  macOS keychain item "Claude Code-credentials".
- Atomic writes to `cache.json` so the plugin never reads a half-written
  file.

#### Self-healing token (key innovation, zero cost)
- Claude Code does not refresh the keychain token while idle, so it
  eventually expires and the API returns 401. When the token is within
  60 seconds of expiry, the refresher renews it directly via the OAuth
  `refresh_token` grant (`platform.claude.com/v1/oauth/token`) and writes
  the rotated tokens back to the keychain — updating only the three
  `claudeAiOauth` fields and preserving everything else (including
  `mcpOAuth`). This is a pure auth call with **zero quota cost** — no
  prompt, no inference. The tight 60-second window avoids racing Claude
  Code's own proactive 5-minute refresh while it's actively in use.

#### Bridge layer (optional Claude Code statusLine)
- `claude-gauge-statusline.py` can be wired in as a Claude Code
  `statusLine` command. It reads `rate_limits` (`five_hour` / `seven_day`
  `used_percentage` + `resets_at`) from the status-bar JSON and writes
  `live.json`. While you actively use Claude Code, the menu bar refreshes
  instantly with zero API/token cost. Only applies to sessions started
  after configuring `statusLine`; an existing `statusLine` must be merged
  manually.

### Security & privacy
- Reads only the keychain OAuth token and calls only the Anthropic usage
  endpoint. Never reads `~/.claude/projects` conversation or code files.
- No telemetry. The token is only ever sent to Anthropic.
- All code is readable bash/Python with no obfuscation.

### Install
- `git clone` then `./install.sh`; uninstall with `./uninstall.sh`
  (leaves Claude Code credentials and data untouched). Cache lives in
  `~/.cache/claude-gauge/`.

[0.1.0]: https://github.com/EarthOnlineLabs/claude-gauge/releases/tag/v0.1.0
