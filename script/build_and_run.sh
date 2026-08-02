#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
PRODUCT_NAME="Dayline"
APP_NAME="Dayline Dev"
BUNDLE_ID="de.obermaier.dayline.dev"
EXPECTED_TEAM_ID="5S5288W3R7"
MIN_SYSTEM_VERSION="26.0"
OAUTH_KEYCHAIN_SERVICE="$BUNDLE_ID.oauth"
APPLICATION_SUPPORT_FOLDER="$APP_NAME"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
BUILD_ONLY_APP="$DIST_DIR/$APP_NAME.app"
INSTALLED_APP="/Applications/$APP_NAME.app"
INSTALLED_BINARY="$INSTALLED_APP/Contents/MacOS/$APP_NAME"
LEGACY_APP="$DIST_DIR/Dayline.app"
LEGACY_BINARY="$LEGACY_APP/Contents/MacOS/Dayline"
LOCK_DIR="${TMPDIR:-/tmp}/dayline-dev-installer.lock"
ICON_SOURCE="$ROOT_DIR/Resources/DaylineIcon.icns"
ICON_FILE="DaylineIcon.icns"
WORDMARK_SOURCE="$ROOT_DIR/Resources/DaylineWordmark.pdf"
WORDMARK_FILE="DaylineWordmark.pdf"
LINEAR_CLIENT_ID="${DAYLINE_LINEAR_CLIENT_ID:-00c88957100199ecb91362294a3f6e55}"
GITHUB_CLIENT_ID="${DAYLINE_GITHUB_CLIENT_ID:-Ov23litV6nyANcKL6p4l}"
LINEAR_URL_SCHEME="${DAYLINE_LINEAR_CALLBACK_SCHEME:-dayline-dev}"

case "$MODE" in
  run|--debug|debug|--logs|logs|--telemetry|telemetry|--verify|verify|--reset-privacy|reset-privacy|--build-only|build-only)
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--reset-privacy|--build-only]" >&2
    exit 2
    ;;
esac

BUILD_ONLY=false
if [[ "$MODE" == "--build-only" || "$MODE" == "build-only" ]]; then
  BUILD_ONLY=true
fi

linear_url_scheme_lower="$(printf '%s' "$LINEAR_URL_SCHEME" | tr '[:upper:]' '[:lower:]')"
if [[ ! "$LINEAR_URL_SCHEME" =~ ^[A-Za-z][A-Za-z0-9+.-]*$ ]] ||
   [[ "$linear_url_scheme_lower" == "dayline" ]]; then
  echo "Invalid Dayline Dev Linear callback scheme: $LINEAR_URL_SCHEME" >&2
  exit 2
fi

PERSISTED_APP="$INSTALLED_APP"
if [[ "$BUILD_ONLY" == true ]]; then
  PERSISTED_APP="$BUILD_ONLY_APP"
fi

GOOGLE_CLIENT_ID=""
if [[ "${DAYLINE_DEV_GOOGLE_CLIENT_ID+x}" == "x" ]]; then
  GOOGLE_CLIENT_ID="$DAYLINE_DEV_GOOGLE_CLIENT_ID"
elif [[ -f "$PERSISTED_APP/Contents/Info.plist" ]]; then
  persisted_bundle_id="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$PERSISTED_APP/Contents/Info.plist" 2>/dev/null || true)"
  if [[ "$persisted_bundle_id" == "$BUNDLE_ID" ]]; then
    GOOGLE_CLIENT_ID="$(/usr/bin/plutil -extract DaylineGoogleClientID raw -o - "$PERSISTED_APP/Contents/Info.plist" 2>/dev/null || true)"
  fi
fi

GOOGLE_URL_SCHEME=""
if [[ -n "$GOOGLE_CLIENT_ID" ]]; then
  if [[ ! "$GOOGLE_CLIENT_ID" =~ ^[A-Za-z0-9.-]+\.apps\.googleusercontent\.com$ ]]; then
    echo "DAYLINE_DEV_GOOGLE_CLIENT_ID is not a valid Google OAuth client ID." >&2
    exit 2
  fi
  GOOGLE_URL_SCHEME="com.googleusercontent.apps.${GOOGLE_CLIENT_ID%.apps.googleusercontent.com}"
  if [[ ! "$GOOGLE_URL_SCHEME" =~ ^[A-Za-z][A-Za-z0-9+.-]*$ ]]; then
    echo "Google OAuth client ID produces an invalid callback scheme." >&2
    exit 2
  fi
fi

LOCK_HELD=false
STAGING_DIR=""
INSTALL_CANDIDATE=""
PREVIOUS_APP=""
INSTALL_TRANSACTION_ACTIVE=false
INSTALL_COMMITTED=false
PREVIOUS_WAS_RUNNING=false

