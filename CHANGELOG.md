# Changelog

All notable changes to ClaudeGauge will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-06-13

First public release. A macOS menu-bar gauge for Claude Code (Pro/Max)
usage — real-time, state-aware, self-healing, and never shows stale data
pretending to be fresh.

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
- macOS notifications when crossing the 75% / 90% thresholds, once per
  window per round.

#### Self-healing token (key innovation)
- Claude Code does not refresh the keychain token while idle, so it
  eventually expires and the API returns 401. When the token is within
  20 minutes of expiry, the refresher runs a one-shot headless
  `claude -p ok` from `/tmp` so Claude Code uses its refresh token to renew
  and write the new token back to the keychain — at negligible cost — after
  which normal API polling resumes.

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

[0.1.0]: https://github.com/EarthOnlineDev/claude-gauge/releases/tag/v0.1.0
