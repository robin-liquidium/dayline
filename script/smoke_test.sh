#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

./script/build_and_run.sh --verify

read -r STATUS_X STATUS_Y STATUS_W STATUS_H <<EOF
$(osascript <<'APPLESCRIPT'
tell application "System Events" to tell process "StatusWidget"
  set p to position of menu bar item 1 of menu bar 2
  set s to size of menu bar item 1 of menu bar 2
  return ((item 1 of p) as text) & " " & ((item 2 of p) as text) & " " & ((item 1 of s) as text) & " " & ((item 2 of s) as text)
end tell
APPLESCRIPT
)
EOF

STATUS_CENTER_X="$((STATUS_X + STATUS_W / 2))"
STATUS_CENTER_Y="$((STATUS_Y + STATUS_H / 2))"

STATUS_CENTER_X="$STATUS_CENTER_X" STATUS_CENTER_Y="$STATUS_CENTER_Y" python3 - <<'PY'
import os
import time
import Quartz

x = int(os.environ["STATUS_CENTER_X"])
y = int(os.environ["STATUS_CENTER_Y"])
for event_type in (Quartz.kCGEventLeftMouseDown, Quartz.kCGEventLeftMouseUp):
    event = Quartz.CGEventCreateMouseEvent(None, event_type, (x, y), Quartz.kCGMouseButtonLeft)
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, event)
    time.sleep(0.08)
PY

osascript <<'APPLESCRIPT'
tell application "System Events"
  repeat 20 times
    if exists process "StatusWidget" then exit repeat
    delay 0.25
  end repeat

  tell process "StatusWidget"
    delay 1

    if not (exists window 1) then error "Status popover did not open"
    if not (exists static text "Today" of group 1 of window 1) then error "Today header missing"
    if not (exists static text "Up Next" of group 1 of window 1) then error "Up Next section missing"
    if not (exists static text "Linear" of group 1 of window 1) then error "Linear section missing"
    if (count of buttons of group 1 of window 1) < 3 then error "Popover actions missing"

    set popoverButtons to buttons of group 1 of window 1
    click item ((count of popoverButtons) - 1) of popoverButtons
    delay 1

    if not (exists window "General") then error "Settings window did not open"
    if value of attribute "AXMain" of window "General" is not true then error "Settings window is not frontmost"
  end tell
end tell
APPLESCRIPT

pgrep -x StatusWidget >/dev/null
