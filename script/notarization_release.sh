#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Dayline"
STATE_SCHEMA=1
STATE_MARKER="dayline-notarization-state"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
RELEASE_DIR="$DIST_DIR/release"
ARTIFACT_DIR="$DIST_DIR/artifacts"
APP_BUNDLE="$RELEASE_DIR/$APP_NAME.app"
if [[ -n "${RUNNER_TEMP:-}" ]]; then
  WORK_DIR="$RUNNER_TEMP/dayline-notarization"
else
  WORK_DIR="$DIST_DIR/notarization-work"
fi

COMMAND="${1:-}"
REQUESTED_TAG="${2:-${RELEASE_TAG:-}}"
REPOSITORY="${GITHUB_REPOSITORY:-}"

usage() {
  cat <<USAGE
usage: $0 submit <tag>
       $0 continue [tag]

submit builds and uploads one exact signed app, submits it to Apple once, and exits.
continue advances pending private draft releases without rebuilding accepted artifacts.
USAGE
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required command not found: $1" >&2
    exit 2
  fi
}

notarytool_with_credentials() {
  if [[ -z "${NOTARY_KEY_PATH:-}" || -z "${NOTARY_KEY_ID:-}" || -z "${NOTARY_ISSUER_ID:-}" ]]; then
    echo "App Store Connect notarization credentials are required." >&2
    exit 2
  fi

  xcrun notarytool "$@" \
    --key "$NOTARY_KEY_PATH" \
    --key-id "$NOTARY_KEY_ID" \
    --issuer "$NOTARY_ISSUER_ID"
}

