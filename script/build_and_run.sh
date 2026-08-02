#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
PRODUCT_NAME="Dayline"
APP_NAME="Dayline Dev"
BUNDLE_ID="de.obermaier.dayline.dev"
MIN_SYSTEM_VERSION="26.0"
OAUTH_KEYCHAIN_SERVICE="$BUNDLE_ID.oauth"
APPLICATION_SUPPORT_FOLDER="$APP_NAME"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLED_APP="/Applications/$APP_NAME.app"
INSTALLED_BINARY="$INSTALLED_APP/Contents/MacOS/$APP_NAME"
ICON_SOURCE="$ROOT_DIR/Resources/DaylineIcon.icns"
ICON_FILE="DaylineIcon.icns"
WORDMARK_SOURCE="$ROOT_DIR/Resources/DaylineWordmark.pdf"
WORDMARK_FILE="DaylineWordmark.pdf"
LINEAR_CLIENT_ID="${DAYLINE_LINEAR_CLIENT_ID:-00c88957100199ecb91362294a3f6e55}"
GITHUB_CLIENT_ID="${DAYLINE_GITHUB_CLIENT_ID:-Ov23litV6nyANcKL6p4l}"
LINEAR_URL_SCHEME="${DAYLINE_LINEAR_CALLBACK_SCHEME:-dayline-dev}"
GOOGLE_CLIENT_ID="${DAYLINE_DEV_GOOGLE_CLIENT_ID:-}"

case "$MODE" in
  run|--debug|debug|--logs|logs|--telemetry|telemetry|--verify|verify|--reset-privacy|reset-privacy)
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--reset-privacy]" >&2
    exit 2
    ;;
esac

if [[ ! "$LINEAR_URL_SCHEME" =~ ^[A-Za-z][A-Za-z0-9+.-]*$ ]]; then
  echo "Invalid Dayline Dev Linear callback scheme: $LINEAR_URL_SCHEME" >&2
  exit 2
fi

GOOGLE_URL_SCHEME=""
if [[ -n "$GOOGLE_CLIENT_ID" ]]; then
  if [[ ! "$GOOGLE_CLIENT_ID" =~ ^[A-Za-z0-9._-]+\.apps\.googleusercontent\.com$ ]]; then
    echo "DAYLINE_DEV_GOOGLE_CLIENT_ID is not a Google OAuth client ID." >&2
    exit 2
  fi
  GOOGLE_URL_SCHEME="com.googleusercontent.apps.${GOOGLE_CLIENT_ID%.apps.googleusercontent.com}"
fi

BUILD_CONFIGURATION="release"
if [[ "$MODE" == "--debug" || "$MODE" == "debug" ]]; then
  BUILD_CONFIGURATION="debug"
fi

cd "$ROOT_DIR"

swift build -c "$BUILD_CONFIGURATION"
BIN_DIR="$(swift build -c "$BUILD_CONFIGURATION" --show-bin-path)"
BUILD_BINARY="$BIN_DIR/$PRODUCT_NAME"

if [[ ! -x "$BUILD_BINARY" ]]; then
  echo "Missing built Dayline executable: $BUILD_BINARY" >&2
  exit 2
fi
if [[ ! -f "$ICON_SOURCE" || ! -f "$WORDMARK_SOURCE" ]]; then
  echo "Missing Dayline app resources." >&2
  exit 2
fi

STAGING_DIR="$(mktemp -d)"
APP_BUNDLE="$STAGING_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
INSTALL_CANDIDATE="/Applications/.$APP_NAME.installing-$$.app"
PREVIOUS_APP="/Applications/.$APP_NAME.previous-$$.app"
INSTALL_SWAPPED=false
INSTALL_COMMITTED=false

cleanup() {
  if [[ "$INSTALL_SWAPPED" == true && "$INSTALL_COMMITTED" != true ]]; then
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
    rm -rf "$INSTALLED_APP"
    if [[ -d "$PREVIOUS_APP" ]]; then
      mv "$PREVIOUS_APP" "$INSTALLED_APP"
    fi
  fi
  rm -rf "$STAGING_DIR" "$INSTALL_CANDIDATE"
}
trap cleanup EXIT

mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$APP_FRAMEWORKS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
/usr/bin/ditto "$BIN_DIR/Sparkle.framework" "$APP_FRAMEWORKS/Sparkle.framework"
cp "$ICON_SOURCE" "$APP_RESOURCES/$ICON_FILE"
cp "$WORDMARK_SOURCE" "$APP_RESOURCES/$WORDMARK_FILE"

VERSION="$(git describe --tags --exact-match 2>/dev/null | sed 's/^v//' || true)"
VERSION="${VERSION:-0.1.0-dev}"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 0)"

/usr/bin/plutil -create xml1 "$INFO_PLIST"
/usr/bin/plutil -insert CFBundleDevelopmentRegion -string "en" "$INFO_PLIST"
/usr/bin/plutil -insert CFBundleDisplayName -string "$APP_NAME" "$INFO_PLIST"
/usr/bin/plutil -insert CFBundleExecutable -string "$APP_NAME" "$INFO_PLIST"
/usr/bin/plutil -insert CFBundleIconFile -string "$ICON_FILE" "$INFO_PLIST"
/usr/bin/plutil -insert CFBundleIdentifier -string "$BUNDLE_ID" "$INFO_PLIST"
/usr/bin/plutil -insert CFBundleInfoDictionaryVersion -string "6.0" "$INFO_PLIST"
/usr/bin/plutil -insert CFBundleName -string "$APP_NAME" "$INFO_PLIST"
/usr/bin/plutil -insert CFBundlePackageType -string "APPL" "$INFO_PLIST"
/usr/bin/plutil -insert CFBundleShortVersionString -string "$VERSION" "$INFO_PLIST"
/usr/bin/plutil -insert CFBundleVersion -string "$BUILD_NUMBER" "$INFO_PLIST"
/usr/bin/plutil -insert LSApplicationCategoryType -string "public.app-category.productivity" "$INFO_PLIST"
/usr/bin/plutil -insert LSMinimumSystemVersion -string "$MIN_SYSTEM_VERSION" "$INFO_PLIST"
/usr/bin/plutil -insert LSMultipleInstancesProhibited -bool YES "$INFO_PLIST"
/usr/bin/plutil -insert LSUIElement -bool YES "$INFO_PLIST"
/usr/bin/plutil -insert NSPrincipalClass -string "NSApplication" "$INFO_PLIST"
/usr/bin/plutil -insert NSCalendarsUsageDescription -string "Dayline shows your upcoming Apple Calendar events in the menu bar." "$INFO_PLIST"
/usr/bin/plutil -insert NSCalendarsFullAccessUsageDescription -string "Dayline shows your upcoming Apple Calendar events in the menu bar." "$INFO_PLIST"
/usr/bin/plutil -insert NSRemindersFullAccessUsageDescription -string "Dayline shows and manages your Apple Reminders from the menu bar." "$INFO_PLIST"
/usr/bin/plutil -insert DaylineApplicationSupportFolder -string "$APPLICATION_SUPPORT_FOLDER" "$INFO_PLIST"
/usr/bin/plutil -insert DaylineOAuthKeychainService -string "$OAUTH_KEYCHAIN_SERVICE" "$INFO_PLIST"
/usr/bin/plutil -insert DaylineGoogleClientID -string "$GOOGLE_CLIENT_ID" "$INFO_PLIST"
/usr/bin/plutil -insert DaylineLinearClientID -string "$LINEAR_CLIENT_ID" "$INFO_PLIST"
/usr/bin/plutil -insert DaylineGitHubClientID -string "$GITHUB_CLIENT_ID" "$INFO_PLIST"
/usr/bin/plutil -insert DaylineLinearCallbackScheme -string "$LINEAR_URL_SCHEME" "$INFO_PLIST"

