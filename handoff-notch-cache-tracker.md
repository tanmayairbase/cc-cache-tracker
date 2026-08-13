# Handoff: Claude Code Cache Tracker (macOS Notch App)

**Status:** Design complete, zero code written. Starting from scratch.
**Prepared:** 2026-08-13
**For:** Claude Code, picking this up fresh in a new session.

---

## 1. What we're building

A macOS menu bar / notch-area app that tracks active Claude Code sessions and
warns before their prompt cache expires, so the user doesn't eat a full
re-ingestion cost by accident.

- Floating panel positioned next to the MacBook notch, always visible.
- Circular badge showing count of active sessions, colored by worst-case state:
  - **Blue** — all sessions fresh (last activity < 45 min ago)
  - **Orange** — at least one session 45–60 min since last activity (expiring in ≤15m)
  - **Red** — at least one session past 60 min and not marked done/handed-off
- Native notification (with sound) when a session crosses into the orange
  zone: *"Cache expiring in 15m for '\<session title>'"*
- Click the badge → popover listing sessions (title, dir/worktree) with a
  per-session menu to mark **Done / Handed off**.
- One 60-second poll loop. No need for a separate 10-min poll — the data
  source (local JSON files) is cheap enough to scan every cycle.

## 2. Confirmed environment facts (do not re-derive, just build against these)

- Org uses **Claude Code against the Anthropic API directly** (not Bedrock/Vertex).
- **1-hour cache TTL is enabled** for this org (confirmed by the user, not
  assumed). This is why the thresholds below are set at 45m / 60m, not
  the Pro-tier 5-minute default.
- Cache state cannot be queried directly from Claude Code or the API — there
  is no endpoint for "is this cache still warm." The only viable signal is
  **time since last API call per session**, tracked via hooks. Treat this as
  an approximation, not ground truth — it's the same limitation every
  cache-timer tool in this space has.

## 3. IMPORTANT CORRECTION to earlier design

An earlier draft of this design assumed Claude Code hooks pass data via
**environment variables** (`$CLAUDE_SESSION_ID`, `$CLAUDE_CWD`). **This is
wrong.** Verified against current Claude Code hooks docs:

> Hooks receive JSON **on stdin**, not env vars. The common envelope
> includes `session_id`, `cwd`, `transcript_path`, and `hook_event_name`,
> plus event-specific fields like `tool_name` and `tool_input`.

So the hook script must be:

```bash
#!/bin/bash
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
CWD=$(echo "$INPUT" | jq -r '.cwd')
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path')

HASH=$(echo -n "$CWD" | md5 | cut -c1-8)
STATE_DIR="$HOME/.claude/notch-tracker"
mkdir -p "$STATE_DIR"

cat > "$STATE_DIR/session-$HASH.json" <<EOF
{
  "session_id": "$SESSION_ID",
  "cwd": "$CWD",
  "transcript_path": "$TRANSCRIPT",
  "title": "$(basename "$CWD")",
  "last_touch": $(date +%s)
}
EOF
```

Register on **PreToolUse and PostToolUse**, matcher `"*"`, synchronous (no
`async: true` — it fires a noisy system notification on every tool call).

**Also verify/decide before implementing further:**
- Whether to *also* hook `SessionStart` / `SessionEnd` — these would let the
  app detect new/closed sessions immediately instead of only inferring
  activity from tool calls. Worth adding; not yet designed.
- Session title: current plan uses `basename(cwd)`. Better option —
  `transcript_path` points to the session's `.jsonl` transcript; the first
  user message in that file is likely a better title than the directory
  name. Not yet implemented — decide during build.

## 4. Scope decision (confirmed with user)

**"Team sharing from the start"** — clarify what this means in practice,
since Claude Code state (`~/.claude/`) is inherently per-machine/per-user:

- This is **not** a multi-user synced dashboard. Each engineer runs their
  own instance against their own local `~/.claude/notch-tracker` files.
- "Team sharing" means: the **app + hook config are distributable** — a
  git repo any engineer on the team can clone, build, and install, with the
  hook wiring documented/scriptable so it's a copy-paste setup, not a
  bespoke one-off.
- Design implication: don't hardcode the user's home directory or machine
  specifics anywhere; keep the hook install step scriptable
  (`scripts/install-hooks.sh` that merges into `settings.json` rather than
  overwriting it, since teammates may already have hooks configured).
- **Not yet decided, ask the user if it comes up:** should the handed-off
  state file survive `git pull` / dotfile sync, or is it purely local
  machine state? Recommend purely local (`~/.claude/notch-tracker/`, not
  synced) unless told otherwise.

## 5. Repo recommendation (confirmed direction: new standalone repo)

Reasoning, for context if this gets questioned later: forking boringNotch
was considered and rejected — it pulls in a large SwiftUI codebase (media
controls, file shelf, calendar widgets) that has nothing to do with this
tool, adds license/merge overhead, and couples us to their release cycle.
The only thing worth borrowing from it is the **notch-adjacent NSPanel
positioning technique** — reference it, don't fork it.

Suggested repo name: `claude-cache-notch` (placeholder — user hasn't
confirmed final name).

