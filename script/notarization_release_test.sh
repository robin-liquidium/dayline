#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/script/notarization_release.sh"

TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dayline-notarization-test.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT

WORK_DIR="$TEST_DIR/work"
REPOSITORY="owner/dayline"
READY_STATE='{
  "stage": "ready_to_publish",
  "tag": "v9.9.9",
  "version": "9.9.9",
  "app_zip_asset": "Dayline-9.9.9.app.zip",
  "app_zip_sha256": "app-sha",
  "final_dmg_asset": "Dayline-9.9.9.dmg",
  "final_dmg_sha256": "dmg-sha",
  "stable_dmg_asset": "Dayline.dmg",
  "stable_dmg_sha256": "dmg-sha",
  "appcast_asset": "appcast.xml",
  "appcast_sha256": "appcast-sha"
}'

fail() {
  echo "notarization_release_test: $*" >&2
  exit 1
}

EVENTS=()

latest_stable_tag() {
  return 0
}

release_notes_for_version() {
  printf '%s\n' "Release notes"
}

verify_ready_release_assets() {
  EVENTS+=("verify")
  mkdir -p "$(dirname "$3")"
  printf '<rss/>\n' > "$3"
}

delete_submission_assets() {
  EVENTS+=("delete")
}

publish_appcast() {
  EVENTS+=("appcast")
}

gh() {
  if [[ " $* " == *" --method PATCH "* ]]; then
    EVENTS+=("publish")
    return 0
  fi
  printf '%s\n' '{"id":42,"draft":true,"assets":[]}'
}

publish_ready_release 42 "$READY_STATE" >/dev/null
[[ "${EVENTS[*]}" == "verify delete publish appcast" ]] ||
  fail "expected verification and cleanup before publication, got: ${EVENTS[*]}"

EVENTS=()
delete_submission_assets() {
  EVENTS+=("delete")
  return 1
}

if publish_ready_release 42 "$READY_STATE" >/dev/null 2>&1; then
  fail "publication succeeded after temporary asset cleanup failed"
fi
[[ "${EVENTS[*]}" == "verify delete" ]] ||
  fail "publication continued after cleanup failure: ${EVENTS[*]}"

EVENTS=()
delete_submission_assets() {
  EVENTS+=("delete")
}
gh() {
  if [[ " $* " == *" --method PATCH "* ]]; then
    EVENTS+=("publish")
    return 1
  fi
  printf '%s\n' '{"id":42,"draft":true,"assets":[]}'
}

if publish_ready_release 42 "$READY_STATE" >/dev/null 2>&1; then
  fail "publication unexpectedly succeeded after the GitHub publish request failed"
fi
[[ "${EVENTS[*]}" == "verify delete publish" ]] ||
  fail "publish failure did not stop before appcast deployment: ${EVENTS[*]}"

EVENTS=()
release_for_tag() {
  printf '%s\n' '{"id":42,"draft":true}'
}
state_from_release() {
  printf '%s\n' "$READY_STATE"
}
ensure_symbols_asset() {
  EVENTS+=("symbols")
}
publish_ready_release() {
  EVENTS+=("resume")
}

continue_release v9.9.9 >/dev/null
[[ "${EVENTS[*]}" == "symbols resume" ]] ||
  fail "ready_to_publish did not resume from final assets: ${EVENTS[*]}"

echo "notarization_release_test: passed"
