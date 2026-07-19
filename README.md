# Dayline

Dayline is a lightweight macOS menu bar app for a compact daily glance at:

- upcoming Google Calendar events for today, with an optional tomorrow section
- active Linear issues assigned to you, sorted by your chosen order
- local notes stored on this Mac, with the first line used as the title

It is intentionally menu-bar-only, native SwiftUI, and small. Data refreshes in the background on a configurable cadence.

![Dayline showing upcoming calendar events, Linear issues, and local notes from the macOS menu bar](website/public/images/dayline-menu-overview.webp)

## Requirements

- macOS 26 or newer
- SwiftPM / Swift 5.9+

No CLI dependencies are required. Dayline talks directly to Google Calendar and Linear using OAuth 2.0 with PKCE and stores tokens in the macOS Keychain.

## Connect Accounts

On first launch, use the menu's `Setup` section to connect Google Calendar and Linear. Authentication opens in the default browser and returns directly to Dayline.

- Google Calendar requests read-only access to the primary calendar.
- Linear requests `read,write` access for assigned issues and issue actions.
- Settings shows the connected account and provides a Disconnect action.

OAuth client IDs are public and bundled in official builds. Source builds can override them with `DAYLINE_GOOGLE_CLIENT_ID` and `DAYLINE_LINEAR_CLIENT_ID`.

### OAuth Application Configuration

For a different Google OAuth application:

1. Enable the Google Calendar API.
2. Configure and publish an external OAuth consent screen.
3. Create an iOS OAuth client with bundle ID `build.local.Dayline`.
4. Set its client ID in `Sources/Dayline/Auth/AuthConfig.swift` or `DAYLINE_GOOGLE_CLIENT_ID`.

For a different Linear OAuth application:

1. Create an OAuth application in Linear.
2. Enable refresh tokens and add `dayline://oauth/callback` as a redirect URI.
3. Mark it public for use across workspaces.
4. Set its client ID in `Sources/Dayline/Auth/AuthConfig.swift` or `DAYLINE_LINEAR_CLIENT_ID`.

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

## Install Locally

Install Dayline into `/Applications`:

```sh
./script/package_release.sh --install
```

This builds a release app, copies it to `/Applications/Dayline.app`, and opens it.

## Public Releases

Public releases are tag-driven. A pushed `vX.Y.Z` tag runs `.github/workflows/release.yml` on `macos-26`, builds and tests the tagged commit, signs with Developer ID, notarizes and staples the app and DMG, then publishes both artifacts to GitHub Releases.

Configure the required encrypted GitHub Secrets once:

```sh
./script/configure_release_secrets.sh
```

After release changes are committed, merged, and synchronized on `main`, publish a version with:

```sh
./script/tag_release.sh 0.1.4
```

Regular pushes and pull requests only run `.github/workflows/ci.yml`; they never publish a release.

### Manual Fallback

Create local release artifacts:

```sh
./script/package_release.sh
```

The release script builds a release SwiftPM binary, wraps it in `dist/release/Dayline.app`, signs it with the best available local certificate, and creates:

- `dist/artifacts/Dayline-<version>.dmg`
- `dist/artifacts/Dayline-<version>.app.zip`

To manually package a clean, exactly tagged commit with local notarization credentials:

```sh
xcrun notarytool store-credentials dayline-notary
NOTARY_PROFILE=dayline-notary ./script/package_release.sh --notarize
```

Then publish the artifacts:

```sh
./script/publish_github_release.sh
```

The release scripts reject dirty, untagged, mismatched, and duplicate public releases.

## Use

Open the menu bar calendar icon to see:

- `Up Next`: remaining timed calendar events today
- `Show tomorrow`: expand or collapse tomorrow's timed calendar events
- `Linear`: active assigned Linear issues
- `+`: create a Linear issue
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

- connected Google Calendar and Linear accounts
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
```

Stable Accessibility identifiers include:

- `dayline.refresh`
- `dayline.settings`
- `dayline.quit`
- `setup.checkAgain`
- `setup.google`
- `setup.google.connect`
- `setup.linear`
- `setup.linear.connect`
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
- `settings.account.google`
- `settings.account.linear`
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
Sources/Dayline/Auth/       OAuth, PKCE, and Keychain token storage
Sources/Dayline/Models/     Value models
Sources/Dayline/Services/   Google Calendar API, Linear GraphQL API, and local persistence
Sources/Dayline/Stores/     App state and refresh loop
Sources/Dayline/Support/    Formatters and small helpers
Sources/Dayline/Views/      SwiftUI views
script/                     Build, smoke, and release helpers
```

## Notes

Calendar and Linear data is fetched directly from each provider over HTTPS. OAuth tokens are stored in the macOS Keychain, and notes are stored locally in Dayline's Application Support folder. A note's first line is its menu title; the rest becomes the preview.
