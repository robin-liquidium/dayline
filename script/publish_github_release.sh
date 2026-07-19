#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Dayline"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_DIR="$ROOT_DIR/dist/artifacts"

cd "$ROOT_DIR"

# resolve_version mirrors package_release.sh so both scripts agree on release names.
resolve_version() {
  if [[ -n "${MARKETING_VERSION:-}" ]]; then
    printf '%s\n' "$MARKETING_VERSION"
    return
  fi

  if git describe --tags --exact-match HEAD >/dev/null 2>&1; then
    git describe --tags --exact-match HEAD | sed 's/^v//'
    return
  fi

  echo "HEAD must have an exact version tag such as v0.1.4." >&2
  exit 2
}

# require_remote fails early when the local repository has not been published yet.
require_remote() {
  if ! git remote get-url origin >/dev/null 2>&1; then
    echo "No git remote named origin is configured." >&2
    echo "Add the GitHub remote first, then rerun this script." >&2
    exit 2
  fi
}

# require_artifact checks that the package step has produced each release asset.
require_artifact() {
  local path="$1"

  if [[ ! -f "$path" ]]; then
    echo "Missing release artifact: $path" >&2
    echo "Run ./script/package_release.sh first." >&2
    exit 2
  fi
}

# require_release_source ensures uploaded assets match a clean tagged commit.
require_release_source() {
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "Refusing to publish from a dirty working tree." >&2
    exit 2
  fi

  local exact_tag
  exact_tag="$(git describe --tags --exact-match HEAD 2>/dev/null || true)"
  if [[ "$exact_tag" != "$TAG" ]]; then
    echo "HEAD tag ($exact_tag) does not match release tag ($TAG)." >&2
    exit 2
  fi

  if gh release view "$TAG" >/dev/null 2>&1; then
    echo "GitHub release $TAG already exists." >&2
    exit 2
  fi
}

VERSION="$(resolve_version)"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid stable release version: $VERSION" >&2
  exit 2
fi
TAG="v$VERSION"
DMG_PATH="$ARTIFACT_DIR/$APP_NAME-$VERSION.dmg"
ZIP_PATH="$ARTIFACT_DIR/$APP_NAME-$VERSION.app.zip"
# Stable asset name so /releases/latest/download/Dayline.dmg always works.
STABLE_DMG_PATH="$ARTIFACT_DIR/$APP_NAME.dmg"

require_remote
require_release_source
require_artifact "$DMG_PATH"
require_artifact "$ZIP_PATH"

cp "$DMG_PATH" "$STABLE_DMG_PATH"

gh release create "$TAG" \
  "$DMG_PATH" \
  "$ZIP_PATH" \
  "$STABLE_DMG_PATH" \
  --verify-tag \
  --fail-on-no-commits \
  --generate-notes \
  --title "$APP_NAME $VERSION" \
  --notes "Requires macOS 26 or newer. Connect Google Calendar and Linear directly from Dayline after installation."
