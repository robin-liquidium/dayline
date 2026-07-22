---
name: dayline-publish-latest
description: "Review and ship the latest Dayline work end to end: inspect all local and unpushed changes, run independent subagents plus Codex and CodeRabbit reviews, investigate and fix legitimate findings, validate the app, create and clean up a PR, merge to main, validate the signed artifact without replacing the installed app, publish the Apple-notarized GitHub release, update the website and Sparkle feed, update Homebrew, and verify every distribution path. Use when Robin invokes $dayline-publish-latest or asks to publish, ship, or release the latest Dayline build."
---

# Dayline Publish Latest

Ship one exact reviewed commit through PR, artifact validation, GitHub, Apple notarization, the website, Sparkle, and Homebrew. Continue automatically through the full production release unless the user explicitly narrows or stops the workflow.

## Authority boundary

- Treat invocation as authorization to create a release branch, review and fix the intended work, commit it, create and merge its PR after all gates pass, push and tag `main`, package and validate Dayline without installing it, publish the release, and update `robin-liquidium/homebrew-tap`.
- Treat every tracked, staged, unstaged, untracked, committed-but-unpushed, and pushed-but-unmerged change relative to `origin/main` as a release candidate. Inspect all of it. Exclude generated, accidental, or unrelated files only after verifying that classification; ask only when ambiguity would materially change the release.
- Preserve unrelated user work. Never force-push, rewrite a published tag, print secrets, or discard changes.
- Never replace, upgrade, delete, or otherwise modify `/Applications/Dayline.app`. Record its version and build before starting and preserve it so Robin can personally test the production Sparkle update after publication.
- Start official notarization unless the user explicitly says otherwise. Do not suppress a new submission merely because another submission is `In Progress`.
- Use GitHub Actions as the sole notarization submitter. Never run local `package_release.sh --notarize` in parallel with CI, and never resubmit merely because Apple is slow.

## Workflow

