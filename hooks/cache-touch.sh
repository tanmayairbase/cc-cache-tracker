#!/bin/bash
# Claude Code hook (PreToolUse/PostToolUse/UserPromptSubmit, matcher "*", sync).
# Not SessionStart: merely resuming/viewing a session (e.g. clicking it in
# the macOS app's sidebar) fires SessionStart without any real API call, so
# it would falsely reset the tracked activity time.
# Reads the hook JSON envelope on stdin and records last-activity state for
# the CacheTracker menu bar app. See README.md.
set -euo pipefail

INPUT=$(cat)

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
CWD=$(echo "$INPUT" | jq -r '.cwd')
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path')

HASH=$(echo -n "$CWD" | md5 | cut -c1-8)
STATE_DIR="$HOME/.claude/cache-tracker"
mkdir -p "$STATE_DIR"

# Prefer ai-title (the auto-generated name shown in Claude Code's own
# "Resume session" picker), then custom-title (a user-set override), then
# the directory name. Both appear as {"type":...} lines anywhere in the
# transcript, not necessarily the first line, and can repeat as they're
# regenerated, so take the last occurrence of whichever is found.
TITLE=""
if [[ -f "$TRANSCRIPT" ]]; then
  TITLE=$(grep -a -E '"type": ?"ai-title"' "$TRANSCRIPT" 2>/dev/null \
    | while IFS= read -r line; do echo "$line" | jq -r 'select(.type == "ai-title") | .aiTitle' 2>/dev/null; done \
    | tail -n 1 || true)
fi
if [[ -z "$TITLE" || "$TITLE" == "null" ]] && [[ -f "$TRANSCRIPT" ]]; then
  TITLE=$(grep -a -E '"type": ?"custom-title"' "$TRANSCRIPT" 2>/dev/null \
    | while IFS= read -r line; do echo "$line" | jq -r 'select(.type == "custom-title") | .customTitle' 2>/dev/null; done \
    | tail -n 1 || true)
fi
if [[ -z "$TITLE" || "$TITLE" == "null" ]]; then
  TITLE=$(basename "$CWD")
fi

jq -n \
  --arg session_id "$SESSION_ID" \
  --arg cwd "$CWD" \
  --arg transcript_path "$TRANSCRIPT" \
  --arg title "$TITLE" \
  --argjson last_touch "$(date +%s)" \
  '{session_id: $session_id, cwd: $cwd, transcript_path: $transcript_path, title: $title, last_touch: $last_touch}' \
  > "$STATE_DIR/session-$HASH.json"
