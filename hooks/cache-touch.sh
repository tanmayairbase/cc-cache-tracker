#!/bin/bash
# Claude Code hook (PreToolUse/PostToolUse/SessionStart, matcher "*", sync).
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

# Prefer the custom-title Claude Code generates for the session (appears as
# a {"type":"custom-title","customTitle":"..."} line anywhere in the
# transcript, once generated, not necessarily the first line — take the
# last one in case it's regenerated); fall back to the directory name if
# it's missing.
TITLE=""
if [[ -f "$TRANSCRIPT" ]]; then
  TITLE=$(grep -a 'custom-title' "$TRANSCRIPT" 2>/dev/null | tail -n 1 | jq -r 'select(.type == "custom-title") | .customTitle' 2>/dev/null || true)
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
