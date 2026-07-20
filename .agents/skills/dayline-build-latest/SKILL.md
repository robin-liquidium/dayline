---
name: dayline-build-latest
description: Build, validate, package, and install the latest Dayline source locally. Use when Robin asks to build or install the latest Dayline app, update the copy in /Applications, test current changes as a packaged app, or invokes $dayline-build-latest. This workflow commits the intended local changes by default but never pushes, tags, creates GitHub releases, or submits anything to Apple.
---

# Dayline Build Latest

Work from the Dayline repository root. Produce a Developer ID-signed local app with the repository's existing scripts, then replace `/Applications/Dayline.app` with that exact build.

## Authority boundary

- Treat explicit invocation as authorization to inspect, stage, and commit only the intended Dayline changes and to replace `/Applications/Dayline.app`.
- Never push, create or move tags, open or merge a PR, create a GitHub release, trigger GitHub Actions, or call `notarytool`.
- Preserve unrelated dirty and untracked files. Stop if intended and unrelated changes overlap in the same file and cannot be separated safely.
- Skip the commit only when there are no changes or Robin explicitly says not to commit.

## Workflow

1. Inspect the real checkout.
   - Run `git status --short --branch`, `git diff --stat`, and the focused diff.
   - Confirm the current branch and fetch no remote state unless needed for read-only version discovery.
   - Identify the intended files before staging anything.

2. Validate before committing.
   - Use `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` for Swift commands on this Mac.
   - Run `swift test` and `git diff --check`.
   - For UI changes, launch `./script/build_mock_and_run.sh`, exercise the changed behavior with real pointer input, and keep screenshots temporary.
   - Run a focused pre-commit review when practical. Verify findings rather than applying them blindly.

3. Commit the intended change.
   - Stage only the intended paths and create one descriptive commit.
   - Re-check `git status`; do not push the commit.

4. Choose the local marketing version.
   - If `HEAD` has an exact stable tag matching `vMAJOR.MINOR.PATCH`, use that version.
   - Otherwise find the highest stable tag matching exactly `vMAJOR.MINOR.PATCH` and increment its patch number. Ignore test tags such as `test-v0.1.7.1` and `v0.1.6-test.1`.
   - This version is local metadata only. Do not create a tag.

5. Package and install.

   ```bash
   DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
     MARKETING_VERSION="$VERSION" \
     ./script/package_release.sh --install
   ```

   Let the script detect the Developer ID identity. Do not add `--notarize`.

6. Verify the exact installed artifact.
   - Read `CFBundleShortVersionString` and `CFBundleVersion` from `/Applications/Dayline.app/Contents/Info.plist`.
   - Run `codesign --verify --deep --strict --verbose=2 /Applications/Dayline.app` and confirm the Developer ID authority and hardened runtime.
   - Compare SHA-256 of the packaged and installed `Contents/MacOS/Dayline` executables.
   - Confirm `/Applications/Dayline.app/Contents/MacOS/Dayline` is running.
   - An `spctl` result of `Unnotarized Developer ID` is expected for this local-only workflow; do not turn that into a new Apple submission.

7. Report the commit, installed version/build, signature, matching hashes, tests, and any deliberately preserved worktree changes.
