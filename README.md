# Dayline

Dayline is a lightweight macOS menu bar app for a compact daily glance at:

- upcoming Google Calendar events for today, with an optional tomorrow section
- active Linear issues assigned to you, sorted by your chosen order

It is intentionally menu-bar-only, native SwiftUI, and small. Data refreshes in the background on a configurable cadence.

## Requirements

- macOS 27 or newer
- SwiftPM / Swift 5.9+
- Google Workspace CLI, available as `gws`
- Linear CLI, available as `linear`

The app currently calls these absolute paths:

- `/opt/homebrew/bin/gws`
- `/opt/homebrew/bin/linear`

If your tools live somewhere else, update `CalendarService.gwsPath` and `LinearService.linearPath`.

## Install CLI Dependencies

### Google Workspace CLI

Install `gws` from the Google Workspace CLI project:

- GitHub: https://github.com/googleworkspace/cli
- Releases: https://github.com/googleworkspace/cli/releases
- Homebrew formula: https://formulae.brew.sh/formula/googleworkspace-cli

Common install options:

```sh
brew install googleworkspace-cli
# or
npm install -g @googleworkspace/cli
```

Authenticate `gws` so it can read Calendar events. The app uses:

```sh
gws calendar events list --params '<json>' --format json
```

### Linear CLI

Install `linear` from `schpet/linear-cli`:

- GitHub: https://github.com/schpet/linear-cli
- Linear API docs: https://linear.app/developers

Authenticate it with Linear:

```sh
linear auth login
```

The app uses `linear api` GraphQL calls to fetch assigned issues and update issue status/priority.

## Run

Build and launch the local app bundle:

```sh
./script/build_and_run.sh
```

Verify it launches:

```sh
./script/build_and_run.sh --verify
```

Useful modes:

```sh
./script/build_and_run.sh --debug
./script/build_and_run.sh --logs
./script/build_and_run.sh --telemetry
```

The script builds with SwiftPM, creates `dist/Dayline.app`, and launches it as a menu-bar accessory app.

## Use

Open the menu bar calendar icon to see:

- `Up Next`: remaining timed calendar events today
- `Show tomorrow`: expand or collapse tomorrow's timed calendar events
- `Linear`: active assigned Linear issues
- `Show more`: reveal more fetched Linear issues
- `Show less`: collapse expanded Linear issues

Issue row shortcuts while hovering a Linear issue:

- `C` by default: copy issue URL. This can be changed in Settings.
- `S`: change issue status.
- `P`: change issue priority.

Settings lets you change:

- refresh cadence
- copy hotkey
- Linear issue ordering

## UI Test Helpers

The app includes a small Accessibility-driven helper for fast local testing:

```sh
./script/menu_test.sh open
./script/menu_test.sh screenshot /tmp/dayline.png
./script/menu_test.sh tree
./script/menu_test.sh identifiers
./script/menu_test.sh press-id calendar.tomorrow.toggle
./script/menu_test.sh press-id linear.showMore
./script/menu_test.sh press-id linear.showLess
./script/menu_test.sh hover refresh
./script/menu_test.sh hover settings
./script/menu_test.sh hover quit
./script/menu_test.sh scroll down
```

Stable Accessibility identifiers include:

- `dayline.refresh`
- `dayline.settings`
- `dayline.quit`
- `calendar.tomorrow.toggle`
- `linear.showMore`
- `linear.showLess`
- `linear.issue.<ISSUE-ID>`
- `settings.refreshCadence`
- `settings.copyIssueHotkey`
- `settings.linearIssueOrder`

Run the smoke test:

```sh
./script/smoke_test.sh
```

## Project Layout

```text
Sources/Dayline/App/        App entrypoint
Sources/Dayline/Models/     Value models
Sources/Dayline/Services/   gws, Linear CLI, and process execution
Sources/Dayline/Stores/     App state and refresh loop
Sources/Dayline/Support/    Formatters and small helpers
Sources/Dayline/Views/      SwiftUI views
script/                          Build, smoke, and menu test helpers
```

## Notes

This is local tooling, not a sandboxed App Store app. It relies on authenticated local CLI tools rather than embedding Google or Linear OAuth flows.
