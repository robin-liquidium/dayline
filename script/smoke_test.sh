#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Dayline Dev"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IDENTIFIERS_FILE="$(mktemp -t dayline-identifiers.XXXXXX)"
trap 'rm -f "$IDENTIFIERS_FILE"' EXIT
export DAYLINE_APP_NAME="$APP_NAME"

cd "$ROOT_DIR"

./script/build_and_run.sh --verify

./script/menu_test.sh identifiers >"$IDENTIFIERS_FILE"

for identifier in \
  "dayline.refresh" \
  "calendar.tomorrow.toggle" \
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

osascript <<APPLESCRIPT
tell application "System Events"
  tell process "$APP_NAME"
    repeat 20 times
      if exists window "$APP_NAME Settings" then exit repeat
      delay 0.25
    end repeat

    if not (exists window "$APP_NAME Settings") then error "Settings window did not open"
    if value of attribute "AXMain" of window "$APP_NAME Settings" is not true then error "Settings window is not frontmost"
  end tell
end tell
APPLESCRIPT

pgrep -x "$APP_NAME" >/dev/null
