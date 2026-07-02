#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Dayline"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IDENTIFIERS_FILE="$(mktemp -t dayline-identifiers.XXXXXX)"
trap 'rm -f "$IDENTIFIERS_FILE"' EXIT

cd "$ROOT_DIR"

./script/build_and_run.sh --verify

./script/menu_test.sh identifiers >"$IDENTIFIERS_FILE"

for identifier in \
  "dayline.refresh" \
  "calendar.tomorrow.toggle" \
  "linear.showMore" \
  "dayline.settings" \
  "dayline.quit"
do
  if ! grep -q "$identifier" "$IDENTIFIERS_FILE"; then
    echo "Missing accessibility identifier: $identifier" >&2
    cat "$IDENTIFIERS_FILE" >&2
    exit 1
  fi
done

./script/menu_test.sh press-id dayline.settings

osascript <<'APPLESCRIPT'
tell application "System Events"
  tell process "Dayline"
    repeat 20 times
      if exists window "Dayline Settings" then exit repeat
      delay 0.25
    end repeat

    if not (exists window "Dayline Settings") then error "Settings window did not open"
    if value of attribute "AXMain" of window "Dayline Settings" is not true then error "Settings window is not frontmost"
  end tell
end tell
APPLESCRIPT

pgrep -x "$APP_NAME" >/dev/null
