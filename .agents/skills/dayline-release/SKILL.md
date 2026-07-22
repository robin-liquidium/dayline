---
name: dayline-release
description: "Cut a Dayline release from a clean main: choose a safe version, update the changelog through a PR, package and validate the signed artifact without installing it, tag to start Apple notarization, publish the GitHub release with changelog-derived notes, verify the website and Sparkle feed, update Homebrew, and verify every distribution path. Use when Robin invokes $dayline-release or asks to release, tag, or cut a new Dayline version. Assumes the work is already merged; use dayline-pr first when it is not."
---

# Dayline Release

Ship the exact commit on `main` through version selection, the changelog, packaging, GitHub, Apple notarization, the website, Sparkle, and Homebrew. Continue automatically through the full production release unless the user explicitly narrows or stops the workflow. If unmerged or unreviewed work should be part of this release, stop and run `dayline-pr` first.

## Authority boundary

- Treat invocation as authorization to create and merge the changelog PR, push and tag `main`, package and validate Dayline without installing it, publish the release, and update `robin-liquidium/homebrew-tap`.
- Never release work that has not gone through the `dayline-pr` review gates in the same overall effort. A clean `main` that equals `origin/main` is the only valid starting point.
- Preserve unrelated user work. Never force-push, rewrite a published tag, print secrets, or discard changes.
- Never replace, upgrade, delete, or otherwise modify `/Applications/Dayline.app`. Record its version and build before starting and preserve it so Robin can personally test the production Sparkle update after publication.
- Start official notarization unless the user explicitly says otherwise. Do not suppress a new submission merely because another submission is `In Progress`.
- Use GitHub Actions as the sole notarization submitter. Never run local `package_release.sh --notarize` in parallel with CI, and never resubmit merely because Apple is slow.

## Workflow

1. Audit and establish the release baseline before mutation.
   - Fetch `origin/main` and tags. Require a clean local `main` equal to `origin/main`. If local work is pending review or merge, stop and hand off to `dayline-pr`.
   - Inspect stable tags, open PRs, GitHub releases and drafts, recent CI/release runs, and the active `main` ruleset. Confirm the repository-scoped `APPCAST_DEPLOY_KEY` secret exists so the notarization workflow can publish the signed Sparkle feed through its narrow ruleset bypass. Detect any existing release draft for the same tag and exact commit so it can be resumed instead of duplicated.

2. Choose a safe release version.
   - Use a version supplied by the user; otherwise fetch remote state and increment the patch component of the highest published stable tag matching exactly `vMAJOR.MINOR.PATCH`.
   - Ignore test-release tags. Never reuse or move an existing stable tag, collide with an existing draft for another commit, or release a version older than the latest stable release.
   - Ensure the resolved `CFBundleVersion` is greater than every previously published build number so Sparkle recognizes the release as an update.

3. Update the changelog through its own PR before tagging.
   - Review every merged PR and user-facing change since the previous stable tag (`git log <last-tag>..origin/main` plus merged-PR metadata) and draft the new entry for `changelog.json` at the repository root. Write for users, not for commit logs.
   - Prepend the entry as the first element of `releases` with the chosen version and today's UTC date, using `new` for New features and `fixed` for Improvements and bug fixes, each item `{ "text": "...", "pr": <number> }` with `pr` omitted when no PR is associated. The same entry becomes the GitHub release notes, so every item should carry its PR number when one exists.
   - Run `bun test` in `website/` to validate the changelog schema, then land the change as a small PR: topic branch, descriptive commit, PR, wait for required checks, merge. The full send-it review gauntlet is not required for this data-only PR, but required checks must be green.
   - Accept that the website announces the new version as soon as this PR merges, before notarization completes — that ordering is intentional so the tagged commit already contains the changelog entry the release notes are generated from.
   - Update local `main` after the merge and require it to equal `origin/main` before packaging or tagging.

4. Build, sign, and verify before publication without installing.

   ```bash
   DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
     MARKETING_VERSION="$VERSION" \
     ./script/package_release.sh
   ```

   - Do not add `--install` or `--notarize` here.
   - Verify Developer ID signing, hardened runtime, DMG integrity, app and DMG versions, and the packaged executable hash without copying or launching the app from `/Applications`.