/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes array" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0 dict" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLName string $BUNDLE_ID.oauth.linear" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes array" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string $LINEAR_URL_SCHEME" "$INFO_PLIST"
if [[ -n "$GOOGLE_URL_SCHEME" ]]; then
  /usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:1 dict" "$INFO_PLIST"
  /usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:1:CFBundleURLName string $BUNDLE_ID.oauth.google" "$INFO_PLIST"
  /usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:1:CFBundleURLSchemes array" "$INFO_PLIST"
  /usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:1:CFBundleURLSchemes:0 string $GOOGLE_URL_SCHEME" "$INFO_PLIST"
fi

DEV_SIGNING_IDENTITY="${DAYLINE_DEV_SIGNING_IDENTITY:-}"
if [[ -z "$DEV_SIGNING_IDENTITY" ]]; then
  DEV_SIGNING_IDENTITY="$(security find-identity -v -p codesigning | awk -F '"' '/"Apple Development:/ { print $2; exit }')"
fi
if [[ -z "$DEV_SIGNING_IDENTITY" ]]; then
  echo "Dayline Dev requires an Apple Development signing identity so privacy approvals remain stable." >&2
  exit 2
fi

/usr/bin/codesign --force --sign "$DEV_SIGNING_IDENTITY" "$APP_FRAMEWORKS/Sparkle.framework"
/usr/bin/codesign --force --sign "$DEV_SIGNING_IDENTITY" "$APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

stop_running_app() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5; do
    if ! pgrep -x "$APP_NAME" >/dev/null; then
      return
    fi
    sleep 1
  done
  echo "$APP_NAME did not quit." >&2
  exit 1
}

stop_running_app
rm -rf "$INSTALL_CANDIDATE" "$PREVIOUS_APP"
/usr/bin/ditto "$APP_BUNDLE" "$INSTALL_CANDIDATE"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$INSTALL_CANDIDATE"

if [[ -e "$INSTALLED_APP" ]]; then
  mv "$INSTALLED_APP" "$PREVIOUS_APP"
fi
if ! mv "$INSTALL_CANDIDATE" "$INSTALLED_APP"; then
  if [[ -d "$PREVIOUS_APP" ]]; then
    mv "$PREVIOUS_APP" "$INSTALLED_APP"
  fi
  exit 1
fi
INSTALL_SWAPPED=true

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$INSTALLED_APP"

if [[ "$MODE" == "--reset-privacy" || "$MODE" == "reset-privacy" ]]; then
  /usr/bin/tccutil reset Calendar "$BUNDLE_ID"
  /usr/bin/tccutil reset Reminders "$BUNDLE_ID"
fi

open_and_verify() {
  if ! /usr/bin/open -n "$INSTALLED_APP"; then
    exit 1
  fi

  local pid=""
  for _ in 1 2 3 4 5; do
    pid="$(pgrep -x "$APP_NAME" | head -n 1 || true)"
    if [[ -n "$pid" ]]; then
      break
    fi
    sleep 1
  done
  if [[ -z "$pid" ]]; then
    echo "$APP_NAME did not launch." >&2
    exit 1
  fi

  local command
  command="$(ps -p "$pid" -o command=)"
  if [[ "$command" != "$INSTALLED_BINARY" ]]; then
    echo "Unexpected $APP_NAME process: $command" >&2
    exit 1
  fi
}

commit_install() {
  rm -rf "$PREVIOUS_APP"
  INSTALL_COMMITTED=true
  rm -rf "$STAGING_DIR" "$INSTALL_CANDIDATE"
}

case "$MODE" in
  --debug|debug)
    commit_install
    exec lldb -- "$INSTALLED_BINARY"
    ;;
  --logs|logs)
    open_and_verify
    commit_install
    exec /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_and_verify
    commit_install
    exec /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  run|--verify|verify|--reset-privacy|reset-privacy)
    open_and_verify
    commit_install
    ;;
esac

echo "Installed and launched $INSTALLED_APP"
echo "Build: $BUILD_CONFIGURATION, bundle ID: $BUNDLE_ID"
if [[ -z "$GOOGLE_CLIENT_ID" ]]; then
  echo "Google Calendar OAuth is disabled until DAYLINE_DEV_GOOGLE_CLIENT_ID is configured."
fi
