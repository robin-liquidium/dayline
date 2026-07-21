#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Dayline Mock"
BUNDLE_ID="build.local.DaylineMock"
MIN_SYSTEM_VERSION="26.0"
VERSION="0.1.0"
BUILD_NUMBER="1"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ICON_SOURCE="$ROOT_DIR/Resources/DaylineIcon.icns"
WORDMARK_SOURCE="$ROOT_DIR/Resources/DaylineWordmark.pdf"

cd "$ROOT_DIR"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
swift build
BUILD_BINARY="$(swift build --show-bin-path)/Dayline"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$APP_FRAMEWORKS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp "$ICON_SOURCE" "$APP_RESOURCES/DaylineIcon.icns"
cp "$WORDMARK_SOURCE" "$APP_RESOURCES/DaylineWordmark.pdf"
/usr/bin/ditto "$(swift build --show-bin-path)/Sparkle.framework" "$APP_FRAMEWORKS/Sparkle.framework"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key>
  <string>DaylineIcon.icns</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

/usr/bin/open -n "$APP_BUNDLE" --args --mock

for _ in {1..30}; do
  if pgrep -x "$APP_NAME" >/dev/null; then
    echo "Launched $APP_BUNDLE"
    echo "Open its menu with: DAYLINE_APP_NAME=\"$APP_NAME\" ./script/menu_test.sh open"
    exit 0
  fi
  sleep 0.1
done

echo "$APP_NAME failed to launch." >&2
exit 1
