#!/bin/bash
# Builds CacheTracker in release mode and assembles a proper macOS .app
# bundle around the SPM executable. A real bundle (with an Info.plist and
# bundle identifier) is required for the menu bar item and
# UNUserNotificationCenter authorization to work reliably — a bare SPM
# binary can silently fail notification authorization.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="CacheTracker"
BUNDLE_ID="com.local.cachetracker"

cd "$REPO_DIR"
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/$APP_NAME"
if [[ ! -x "$BIN_PATH" ]]; then
  echo "error: built binary not found at $BIN_PATH" >&2
  exit 1
fi

APP_BUNDLE="$REPO_DIR/$APP_NAME.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$REPO_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSUserNotificationsUsageDescription</key>
    <string>Notifies you before your Claude Code prompt cache expires so you don't pay for a full re-ingestion.</string>
    <key>NSHumanReadableCopyright</key>
    <string>Internal tool.</string>
</dict>
</plist>
PLIST

# Ad-hoc sign so the app can run locally and request notification
# authorization ("Sign to Run Locally" equivalent via codesign -s -).
codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null 2>&1 || true

echo "Built $APP_BUNDLE"

# Install into /Applications so the app has a stable path (survives repo
# cleanup, shows up in Spotlight/Launchpad) instead of only living inside
# the repo checkout.
INSTALLED_APP="/Applications/$APP_NAME.app"
pkill -9 -f "$INSTALLED_APP/Contents/MacOS/$APP_NAME" >/dev/null 2>&1 || true
rm -rf "$INSTALLED_APP"
cp -R "$APP_BUNDLE" "$INSTALLED_APP"
echo "Installed $INSTALLED_APP"
echo "Run with: open \"$INSTALLED_APP\""
