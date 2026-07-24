---
name: dayline-pr
description: "Review and ship the latest Dayline work to main: inspect all local and unpushed changes, run independent subagents plus Codex and CodeRabbit reviews through the send-it workflow, investigate and fix legitimate findings, validate the app, create and clean up a PR, and optionally merge it when asked. Stops at a green main — it never tags, packages, or releases. Use when Robin invokes $dayline-pr or asks to review and land current Dayline work without cutting a release."
---

# Dayline PR

Get the current Dayline work reviewed, merged, and synced into `main`. This is the first half of the release pipeline: it ends with a clean `main`, never with a tag or release. When Robin wants the full ship including the release, use `dayline-publish-latest` instead.

## Authority boundary

- Treat invocation as authorization to create a topic branch, review and fix the intended work, commit it, and create its PR. Merge only when Robin explicitly asks for a merge or when invoked from `dayline-release`/`dayline-publish-latest`, which carry merge authorization.
- Treat every tracked, staged, unstaged, untracked, committed-but-unpushed, and pushed-but-unmerged change relative to `origin/main` as a candidate. Inspect all of it. Exclude generated, accidental, or unrelated files only after verifying that classification; ask only when ambiguity would materially change the outcome.
- Preserve unrelated user work. Never force-push, print secrets, or discard changes.
- Never tag, package, create GitHub releases, submit to Apple, or update Homebrew — that is `dayline-release`.

## Workflow

1. Get the work reviewed, merged, and synced by following the `send-it` skill (`~/.agents/skills/send-it/SKILL.md`) steps 1–9. Its commit-first flow, secret scan, review round loop (autoreview Codex and opencode engines plus CodeRabbit), finding ledger, screenshot rules, CI/bot monitoring, and merge gates apply verbatim. If the send-it skill is unavailable, stop and report instead of falling back to ad-hoc review commands. Dayline-specific deltas:
   - The base branch is always `main`; always use a topic branch and PR, even when work began on `main`. Push directly to `main` only when Robin explicitly requests that.
   - Merge authorization: when Robin explicitly asks for a merge, or when this skill was invoked from `dayline-release`/`dayline-publish-latest`, that satisfies send-it's merge gate — merge only after all send-it gates pass.
   - Additionally run independent lens subagents on the round-1 full diff — distinct lenses such as correctness/state, SwiftUI/macOS behavior, tests, security, and release integrity — giving them the raw diff and relevant files, not prior conclusions, and instructing each one explicitly to ONLY REVIEW AND NOT CHANGE/EDIT ANYTHING. Their findings enter the same triage and wont-fix ledger, and the review loop is not clean until the lenses also report no legitimate findings.
   - Validation (send-it step 7) additionally requires: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` for all Swift commands; `swift build`, `swift test`, `git diff --check`, and shell syntax checks for touched scripts; and for user-visible changes, build and run the real app or isolated mock app and exercise every materially changed flow — compilation or unit tests alone are not proof that a SwiftUI interaction works.

2. After merge, update local `main`.
   - Require clean local `main` to equal `origin/main`. Leave the repository on `main` so `dayline-release` can start immediately.
   - If unrelated local changes prevent a clean `main` sync, stop and report — never discard them and never sweep them into a commit.

3. Close out with evidence.
   - Report the PR URL and merge commit, latest-head CI and review state, and clean or intentionally dirty worktree state.
   - State clearly that no release was started. Suggest `dayline-release` when Robin wants to ship what landed.
