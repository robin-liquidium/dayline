# Dayline

Dayline is a lightweight macOS menu bar app for a compact daily glance at:

- upcoming Google Calendar events for today, with an optional tomorrow section
- active Linear issues assigned to you, sorted by your chosen order
- local notes stored on this Mac, with the first line used as the title

It is intentionally menu-bar-only, native SwiftUI, and small. Data refreshes in the background on a configurable cadence.

## Requirements

- macOS 26 or newer
- SwiftPM / Swift 5.9+
- Google Workspace CLI, available as `gws`
- Linear CLI, available as `linear`

The app currently calls these absolute paths:

- `/opt/homebrew/bin/gws`
- `/opt/homebrew/bin/linear`

If your tools live somewhere else, launch Dayline with:

```sh
DAYLINE_GWS_PATH=/path/to/gws DAYLINE_LINEAR_PATH=/path/to/linear ./script/build_and_run.sh direct
```

On launch, Dayline checks whether both CLIs are installed and authenticated. If either tool is missing or unauthenticated, the menu shows a `Setup` section with install/auth buttons and a check-again button.

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
gws auth login
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

## Test Dependency Setup

Test missing or unauthenticated CLIs without touching your real local `gws` or `linear` installation:

```sh
./script/dependency_sandbox.sh missing
./script/dependency_sandbox.sh unauthenticated
./script/dependency_sandbox.sh ready
./script/dependency_sandbox.sh gws-missing
./script/dependency_sandbox.sh linear-missing
```

The sandbox creates temporary fake CLI executables and launches Dayline with `DAYLINE_GWS_PATH` and `DAYLINE_LINEAR_PATH` pointed at those fakes. Install buttons use harmless fake `echo` commands in this mode, and auth buttons run fake auth commands, so your real credentials and packages are not changed.

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

## Install And Release

Install Dayline into `/Applications`:

```sh
./script/package_release.sh --install
```

Create GitHub-release-ready artifacts:

```sh
./script/package_release.sh
```

The release script builds a release SwiftPM binary, wraps it in `dist/release/Dayline.app`, signs it with the best available local certificate, and creates:

- `dist/artifacts/Dayline-<version>.dmg`
- `dist/artifacts/Dayline-<version>.app.zip`

For public distribution outside the Mac App Store, Apple expects a Developer ID-signed and notarized app. After installing a `Developer ID Application` certificate and storing notary credentials, build the notarized DMG with:

```sh
xcrun notarytool store-credentials dayline-notary
NOTARY_PROFILE=dayline-notary ./script/package_release.sh --notarize
```

Upload the notarized `.dmg` to a GitHub Release. The zipped `.app` is useful as a secondary direct-download asset because GitHub cannot serve a raw `.app` bundle as a single file.

After the repo has a GitHub `origin` remote, publish the current artifacts as a release with:

```sh
./script/publish_github_release.sh
```

## Use

Open the menu bar calendar icon to see:

- `Up Next`: remaining timed calendar events today
- `Show tomorrow`: expand or collapse tomorrow's timed calendar events
- `Linear`: active assigned Linear issues
- `+`: create a Linear issue with the Linear CLI default team
- issue rows: horizontally swipe or scroll to reveal `Cancel`
- `Show more`: reveal more fetched Linear issues
- `Show less`: collapse expanded Linear issues
- `Notes`: local notes stored on this Mac
- `+`: create a local note in a small editor window
- note rows: horizontally swipe or scroll to reveal `Delete`
- `Show more`: reveal more fetched notes
- `Show less`: collapse expanded notes

Issue row shortcuts while hovering a Linear issue:

- `C` by default: copy issue URL. This can be changed in Settings.
- `S` by default: change issue status. This can be changed in Settings.
- `P` by default: change issue priority. This can be changed in Settings.

Settings lets you change:

- launch at login
- refresh cadence
- copy hotkey
- status picker hotkey
- priority picker hotkey
- Linear issue ordering
- default note count
- note ordering by update time, creation time, or first-line title

## UI Test Helpers

The app includes a small Accessibility-driven helper for fast local testing:

```sh
./script/menu_test.sh open
./script/menu_test.sh screenshot /tmp/dayline.png
./script/menu_test.sh tree
./script/menu_test.sh identifiers
./script/menu_test.sh press-id calendar.tomorrow.toggle
./script/menu_test.sh press-id linear.new
./script/menu_test.sh press-id linear.showMore
./script/menu_test.sh press-id linear.showLess
./script/menu_test.sh press-id notes.new
./script/menu_test.sh press-id notes.showMore
./script/menu_test.sh press-id notes.showLess
./script/menu_test.sh hover refresh
./script/menu_test.sh hover settings
./script/menu_test.sh hover quit
./script/menu_test.sh scroll down
./script/dependency_sandbox.sh unauthenticated
```

Stable Accessibility identifiers include:

- `dayline.refresh`
- `dayline.settings`
- `dayline.quit`
- `setup.checkAgain`
- `setup.gws`
- `setup.gws.install`
- `setup.gws.auth`
- `setup.linear`
- `setup.linear.install`
- `setup.linear.auth`
- `calendar.tomorrow.toggle`
- `linear.new`
- `linear.showMore`
- `linear.showLess`
- `linear.issue.<ISSUE-ID>`
- `linear.cancel.<ISSUE-ID>`
- `linearEditor.title`
- `linearEditor.description`
- `linearEditor.create`
- `linearEditor.cancel`
- `notes.new`
- `notes.showMore`
- `notes.showLess`
- `notes.note.<NOTE-ID>`
- `notes.delete.<NOTE-ID>`
- `noteEditor.text`
- `noteEditor.save`
- `noteEditor.cancel`
- `settings.launchAtLogin`
- `settings.refreshCadence`
- `settings.menuBarEventLeadTime`
- `settings.menuBarEventPostStartGrace`
- `settings.copyIssueHotkey`
- `settings.statusPickerHotkey`
- `settings.priorityPickerHotkey`
- `settings.linearIssueOrder`
- `settings.defaultNoteCount`
- `settings.localNoteSortOrder`

Run the smoke test:

```sh
./script/smoke_test.sh
```

## Project Layout

```text
Sources/Dayline/App/        App entrypoint
Sources/Dayline/Models/     Value models
Sources/Dayline/Services/   gws, Linear CLI, local persistence, and process execution
Sources/Dayline/Stores/     App state and refresh loop
Sources/Dayline/Support/    Formatters and small helpers
Sources/Dayline/Views/      SwiftUI views
script/                          Build, smoke, and menu test helpers
```

## Notes

This is local tooling, not a sandboxed App Store app. Calendar and Linear rely on authenticated local CLI tools; notes are stored locally in Dayline's Application Support folder. A note's first line is its menu title; the rest becomes the preview.
