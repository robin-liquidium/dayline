#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${DAYLINE_APP_NAME:-Dayline}"
MENU_ITEM_NAME="Calendar"

usage() {
  cat >&2 <<USAGE
usage: $0 <command> [args]

Commands:
  open                         Open the Dayline menu bar popover.
  bounds                       Print the menu bar item bounds.
  tree                         Print the popover accessibility tree.
  identifiers                  Print exposed AXIdentifier values.
  screenshot [path]            Open the popover and capture a cropped screenshot.
  press <button-index>         Press a button inside the popover scroll area.
  press-id <identifier>        Press an element by AXIdentifier.
  hover <refresh|settings|quit> Move the pointer over a common chrome control.
  scroll <up|down> [steps]     Scroll the open popover.

Common identifiers:
  dayline.refresh
  dayline.settings
  dayline.quit
  calendar.tomorrow.toggle
  linear.showMore
  linear.showLess
USAGE
}

require_app() {
  if ! pgrep -x "$APP_NAME" >/dev/null; then
    echo "$APP_NAME is not running. Run ./script/build_and_run.sh first." >&2
    exit 1
  fi
}

menu_item_bounds() {
  for _ in {1..30}; do
    if osascript <<APPLESCRIPT
tell application "System Events"
  tell process "$APP_NAME"
    if exists menu bar item "$MENU_ITEM_NAME" of menu bar 2 then
      set itemRef to menu bar item "$MENU_ITEM_NAME" of menu bar 2
    else
      set itemRef to menu bar item 1 of menu bar 2
    end if
    set p to position of itemRef
    set s to size of itemRef
    return ((item 1 of p) as text) & " " & ((item 2 of p) as text) & " " & ((item 1 of s) as text) & " " & ((item 2 of s) as text)
  end tell
end tell
APPLESCRIPT
    then
      return
    fi
    sleep 0.1
  done

  echo "Could not find Dayline menu bar item." >&2
  exit 1
}

window_count() {
  osascript <<APPLESCRIPT
tell application "System Events"
  tell process "$APP_NAME"
    return count of windows
  end tell
end tell
APPLESCRIPT
}

click_point() {
  local x="$1"
  local y="$2"
  POINT_X="$x" POINT_Y="$y" python3 - <<'PY'
import os
import time
import Quartz

x = int(float(os.environ["POINT_X"]))
y = int(float(os.environ["POINT_Y"]))
for event_type in (Quartz.kCGEventLeftMouseDown, Quartz.kCGEventLeftMouseUp):
    event = Quartz.CGEventCreateMouseEvent(None, event_type, (x, y), Quartz.kCGMouseButtonLeft)
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, event)
    time.sleep(0.08)
PY
}

open_popover() {
  require_app
  if [[ "$(window_count)" != "0" ]]; then
    return
  fi

  read -r x y w h <<<"$(menu_item_bounds)"
  click_point "$((x + w / 2))" "$((y + h / 2))"

  for _ in {1..20}; do
    if [[ "$(window_count)" != "0" ]]; then
      return
    fi
    sleep 0.1
  done

  echo "Dayline popover did not open." >&2
  exit 1
}

popover_bounds() {
  osascript <<APPLESCRIPT
tell application "System Events"
  tell process "$APP_NAME"
    if not (exists window 1) then error "Dayline popover is not open"
    set p to position of window 1
    set s to size of window 1
    return ((item 1 of p) as text) & " " & ((item 2 of p) as text) & " " & ((item 1 of s) as text) & " " & ((item 2 of s) as text)
  end tell
end tell
APPLESCRIPT
}

move_pointer() {
  local x="$1"
  local y="$2"
  POINT_X="$x" POINT_Y="$y" python3 - <<'PY'
import os
import time
import Quartz

x = int(float(os.environ["POINT_X"]))
y = int(float(os.environ["POINT_Y"]))
event = Quartz.CGEventCreateMouseEvent(None, Quartz.kCGEventMouseMoved, (x, y), Quartz.kCGMouseButtonLeft)
Quartz.CGEventPost(Quartz.kCGHIDEventTap, event)
time.sleep(0.2)
PY
}

