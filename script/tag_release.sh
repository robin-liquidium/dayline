#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VERSION="${1:-}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "usage: $0 <version>" >&2
  echo "example: $0 0.1.4" >&2
  exit 2
fi

TAG="v$VERSION"

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI (gh) is required." >&2
  exit 2
fi

if [[ "$(git branch --show-current)" != "main" ]]; then
  echo "Releases must be tagged from main." >&2
  exit 2
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Working tree is dirty. Commit and push the release changes first." >&2
  exit 2
fi

git fetch origin main --tags

if [[ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]]; then
  echo "Local main does not match origin/main. Pull or push before releasing." >&2
  exit 2
fi

if git rev-parse "$TAG" >/dev/null 2>&1 || git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1; then
  echo "Tag $TAG already exists." >&2
  exit 2
fi

if gh release view "$TAG" >/dev/null 2>&1; then
  echo "GitHub release $TAG already exists." >&2
  exit 2
fi

git tag -a "$TAG" -m "Dayline $VERSION"
git push origin "$TAG"

echo
echo "Pushed $TAG. GitHub Actions will build, sign, notarize, and publish the release."
echo "Follow it with: gh run watch"
