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

1. Audit and establish the complete release diff before mutation.
   - Fetch `origin/main` and tags, then inspect `git status --short --branch`, `git diff`, `git diff --cached`, untracked file contents, `git diff --stat origin/main...HEAD`, `git diff --numstat origin/main...HEAD`, and the full `origin/main...HEAD` diff.
   - Inspect stable tags, open PRs, GitHub releases and drafts, recent CI/release runs, and the active `main` ruleset. Confirm the repository-scoped `APPCAST_DEPLOY_KEY` secret exists so the notarization workflow can publish the signed Sparkle feed through its narrow ruleset bypass. Detect any existing release draft for the same tag and exact commit so it can be resumed instead of duplicated.
   - Create or switch to a topic/release branch before cleanup or commits. Default to a PR even when work began on `main`; push directly to `main` only when the user explicitly requests that.

2. Minimize and review the entire intended change.
   - Remove dead code, duplication, debug scaffolding, accidental generated files, unused helpers, unnecessary abstractions or renames, and unrelated style churn when behavior and clarity are preserved. Do not sacrifice meaningful tests, accessibility, security, edge cases, or clarity merely to shrink the diff.
   - Run multiple independent review subagents for broad or risky work, using distinct lenses such as correctness/state, SwiftUI/macOS behavior, tests, security, and release integrity. Give them the raw diff and relevant files, not prior conclusions.
   - Review dirty changes with `codex review --uncommitted` and committed branch changes with `codex review --base origin/main`.
   - When CodeRabbit CLI is installed and authenticated, review the union of local changes with `coderabbit review --agent -t all --base origin/main`. Run another Codex and CodeRabbit pass when the change is broad or risky, or when an earlier pass found issues.
   - If CodeRabbit cannot run because of tooling, authentication, private-code export restrictions, or rate limits, record that and continue after the independent subagents, Codex review, targeted validation, and hosted CI are clean. Do not treat unavailable CodeRabbit as a successful review or block an otherwise complete release on its availability.
   - Treat every finding as a hypothesis. Reproduce or trace the issue, inspect related code and tests, and consult primary documentation for version-sensitive or external behavior. Fix only confirmed, in-scope findings; keep a concise rationale for false positives.
   - After each fix batch, run targeted validation and repeat affected reviewers. Remove exploratory instrumentation and superseded fixes. Continue until no legitimate local finding remains.

3. Validate the finished candidate.
   - Use `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` for Swift commands.
   - Run `swift build`, `swift test`, `git diff --check`, shell syntax checks for touched scripts, and any additional checks required by `AGENTS.md`, package scripts, or CI configuration.
   - For user-visible changes, build and run the real app or isolated mock app and exercise every materially changed flow. Do not accept compilation or unit tests alone as proof that a SwiftUI interaction works.
   - Capture useful before/after screenshots for UI PRs when practical. Keep screenshots and generated review artifacts out of git; attach verified temporary links to the PR only when upload succeeds.

4. Create, review, and merge the PR.
   - Stage only intended paths, inspect the staged diff, commit descriptively, push the topic branch, and create a PR with a concise summary, validation evidence, and UI screenshots when available.
   - Monitor the latest PR head SHA, mergeability, required checks, reviews, comments, and review threads. Allow CI and review bots enough time to review each new head.
   - Investigate every new finding. Fix legitimate issues, resolve fixed, outdated, and verified-false-positive threads, rerun targeted checks and affected local reviewers, commit, push, and restart the loop from the new head SHA.
   - Merge only when the latest head is mergeable, required checks are green, required reviewers finished successfully or were skipped under the explicit exception above, unresolved actionable threads equal zero, and the worktree has no unintended tracked changes.
   - Update local `main` after merge. Require clean local `main` to equal `origin/main` before packaging or tagging.

5. Choose a safe release version.
   - Use a version supplied by the user; otherwise fetch remote state and increment the patch component of the highest published stable tag matching exactly `vMAJOR.MINOR.PATCH`.
   - Ignore test-release tags. Never reuse or move an existing stable tag, collide with an existing draft for another commit, or release a version older than the latest stable release.
   - Ensure the resolved `CFBundleVersion` is greater than every previously published build number so Sparkle recognizes the release as an update.

