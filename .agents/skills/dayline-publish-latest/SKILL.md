---
name: dayline-publish-latest
description: "Review and ship the latest Dayline work end to end: land all current changes on main through the dayline-pr workflow, then cut the full production release through the dayline-release workflow — changelog, packaging, Apple-notarized GitHub release with changelog-derived notes, website, Sparkle feed, and Homebrew. Use when Robin invokes $dayline-publish-latest or asks to publish, ship, or release the latest Dayline build in one go."
---

# Dayline Publish Latest

Ship the latest Dayline work end to end by running the two half-workflows in order. Continue automatically through the full production release unless the user explicitly narrows or stops the workflow.

## Workflow

1. Follow the `dayline-pr` skill (`.agents/skills/dayline-pr/SKILL.md`) completely. This skill's invocation explicitly authorizes the merge, satisfying its merge gate — merge only after all of its review gates pass. Stop if `dayline-pr` is unavailable or cannot finish with a clean `main` equal to `origin/main`.

2. Follow the `dayline-release` skill (`.agents/skills/dayline-release/SKILL.md`) completely, starting from the clean merged `main` that step 1 produced.

3. Close out with one combined report: the feature PR and merge commit from `dayline-pr`, plus the changelog PR, stable tag, release URL, release-notes verification, Apple submission IDs/stages, signatures and hashes, website download target, live changelog page, live Sparkle feed, Homebrew verification, preserved installed version/build, and worktree state from `dayline-release`. Clearly distinguish `signed`, `notarized`, `stapled`, `submitted`, and `published`, and never claim the manual in-app Sparkle update succeeded — that remains Robin's personal test.
