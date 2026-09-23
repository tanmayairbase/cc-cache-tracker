<div align="center">
  <img src="docs/icon.png" width="96" height="96" alt="CacheTracker icon">
  <h1>CacheTracker</h1>
</div>

Claude Code's prompt cache has a 1-hour TTL. There's no API to check if a
session's cache is still warm; the only real signal is time since last
activity. Lose track of that and you eat an expensive silent re-ingestion
next time you touch a stale session. CacheTracker watches your active
sessions' last-activity time and warns you before that happens.

It lives in the menu bar, not pinned to a specific spot on the built-in
display, because most of the team works off external monitors.

- Badge = count of active sessions, colored by worst case: **blue** (fresh),
  **orange** (40–55 min idle), **red** (55+ min idle, not handed off).
- Notification when a session first crosses into orange, and again when it
  crosses into red.
  <img width="359" height="92" alt="Screenshot 2026-08-26 at 12-41-29" src="https://github.com/user-attachments/assets/7be4dd22-1f13-47c6-b0f0-7dc16473be23" /> and <img width="362" height="92" alt="Screenshot 2026-08-26 at 12-56-20" src="https://github.com/user-attachments/assets/5f7f7512-b33d-4598-8335-c9089c897471" />


- Click the badge for a session list; check one off to mark it done/handed
  off (auto-reopens if that session sees new activity).

## Install

Requires `jq`.

```
./scripts/install-hooks.sh   # merges hooks into ~/.claude/settings.json, doesn't clobber existing ones
./scripts/build-app.sh
open /Applications/CacheTracker.app
```

Grant notification permission when prompted. No Dock icon, menu bar only.
No launch-at-login yet, so relaunch after reboots.

## How it works

`hooks/cache-touch.sh` fires on every Claude Code tool call and user prompt
submit, writing last-activity state to `~/.claude/cache-tracker/`. It does
not fire on `SessionStart`: just resuming/opening a session (e.g. clicking
it in the macOS app's sidebar) doesn't send anything to the API, so that
event doesn't move the timer. The app
polls that directory every 60s and computes status from elapsed time.
Marking a session done writes to a separate `handoffs.json` so it's never
clobbered by the hook. Sessions idle 24h+ drop out of the active list but
their state file is left on disk.

## Uninstall

Remove the `hooks/cache-touch.sh` entries from `~/.claude/settings.json`,
quit the app, delete `/Applications/CacheTracker.app`, optionally delete
`~/.claude/cache-tracker/`.
