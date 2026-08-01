#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="$ROOT_DIR/dist/ui-test-results"
RUN_ID="${DAYLINE_UI_TEST_RUN_ID:-$(date +%Y%m%d-%H%M%S)-$(/usr/bin/uuidgen | /usr/bin/tr '[:upper:]' '[:lower:]')}"
if [[ ! "$RUN_ID" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]]; then
  echo "DAYLINE_UI_TEST_RUN_ID must be a 1-64 character alphanumeric, dot, underscore, or hyphen token." >&2
  exit 2
fi
RUN_DIR="$RESULTS_DIR/$RUN_ID"
RESULT_PATH="${DAYLINE_UI_TEST_RESULT_PATH:-$RUN_DIR/DaylineUITests.xcresult}"
DERIVED_DATA_PATH="$ROOT_DIR/dist/ui-test-derived-data/$RUN_ID"
RUNNER_PATH="$DERIVED_DATA_PATH/Build/Products/Debug/DaylineUITests-Runner.app"
RUN_STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
IS_TARGETED_RUN=false
for argument in "$@"; do
  if [[ "$argument" == -only-testing* ]]; then
    IS_TARGETED_RUN=true
    break
  fi
done

mkdir -p "$RUN_DIR/app-logs" "$(dirname "$RESULT_PATH")"

export DAYLINE_UI_TEST_RUN_ID="$RUN_ID"
export DAYLINE_UI_TEST_LOG_DIR="$RUN_DIR/app-logs"

finish_run() {
  local exit_code=$?
  {
    echo "run_id=$RUN_ID"
    echo "started_at=$RUN_STARTED_AT"
    echo "finished_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "exit_code=$exit_code"
    echo "result_bundle=$RESULT_PATH"
    echo "app_log_directory=$DAYLINE_UI_TEST_LOG_DIR"
  } >"$RUN_DIR/run-metadata.txt"
}
trap finish_run EXIT

exec > >(/usr/bin/tee "$RUN_DIR/runner.log") 2>&1

cd "$ROOT_DIR"

./script/build_mock_and_run.sh --build-only

xcodebuild build-for-testing \
  -project UITests/DaylineUITests.xcodeproj \
  -scheme DaylineUITests \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_PATH"

# Xcode's copied XCTRunner inherits provenance metadata on newer macOS versions,
# which makes Gatekeeper reject the otherwise valid generated runner.
/usr/bin/xattr -cr "$RUNNER_PATH"

XCTESTRUN_COUNT="$(/usr/bin/find "$DERIVED_DATA_PATH/Build/Products" -type f -name '*.xctestrun' -print | /usr/bin/wc -l | /usr/bin/tr -d '[:space:]')"
if [[ "$XCTESTRUN_COUNT" != "1" ]]; then
  echo "Expected exactly one .xctestrun file, found $XCTESTRUN_COUNT." >&2
  exit 1
fi
XCTESTRUN_PATH="$(/usr/bin/find "$DERIVED_DATA_PATH/Build/Products" -type f -name '*.xctestrun' -print)"

/usr/bin/plutil -remove 'DaylineUITests.EnvironmentVariables.DAYLINE_UI_TEST_RUN_ID' "$XCTESTRUN_PATH" 2>/dev/null || true
/usr/bin/plutil -remove 'DaylineUITests.EnvironmentVariables.DAYLINE_UI_TEST_LOG_DIR' "$XCTESTRUN_PATH" 2>/dev/null || true
/usr/bin/plutil -insert 'DaylineUITests.EnvironmentVariables.DAYLINE_UI_TEST_RUN_ID' -string "$RUN_ID" "$XCTESTRUN_PATH"
/usr/bin/plutil -insert 'DaylineUITests.EnvironmentVariables.DAYLINE_UI_TEST_LOG_DIR' -string "$DAYLINE_UI_TEST_LOG_DIR" "$XCTESTRUN_PATH"

set +e
xcodebuild test-without-building \
  -xctestrun "$XCTESTRUN_PATH" \
  -destination 'platform=macOS' \
  -resultBundlePath "$RESULT_PATH" \
  "$@"
TEST_EXIT_CODE=$?
set -e

RESULT_EXPORT_EXIT_CODE=0
if [[ -d "$RESULT_PATH" ]]; then
  xcrun xcresulttool get test-results summary --path "$RESULT_PATH" >"$RUN_DIR/summary.json" || RESULT_EXPORT_EXIT_CODE=$?
  xcrun xcresulttool get test-results tests --path "$RESULT_PATH" >"$RUN_DIR/tests.json" || RESULT_EXPORT_EXIT_CODE=$?
  xcrun xcresulttool export attachments \
    --path "$RESULT_PATH" \
    --output-path "$RUN_DIR/checkpoints" || RESULT_EXPORT_EXIT_CODE=$?
fi

if [[ "$TEST_EXIT_CODE" -ne 0 ]]; then
  exit "$TEST_EXIT_CODE"
fi

if [[ "$RESULT_EXPORT_EXIT_CODE" -ne 0 ]]; then
  exit "$RESULT_EXPORT_EXIT_CODE"
fi

if [[ "$IS_TARGETED_RUN" == false ]]; then
  APP_LOG="$RUN_DIR/app-logs/dayline.log"
  if [[ ! -f "$APP_LOG" ]]; then
    echo "Full UI test run did not produce the run-scoped app log." >&2
    exit 1
  fi

  REQUIRED_BREADCRUMBS=(
    "App launched version"
    "Mock refresh completed"
    "Issue source selected github"
    "Issue source selected linear"
    "Linear issues expanded visible"
    "Linear issues collapsed visible"
    "Linear issue priority changed"
    "Linear issue labels changed count"
    "Linear issue status changed"
    "Linear issue assignee changed"
    "Linear issue created"
    "GitHub issue created"
    "Local note created total"
    "Local note updated total"
    "Local note deleted total"
    "Note formatting command requested: bold"
    "Note formatting command requested: italic"
    "Note formatting command requested: unordered list"
    "Note formatting command requested: link"
  )
  for breadcrumb in "${REQUIRED_BREADCRUMBS[@]}"; do
    if ! /usr/bin/grep -Fq "[run $RUN_ID] $breadcrumb" "$APP_LOG"; then
      echo "Missing required run-scoped app breadcrumb: $breadcrumb" >&2
      exit 1
    fi
  done

  if /usr/bin/grep -Eiq '(^|[[:space:]])(error|fault|failed|failure)(:|[[:space:]]|$)' "$RUN_DIR"/app-logs/dayline*.log; then
    echo "Run-scoped app logs contain an error, fault, failure, or failed breadcrumb." >&2
    exit 1
  fi
fi

echo "UI test evidence: $RUN_DIR"
