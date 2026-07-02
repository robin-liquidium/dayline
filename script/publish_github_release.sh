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

  if git describe --tags --abbrev=0 >/dev/null 2>&1; then
    git describe --tags --abbrev=0 | sed 's/^v//'
    return
  fi

  printf '0.1.0\n'
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

VERSION="$(resolve_version)"
TAG="v$VERSION"
DMG_PATH="$ARTIFACT_DIR/$APP_NAME-$VERSION.dmg"
ZIP_PATH="$ARTIFACT_DIR/$APP_NAME-$VERSION.app.zip"
NOTES_FILE="$(mktemp -t dayline-release-notes.XXXXXX)"
trap 'rm -f "$NOTES_FILE"' EXIT

require_remote
require_artifact "$DMG_PATH"
require_artifact "$ZIP_PATH"

cat >"$NOTES_FILE" <<NOTES
$APP_NAME $VERSION

Downloads:
- Recommended: $APP_NAME-$VERSION.dmg
- Direct app bundle archive: $APP_NAME-$VERSION.app.zip

Requirements:
- macOS 26 or newer
- Local authenticated gws and linear CLIs
NOTES

gh release create "$TAG" \
  "$DMG_PATH" \
  "$ZIP_PATH" \
  --title "$APP_NAME $VERSION" \
  --notes-file "$NOTES_FILE"
