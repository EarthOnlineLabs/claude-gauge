# ClaudeGauge

> Your Claude Code usage, right in the menu bar — a glance is all it takes.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Platform: macOS](https://img.shields.io/badge/platform-macOS-black.svg)
![Powered by SwiftBar](https://img.shields.io/badge/powered%20by-SwiftBar-orange.svg)

[简体中文](README.zh-CN.md)

![ClaudeGauge — the menu bar gauge and its expanded dropdown showing 5-hour and weekly usage](./docs/screenshots/showcase.png)

When you're deep in Claude Code, the same question keeps nagging: *how much of my 5-hour limit is left? Am I about to hit the weekly wall?* Finding out means stopping to run `/usage` or open the [claude.ai usage page](https://claude.ai/settings/usage). ClaudeGauge keeps that number in the top-right of your menu bar, so you never have to break flow to check.

## One number, three colors

The whole tool is a single percentage that changes color as a limit gets closer. You don't read it — you just notice it:

- **Black** — plenty left. It stays quiet and out of the way.
- **Orange** — getting low (75%+). It brings along a reset countdown, so you can decide whether to push on or wait.
- **Red** — nearly out (90%+).

Click it for the full breakdown: your current 5-hour window and this week's window, each with a progress bar and a reset time. If the data goes stale, the number grays out — so you can always tell whether you're looking at something current.

![ClaudeGauge in its warning and critical states — the gauge and dropdown turn amber at 75%, red at 90%, surfacing the window that's biting](./docs/screenshots/states.png)

<sub>Whichever window is about to bite is the one that surfaces — amber for the 5-hour session, red for the weekly wall — each with its reset countdown.</sub>

## Safe to leave running

A usage gauge has to read your account, so *how* it does that matters more than any feature:

- **Reads only your usage** — never your conversations, prompts, files, or code. (Most usage trackers read your `~/.claude` conversation logs to count usage; this one never does.)
- **Talks only to Anthropic** — your token goes to Anthropic's own usage endpoint and nowhere else: no third-party servers, none of ours, no analytics.
- **Open and auditable** — plain bash and python with no obfuscation; read it before you run it. Uninstalling removes everything and never touches your credentials.
- **Tiny** — a small menu-bar script plus a light background refresh. That's the whole thing.

## Install

```bash
git clone https://github.com/EarthOnlineDev/claude-gauge.git
cd claude-gauge
./install.sh
```

The percentage appears in the top-right of your menu bar within a few seconds. To remove it later: `./uninstall.sh` — it cleans up completely and never touches your credentials.

> Requires macOS, a Claude **Pro or Max** subscription, and a logged-in [Claude Code](https://claude.com/claude-code). The menu-bar host [SwiftBar](https://github.com/swiftbar/SwiftBar) is installed for you if it's missing.

**Optional — live updates while you work.** Add one line to `~/.claude/settings.json` (merge it if you already have a `statusLine`):

```json
"statusLine": { "type": "command", "command": "~/.claude/claude-gauge-statusline.py" }
```

Now the menu bar updates instantly as you use Claude Code — all local, zero cost. It only affects sessions started after you add it. Without it, the background refresher still updates every minute or so.

## How it works (for the curious)

ClaudeGauge is three small, independent pieces that talk only through files in `~/.cache/claude-gauge/`, so any one can fail without taking the others down:

- **Render** — a [SwiftBar](https://github.com/swiftbar/SwiftBar) plugin that draws the number and the dropdown.
- **Refresh** — a background job that fetches your usage from the same endpoint Claude Code's `/usage` uses, authenticating with the token Claude Code already keeps in your keychain. It **polls adaptively** — barely at all when you have headroom, faster as a limit approaches — to stay well clear of rate limits. It also **keeps itself alive at zero cost**: that token expires while Claude Code is idle, so when it's about to, the refresher renews it with a direct OAuth refresh — an auth call that costs nothing against your quota, never a prompt or an inference. The gauge never goes dead.
- **Bridge (optional)** — lets Claude Code hand its live usage numbers straight to the gauge, for the instant updates described above.

On a MacBook with a notch, the menu-bar text is always kept short enough that the notch can't swallow it.

For the full design — the layers, the display rules, and the data flow — see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Contributing

Issues and pull requests are welcome. ClaudeGauge is released under the [MIT License](LICENSE) by [EarthOnline](https://github.com/EarthOnlineDev).
