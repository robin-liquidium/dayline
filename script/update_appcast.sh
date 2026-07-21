#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WEBSITE_APPCAST="$ROOT_DIR/website/public/appcast.xml"
COMMAND="${1:-}"
TAG="${2:-}"
REPOSITORY="${GITHUB_REPOSITORY:-}"
APPCAST_WORK_DIR=""

cleanup() {
  if [[ -n "$APPCAST_WORK_DIR" && -d "$APPCAST_WORK_DIR" ]]; then
    if [[ -e "$APPCAST_WORK_DIR/repository/.git" ]]; then
      git -C "$ROOT_DIR" worktree remove --force "$APPCAST_WORK_DIR/repository" || true
    fi
    /bin/rm -rf "$APPCAST_WORK_DIR"
  fi
}

trap cleanup EXIT

usage() {
  cat <<USAGE
usage: $0 generate <tag> <app-zip> <output-appcast>
       $0 publish <tag> <signed-appcast>

generate signs a stable Sparkle feed containing the supplied notarized app ZIP.
publish atomically commits only website/public/appcast.xml to the default branch.
USAGE
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required command not found: $1" >&2
    exit 2
  fi
}

require_stable_tag() {
  if [[ ! "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Stable update tag must look like v0.1.7." >&2
    exit 2
  fi
}

latest_stable_tag() {
  gh api "repos/$REPOSITORY/releases?per_page=100" |
    jq -r '
      [.[]
        | select(.draft == false and .prerelease == false)
        | select(.tag_name | test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))]
      | sort_by(.tag_name | ltrimstr("v") | split(".") | map(tonumber))
      | (last // {})
      | .tag_name // empty
    '
}

generate_appcast() {
  local app_zip="${3:-}"
  local output_appcast="${4:-}"
  local generator verifier archives_dir

  [[ -n "$app_zip" && -f "$app_zip" ]] || { echo "Missing notarized app ZIP: $app_zip" >&2; exit 2; }
  [[ -n "$output_appcast" ]] || { usage >&2; exit 2; }
  [[ -n "${DAYLINE_SPARKLE_PRIVATE_KEY:-}" ]] || {
    echo "Missing DAYLINE_SPARKLE_PRIVATE_KEY." >&2
    exit 2
  }

  generator="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"
  verifier="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin/sign_update"
  [[ -x "$generator" && -x "$verifier" ]] || {
    echo "Sparkle publishing tools are missing. Run swift build first." >&2
    exit 2
  }

  APPCAST_WORK_DIR="$(mktemp -d "${RUNNER_TEMP:-/tmp}/dayline-appcast.XXXXXX")"
  archives_dir="$APPCAST_WORK_DIR/archives"
  mkdir -p "$archives_dir"
  /usr/bin/ditto "$app_zip" "$archives_dir/$(basename "$app_zip")"
  /usr/bin/ditto "$WEBSITE_APPCAST" "$archives_dir/appcast.xml"

  printf '%s' "$DAYLINE_SPARKLE_PRIVATE_KEY" |
    "$generator" \
      --ed-key-file - \
      --download-url-prefix "https://github.com/$REPOSITORY/releases/download/$TAG/" \
      --maximum-deltas 0 \
      --maximum-versions 3 \
      -o "$archives_dir/appcast.xml" \
      "$archives_dir"

  printf '%s' "$DAYLINE_SPARKLE_PRIVATE_KEY" |
    "$verifier" --ed-key-file - --verify "$archives_dir/appcast.xml"
  /usr/bin/ditto "$archives_dir/appcast.xml" "$output_appcast"
  echo "Generated signed appcast for $TAG"
}

publish_appcast() {
  local signed_appcast="${3:-}"
  local latest_tag publisher_checkout remote_content_sha local_content_sha

  [[ -n "$signed_appcast" && -f "$signed_appcast" ]] || { echo "Missing signed appcast: $signed_appcast" >&2; exit 2; }
  [[ -n "$REPOSITORY" ]] || REPOSITORY="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
  latest_tag="$(latest_stable_tag)"
  if [[ "$TAG" != "$latest_tag" ]]; then
    echo "Refusing to publish $TAG because the newest stable release is ${latest_tag:-none}." >&2
    exit 2
  fi

  [[ -n "${APPCAST_GIT_SSH_COMMAND:-}" ]] || {
    echo "Missing APPCAST_GIT_SSH_COMMAND for protected appcast publication." >&2
    exit 2
  }

  APPCAST_WORK_DIR="$(mktemp -d "${RUNNER_TEMP:-/tmp}/dayline-appcast-publish.XXXXXX")"
  publisher_checkout="$APPCAST_WORK_DIR/repository"
  git fetch origin main
  git worktree add --detach "$publisher_checkout" origin/main

  remote_content_sha="$(/usr/bin/shasum -a 256 "$publisher_checkout/website/public/appcast.xml" | awk '{print $1}')"
  local_content_sha="$(/usr/bin/shasum -a 256 "$signed_appcast" | awk '{print $1}')"

  if [[ "$remote_content_sha" == "$local_content_sha" ]]; then
    echo "Production appcast already contains $TAG"
    return
  fi

  /usr/bin/ditto "$signed_appcast" "$publisher_checkout/website/public/appcast.xml"
  git -C "$publisher_checkout" config user.name "Dayline Release Bot"
  git -C "$publisher_checkout" config user.email "dayline-release@users.noreply.github.com"
  git -C "$publisher_checkout" add website/public/appcast.xml
  git -C "$publisher_checkout" commit -m "Publish $TAG update feed"
  GIT_SSH_COMMAND="$APPCAST_GIT_SSH_COMMAND" \
    git -C "$publisher_checkout" push git@github.com:"$REPOSITORY".git HEAD:main
  echo "Published $TAG appcast to website/public/appcast.xml"
}

require_command gh
require_command jq

case "$COMMAND" in
  generate|publish)
    require_stable_tag
    if [[ -z "$REPOSITORY" ]]; then
      REPOSITORY="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
    fi
    if [[ "$COMMAND" == "generate" ]]; then
      generate_appcast "$@"
    else
      publish_appcast "$@"
    fi
    ;;
  --help|-h|help) usage ;;
  *) usage >&2; exit 2 ;;
esac
