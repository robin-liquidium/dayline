#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Dayline"
BUNDLE_ID="build.local.Dayline"
MIN_SYSTEM_VERSION="26.0"

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
ICON_FILE="DaylineIcon.icns"
WORDMARK_SOURCE="$ROOT_DIR/Resources/DaylineWordmark.pdf"
WORDMARK_FILE="DaylineWordmark.pdf"

cd "$ROOT_DIR"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

swift build
BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$APP_FRAMEWORKS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
/usr/bin/ditto "$(swift build --show-bin-path)/Sparkle.framework" "$APP_FRAMEWORKS/Sparkle.framework"

if [[ -f "$ICON_SOURCE" ]]; then
  cp "$ICON_SOURCE" "$APP_RESOURCES/$ICON_FILE"
fi
cp "$WORDMARK_SOURCE" "$APP_RESOURCES/$WORDMARK_FILE"

# Keep these in sync with AuthConfig / AuthProvider callback schemes.
GOOGLE_CLIENT_ID="${DAYLINE_GOOGLE_CLIENT_ID:-551177930544-9sl0govp6ok205csb939j4p2dhckrgbk.apps.googleusercontent.com}"
GOOGLE_URL_SCHEME="com.googleusercontent.apps.${GOOGLE_CLIENT_ID%.apps.googleusercontent.com}"
LINEAR_CLIENT_ID="${DAYLINE_LINEAR_CLIENT_ID:-00c88957100199ecb91362294a3f6e55}"
GITHUB_CLIENT_ID="${DAYLINE_GITHUB_CLIENT_ID:-Ov23litV6nyANcKL6p4l}"
# Dev builds use a distinct callback scheme so OAuth redirects reach this app
# instead of an installed production build. Requires dayline-dev://oauth/callback
# to be registered as a redirect URI in the Linear OAuth app.
LINEAR_URL_SCHEME="${DAYLINE_LINEAR_CALLBACK_SCHEME:-dayline-dev}"

VERSION="$(git describe --tags --exact-match 2>/dev/null | sed 's/^v//' || true)"
VERSION="${VERSION:-0.1.0-dev}"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 0)"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key>
  <string>$ICON_FILE</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>DaylineGoogleClientID</key>
  <string>$GOOGLE_CLIENT_ID</string>
  <key>DaylineLinearClientID</key>
  <string>$LINEAR_CLIENT_ID</string>
  <key>DaylineGitHubClientID</key>
  <string>$GITHUB_CLIENT_ID</string>
  <key>DaylineLinearCallbackScheme</key>
  <string>$LINEAR_URL_SCHEME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key>
      <string>$BUNDLE_ID.oauth.linear</string>
      <key>CFBundleURLSchemes</key>
      <array>
        <string>$LINEAR_URL_SCHEME</string>
      </array>
    </dict>
    <dict>
      <key>CFBundleURLName</key>
      <string>$BUNDLE_ID.oauth.google</string>
      <key>CFBundleURLSchemes</key>
      <array>
        <string>$GOOGLE_URL_SCHEME</string>
      </array>
    </dict>
  </array>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSMultipleInstancesProhibited</key>
  <true/>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

# Sign the complete bundle so its metadata and resources are sealed too.
DEV_SIGNING_IDENTITY="${DAYLINE_DEV_SIGNING_IDENTITY:-}"
if [[ -z "$DEV_SIGNING_IDENTITY" ]]; then
  IDENTITY_OUTPUT="$(security find-identity -v -p codesigning)"
  while IFS= read -r identity_line; do
    if [[ "$identity_line" =~ \"(Apple\ Development:[^\"]*)\" ]]; then
      DEV_SIGNING_IDENTITY="${BASH_REMATCH[1]}"
      break
    fi
  done <<< "$IDENTITY_OUTPUT"
fi
if [[ -n "$DEV_SIGNING_IDENTITY" ]]; then
  /usr/bin/codesign --force --sign "$DEV_SIGNING_IDENTITY" "$APP_FRAMEWORKS/Sparkle.framework"
  /usr/bin/codesign --force --sign "$DEV_SIGNING_IDENTITY" "$APP_BUNDLE"
fi

open_app() {
  /usr/bin/open "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --direct|direct)
    "$APP_BINARY"
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--direct|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
