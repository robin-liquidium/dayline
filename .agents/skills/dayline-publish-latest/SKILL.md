---
name: dayline-publish-latest
description: Safely publish the latest Dayline source through commit, validation, main-branch landing, push, signed packaging, local installation, GitHub test release, and optionally one official Apple-notarized release. Use when Robin asks to publish, ship, or release the latest Dayline build, update GitHub and /Applications together, or invokes $dayline-publish-latest. The workflow must live-check Apple submissions and skip notarization while any submission is still In Progress.
---

# Dayline Publish Latest

Ship one exact commit through source, local installation, GitHub assets, and—only when safe—the official notarized release. Never rebuild or resubmit merely because Apple is slow.

## Authority boundary

- Treat explicit invocation as authorization to commit the intended changes, land them on `main`, push `origin/main`, package and install the app, and create the described GitHub release assets.
- Preserve unrelated dirty and untracked files. Never force-push, rewrite a published tag, or discard user changes.
- Do not submit to Apple when any Dayline notarization is `In Progress`. An explicit user override must name that risk; a generic “ship it” is not an override.
- Use GitHub Actions as the sole notarization submitter. Never run local `package_release.sh --notarize` in parallel with CI.

## Workflow

1. Audit current state before mutation.
   - Inspect `git status --short --branch`, focused diffs, `origin/main`, stable tags, open PRs, GitHub releases, and recent CI/release runs.
   - Query `xcrun notarytool history` with the configured App Store Connect credentials when available. Print IDs, names, dates, and statuses only; never print key contents.
   - If an older submission is `Accepted`, decide whether that exact artifact is still the intended release. Staple and publish it only when it is current; if it is obsolete, stop its continuation safely and do not promote an outdated build.

2. Review and validate the intended changes.
   - Use `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` for Swift commands.
   - Run `swift test`, `git diff --check`, a focused code review, and behavior-level UI validation when relevant.
   - Keep screenshots and generated review artifacts out of git.

3. Land one clean commit on `main`.
   - Stage only intended paths and commit descriptively.
   - When already on `main` and explicitly told to push there, push after validation.
   - From a topic branch, create a PR, wait for current-head checks/review, merge it, then update local `main`. Invocation of this skill authorizes merging the intended release change after those gates pass.
   - Require clean local `main` to equal `origin/main` before packaging or tagging.

4. Choose the release version.
   - Use a version Robin supplied; otherwise increment the patch component of the highest tag matching exactly `vMAJOR.MINOR.PATCH`.
   - Ignore test-release tags. Never reuse or move an existing stable tag.

5. Build, sign, install, and verify before publication.

   ```bash
   DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
     MARKETING_VERSION="$VERSION" \
     ./script/package_release.sh --install
   ```

   - Do not add `--notarize` here.
   - Verify Developer ID signing, hardened runtime, DMG integrity, app and DMG versions, installed process liveness, and matching packaged/installed executable hashes.

6. Publish an immediate signed test release.
   - Use a tag shaped `test-vMAJOR.MINOR.PATCH.N`, targeting the exact clean `main` commit. Do not use a tag beginning with `v`; `.github/workflows/release.yml` treats every `v*` tag as an official release trigger.
   - Upload only the versioned DMG and versioned app ZIP. The stable `Dayline.dmg` asset is reserved for notarized production releases.
   - Title and notes must say `signed test build (not notarized)`, briefly describe the tester-visible changes and requirements, and explain the Gatekeeper right-click **Open** / **Open Anyway** path. Keep source commits, hashes, certificate identities, and other internal verification metadata out of public release notes.
   - Mark it as a prerelease and never mark it latest. The website and Sparkle feed must continue pointing at the latest notarized stable release.
   - Download the uploaded assets into a temporary directory and verify their hashes. Confirm GitHub's latest-release API and stable download redirect still point at the notarized stable release.

7. Gate the official Apple release.
   - If any Dayline submission is `In Progress`, stop here. Do not create `v$VERSION`, because pushing it automatically submits another artifact to Apple. Report that the signed test release is live and reserve the same version for a later official attempt.
   - If Apple leaves submissions stuck for more than 24 hours, collect their IDs and timestamps and escalate to Apple Developer Support. Do not probe the service by uploading more copies.
   - If no submission is `In Progress`, run `./script/tag_release.sh "$VERSION"` exactly once. This stable tag is the only action that should start notarization.
   - The tag workflow must preserve the exact signed app in a private draft release before submitting it once, then exit without holding a runner open.
   - `.github/workflows/notarization-continuation.yml` polls pending drafts every ten minutes and can also be dispatched manually for one tag. It resumes the stored submission ID; never restart the submit job merely because processing is slow.
   - On app acceptance, continuation staples the preserved app, creates and submits the DMG once, and persists that second submission ID. On DMG acceptance, it staples and validates the final artifacts, runs Gatekeeper verification, publishes `v$VERSION`, and promotes it as latest.
   - On `Invalid` or `Rejected`, retrieve the notarization log, fix the exact failure, and submit one replacement artifact only after the fix is committed.

8. Close out with evidence.
   - Report the main commit, CI checks, installed version/build, signature and hashes, prerelease URL, official workflow/submission status, GitHub stable-download target, and clean or intentionally dirty worktree state.
   - Clearly distinguish `signed`, `notarized`, and `stapled`; never call a signed-only test build generally installable.