release_for_tag() {
  local tag="$1"
  gh api "repos/$REPOSITORY/releases?per_page=100" |
    jq -c --arg tag "$tag" '.[] | select(.tag_name == $tag)' |
    head -n 1
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

version_is_greater() {
  local candidate="${1#v}"
  local baseline="${2#v}"
  local candidate_major candidate_minor candidate_patch baseline_major baseline_minor baseline_patch

  IFS=. read -r candidate_major candidate_minor candidate_patch <<< "$candidate"
  IFS=. read -r baseline_major baseline_minor baseline_patch <<< "$baseline"
  (( 10#$candidate_major > 10#$baseline_major )) ||
    (( 10#$candidate_major == 10#$baseline_major && 10#$candidate_minor > 10#$baseline_minor )) ||
    (( 10#$candidate_major == 10#$baseline_major && 10#$candidate_minor == 10#$baseline_minor && 10#$candidate_patch > 10#$baseline_patch ))
}

other_active_release_tag() {
  local requested_tag="$1"
  gh api "repos/$REPOSITORY/releases?per_page=100" |
    jq -r --arg marker "$STATE_MARKER" --arg requested "$requested_tag" '
      .[]
      | select(.draft == true and .tag_name != $requested)
      | (.body | fromjson?) as $state
      | select($state.marker == $marker)
      | select($state.stage != "failed" and $state.stage != "superseded")
      | .tag_name
    ' |
    head -n 1
}

state_from_release() {
  local release_json="$1"
  jq -er --arg marker "$STATE_MARKER" '
    select(.draft == true)
    | .body
    | fromjson
    | select(.marker == $marker)
  ' <<< "$release_json"
}

save_state() {
  local release_id="$1"
  local state_json="$2"
  gh api --method PATCH "repos/$REPOSITORY/releases/$release_id" \
    -f body="$(jq -c . <<< "$state_json")" >/dev/null
}

create_draft_release() {
  local tag="$1"
  local version="$2"
  local commit_sha="$3"
  local state_json="$4"

  gh api --method POST "repos/$REPOSITORY/releases" \
    -f tag_name="$tag" \
    -f target_commitish="$commit_sha" \
    -f name="$APP_NAME $version — notarization pending" \
    -f body="$(jq -c . <<< "$state_json")" \
    -F draft=true \
    -F prerelease=false
}

delete_asset_if_present() {
  local release_json="$1"
  local asset_name="$2"
  local asset_id
  asset_id="$(jq -r --arg name "$asset_name" '.assets[]? | select(.name == $name) | .id' <<< "$release_json")"
  if [[ -n "$asset_id" ]]; then
    gh api --method DELETE "repos/$REPOSITORY/releases/assets/$asset_id" >/dev/null
  fi
}

delete_submission_assets() {
  local release_id="$1"
  local asset_ids asset_id

  asset_ids="$(gh api "repos/$REPOSITORY/releases/$release_id" |
    jq -r '.assets[]? | select(.name | test("-(app|dmg)-notary\\.(zip|dmg)$")) | .id')"
  [[ -n "$asset_ids" ]] || return 0
  while IFS= read -r asset_id; do
    gh api --method DELETE "repos/$REPOSITORY/releases/assets/$asset_id" >/dev/null
  done <<< "$asset_ids"
}

upload_asset() {
  local release_id="$1"
  local asset_name="$2"
  local path="$3"
  local content_type="application/octet-stream"
  local release_json

  case "$asset_name" in
    *.zip) content_type="application/zip" ;;
    *.dmg) content_type="application/x-apple-diskimage" ;;
    *.xml) content_type="application/xml" ;;
    *.json) content_type="application/json" ;;
  esac

  release_json="$(gh api "repos/$REPOSITORY/releases/$release_id")"
  delete_asset_if_present "$release_json" "$asset_name"
  gh api --hostname uploads.github.com --method POST \
    -H "Content-Type: $content_type" \
    --input "$path" \
    "repos/$REPOSITORY/releases/$release_id/assets?name=$asset_name" >/dev/null
}

download_asset() {
  local release_json="$1"
  local asset_name="$2"
  local destination="$3"
  local asset_id
  asset_id="$(jq -r --arg name "$asset_name" '.assets[]? | select(.name == $name) | .id' <<< "$release_json")"
  if [[ -z "$asset_id" ]]; then
    echo "Draft release is missing required asset: $asset_name" >&2
    return 1
  fi
  gh api -H "Accept: application/octet-stream" \
    "repos/$REPOSITORY/releases/assets/$asset_id" > "$destination"
}

sha256() {
  /usr/bin/shasum -a 256 "$1" | awk '{print $1}'
}

verify_sha256() {
  local path="$1"
  local expected="$2"
  local actual
  actual="$(sha256 "$path")"
  if [[ "$actual" != "$expected" ]]; then
    echo "SHA-256 mismatch for $path: expected $expected, got $actual" >&2
    return 1
  fi
}

submission_id_from_history() {
  local submission_name="$1"
  local history
  history="$(notarytool_with_credentials history --output-format json)"
  jq -r --arg name "$submission_name" '
    [.history[]? | select(.name == $name)]
    | sort_by(.createdDate)
    | last
    | .id // empty
  ' <<< "$history"
}

submit_preserved_asset() {
  local release_id="$1"
  local release_json="$2"
  local state_json="$3"
  local kind="$4"
  local asset_name asset_sha destination submission submission_id recovered_id now

  asset_name="$(jq -r --arg kind "$kind" '.[$kind + "_submission_asset"]' <<< "$state_json")"
  asset_sha="$(jq -r --arg kind "$kind" '.[$kind + "_submission_sha256"]' <<< "$state_json")"
  destination="$WORK_DIR/$asset_name"
  mkdir -p "$WORK_DIR"
  download_asset "$release_json" "$asset_name" "$destination" || return 1
  verify_sha256 "$destination" "$asset_sha" || return 1

  recovered_id="$(submission_id_from_history "$asset_name")"
  if [[ -n "$recovered_id" ]]; then
    submission_id="$recovered_id"
    echo "Recovered existing $kind submission $submission_id for $asset_name"
  else
    submission="$(notarytool_with_credentials submit "$destination" --output-format json)"
    submission_id="$(jq -r '.id // empty' <<< "$submission")"
    if [[ -z "$submission_id" ]]; then
      echo "Could not read Apple submission ID: $submission" >&2
      return 1
    fi
    echo "Submitted $kind artifact once: $submission_id"
  fi

  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  state_json="$(jq -c \
    --arg stage "${kind}_pending" \
    --arg id "$submission_id" \
    --arg now "$now" \
    --arg kind "$kind" \
    '.stage = $stage | .[$kind + "_submission_id"] = $id | .updated_at = $now' \
    <<< "$state_json")"
  save_state "$release_id" "$state_json" || return 1
}

record_terminal_failure() {
  local release_id="$1"
  local state_json="$2"
  local kind="$3"
  local submission_id="$4"
  local status="$5"
  local log_path="$WORK_DIR/$APP_NAME-$kind-notarization-log.json"
  local now

  if notarytool_with_credentials log "$submission_id" "$log_path"; then
    upload_asset "$release_id" "$(basename "$log_path")" "$log_path"
  fi
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  state_json="$(jq -c \
    --arg stage "failed" \
    --arg kind "$kind" \
    --arg status "$status" \
    --arg now "$now" \
    '.stage = $stage | .failed_stage = $kind | .apple_status = $status | .updated_at = $now' \
    <<< "$state_json")"
  save_state "$release_id" "$state_json"
  echo "$kind notarization failed: $submission_id ($status)" >&2
}

advance_accepted_app() {
  local release_id="$1"
  local release_json="$2"
  local state_json="$3"
  local version build_number app_asset app_sha app_zip dmg dmg_asset dmg_sha now

  version="$(jq -r '.version' <<< "$state_json")"
  build_number="$(jq -r '.build_number' <<< "$state_json")"
  app_asset="$(jq -r '.app_submission_asset' <<< "$state_json")"
  app_sha="$(jq -r '.app_submission_sha256' <<< "$state_json")"

  rm -rf "$WORK_DIR" "$RELEASE_DIR" "$ARTIFACT_DIR"
  mkdir -p "$WORK_DIR" "$RELEASE_DIR"
  download_asset "$release_json" "$app_asset" "$WORK_DIR/$app_asset" || return 1
  verify_sha256 "$WORK_DIR/$app_asset" "$app_sha" || return 1
  /usr/bin/ditto -x -k "$WORK_DIR/$app_asset" "$RELEASE_DIR" || return 1

  /usr/bin/codesign --verify --strict --verbose=2 "$APP_BUNDLE"
  xcrun stapler staple "$APP_BUNDLE"
  xcrun stapler validate "$APP_BUNDLE"

  MARKETING_VERSION="$version" BUILD_NUMBER="$build_number" \
    "$ROOT_DIR/script/package_release.sh" --package-existing

  app_zip="$ARTIFACT_DIR/$APP_NAME-$version.app.zip"
  dmg="$ARTIFACT_DIR/$APP_NAME-$version.dmg"
  dmg_asset="$APP_NAME-$version-${GITHUB_RUN_ID:-manual}-dmg-notary.dmg"
  cp "$dmg" "$WORK_DIR/$dmg_asset"
  dmg_sha="$(sha256 "$WORK_DIR/$dmg_asset")"

  upload_asset "$release_id" "$(basename "$app_zip")" "$app_zip"
  upload_asset "$release_id" "$dmg_asset" "$WORK_DIR/$dmg_asset"

  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  state_json="$(jq -c \
    --arg stage "dmg_prepared" \
    --arg app_zip_asset "$(basename "$app_zip")" \
    --arg app_zip_sha256 "$(sha256 "$app_zip")" \
    --arg dmg_submission_asset "$dmg_asset" \
    --arg dmg_submission_sha256 "$dmg_sha" \
    --arg now "$now" \
    '.stage = $stage
      | .app_zip_asset = $app_zip_asset
      | .app_zip_sha256 = $app_zip_sha256
      | .dmg_submission_asset = $dmg_submission_asset
      | .dmg_submission_sha256 = $dmg_submission_sha256
      | .updated_at = $now' \
    <<< "$state_json")"
  save_state "$release_id" "$state_json"

  release_json="$(gh api "repos/$REPOSITORY/releases/$release_id")"
  submit_preserved_asset "$release_id" "$release_json" "$state_json" "dmg"
}

finalize_accepted_dmg() {
  local release_id="$1"
  local release_json="$2"
  local state_json="$3"
  local version app_zip_asset app_zip_sha dmg_asset dmg_sha final_dmg stable_dmg app_zip extracted_app appcast latest_tag now

  version="$(jq -r '.version' <<< "$state_json")"
  latest_tag="$(latest_stable_tag)"
  if [[ -n "$latest_tag" ]] && ! version_is_greater "v$version" "$latest_tag"; then
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    state_json="$(jq -c --arg stage "superseded" --arg latest "$latest_tag" --arg now "$now" \
      '.stage = $stage | .superseded_by = $latest | .updated_at = $now' <<< "$state_json")"
    save_state "$release_id" "$state_json"
    echo "Refusing to publish v$version because $latest_tag is already the newest stable release."
    return 0
  fi
  app_zip_asset="$(jq -r '.app_zip_asset' <<< "$state_json")"
  app_zip_sha="$(jq -r '.app_zip_sha256' <<< "$state_json")"
  dmg_asset="$(jq -r '.dmg_submission_asset' <<< "$state_json")"
  dmg_sha="$(jq -r '.dmg_submission_sha256' <<< "$state_json")"

  rm -rf "$WORK_DIR" "$ARTIFACT_DIR"
  mkdir -p "$WORK_DIR" "$ARTIFACT_DIR"
  app_zip="$ARTIFACT_DIR/$app_zip_asset"
  final_dmg="$ARTIFACT_DIR/$APP_NAME-$version.dmg"
  stable_dmg="$ARTIFACT_DIR/$APP_NAME.dmg"
  download_asset "$release_json" "$app_zip_asset" "$app_zip" || return 1
  download_asset "$release_json" "$dmg_asset" "$final_dmg" || return 1
  verify_sha256 "$app_zip" "$app_zip_sha" || return 1
  verify_sha256 "$final_dmg" "$dmg_sha" || return 1

  xcrun stapler staple "$final_dmg"
  xcrun stapler validate "$final_dmg"
  /usr/bin/hdiutil verify "$final_dmg"
  /usr/bin/codesign --verify --strict --verbose=2 "$final_dmg"
  /usr/sbin/spctl --assess --type open --context context:primary-signature --verbose=2 "$final_dmg"

  mkdir -p "$WORK_DIR/app-check"
  /usr/bin/ditto -x -k "$app_zip" "$WORK_DIR/app-check"
  extracted_app="$WORK_DIR/app-check/$APP_NAME.app"
  /usr/bin/codesign --verify --strict --verbose=2 "$extracted_app"
  xcrun stapler validate "$extracted_app"
  /usr/sbin/spctl --assess --type execute --verbose=2 "$extracted_app"

  cp "$final_dmg" "$stable_dmg"
  upload_asset "$release_id" "$(basename "$final_dmg")" "$final_dmg"
  upload_asset "$release_id" "$(basename "$stable_dmg")" "$stable_dmg"

  appcast="$ARTIFACT_DIR/appcast.xml"
  "$ROOT_DIR/script/update_appcast.sh" generate "v$version" "$app_zip" "$appcast"
  upload_asset "$release_id" "$(basename "$appcast")" "$appcast"

  latest_tag="$(latest_stable_tag)"
  if [[ -n "$latest_tag" ]] && ! version_is_greater "v$version" "$latest_tag"; then
    echo "Refusing to publish v$version because $latest_tag became the newest stable release." >&2
    return 1
  fi

  gh api --method PATCH "repos/$REPOSITORY/releases/$release_id" \
    -f name="$APP_NAME $version" \
    -f body="Requires macOS 26 or newer. Connect Google Calendar and Linear directly from Dayline after installation." \
    -F draft=false \
    -F prerelease=false \
    -f make_latest=true >/dev/null

  "$ROOT_DIR/script/update_appcast.sh" publish "v$version" "$appcast"
  if ! delete_submission_assets "$release_id"; then
    echo "Warning: published v$version, but temporary notarization assets still need cleanup." >&2
  fi

  echo "Published notarized release v$version"
}

ensure_prepared_app_asset() {
  local release_id="$1"
  local release_json="$2"
  local state_json="$3"
  local tag commit_sha tagged_commit version build_number app_asset app_sha asset_json asset_id asset_state recovered_id
  local rebuild_root source_dir app_path verification_path now

  app_asset="$(jq -r '.app_submission_asset' <<< "$state_json")" || return 1
  app_sha="$(jq -r '.app_submission_sha256' <<< "$state_json")" || return 1
  asset_json="$(jq -c --arg name "$app_asset" '.assets[]? | select(.name == $name)' <<< "$release_json")" || return 1
  asset_id="$(jq -r '.id // empty' <<< "$asset_json")" || return 1
  asset_state="$(jq -r '.state // empty' <<< "$asset_json")" || return 1
  if [[ -n "$asset_id" && "$asset_state" == "uploaded" ]]; then
    mkdir -p "$WORK_DIR" || return 1
    verification_path="$WORK_DIR/verify-$app_asset"
    download_asset "$release_json" "$app_asset" "$verification_path" || return 1
    if verify_sha256 "$verification_path" "$app_sha"; then
      rm -f "$verification_path" || return 1
      return 0
    fi
    rm -f "$verification_path" || return 1
  fi

  recovered_id="$(submission_id_from_history "$app_asset")" || return 1
  if [[ -n "$recovered_id" ]]; then
    echo "Apple submission $recovered_id exists for missing asset $app_asset; refusing to rebuild different bytes." >&2
    return 1
  fi
  if [[ -n "$asset_id" ]]; then
    delete_asset_if_present "$release_json" "$app_asset" || return 1
  fi

  tag="$(jq -r '.tag' <<< "$state_json")" || return 1
  commit_sha="$(jq -r '.commit_sha' <<< "$state_json")" || return 1
  version="$(jq -r '.version' <<< "$state_json")" || return 1
  build_number="$(jq -r '.build_number' <<< "$state_json")" || return 1
  git fetch --no-tags origin "refs/tags/$tag:refs/tags/$tag" || return 1
  tagged_commit="$(git rev-parse "${tag}^{commit}")" || return 1
  if [[ "$tagged_commit" != "$commit_sha" ]]; then
    echo "$tag resolves to $tagged_commit, not the draft commit $commit_sha; refusing recovery." >&2
    return 1
  fi

  rebuild_root="$(mktemp -d "${RUNNER_TEMP:-/tmp}/dayline-release-rebuild.XXXXXX")" || return 1
  source_dir="$rebuild_root/source"
  if ! git worktree add --detach "$source_dir" "$commit_sha"; then
    rmdir "$rebuild_root" || true
    return 1
  fi
  if ! (
    cd "$source_dir"
    MARKETING_VERSION="$version" BUILD_NUMBER="$build_number" \
      ./script/package_release.sh --prepare-notarization
  ); then
    git worktree remove --force "$source_dir" || true
    rmdir "$rebuild_root" || true
    return 1
  fi

  mkdir -p "$WORK_DIR" || return 1
  app_path="$WORK_DIR/$app_asset"
  if ! mv "$source_dir/dist/$APP_NAME-notary.zip" "$app_path"; then
    git worktree remove --force "$source_dir" || true
    rmdir "$rebuild_root" || true
    return 1
  fi
  git worktree remove --force "$source_dir" || return 1
  rmdir "$rebuild_root" || true

  app_sha="$(sha256 "$app_path")" || return 1
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)" || return 1
  state_json="$(jq -c --arg sha "$app_sha" --arg now "$now" \
    '.app_submission_sha256 = $sha | .updated_at = $now' <<< "$state_json")" || return 1
  save_state "$release_id" "$state_json" || return 1
  upload_asset "$release_id" "$app_asset" "$app_path" || return 1
  echo "Rebuilt and preserved missing app asset for $tag."
}

continue_release() {
  local tag="$1"
  local release_json release_id state_json stage kind submission_id info status

  release_json="$(release_for_tag "$tag")"
  if [[ -z "$release_json" ]]; then
    echo "No release exists for $tag; skipping."
    return 0
  fi
  if [[ "$(jq -r '.draft' <<< "$release_json")" != "true" ]]; then
    local latest_tag published_appcast="$WORK_DIR/$tag-appcast.xml"
    latest_tag="$(latest_stable_tag)"
    if [[ "$tag" != "$latest_tag" ]]; then
      echo "$tag is published but is not the newest stable release ($latest_tag); skipping feed publication."
      if ! delete_submission_assets "$(jq -r '.id' <<< "$release_json")"; then
        echo "Warning: could not clean temporary notarization assets from $tag." >&2
      fi
      return 0
    fi
    if download_asset "$release_json" "appcast.xml" "$published_appcast"; then
      "$ROOT_DIR/script/update_appcast.sh" publish "$tag" "$published_appcast"
      echo "$tag is already published; ensured its appcast is live."
    else
      echo "$tag is already published without an appcast asset; skipping feed publication."
    fi
    if ! delete_submission_assets "$(jq -r '.id' <<< "$release_json")"; then
      echo "Warning: could not clean temporary notarization assets from $tag." >&2
    fi
    return 0
  fi

  state_json="$(state_from_release "$release_json")"
  release_id="$(jq -r '.id' <<< "$release_json")"
  stage="$(jq -r '.stage' <<< "$state_json")"
  echo "$tag notarization stage: $stage"

  case "$stage" in
    app_prepared)
      ensure_prepared_app_asset "$release_id" "$release_json" "$state_json" || return 1
      release_json="$(gh api "repos/$REPOSITORY/releases/$release_id")"
      state_json="$(state_from_release "$release_json")"
      submit_preserved_asset "$release_id" "$release_json" "$state_json" "app"
      return 0
      ;;
    dmg_prepared)
      submit_preserved_asset "$release_id" "$release_json" "$state_json" "dmg"
      return 0
      ;;
    app_pending) kind="app" ;;
    dmg_pending) kind="dmg" ;;
    failed|superseded)
      echo "$tag previously reached terminal stage $stage; leaving its draft intact."
      return 0
      ;;
    *)
      echo "Unknown notarization stage for $tag: $stage" >&2
      return 1
      ;;
  esac

  submission_id="$(jq -r --arg kind "$kind" '.[$kind + "_submission_id"]' <<< "$state_json")"
  info="$(notarytool_with_credentials info "$submission_id" --output-format json)"
  status="$(jq -r '.status // "Unknown"' <<< "$info")"
  echo "$tag $kind submission $submission_id: $status"

  case "$status" in
    "In Progress") return 0 ;;
    Accepted)
      if [[ "$kind" == "app" ]]; then
        advance_accepted_app "$release_id" "$release_json" "$state_json"
      else
        finalize_accepted_dmg "$release_id" "$release_json" "$state_json"
      fi
      ;;
    Invalid|Rejected)
      record_terminal_failure "$release_id" "$state_json" "$kind" "$submission_id" "$status"
      return 1
      ;;
    *)
      echo "Apple returned unexpected status for $tag: $status" >&2
      return 1
      ;;
  esac
}

