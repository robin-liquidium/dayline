#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEV_PLIST="$ROOT_DIR/dist/Dayline Dev.app/Contents/Info.plist"
MOCK_PLIST="$ROOT_DIR/dist/Dayline Mock.app/Contents/Info.plist"
RELEASE_PLIST="$ROOT_DIR/dist/release/Dayline.app/Contents/Info.plist"
DEV_APP="$ROOT_DIR/dist/Dayline Dev.app"
RELEASE_APP="$ROOT_DIR/dist/release/Dayline.app"
RELEASE_DMG="$ROOT_DIR/dist/artifacts/Dayline-0.1.0-dev.dmg"
TEST_GOOGLE_CLIENT_ID="1234567890-dayline-dev-contract.apps.googleusercontent.com" # autoreview:allow-secret
TEST_GOOGLE_SCHEME="com.googleusercontent.apps.1234567890-dayline-dev-contract"
INSTALLER_LOCK_DIR="${TMPDIR:-/tmp}/dayline-dev-installer.lock"
LOG_FILE="$(mktemp -t dayline-bundle-contract.XXXXXX)"
MALFORMED_PLIST="$(mktemp -t dayline-malformed-plist.XXXXXX)"
DMG_MOUNT=""

cleanup() {
  if [[ -n "$DMG_MOUNT" && -d "$DMG_MOUNT" ]]; then
    /usr/bin/hdiutil detach "$DMG_MOUNT" >/dev/null 2>&1 || true
    rmdir "$DMG_MOUNT" 2>/dev/null || true
  fi
  rm -f "$LOG_FILE" "$MALFORMED_PLIST"
  rm -rf "$INSTALLER_LOCK_DIR"
}
trap cleanup EXIT

cd "$ROOT_DIR"

fail() {
  echo "app_bundle_contract_test: $*" >&2
  tail -80 "$LOG_FILE" >&2 || true
  exit 1
}

plist_value() {
  /usr/bin/plutil -extract "$2" raw -o - "$1" 2>/dev/null
}

assert_value() {
  local plist="$1"
  local key="$2"
  local expected="$3"
  local actual
  actual="$(plist_value "$plist" "$key" || true)"
  [[ "$actual" == "$expected" ]] || fail "$plist $key was '$actual', expected '$expected'"
}

assert_nonempty() {
  local actual
  actual="$(plist_value "$1" "$2" || true)"
  [[ -n "$actual" ]] || fail "$1 is missing non-empty $2"
}

assert_missing() {
  if /usr/bin/plutil -extract "$2" raw -o - "$1" >/dev/null 2>&1; then
    fail "$1 unexpectedly contains $2"
  fi
}

assert_eventkit_entitlement() {
  local value
  value="$(/usr/bin/codesign -d --entitlements :- "$1" 2>/dev/null \
    | /usr/bin/plutil -extract 'com\.apple\.security\.personal-information\.calendars' raw -expect bool -o - - 2>/dev/null || true)"
  [[ "$value" == "true" ]] || fail "$1 is missing the EventKit entitlement"
}

url_schemes() {
  local plist="$1"
  local type_index=0
  local scheme_index value
  /usr/bin/plutil -lint "$plist" >/dev/null 2>&1 || fail "$plist is not a readable property list"
  while /usr/libexec/PlistBuddy -c "Print :CFBundleURLTypes:$type_index" "$plist" >/dev/null 2>&1; do
    scheme_index=0
    while value="$(/usr/libexec/PlistBuddy -c "Print :CFBundleURLTypes:$type_index:CFBundleURLSchemes:$scheme_index" "$plist" 2>/dev/null)"; do
      printf '%s\n' "$value"
      scheme_index=$((scheme_index + 1))
    done
    type_index=$((type_index + 1))
  done
}

assert_url_scheme() {
  local schemes
  schemes="$(url_schemes "$1")"
  grep -Fxq "$2" <<<"$schemes" || fail "$1 does not register URL scheme $2"
}

assert_no_google_url_scheme() {
  local schemes
  schemes="$(url_schemes "$1")"
  if grep -Fq 'com.googleusercontent.apps.' <<<"$schemes"; then
    fail "$1 unexpectedly registers a Google URL scheme"
  fi
}

printf '%s\n' 'not a property list' >"$MALFORMED_PLIST"
if (url_schemes "$MALFORMED_PLIST" >/dev/null 2>&1); then
  fail "malformed property list unexpectedly passed URL-scheme extraction"
fi

rm -rf "$INSTALLER_LOCK_DIR"
mkdir "$INSTALLER_LOCK_DIR"
printf '%s\n' "$$" >"$INSTALLER_LOCK_DIR/pid"
if ./script/build_and_run.sh --build-only >"$LOG_FILE" 2>&1; then
  fail "concurrent installer lock was ignored"
