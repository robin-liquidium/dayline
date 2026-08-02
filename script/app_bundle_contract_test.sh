#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEV_PLIST="$ROOT_DIR/dist/Dayline Dev.app/Contents/Info.plist"
MOCK_PLIST="$ROOT_DIR/dist/Dayline Mock.app/Contents/Info.plist"
RELEASE_PLIST="$ROOT_DIR/dist/release/Dayline.app/Contents/Info.plist"
TEST_GOOGLE_CLIENT_ID="1234567890-dayline-dev-contract.apps.googleusercontent.com" # autoreview:allow-secret
TEST_GOOGLE_SCHEME="com.googleusercontent.apps.1234567890-dayline-dev-contract"
INSTALLER_LOCK_DIR="${TMPDIR:-/tmp}/dayline-dev-installer.lock"
LOG_FILE="$(mktemp -t dayline-bundle-contract.XXXXXX)"
trap 'rm -f "$LOG_FILE"; rm -rf "$INSTALLER_LOCK_DIR"' EXIT

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

url_schemes() {
  local plist="$1"
  local type_index=0
  local scheme_index value
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

echo "app_bundle_contract_test: passed"