6. Build, sign, and verify before publication without installing.

   ```bash
   DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
     MARKETING_VERSION="$VERSION" \
     ./script/package_release.sh
   ```

   - Do not add `--install` or `--notarize` here.
   - Verify Developer ID signing, hardened runtime, DMG integrity, app and DMG versions, and the packaged executable hash without copying or launching the app from `/Applications`.

7. Start and safely continue the official release unless the user opted out.
   - Run `./script/tag_release.sh "$VERSION"` exactly once. The stable tag is the only action that starts official notarization; do not block it on other Apple submissions being `In Progress`. If this or any later exactly-once action returns an uncertain result, reconcile remote tags, workflow runs, draft releases, and persisted Apple submission IDs before retrying. Resume the existing release when they identify one exact attempt; abort safely when the state remains ambiguous.
   - Monitor the initial workflow until it has preserved the exact signed app in a private draft release and recorded its Apple submission ID. Confirm the scheduled continuation workflow is enabled.
   - `.github/workflows/notarization-continuation.yml` resumes persisted submission IDs every ten minutes. Never restart the submission workflow or upload another copy merely because processing takes 24 hours or longer.
   - On app acceptance, continuation staples the preserved app, creates and submits the DMG once, and persists that submission ID. Apply the same remote-state reconciliation before any uncertain DMG submission retry. On DMG acceptance, it staples and validates the artifacts, runs Gatekeeper verification, publishes `v$VERSION` as latest, and publishes the signed appcast.
   - On `Invalid` or `Rejected`, retrieve the notarization log, diagnose and fix the exact failure, send the fix through the review/PR gates, and submit one replacement artifact only after that fix lands.
   - If Apple is still processing, establish a durable, persisted continuation for every remaining distribution check before exiting; live monitoring is supplemental only. Report the exact persisted stage and IDs, but do not call the production release complete.

8. Verify the production distribution chain after notarization.
   - Confirm the stable GitHub release is public, non-prerelease, latest, and contains the versioned DMG, versioned app ZIP, stable `Dayline.dmg`, and signed `appcast.xml`.
   - Download the published assets and verify hashes, versions, Developer ID signatures, hardened runtime, staples, Gatekeeper acceptance, and DMG integrity.
   - Confirm the website download resolves to the new notarized `Dayline.dmg` and the live `https://dayline.robin.build/appcast.xml` matches the signed release asset with the new version and monotonically increasing build.
   - Do not click the update button, run an automated Sparkle update, install an isolated previous version, relaunch through Sparkle, or install the final artifact into `/Applications`. Leave the entire in-app update experience for Robin to perform manually.
   - Recheck that `/Applications/Dayline.app` still has the exact version and build recorded before the release.

9. Update and verify Homebrew.
   - In `robin-liquidium/homebrew-tap`, update `Casks/dayline.rb` to the new version and the SHA-256 of the final notarized versioned DMG.
   - Create a focused tap PR, wait for its complete test matrix and review state, fix legitimate findings, merge it, and synchronize the tap's `main`.
   - Run `brew update`, then `brew fetch --cask robin-liquidium/tap/dayline` without installing it. Verify the fetched cask version, URL, checksum, signature, staple, Gatekeeper result, and DMG integrity.
   - Never run `brew install`, `brew reinstall`, or `brew upgrade` for Dayline.

10. Close out with evidence.
    - Report the Dayline PR and merge commit, latest-head CI and review state, stable tag and release URL, Apple submission IDs/stages, signatures and hashes, website download target, live Sparkle feed, Homebrew PR and fetched-cask verification, preserved installed version/build, and clean or intentionally dirty worktree state.
    - State that the release is available through GitHub, the website, Sparkle, and Homebrew while the manual in-app update experience remains intentionally untested for Robin. Never claim that manual update succeeded.
    - Clearly distinguish `signed`, `notarized`, `stapled`, `submitted`, and `published`. If Apple or another durable continuation is pending, say exactly what remains instead of claiming the release is complete.