fi
grep -Fq "Another Dayline Dev build is already running" "$LOG_FILE" ||
  fail "concurrent installer failure was not explained"

rm -rf "$INSTALLER_LOCK_DIR"
mkdir "$INSTALLER_LOCK_DIR"
printf '%s\n' "999999" >"$INSTALLER_LOCK_DIR/pid"

DAYLINE_DEV_GOOGLE_CLIENT_ID="$TEST_GOOGLE_CLIENT_ID" \
  ./script/build_and_run.sh --build-only >"$LOG_FILE" 2>&1
assert_value "$DEV_PLIST" CFBundleIdentifier "de.obermaier.dayline.dev"
assert_value "$DEV_PLIST" DaylineApplicationSupportFolder "Dayline Dev"
assert_value "$DEV_PLIST" DaylineOAuthKeychainService "de.obermaier.dayline.dev.oauth"
assert_value "$DEV_PLIST" DaylineDevelopmentBuild "true"
assert_value "$DEV_PLIST" DaylineOAuthConfigurationIsAuthoritative "true"
assert_value "$DEV_PLIST" DaylineLinearCallbackScheme "dayline-dev"
assert_value "$DEV_PLIST" DaylineGoogleClientID "$TEST_GOOGLE_CLIENT_ID"
assert_nonempty "$DEV_PLIST" NSRemindersFullAccessUsageDescription
assert_url_scheme "$DEV_PLIST" dayline-dev
assert_url_scheme "$DEV_PLIST" "$TEST_GOOGLE_SCHEME"
assert_missing "$DEV_PLIST" SUFeedURL
assert_eventkit_entitlement "$DEV_APP"

./script/build_and_run.sh --build-only >"$LOG_FILE" 2>&1
assert_value "$DEV_PLIST" DaylineGoogleClientID "$TEST_GOOGLE_CLIENT_ID"
assert_url_scheme "$DEV_PLIST" "$TEST_GOOGLE_SCHEME"

DAYLINE_DEV_GOOGLE_CLIENT_ID="" ./script/build_and_run.sh --build-only >"$LOG_FILE" 2>&1
assert_value "$DEV_PLIST" DaylineGoogleClientID ""
assert_no_google_url_scheme "$DEV_PLIST"

./script/build_mock_and_run.sh --build-only >"$LOG_FILE" 2>&1
assert_value "$MOCK_PLIST" CFBundleIdentifier "build.local.DaylineMock"
assert_value "$MOCK_PLIST" DaylineApplicationSupportFolder "Dayline Mock"
assert_value "$MOCK_PLIST" DaylineOAuthKeychainService "build.local.DaylineMock.oauth"
assert_nonempty "$MOCK_PLIST" NSRemindersFullAccessUsageDescription
assert_missing "$MOCK_PLIST" SUFeedURL

MARKETING_VERSION="0.1.0-dev" CODESIGN_IDENTITY="-" \
  ./script/package_release.sh >"$LOG_FILE" 2>&1
assert_value "$RELEASE_PLIST" CFBundleIdentifier "de.obermaier.dayline"
assert_value "$RELEASE_PLIST" DaylineApplicationSupportFolder "Dayline"
assert_value "$RELEASE_PLIST" DaylineOAuthKeychainService "build.local.Dayline.oauth"
assert_nonempty "$RELEASE_PLIST" NSRemindersFullAccessUsageDescription
assert_nonempty "$RELEASE_PLIST" SUFeedURL
assert_url_scheme "$RELEASE_PLIST" dayline
assert_url_scheme "$RELEASE_PLIST" com.googleusercontent.apps.551177930544-9sl0govp6ok205csb939j4p2dhckrgbk
assert_eventkit_entitlement "$RELEASE_APP"

DMG_MOUNT="$(mktemp -d "${TMPDIR:-/tmp}/dayline-dmg-contract.XXXXXX")"
/usr/bin/hdiutil attach -readonly -nobrowse -mountpoint "$DMG_MOUNT" "$RELEASE_DMG" >/dev/null
[[ -d "$DMG_MOUNT/Dayline.app" ]] || fail "release DMG is missing Dayline.app"
[[ -L "$DMG_MOUNT/Applications" ]] || fail "release DMG is missing the Applications drop link"
[[ "$(readlink "$DMG_MOUNT/Applications")" == "/Applications" ]] ||
  fail "release DMG Applications link has the wrong destination"
[[ -f "$DMG_MOUNT/.DS_Store" ]] || fail "release DMG is missing Finder layout metadata"
[[ -f "$DMG_MOUNT/.background/DaylineDMGBackground.png" ]] ||
  fail "release DMG is missing its arrow background"
/usr/bin/hdiutil detach "$DMG_MOUNT" >/dev/null
rmdir "$DMG_MOUNT"
DMG_MOUNT=""

echo "app_bundle_contract_test: passed"
