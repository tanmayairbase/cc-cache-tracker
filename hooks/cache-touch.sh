#!/bin/bash
# Claude Code hook (PreToolUse/PostToolUse/SessionStart, matcher "*", sync).
# Reads the hook JSON envelope on stdin and records last-activity state for
# the notch cache tracker app. See docs/architecture.md.
set -euo pipefail

INPUT=$(cat)

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
CWD=$(echo "$INPUT" | jq -r '.cwd')
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path')

HASH=$(echo -n "$CWD" | md5 | cut -c1-8)
STATE_DIR="$HOME/.claude/notch-tracker"
mkdir -p "$STATE_DIR"

# Prefer the ai-title Claude Code writes as the transcript's first line;
# fall back to the directory name if it's missing/malformed.
TITLE=""
if [[ -f "$TRANSCRIPT" ]]; then
  TITLE=$(head -n 1 "$TRANSCRIPT" 2>/dev/null | jq -r 'select(.type == "ai-title") | .aiTitle' 2>/dev/null || true)
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