Suggested structure:
```
claude-cache-notch/
├── README.md                  # what it is, install steps, screenshots
├── hooks/
│   └── cache-touch.sh          # the hook script from section 3
├── scripts/
│   └── install-hooks.sh        # merges hook config into settings.json
├── NotchCacheTracker/          # Xcode project
│   ├── NotchCacheTracker.xcodeproj
│   ├── App/
│   │   ├── NotchCacheTrackerApp.swift
│   │   └── AppDelegate.swift
│   ├── Models/
│   │   ├── SessionState.swift
│   │   └── CacheStatus.swift
│   ├── Services/
│   │   ├── SessionStore.swift      # reads/merges state files
│   │   ├── Poller.swift            # 60s timer
│   │   └── NotificationService.swift
│   ├── UI/
│   │   ├── NotchPanel.swift        # NSPanel host
│   │   ├── BadgeView.swift         # circular count badge
│   │   └── SessionListPopover.swift
│   └── Resources/
│       └── Info.plist              # notification permission usage string
└── docs/
    └── architecture.md
```

## 6. Task checklist for this session

Rough build order, not strict:

1. [ ] `git init` new repo, scaffold Xcode project (macOS app, SwiftUI,
   min target macOS 14+ since notch MacBooks start there; confirm exact
   min version needed once we know which Mac models are in scope).
2. [ ] Write `hooks/cache-touch.sh`, test it standalone with a piped fake
   JSON payload (see hooks docs example: `echo '{"session_id":"x",...}' |
   bash cache-touch.sh`).
3. [ ] Write `scripts/install-hooks.sh` — merge into `~/.claude/settings.json`
   without clobbering existing hooks (use `jq` to splice into the hooks array).
4. [ ] `SessionState` + `CacheStatus` models (section 3 field names + 45m/60m
   thresholds from section 1).
5. [ ] `SessionStore` — scan `~/.claude/notch-tracker/*.json`, merge with a
   separate `handoffs.json` for done/handed-off overrides (must not be
   clobbered by hook writes — see prior design note on this).
6. [ ] `Poller` — 60s `Timer`, recompute statuses, diff against previous
   poll to fire notifications only on state *transitions* (fresh→orange,
   not every poll while orange).
7. [ ] `NotificationService` — request `UNUserNotificationCenter`
   authorization on launch, fire local notification with sound on
   fresh→orange transition.
8. [ ] `NotchPanel` — borderless `NSPanel`, positioned via
   `NSScreen.main!.safeAreaInsets`, always-on-top, non-activating.
9. [ ] `BadgeView` — circular SwiftUI badge, border + text color driven by
   `CacheStatus`, background per section 1 color map.
10. [ ] `SessionListPopover` — session rows (title, cwd/worktree) + a
    `Menu` per row with "Mark done/handed-off".
11. [ ] Manual test pass: run a real Claude Code session, confirm hook
    files appear, confirm badge transitions blue→orange near the 45m mark,
    confirm notification fires once, confirm mark-done sticks across polls
    and doesn't get reverted by subsequent hook writes.
12. [ ] `README.md` with install steps for a teammate: clone, build, run
    `scripts/install-hooks.sh`, grant notification permission.

## 7. Explicitly out of scope for this pass

- Any cross-machine or cross-user sync of session state.
- App Store distribution / notarization (internal tool — direct build or
  internal signing is fine for now; revisit if it needs wider rollout).
- Handling Bedrock/Vertex-backed Claude Code (org confirmed direct API use).
- Precise cache-state accuracy guarantees — this is explicitly a
  best-effort proxy based on last-tool-call time, not a real cache query.

## 8. Open questions to raise with the user during/after build

- Final repo name and where it should be hosted (internal GitHub org?).
- Minimum macOS version to support across the team's machines.
- Whether `SessionStart`/`SessionEnd` hooks should be added for faster
  session discovery (currently: new sessions only appear once the first
  tool call fires `PreToolUse`).
- Whether handed-off state should ever expire/reset (e.g., a session marked
  done that gets touched again 3 days later — should it silently reopen?).

---

## 9. Grill session update (2026-08-13) — decisions locked, starting build

- **Repo**: local only for now (`git init` in this directory, name
  `cc-cache-tracker`). No remote/org/host decided yet — revisit later.
- **Min macOS version**: 14+ (Sonoma). No need to support older OSes unless
  a teammate reports one.
- **Hooks**: `PreToolUse` + `PostToolUse` (sync, matcher `"*"`) as designed,
  **plus `SessionStart`** so a session appears in the app the instant it
  opens rather than waiting for the first tool call. **No `SessionEnd`** —
  there's no reliable "session closed" signal (crashes, closed terminals),
  so staleness is handled via the 45m/60m thresholds and the 24h auto-hide
  below instead of trying to detect closure.
- **Session title**: Claude Code already writes a first-line
  `{"type":"ai-title","aiTitle":"..."}` entry into the transcript `.jsonl`.
  Read and cache that in the hook-written state file; fall back to
  `basename(cwd)` if the line is missing or malformed. (AgentStash was
  checked as a reference and turned out to be for GitHub Copilot sessions,
  not Claude Code — no reusable logic there.)
- **Handoff expiry**: a session marked done/handed-off silently reopens the
  moment a new hook fires for it (any new tool call = real activity = real
  cache-expiry risk again). No manual-only lock.
- **Stale session cleanup**: sessions with no activity for 24h are
  auto-hidden from the badge count and popover list, but their JSON state
  file is left on disk — no deletion, no destructive cleanup path.
- **Launch at login**: deferred to v2. Not building `SMAppService`
  registration in this pass.
- **Cache thresholds**: hardcoded constants (45m/60m) in `CacheStatus.swift`.
  No settings UI / `UserDefaults` plumbing for v1.
- **Notification signing**: confirmed as a non-issue — a local, unsigned
  ("Sign to Run Locally") Xcode build gets a bundle identifier automatically
  and can request `UNUserNotificationCenter` authorization without a
  Developer ID or notarization.

Build starting now against the checklist in section 6, in order.