case "${1:-}" in
  open)
    open_popover
    ;;
  bounds)
    require_app
    menu_item_bounds
    ;;
  tree)
    open_popover
    osascript <<APPLESCRIPT
tell application "System Events"
  tell process "$APP_NAME"
    return entire contents of windows
  end tell
end tell
APPLESCRIPT
    ;;
  identifiers)
    open_popover
    osascript <<APPLESCRIPT
on collectIdentifiers(rootElement)
  set collectedText to ""
  tell application "System Events"
    try
      set identifierValue to value of attribute "AXIdentifier" of rootElement
      if identifierValue is not missing value then
        set roleValue to value of attribute "AXRole" of rootElement
        set titleValue to ""
        try
          set titleValue to value of attribute "AXTitle" of rootElement
        end try
        set collectedText to collectedText & identifierValue & " | " & roleValue & " | " & titleValue & linefeed
      end if
    end try

    repeat with childElement in UI elements of rootElement
      set collectedText to collectedText & my collectIdentifiers(childElement)
    end repeat
  end tell
  return collectedText
end collectIdentifiers

tell application "System Events"
  tell process "$APP_NAME"
    return my collectIdentifiers(window 1)
  end tell
end tell
APPLESCRIPT
    ;;
  screenshot)
    open_popover
    out="${2:-/tmp/dayline-popover.png}"
    read -r x y w h <<<"$(popover_bounds)"
    screencapture -x -R "$x,$y,$w,$h" "$out"
    echo "$out"
    ;;
  press)
    open_popover
    index="${2:-}"
    if [[ -z "$index" ]]; then
      usage
      exit 2
    fi
    osascript <<APPLESCRIPT
tell application "System Events"
  tell process "$APP_NAME"
    perform action "AXPress" of button $index of scroll area 1 of group 1 of window 1
  end tell
end tell
APPLESCRIPT
    ;;
  press-id)
    open_popover
    identifier="${2:-}"
    if [[ -z "$identifier" ]]; then
      usage
      exit 2
    fi
    osascript <<APPLESCRIPT
on findByIdentifier(rootElement, targetIdentifier)
  tell application "System Events"
    try
      if value of attribute "AXIdentifier" of rootElement is targetIdentifier then
        return rootElement
      end if
    end try

    repeat with childElement in UI elements of rootElement
      set foundElement to my findByIdentifier(childElement, targetIdentifier)
      if foundElement is not missing value then
        return foundElement
      end if
    end repeat
  end tell

  return missing value
end findByIdentifier

tell application "System Events"
  tell process "$APP_NAME"
    set targetElement to my findByIdentifier(window 1, "$identifier")
    if targetElement is missing value then error "No element with AXIdentifier $identifier"
    perform action "AXPress" of targetElement
  end tell
end tell
APPLESCRIPT
    ;;
  hover)
    open_popover
    target="${2:-}"
    read -r x y w h <<<"$(popover_bounds)"
    case "$target" in
      refresh)
        move_pointer "$((x + w - 28))" "$((y + 28))"
        ;;
      settings)
        move_pointer "$((x + 45))" "$((y + h - 27))"
        ;;
      quit)
        move_pointer "$((x + w - 45))" "$((y + h - 27))"
        ;;
      *)
        usage
        exit 2
        ;;
    esac
    ;;
  scroll)
    open_popover
    direction="${2:-down}"
    steps="${3:-8}"
    read -r x y w h <<<"$(popover_bounds)"
    move_pointer "$((x + w / 2))" "$((y + h / 2))"
    SCROLL_DIRECTION="$direction" SCROLL_STEPS="$steps" python3 - <<'PY'
import os
import time
import Quartz

direction = os.environ["SCROLL_DIRECTION"]
steps = int(os.environ["SCROLL_STEPS"])
delta = 6 if direction == "up" else -6
for _ in range(steps):
    event = Quartz.CGEventCreateScrollWheelEvent(None, Quartz.kCGScrollEventUnitLine, 1, delta)
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, event)
    time.sleep(0.03)
PY
    ;;
  *)
    usage
    exit 2
    ;;
esac