submit_release() {
  local tag="$1"
  local version commit_sha build_number release_json release_id app_asset app_path app_sha now state_json active_tag latest_tag

  if [[ ! "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Release tag must look like v0.1.6." >&2
    exit 2
  fi
  version="${tag#v}"
  commit_sha="$(git rev-parse HEAD)"
  build_number="${BUILD_NUMBER:-$(git rev-list --count HEAD)}"

  release_json="$(release_for_tag "$tag")"
  if [[ -n "$release_json" ]]; then
    if [[ "$(jq -r '.draft' <<< "$release_json")" != "true" ]]; then
      echo "$tag is already published; refusing to create another submission."
      return 0
    fi
    state_json="$(state_from_release "$release_json")"
    if [[ "$(jq -r '.commit_sha' <<< "$state_json")" != "$commit_sha" ]]; then
      echo "Existing $tag draft belongs to a different commit." >&2
      return 1
    fi
  fi

  active_tag="$(other_active_release_tag "$tag")"
  if [[ -n "$active_tag" ]]; then
    echo "Refusing to submit $tag while $active_tag is still active." >&2
    return 1
  fi
  latest_tag="$(latest_stable_tag)"
  if [[ -n "$latest_tag" ]] && ! version_is_greater "$tag" "$latest_tag"; then
    echo "Refusing to submit $tag because it is not newer than $latest_tag." >&2
    return 1
  fi

  if [[ -n "$release_json" ]]; then
    continue_release "$tag"
    return 0
  fi

  MARKETING_VERSION="$version" BUILD_NUMBER="$build_number" \
    "$ROOT_DIR/script/package_release.sh" --prepare-notarization

  mkdir -p "$WORK_DIR"
  app_asset="$APP_NAME-$version-${GITHUB_RUN_ID:-manual}-app-notary.zip"
  app_path="$WORK_DIR/$app_asset"
  mv "$DIST_DIR/$APP_NAME-notary.zip" "$app_path"
  app_sha="$(sha256 "$app_path")"
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  state_json="$(jq -n -c \
    --arg marker "$STATE_MARKER" \
    --argjson schema "$STATE_SCHEMA" \
    --arg stage "app_prepared" \
    --arg tag "$tag" \
    --arg version "$version" \
    --arg commit_sha "$commit_sha" \
    --arg build_number "$build_number" \
    --arg app_submission_asset "$app_asset" \
    --arg app_submission_sha256 "$app_sha" \
    --arg now "$now" \
    '{marker: $marker, schema: $schema, stage: $stage, tag: $tag, version: $version,
      commit_sha: $commit_sha, build_number: $build_number,
      app_submission_asset: $app_submission_asset,
      app_submission_sha256: $app_submission_sha256,
      created_at: $now, updated_at: $now}')"

  release_json="$(create_draft_release "$tag" "$version" "$commit_sha" "$state_json")"
  release_id="$(jq -r '.id' <<< "$release_json")"
  upload_asset "$release_id" "$app_asset" "$app_path"
  release_json="$(gh api "repos/$REPOSITORY/releases/$release_id")"
  submit_preserved_asset "$release_id" "$release_json" "$state_json" "app"
}

continue_all() {
  local tags tag latest_tag
  tags="$(gh api "repos/$REPOSITORY/releases?per_page=100" |
    jq -r --arg marker "$STATE_MARKER" '
      [.[]
        | select(.draft == true)
        | (.body | fromjson?) as $state
        | select($state.marker == $marker)
        | select($state.stage != "failed" and $state.stage != "superseded")]
      | sort_by(.tag_name | ltrimstr("v") | split(".") | map(tonumber))
      | .[].tag_name
    ')"
  if [[ -z "$tags" ]]; then
    echo "No pending Dayline notarization drafts."
  else
    while IFS= read -r tag; do
      continue_release "$tag"
    done <<< "$tags"
  fi

  # Reconcile the production feed after a transient publish failure on an
  # otherwise-complete release. This is idempotent when the feed is current.
  latest_tag="$(latest_stable_tag)"
  if [[ "$latest_tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    continue_release "$latest_tag"
  fi
}

require_command gh
require_command jq
require_command xcrun

if [[ -z "$REPOSITORY" ]]; then
  REPOSITORY="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
fi

cd "$ROOT_DIR"
mkdir -p "$WORK_DIR"

case "$COMMAND" in
  submit)
    [[ -n "$REQUESTED_TAG" ]] || { usage >&2; exit 2; }
    submit_release "$REQUESTED_TAG"
    ;;
  continue)
    if [[ -n "$REQUESTED_TAG" ]]; then
      continue_release "$REQUESTED_TAG"
    else
      continue_all
    fi
    ;;
  --help|-h|help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