pids_for_executable() {
  local executable="$1"
  local process_name pid command
  process_name="$(basename "$executable")"
  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    command="$(ps -p "$pid" -o command= 2>/dev/null || true)"
    if [[ "$command" == "$executable" || "$command" == "$executable "* ]]; then
      printf '%s\n' "$pid"
    fi
  done < <(pgrep -x "$process_name" 2>/dev/null || true)
}

is_executable_running() {
  [[ -n "$(pids_for_executable "$1")" ]]
}

stop_executable() {
  local executable="$1"
  local pids pid
  pids="$(pids_for_executable "$executable")"
  if [[ -n "$pids" ]]; then
    while IFS= read -r pid; do
      [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
    done <<<"$pids"
  fi
  for _ in 1 2 3 4 5; do
    if ! is_executable_running "$executable"; then
      return
    fi
    sleep 1
  done
  echo "Process did not quit: $executable" >&2
  return 1
}

register_app() {
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$1"
}

unregister_app() {
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$1" >/dev/null 2>&1 || true
}

cleanup() {
  local status=$?
  trap - EXIT INT TERM HUP

  if [[ "$INSTALL_TRANSACTION_ACTIVE" == true && "$INSTALL_COMMITTED" != true ]]; then
    while IFS= read -r pid; do
      [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
    done < <(pids_for_executable "$INSTALLED_BINARY")
    rm -rf "$INSTALLED_APP"
    if [[ -n "$PREVIOUS_APP" && -d "$PREVIOUS_APP" ]]; then
      mv "$PREVIOUS_APP" "$INSTALLED_APP"
      register_app "$INSTALLED_APP" || true
      if [[ "$PREVIOUS_WAS_RUNNING" == true ]]; then
        /usr/bin/open -n "$INSTALLED_APP" >/dev/null 2>&1 || true
      fi
    fi
  fi

  [[ -z "$STAGING_DIR" ]] || rm -rf "$STAGING_DIR"
  [[ -z "$INSTALL_CANDIDATE" ]] || rm -rf "$INSTALL_CANDIDATE"
  if [[ "$LOCK_HELD" == true ]]; then
    rm -rf "$LOCK_DIR"
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

acquire_lock() {
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    printf '%s\n' "$$" >"$LOCK_DIR/pid"
    LOCK_HELD=true
    return
  fi

  local owner_pid=""
  owner_pid="$(sed -n '1p' "$LOCK_DIR/pid" 2>/dev/null || true)"
  if [[ "$owner_pid" =~ ^[0-9]+$ ]] && kill -0 "$owner_pid" 2>/dev/null; then
    echo "Another Dayline Dev build is already running (PID $owner_pid)." >&2
    exit 1
  fi

  rm -rf "$LOCK_DIR"
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "Could not acquire the Dayline Dev installer lock." >&2
    exit 1
  fi
  printf '%s\n' "$$" >"$LOCK_DIR/pid"
  LOCK_HELD=true
}

acquire_lock

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
/usr/bin/plutil -insert DaylineDevelopmentBuild -bool YES "$INFO_PLIST"
/usr/bin/plutil -insert DaylineOAuthKeychainService -string "$OAUTH_KEYCHAIN_SERVICE" "$INFO_PLIST"
/usr/bin/plutil -insert DaylineOAuthConfigurationIsAuthoritative -bool YES "$INFO_PLIST"
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

available_development_identities() {
  security find-identity -v -p codesigning | awk -F '"' '/"Apple Development:/ { print $2 }' | awk '!seen[$0]++'
}

DEV_SIGNING_IDENTITY="${DAYLINE_DEV_SIGNING_IDENTITY:-}"
if [[ -z "$DEV_SIGNING_IDENTITY" && -d "$INSTALLED_APP" ]]; then
  installed_authority="$(/usr/bin/codesign -dvvv "$INSTALLED_APP" 2>&1 | sed -n 's/^Authority=\(Apple Development:.*\)$/\1/p' | head -n 1)"
  if [[ -n "$installed_authority" ]]; then
    if available_development_identities | grep -Fxq "$installed_authority"; then
      DEV_SIGNING_IDENTITY="$installed_authority"
    else
      echo "The signing identity used by the installed Dayline Dev app is unavailable: $installed_authority" >&2
      exit 2
    fi
  fi
fi

if [[ -z "$DEV_SIGNING_IDENTITY" ]]; then
  identities=()
  while IFS= read -r identity; do
    [[ -n "$identity" ]] && identities+=("$identity")
  done < <(available_development_identities)
  if [[ ${#identities[@]} -eq 1 ]]; then
    DEV_SIGNING_IDENTITY="${identities[0]}"
  elif [[ "$BUILD_ONLY" == true && ${#identities[@]} -eq 0 ]]; then
    DEV_SIGNING_IDENTITY="-"
  else
    echo "Select one stable Apple Development identity with DAYLINE_DEV_SIGNING_IDENTITY." >&2
    exit 2
  fi
fi

SIGNING_ARGS=(--force --options runtime --sign "$DEV_SIGNING_IDENTITY")
if [[ "$MODE" == "--debug" || "$MODE" == "debug" ]]; then
  DEBUG_ENTITLEMENTS="$STAGING_DIR/DaylineDevDebug.entitlements"
  /usr/bin/plutil -create xml1 "$DEBUG_ENTITLEMENTS"
  /usr/bin/plutil -insert com.apple.security.get-task-allow -bool YES "$DEBUG_ENTITLEMENTS"
  SIGNING_ARGS+=(--entitlements "$DEBUG_ENTITLEMENTS")
fi

/usr/bin/codesign "${SIGNING_ARGS[@]}" "$APP_FRAMEWORKS/Sparkle.framework"
/usr/bin/codesign "${SIGNING_ARGS[@]}" "$APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

signature_details="$(/usr/bin/codesign -dvvv "$APP_BUNDLE" 2>&1)"
if [[ "$signature_details" != *"runtime"* ]]; then
  echo "Dayline Dev was not signed with Hardened Runtime." >&2
  exit 2
fi
if [[ "$DEV_SIGNING_IDENTITY" != "-" ]]; then
  team_id="$(sed -n 's/^TeamIdentifier=//p' <<<"$signature_details" | head -n 1)"
  if [[ "$team_id" != "$EXPECTED_TEAM_ID" ]]; then
    echo "Dayline Dev signing team $team_id does not match $EXPECTED_TEAM_ID." >&2
    exit 2
  fi
fi

if [[ "$BUILD_ONLY" == true ]]; then
  mkdir -p "$DIST_DIR"
  rm -rf "$BUILD_ONLY_APP"
  /usr/bin/ditto "$APP_BUNDLE" "$BUILD_ONLY_APP"
  /usr/bin/codesign --verify --deep --strict --verbose=2 "$BUILD_ONLY_APP"
  echo "Built $BUILD_ONLY_APP"
  exit 0
fi

PREVIOUS_WAS_RUNNING=false
if is_executable_running "$INSTALLED_BINARY"; then
  PREVIOUS_WAS_RUNNING=true
fi
stop_executable "$INSTALLED_BINARY"

INSTALL_CANDIDATE="/Applications/.$APP_NAME.installing-$$.app"
PREVIOUS_APP="/Applications/.$APP_NAME.previous-$$.app"
rm -rf "$INSTALL_CANDIDATE" "$PREVIOUS_APP"
/usr/bin/ditto "$APP_BUNDLE" "$INSTALL_CANDIDATE"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$INSTALL_CANDIDATE"

INSTALL_TRANSACTION_ACTIVE=true
if [[ -e "$INSTALLED_APP" ]]; then
  mv "$INSTALLED_APP" "$PREVIOUS_APP"
fi
if [[ -e "$INSTALLED_APP" ]]; then
  echo "$INSTALLED_APP unexpectedly reappeared during installation." >&2
  exit 1
fi
mv "$INSTALL_CANDIDATE" "$INSTALLED_APP"
register_app "$INSTALLED_APP"

if [[ -d "$LEGACY_APP" ]]; then
  legacy_bundle_id="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$LEGACY_APP/Contents/Info.plist" 2>/dev/null || true)"
  if [[ "$legacy_bundle_id" == "build.local.Dayline" ]]; then
    stop_executable "$LEGACY_BINARY"
    unregister_app "$LEGACY_APP"
    rm -rf "$LEGACY_APP"
  fi
fi

if [[ "$MODE" == "--reset-privacy" || "$MODE" == "reset-privacy" ]]; then
  /usr/bin/tccutil reset Calendar "$BUNDLE_ID"
  /usr/bin/tccutil reset Reminders "$BUNDLE_ID"
fi

open_and_verify() {
  /usr/bin/open -n "$INSTALLED_APP"
  for _ in 1 2 3 4 5; do
    if is_executable_running "$INSTALLED_BINARY"; then
      return
    fi
    sleep 1
  done
  echo "$APP_NAME did not launch from $INSTALLED_BINARY." >&2
  return 1
}

commit_install() {
  rm -rf "$PREVIOUS_APP"
  INSTALL_COMMITTED=true
  INSTALL_TRANSACTION_ACTIVE=false
  rm -rf "$STAGING_DIR" "$INSTALL_CANDIDATE"
  if [[ "$LOCK_HELD" == true ]]; then
    rm -rf "$LOCK_DIR"
    LOCK_HELD=false
  fi
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