1. Get the work reviewed, merged, and synced by following the `send-it` skill (`~/.agents/skills/send-it/SKILL.md`) steps 1–9. Its commit-first flow, secret scan, review round loop (autoreview Codex and opencode engines plus CodeRabbit), finding ledger, screenshot rules, CI/bot monitoring, and merge gates apply verbatim. If the send-it skill is unavailable, stop and report instead of falling back to ad-hoc review commands. Dayline-specific deltas:
   - This skill's invocation explicitly authorizes the merge, satisfying send-it's merge gate — merge only after all send-it gates pass. Push directly to `main` only when the user explicitly requests that.
   - The base branch is always `main`; always use a topic branch and PR, even when work began on `main`.
   - Additionally run independent lens subagents on the round-1 full diff — distinct lenses such as correctness/state, SwiftUI/macOS behavior, tests, security, and release integrity — giving them the raw diff and relevant files, not prior conclusions. Their findings enter the same triage and wont-fix ledger, and the review loop is not clean until the lenses also report no legitimate findings.
   - Validation (send-it step 7) additionally requires: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` for all Swift commands; `swift build`, `swift test`, `git diff --check`, and shell syntax checks for touched scripts; and for user-visible changes, build and run the real app or isolated mock app and exercise every materially changed flow — compilation or unit tests alone are not proof that a SwiftUI interaction works.
   - Before starting, inspect stable tags, open PRs, GitHub releases and drafts, recent CI/release runs, and the active `main` ruleset. Confirm the repository-scoped `APPCAST_DEPLOY_KEY` secret exists so the notarization workflow can publish the signed Sparkle feed through its narrow ruleset bypass. Detect any existing release draft for the same tag and exact commit so it can be resumed instead of duplicated.
   - After merge, update local `main`. Require clean local `main` to equal `origin/main` before packaging or tagging.

2. Choose a safe release version.
   - Use a version supplied by the user; otherwise fetch remote state and increment the patch component of the highest published stable tag matching exactly `vMAJOR.MINOR.PATCH`.
   - Ignore test-release tags. Never reuse or move an existing stable tag, collide with an existing draft for another commit, or release a version older than the latest stable release.
   - Ensure the resolved `CFBundleVersion` is greater than every previously published build number so Sparkle recognizes the release as an update.

3. Build, sign, and verify before publication without installing.

   ```bash
   DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
     MARKETING_VERSION="$VERSION" \
     ./script/package_release.sh
   ```

   - Do not add `--install` or `--notarize` here.
   - Verify Developer ID signing, hardened runtime, DMG integrity, app and DMG versions, and the packaged executable hash without copying or launching the app from `/Applications`.

4. Start and safely continue the official release unless the user opted out.
   - Run `./script/tag_release.sh "$VERSION"` exactly once. The stable tag is the only action that starts official notarization; do not block it on other Apple submissions being `In Progress`. If this or any later exactly-once action returns an uncertain result, reconcile remote tags, workflow runs, draft releases, and persisted Apple submission IDs before retrying. Resume the existing release when they identify one exact attempt; abort safely when the state remains ambiguous.
   - Monitor the initial workflow until it has preserved the exact signed app in a private draft release and recorded its Apple submission ID. Confirm the scheduled continuation workflow is enabled.
   - `.github/workflows/notarization-continuation.yml` resumes persisted submission IDs every ten minutes. Never restart the submission workflow or upload another copy merely because processing takes 24 hours or longer.
   - On app acceptance, continuation staples the preserved app, creates and submits the DMG once, and persists that submission ID. Apply the same remote-state reconciliation before any uncertain DMG submission retry. On DMG acceptance, it staples and validates the artifacts, runs Gatekeeper verification, publishes `v$VERSION` as latest, and publishes the signed appcast.
   - On `Invalid` or `Rejected`, retrieve the notarization log, diagnose and fix the exact failure, send the fix through the review/PR gates, and submit one replacement artifact only after that fix lands.
   - If Apple is still processing, establish a durable, persisted continuation for every remaining distribution check before exiting; live monitoring is supplemental only. Report the exact persisted stage and IDs, but do not call the production release complete.

5. Verify the production distribution chain after notarization.
   - Confirm the stable GitHub release is public, non-prerelease, latest, and contains the versioned DMG, versioned app ZIP, stable `Dayline.dmg`, and signed `appcast.xml`.
   - Download the published assets and verify hashes, versions, Developer ID signatures, hardened runtime, staples, Gatekeeper acceptance, and DMG integrity.
   - Confirm the website download resolves to the new notarized `Dayline.dmg` and the live `https://dayline.robin.build/appcast.xml` matches the signed release asset with the new version and monotonically increasing build.
   - Do not click the update button, run an automated Sparkle update, install an isolated previous version, relaunch through Sparkle, or install the final artifact into `/Applications`. Leave the entire in-app update experience for Robin to perform manually.
   - Recheck that `/Applications/Dayline.app` still has the exact version and build recorded before the release.

6. Update and verify Homebrew.
   - In `robin-liquidium/homebrew-tap`, update `Casks/dayline.rb` to the new version and the SHA-256 of the final notarized versioned DMG.
   - Create a focused tap PR, wait for its complete test matrix and review state, fix legitimate findings, merge it, and synchronize the tap's `main`.
   - Run `brew update`, then `brew fetch --cask robin-liquidium/tap/dayline` without installing it. Verify the fetched cask version, URL, checksum, signature, staple, Gatekeeper result, and DMG integrity.
   - Never run `brew install`, `brew reinstall`, or `brew upgrade` for Dayline.

7. Close out with evidence.
   - Report the Dayline PR and merge commit, latest-head CI and review state, stable tag and release URL, Apple submission IDs/stages, signatures and hashes, website download target, live Sparkle feed, Homebrew PR and fetched-cask verification, preserved installed version/build, and clean or intentionally dirty worktree state.
   - State that the release is available through GitHub, the website, Sparkle, and Homebrew while the manual in-app update experience remains intentionally untested for Robin. Never claim that manual update succeeded.
   - Clearly distinguish `signed`, `notarized`, `stapled`, `submitted`, and `published`. If Apple or another durable continuation is pending, say exactly what remains instead of claiming the release is complete.