5. Start and safely continue the official release unless the user opted out.
   - Run `./script/tag_release.sh "$VERSION"` exactly once. The stable tag is the only action that starts official notarization; do not block it on other Apple submissions being `In Progress`. If this or any later exactly-once action returns an uncertain result, reconcile remote tags, workflow runs, draft releases, and persisted Apple submission IDs before retrying. Resume the existing release when they identify one exact attempt; abort safely when the state remains ambiguous.
   - Monitor the initial workflow until it has preserved the exact signed app in a private draft release and recorded its Apple submission ID. Confirm the scheduled continuation workflow is enabled.
   - `.github/workflows/notarization-continuation.yml` resumes persisted submission IDs every ten minutes. Never restart the submission workflow or upload another copy merely because processing takes 24 hours or longer.
   - On app acceptance, continuation staples the preserved app, creates and submits the DMG once, and persists that submission ID. Apply the same remote-state reconciliation before any uncertain DMG submission retry. On DMG acceptance, it staples and validates the artifacts, runs Gatekeeper verification, publishes `v$VERSION` as latest with release notes generated from the `changelog.json` entry, and publishes the signed appcast.
   - On `Invalid` or `Rejected`, retrieve the notarization log, diagnose and fix the exact failure, send the fix through the `dayline-pr` review gates, and submit one replacement artifact only after that fix lands.
   - If Apple is still processing, establish a durable, persisted continuation for every remaining distribution check before exiting; live monitoring is supplemental only. Report the exact persisted stage and IDs, but do not call the production release complete.

6. Verify the production distribution chain after notarization.
   - Confirm the stable GitHub release is public, non-prerelease, latest, and contains the versioned DMG, versioned app ZIP, stable `Dayline.dmg`, and signed `appcast.xml`.
   - Confirm the release notes body matches the `changelog.json` entry for the version, with each change linked to its PR. If the entry was missing at publish time and the static fallback body was used, fix the body with `gh release edit` from the changelog entry and investigate why the entry was absent.
   - Download the published assets and verify hashes, versions, Developer ID signatures, hardened runtime, staples, Gatekeeper acceptance, and DMG integrity.
   - Confirm the website download resolves to the new notarized `Dayline.dmg`, the live `https://dayline.robin.build/appcast.xml` matches the signed release asset with the new version and monotonically increasing build, and `https://dayline.robin.build/changelog` shows the new version at the top.
   - Do not click the update button, run an automated Sparkle update, install an isolated previous version, relaunch through Sparkle, or install the final artifact into `/Applications`. Leave the entire in-app update experience for Robin to perform manually.
   - Recheck that `/Applications/Dayline.app` still has the exact version and build recorded before the release.

7. Update and verify Homebrew.
   - In `robin-liquidium/homebrew-tap`, update `Casks/dayline.rb` to the new version and the SHA-256 of the final notarized versioned DMG.
   - Create a focused tap PR, wait for its complete test matrix and review state, fix legitimate findings, merge it, and synchronize the tap's `main`.
   - Run `brew update`, then `brew fetch --cask robin-liquidium/tap/dayline` without installing it. Verify the fetched cask version, URL, checksum, signature, staple, Gatekeeper result, and DMG integrity.
   - Never run `brew install`, `brew reinstall`, or `brew upgrade` for Dayline.

8. Close out with evidence.
   - Report the changelog PR and merge commit, stable tag and release URL, release-notes verification, Apple submission IDs/stages, signatures and hashes, website download target, live changelog page, live Sparkle feed, Homebrew PR and fetched-cask verification, preserved installed version/build, and clean or intentionally dirty worktree state.
   - State that the release is available through GitHub, the website, Sparkle, and Homebrew while the manual in-app update experience remains intentionally untested for Robin. Never claim that manual update succeeded.
   - Clearly distinguish `signed`, `notarized`, `stapled`, `submitted`, and `published`. If Apple or another durable continuation is pending, say exactly what remains instead of claiming the release is complete.
