#!/bin/bash
# Merges the cache-tracker hooks into ~/.claude/settings.json without
# clobbering any hooks a teammate already has configured.
set -euo pipefail

SETTINGS="$HOME/.claude/settings.json"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK_SCRIPT="$REPO_DIR/hooks/cache-touch.sh"

if [[ ! -x "$HOOK_SCRIPT" ]]; then
  echo "error: $HOOK_SCRIPT not found or not executable" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required (brew install jq)" >&2
  exit 1
fi

mkdir -p "$(dirname "$SETTINGS")"
if [[ ! -f "$SETTINGS" ]]; then
  echo '{}' > "$SETTINGS"
fi

cp "$SETTINGS" "$SETTINGS.bak.$(date +%s)"

TMP=$(mktemp)
jq \
  --arg command "$HOOK_SCRIPT" \
  '
  def addHook(event):
    .hooks[event] = ((.hooks[event] // []) as $existing
      | if ($existing | any(.matcher == "*" and (.hooks[]?.command == $command)))
        then $existing
        else $existing + [{matcher: "*", hooks: [{type: "command", command: $command}]}]
        end);

  # Merely resuming/opening a session (SessionStart) does not touch the
  # actual prompt cache, so it should not reset last-activity. Drop any
  # prior install of this hook on that event.
  def removeHook(event):
    if (.hooks[event]? != null) then
      .hooks[event] = (.hooks[event] | map(
        if .matcher == "*" then
          .hooks = (.hooks | map(select(.command != $command)))
        else . end
      ) | map(select((.hooks | length) > 0)))
    else . end;

  removeHook("SessionStart")
  | addHook("PreToolUse")
  | addHook("PostToolUse")
  | addHook("UserPromptSubmit")
  ' \
  "$SETTINGS" > "$TMP"

mv "$TMP" "$SETTINGS"
echo "Installed cache-tracker hooks into $SETTINGS (backup written alongside it)."
